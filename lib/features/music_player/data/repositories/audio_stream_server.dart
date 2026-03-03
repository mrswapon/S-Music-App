import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Local HTTP proxy that streams YouTube audio to just_audio via localhost.
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

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Starts a local proxy for the given [streamInfo].
  /// Downloads via youtube_explode's authenticated stream client.
  /// Waits for the first chunk before returning the localhost URL.
  Future<String> serve(YoutubeExplode yt, StreamInfo streamInfo) async {
    await stop();

    _currentStream = streamInfo;
    _cancelled = false;
    _firstChunkReady = Completer<bool>();

    _server = await HttpServer.bind('127.0.0.1', 0);
    final port = _server!.port;
    debugPrint('[StreamServer] Started on port $port');

    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('[StreamServer] Server error: $e');
    });

    // Start downloading in the background
    _backgroundDownload(yt, streamInfo);

    return _awaitFirstChunk(port);
  }

  /// Starts a local proxy that downloads the CDN URL using a raw HttpClient
  /// with proper YouTube headers. Bypasses youtube_explode's stream client.
  Future<String> serveFromUrl(
      Uri cdnUrl, StreamInfo streamInfo) async {
    await stop();

    _currentStream = streamInfo;
    _cancelled = false;
    _firstChunkReady = Completer<bool>();

    _server = await HttpServer.bind('127.0.0.1', 0);
    final port = _server!.port;
    debugPrint('[StreamServer] Started on port $port (manual HTTP)');

    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('[StreamServer] Server error: $e');
    });

    _backgroundDownloadFromUrl(cdnUrl);

    return _awaitFirstChunk(port);
  }

  Future<String> _awaitFirstChunk(int port) async {
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

  /// Downloads via youtube_explode's authenticated stream client.
  void _backgroundDownload(YoutubeExplode yt, StreamInfo streamInfo) async {
    try {
      debugPrint('[StreamServer] Background download started '
          '(youtube_explode stream client)…');
      final stream = yt.videos.streamsClient.get(streamInfo);

      await for (final chunk in stream) {
        if (_cancelled) return;
        _appendChunk(Uint8List.fromList(chunk));
      }

      if (!_cancelled) _finalizeDownload();
    } catch (e) {
      _handleDownloadError(e);
    }
  }

  /// Downloads the CDN URL directly using Dart's HttpClient with YouTube
  /// headers. This bypasses youtube_explode's HTTP client entirely.
  void _backgroundDownloadFromUrl(Uri url) async {
    HttpClient? client;
    try {
      debugPrint('[StreamServer] Background download started '
          '(manual HTTP client)…');
      client = HttpClient();
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', _userAgent);
      request.headers.set('Origin', 'https://www.youtube.com');
      request.headers.set('Referer', 'https://www.youtube.com/');
      request.headers.set('Accept', '*/*');
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');

      final response = await request.close();
      debugPrint('[StreamServer] HTTP ${response.statusCode} from CDN');

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('CDN returned ${response.statusCode}');
      }

      await for (final chunk in response) {
        if (_cancelled) return;
        _appendChunk(Uint8List.fromList(chunk));
      }

      if (!_cancelled) _finalizeDownload();
    } catch (e) {
      _handleDownloadError(e);
    } finally {
      client?.close();
    }
  }

  void _appendChunk(Uint8List bytes) {
    _chunks.add(bytes);
    _downloadedBytes += bytes.length;

    if (_firstChunkReady != null && !_firstChunkReady!.isCompleted) {
      debugPrint(
          '[StreamServer] First chunk received: ${bytes.length} bytes');
      _firstChunkReady!.complete(true);
    }

    _notifyWaiters();
  }

  void _finalizeDownload() {
    final builder = BytesBuilder(copy: false);
    for (final c in _chunks) {
      builder.add(c);
    }
    _mergedBuffer = builder.toBytes();
    _downloadComplete = true;
    _notifyWaiters();
    debugPrint('[StreamServer] Download complete: $_downloadedBytes bytes');
  }

  void _handleDownloadError(Object e) {
    if (_cancelled) return;
    debugPrint('[StreamServer] Download error: $e');

    if (_firstChunkReady != null && !_firstChunkReady!.isCompleted) {
      _firstChunkReady!.complete(false);
    }

    _downloadComplete = true;
    _notifyWaiters();
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

      // --- Detect content type (video for muxed, audio otherwise) ---
      final contentType = streamInfo is MuxedStreamInfo
          ? 'video/${streamInfo.container.name}'
          : 'audio/${streamInfo.container.name}';

      // --- HEAD ---
      if (method == 'HEAD') {
        request.response.statusCode = 200;
        request.response.headers.set('Content-Type', contentType);
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
      request.response.headers.set('Content-Type', contentType);
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
