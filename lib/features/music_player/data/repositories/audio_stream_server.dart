import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Local HTTP proxy that streams YouTube audio through youtube_explode's
/// authenticated client. just_audio connects to localhost — no 403 errors.
///
/// Uses progressive buffering: the server starts immediately and streams
/// data to the player as it downloads, instead of waiting for the full file.
class AudioStreamServer {
  HttpServer? _server;
  StreamInfo? _currentStream;

  // Progressive buffer state
  final List<Uint8List> _chunks = [];
  int _downloadedBytes = 0;
  bool _downloadComplete = false;
  bool _cancelled = false;
  Uint8List? _mergedBuffer;
  final List<Completer<void>> _waiters = [];

  // Completes when the first chunk arrives (or download fails)
  Completer<bool>? _firstChunkReady;

  /// Starts a local proxy for the given [streamInfo].
  /// Downloads via youtube_explode's authenticated stream client.
  /// Waits for the first chunk before returning the localhost URL.
  Future<String> serve(YoutubeExplode yt, StreamInfo streamInfo) async {
    await stop();

    _currentStream = streamInfo;
    _cancelled = false;
    _firstChunkReady = Completer<bool>();

    // Start the HTTP server instantly (no download wait)
    _server = await HttpServer.bind('127.0.0.1', 0);
    final port = _server!.port;
    debugPrint('[StreamServer] Started on port $port');

    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('[StreamServer] Server error: $e');
    });

    // Start downloading in the background
    _backgroundDownload(yt, streamInfo);

    // Wait for the first chunk (or failure) before giving the URL to the
    // player. This prevents ExoPlayer from timing out while YouTube's
    // connection is still being established.
    final ok = await _firstChunkReady!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => _downloadedBytes > 0,
    );
    if (!ok && _downloadedBytes == 0) {
      debugPrint('[StreamServer] No data arrived — aborting');
      await stop();
      throw Exception('YouTube stream failed to start');
    }

    debugPrint('[StreamServer] First chunk ready '
        '($_downloadedBytes bytes buffered), returning URL');
    return 'http://127.0.0.1:$port/audio';
  }

  /// Downloads audio chunks from YouTube using youtube_explode's authenticated
  /// stream client (handles throttle decipher, cookies, etc.).
  void _backgroundDownload(YoutubeExplode yt, StreamInfo streamInfo) async {
    try {
      debugPrint('[StreamServer] Background download started '
          '(youtube_explode v3 stream client)…');
      final stream = yt.videos.streamsClient.get(streamInfo);

      await for (final chunk in stream) {
        if (_cancelled) return;
        final bytes = Uint8List.fromList(chunk);
        _chunks.add(bytes);
        _downloadedBytes += bytes.length;

        // Signal that data is available so serve() can return the URL
        if (_firstChunkReady != null && !_firstChunkReady!.isCompleted) {
          debugPrint('[StreamServer] First chunk received: ${bytes.length} bytes');
          _firstChunkReady!.complete(true);
        }

        _notifyWaiters();
      }

      if (_cancelled) return;

      // Merge all chunks into a single buffer for fast range-request serving
      final builder = BytesBuilder(copy: false);
      for (final c in _chunks) {
        builder.add(c);
      }
      _mergedBuffer = builder.toBytes();
      _downloadComplete = true;
      _notifyWaiters();
      debugPrint('[StreamServer] Download complete: $_downloadedBytes bytes');
    } catch (e) {
      if (_cancelled) return;
      debugPrint('[StreamServer] Download error: $e');

      // Signal failure so serve() doesn't hang forever
      if (_firstChunkReady != null && !_firstChunkReady!.isCompleted) {
        _firstChunkReady!.complete(false);
      }

      _downloadComplete = true;
      _notifyWaiters();
    }
  }

  void _notifyWaiters() {
    for (final w in _waiters) {
      if (!w.isCompleted) w.complete();
    }
    _waiters.clear();
  }

  Future<void> _waitForData() {
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void _handleRequest(HttpRequest request) async {
    final streamInfo = _currentStream;
    if (streamInfo == null) {
      request.response.statusCode = 503;
      await request.response.close();
      return;
    }

    try {
      final totalBytes = streamInfo.size.totalBytes;
      final method = request.method;

      // --- Parse Range header (e.g. "bytes=12345-") ---
      int start = 0;
      int end = totalBytes - 1;
      bool isRange = false;
      final rangeHeader = request.headers.value('Range');
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        isRange = true;
        final parts = rangeHeader.substring(6).split('-');
        start = int.tryParse(parts[0]) ?? 0;
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? (totalBytes - 1);
        }
      }
      end = end.clamp(0, totalBytes - 1);
      final contentLength = end - start + 1;

      debugPrint('[StreamServer] $method '
          '${isRange ? "range=$start-$end" : "full"} '
          '(buffered: $_downloadedBytes/$totalBytes)');

      // --- HEAD ---
      if (method == 'HEAD') {
        request.response.statusCode = 200;
        request.response.headers
            .set('Content-Type', 'audio/${streamInfo.container.name}');
        request.response.headers.set('Accept-Ranges', 'bytes');
        request.response.headers.set('Content-Length', '$totalBytes');
        await request.response.close();
        return;
      }

      // --- Response headers ---
      if (isRange) {
        request.response.statusCode = 206;
        request.response.headers
            .set('Content-Range', 'bytes $start-$end/$totalBytes');
      } else {
        request.response.statusCode = 200;
      }
      request.response.headers
          .set('Content-Type', 'audio/${streamInfo.container.name}');
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.set('Content-Length', '$contentLength');

      // --- Fast path: full buffer ready ---
      if (_mergedBuffer != null) {
        request.response.add(_mergedBuffer!.sublist(start, end + 1));
        await request.response.close();
        debugPrint('[StreamServer] Served $contentLength bytes from buffer');
        return;
      }

      // --- Progressive path: serve chunks as they arrive ---
      int pos = 0; // byte position in the overall stream
      int sent = 0; // bytes sent in this response
      int chunkIdx = 0;

      while (sent < contentLength) {
        // Wait for more chunks if we've consumed all available
        while (chunkIdx >= _chunks.length && !_downloadComplete) {
          await _waitForData();
        }
        if (chunkIdx >= _chunks.length) break; // download finished or failed

        final chunk = _chunks[chunkIdx];
        final chunkStart = pos;
        final chunkEnd = pos + chunk.length - 1;

        if (chunkEnd >= start) {
          // This chunk overlaps with the requested range
          final sliceStart = (start > chunkStart) ? start - chunkStart : 0;
          final sliceEnd =
              ((end < chunkEnd) ? end - chunkStart : chunk.length - 1) + 1;
          final bytesToSend = sliceEnd - sliceStart;

          if (bytesToSend > 0) {
            request.response.add(chunk.sublist(sliceStart, sliceEnd));
            await request.response.flush();
            sent += bytesToSend;
          }
        }

        pos += chunk.length;
        chunkIdx++;
      }

      await request.response.close();
      debugPrint('[StreamServer] Served $sent bytes progressively');
    } catch (e) {
      debugPrint('[StreamServer] Error: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _cancelled = true;
    if (_firstChunkReady != null && !_firstChunkReady!.isCompleted) {
      _firstChunkReady!.complete(false);
    }
    _firstChunkReady = null;
    await _server?.close(force: true);
    _server = null;
    _currentStream = null;
    _mergedBuffer = null;
    _chunks.clear();
    _downloadedBytes = 0;
    _downloadComplete = false;
    _notifyWaiters();
  }
}
