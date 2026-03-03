import 'dart:convert';
import 'dart:io' show HttpClient, HttpException;

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song_model.dart';
import '../../domain/entities/song.dart';
import 'audio_stream_server.dart';

class YouTubeRepository {
  YoutubeExplode _yt = YoutubeExplode();
  final AudioStreamServer _streamServer = AudioStreamServer();

  /// Dynamically fetched Piped instances (cached after first fetch).
  List<String>? _cachedPipedInstances;

  /// Last Piped instance that successfully returned a stream.
  String? _workingPipedInstance;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _todayQuery {
    final now = DateTime.now();
    return '${_months[now.month - 1]} ${now.day} ${now.year}';
  }

  Future<List<Song>> getTrendingSongs() async {
    try {
      final query = 'trending music today $_todayQuery official audio';
      debugPrint('[YouTubeRepo] Trending query: $query');

      final searchList = await _yt.search.search(query);

      return searchList.take(20).map((video) {
        return SongModel.fromYouTube(
          videoId: video.id.value,
          title: _cleanTitle(video.title),
          artist: video.author,
          duration: video.duration,
          thumbnailUrl: video.thumbnails.highResUrl,
          viewCount: video.engagement.viewCount,
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch trending songs: $e');
    }
  }

  Future<List<Song>> getViralSongs() async {
    try {
      final query = 'viral songs today $_todayQuery trending now';
      debugPrint('[YouTubeRepo] Viral query: $query');

      final searchList = await _yt.search.search(query);

      return searchList.take(20).map((video) {
        return SongModel.fromYouTube(
          videoId: video.id.value,
          title: _cleanTitle(video.title),
          artist: video.author,
          duration: video.duration,
          thumbnailUrl: video.thumbnails.highResUrl,
          viewCount: video.engagement.viewCount,
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch viral songs: $e');
    }
  }

  // ─── Piped API ───────────────────────────────────────────────

  /// Fetches the live list of Piped API instances.
  Future<List<String>> _fetchPipedInstances() async {
    if (_cachedPipedInstances != null) return _cachedPipedInstances!;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('https://piped-instances.kavin.rocks/'),
      );
      final response =
          await request.close().timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final body = await response.transform(const Utf8Decoder()).join();
      final list = jsonDecode(body) as List<dynamic>;

      _cachedPipedInstances = list
          .where((e) =>
              e['api_url'] != null &&
              (e['api_url'] as String).isNotEmpty)
          .map((e) => e['api_url'] as String)
          .toList();

      debugPrint(
          '[YouTubeRepo] Fetched ${_cachedPipedInstances!.length} Piped instances');
      return _cachedPipedInstances!;
    } catch (e) {
      debugPrint('[YouTubeRepo] Failed to fetch Piped instance list: $e');
      return [];
    } finally {
      client.close();
    }
  }

  /// Gets an audio stream URL from a Piped API instance.
  /// Dynamically discovers instances and caches the working one.
  Future<String> getPipedStreamUrl(String videoId) async {
    // Try the previously-working instance first
    if (_workingPipedInstance != null) {
      try {
        return await _tryPipedInstance(_workingPipedInstance!, videoId);
      } catch (_) {
        _workingPipedInstance = null;
      }
    }

    final instances = await _fetchPipedInstances();
    if (instances.isEmpty) {
      throw Exception('No Piped instances available');
    }

    // Try up to 10 instances
    for (final instance in instances.take(10)) {
      try {
        final url = await _tryPipedInstance(instance, videoId);
        _workingPipedInstance = instance;
        return url;
      } catch (e) {
        debugPrint('[YouTubeRepo] Piped $instance failed: $e');
      }
    }
    throw Exception('All Piped instances failed for $videoId');
  }

  Future<String> _tryPipedInstance(String instance, String videoId) async {
    debugPrint('[YouTubeRepo] Trying Piped: $instance');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.parse('$instance/streams/$videoId'),
      );
      request.headers.set('User-Agent', 'SMusicApp/1.0');

      final response =
          await request.close().timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final body = await response.transform(const Utf8Decoder()).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        throw Exception(json['error']);
      }

      final audioStreams = json['audioStreams'] as List<dynamic>?;
      if (audioStreams == null || audioStreams.isEmpty) {
        throw Exception('No audio streams');
      }

      // Sort by bitrate descending, pick best >= 96 kbps
      audioStreams.sort((a, b) =>
          ((b['bitrate'] as int?) ?? 0)
              .compareTo((a['bitrate'] as int?) ?? 0));

      final stream = audioStreams.firstWhere(
        (s) => ((s['bitrate'] as int?) ?? 0) >= 96000,
        orElse: () => audioStreams.first,
      );

      final url = stream['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('Empty stream URL');
      }

      debugPrint('[YouTubeRepo] Piped stream: ${stream['quality']}, '
          '${stream['mimeType']}');
      return url;
    } finally {
      client.close();
    }
  }

  // ─── Piped Video API ─────────────────────────────────────────

  /// Gets a muxed video stream URL from a Piped API instance.
  /// Filters for muxed streams (videoOnly == false) and picks 720p or best.
  Future<String> getPipedVideoStreamUrl(String videoId) async {
    if (_workingPipedInstance != null) {
      try {
        return await _tryPipedVideoInstance(_workingPipedInstance!, videoId);
      } catch (_) {
        // Fall through to try other instances
      }
    }

    final instances = await _fetchPipedInstances();
    if (instances.isEmpty) {
      throw Exception('No Piped instances available');
    }

    for (final instance in instances.take(10)) {
      try {
        final url = await _tryPipedVideoInstance(instance, videoId);
        _workingPipedInstance = instance;
        return url;
      } catch (e) {
        debugPrint('[YouTubeRepo] Piped video $instance failed: $e');
      }
    }
    throw Exception('All Piped instances failed for video $videoId');
  }

  Future<String> _tryPipedVideoInstance(
      String instance, String videoId) async {
    debugPrint('[YouTubeRepo] Trying Piped video: $instance');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.parse('$instance/streams/$videoId'),
      );
      request.headers.set('User-Agent', 'SMusicApp/1.0');

      final response =
          await request.close().timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final body = await response.transform(const Utf8Decoder()).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        throw Exception(json['error']);
      }

      final videoStreams = json['videoStreams'] as List<dynamic>?;
      if (videoStreams == null || videoStreams.isEmpty) {
        throw Exception('No video streams');
      }

      // Filter muxed streams (videoOnly == false means audio+video)
      final muxedStreams = videoStreams
          .where((s) => s['videoOnly'] == false)
          .toList();
      if (muxedStreams.isEmpty) {
        throw Exception('No muxed video streams');
      }

      // Sort by height descending
      muxedStreams.sort((a, b) =>
          ((b['height'] as int?) ?? 0)
              .compareTo((a['height'] as int?) ?? 0));

      // Prefer 720p, otherwise best available
      final stream = muxedStreams.firstWhere(
        (s) => (s['height'] as int?) == 720,
        orElse: () => muxedStreams.first,
      );

      final url = stream['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('Empty video stream URL');
      }

      debugPrint('[YouTubeRepo] Piped video stream: ${stream['quality']}, '
          '${stream['mimeType']}');
      return url;
    } finally {
      client.close();
    }
  }

  // ─── Invidious API ─────────────────────────────────────────

  /// Gets an audio stream URL via an Invidious instance.
  /// Uses /latest_version with local=true for proxied streaming.
  Future<String> getInvidiousStreamUrl(String videoId) async {
    // Fetch live instance list
    List<String> instances;
    try {
      instances = await _fetchInvidiousInstances();
    } catch (_) {
      instances = [];
    }

    if (instances.isEmpty) {
      throw Exception('No Invidious instances available');
    }

    for (final instance in instances.take(8)) {
      try {
        debugPrint('[YouTubeRepo] Trying Invidious: $instance');
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 8);
        try {
          final request = await client.getUrl(
            Uri.parse(
                '$instance/api/v1/videos/$videoId?fields=adaptiveFormats'),
          );
          final response =
              await request.close().timeout(const Duration(seconds: 12));

          if (response.statusCode != 200) {
            debugPrint(
                '[YouTubeRepo] Invidious HTTP ${response.statusCode}');
            continue;
          }

          final body =
              await response.transform(const Utf8Decoder()).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final formats = json['adaptiveFormats'] as List<dynamic>?;

          if (formats == null || formats.isEmpty) continue;

          // Filter audio-only
          final audioFormats = formats
              .where((f) =>
                  (f['type'] as String?)?.startsWith('audio/') == true)
              .toList();
          if (audioFormats.isEmpty) continue;

          // Sort by bitrate descending
          audioFormats.sort((a, b) =>
              (int.tryParse('${b['bitrate']}') ?? 0)
                  .compareTo(int.tryParse('${a['bitrate']}') ?? 0));

          final best = audioFormats.firstWhere(
            (f) => (int.tryParse('${f['bitrate']}') ?? 0) >= 96000,
            orElse: () => audioFormats.first,
          );

          final itag = best['itag'];
          if (itag == null) continue;

          // Proxied through Invidious with local=true
          final proxyUrl =
              '$instance/latest_version?id=$videoId&itag=$itag&local=true';
          debugPrint('[YouTubeRepo] Invidious stream: itag=$itag, '
              '${best['type']}');
          return proxyUrl;
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('[YouTubeRepo] Invidious $instance failed: $e');
      }
    }
    throw Exception('All Invidious instances failed for $videoId');
  }

  /// Gets a muxed video stream URL via an Invidious instance.
  /// Reads formatStreams[] (muxed) and filters for video/mp4.
  Future<String> getInvidiousVideoStreamUrl(String videoId) async {
    List<String> instances;
    try {
      instances = await _fetchInvidiousInstances();
    } catch (_) {
      instances = [];
    }

    if (instances.isEmpty) {
      throw Exception('No Invidious instances available');
    }

    for (final instance in instances.take(8)) {
      try {
        debugPrint('[YouTubeRepo] Trying Invidious video: $instance');
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 8);
        try {
          final request = await client.getUrl(
            Uri.parse(
                '$instance/api/v1/videos/$videoId?fields=formatStreams'),
          );
          final response =
              await request.close().timeout(const Duration(seconds: 12));

          if (response.statusCode != 200) {
            debugPrint(
                '[YouTubeRepo] Invidious video HTTP ${response.statusCode}');
            continue;
          }

          final body =
              await response.transform(const Utf8Decoder()).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final formats = json['formatStreams'] as List<dynamic>?;

          if (formats == null || formats.isEmpty) continue;

          // Filter for video/mp4 muxed streams
          final videoFormats = formats
              .where((f) =>
                  (f['type'] as String?)?.startsWith('video/mp4') == true)
              .toList();
          if (videoFormats.isEmpty) continue;

          // Sort by quality label (prefer 720p)
          final best = videoFormats.firstWhere(
            (f) => (f['qualityLabel'] as String?)?.contains('720') == true,
            orElse: () => videoFormats.first,
          );

          final itag = best['itag'];
          if (itag == null) continue;

          // Proxied through Invidious with local=true
          final proxyUrl =
              '$instance/latest_version?id=$videoId&itag=$itag&local=true';
          debugPrint('[YouTubeRepo] Invidious video stream: itag=$itag, '
              '${best['type']}');
          return proxyUrl;
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('[YouTubeRepo] Invidious video $instance failed: $e');
      }
    }
    throw Exception('All Invidious instances failed for video $videoId');
  }

  Future<List<String>> _fetchInvidiousInstances() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse('https://api.invidious.io/instances.json?sort_by=health'),
      );
      final response =
          await request.close().timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return [];

      final body = await response.transform(const Utf8Decoder()).join();
      final list = jsonDecode(body) as List<dynamic>;

      // Each entry is [domain, details]. Filter for HTTPS instances with API.
      final instances = <String>[];
      for (final entry in list) {
        if (entry is List && entry.length >= 2) {
          final details = entry[1] as Map<String, dynamic>?;
          if (details != null &&
              details['api'] == true &&
              details['type'] == 'https') {
            instances.add('https://${entry[0]}');
          }
        }
      }

      debugPrint(
          '[YouTubeRepo] Fetched ${instances.length} Invidious instances');
      return instances;
    } catch (e) {
      debugPrint(
          '[YouTubeRepo] Failed to fetch Invidious instance list: $e');
      return [];
    } finally {
      client.close();
    }
  }

  /// Picks the best audio stream from a manifest.
  StreamInfo _pickStream(StreamManifest manifest) {
    if (manifest.audioOnly.isNotEmpty) {
      final sorted = manifest.audioOnly.sortByBitrate();
      final info = sorted.firstWhere(
        (s) => s.bitrate.kiloBitsPerSecond >= 96,
        orElse: () => sorted.last,
      );
      debugPrint('[YouTubeRepo] Audio stream: '
          '${info.bitrate.kiloBitsPerSecond}kbps, '
          '${info.size.totalMegaBytes.toStringAsFixed(1)} MB');
      return info;
    } else if (manifest.muxed.isNotEmpty) {
      final sorted = manifest.muxed.sortByBitrate();
      debugPrint('[YouTubeRepo] Muxed stream fallback');
      return sorted.first;
    }
    throw Exception('No audio streams available');
  }

  /// Fetches the stream manifest once and returns the best stream info.
  /// Call this once, then pass the result to the playback strategies.
  Future<StreamInfo> getStreamInfo(String videoId) async {
    debugPrint('[YouTubeRepo] Getting manifest for: $videoId');
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    debugPrint('[YouTubeRepo] Manifest received. '
        'Audio: ${manifest.audioOnly.length}, '
        'Muxed: ${manifest.muxed.length}');
    return _pickStream(manifest);
  }

  /// Fetches the stream manifest and returns the best muxed stream info
  /// (audio + video combined). Used as video fallback.
  Future<StreamInfo> getMuxedStreamInfo(String videoId) async {
    debugPrint('[YouTubeRepo] Getting muxed manifest for: $videoId');
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    if (manifest.muxed.isEmpty) {
      throw Exception('No muxed streams available');
    }
    final sorted = manifest.muxed.sortByVideoQuality();
    // Prefer 720p, otherwise best available
    final info = sorted.firstWhere(
      (s) => s.qualityLabel.contains('720'),
      orElse: () => sorted.first,
    );
    debugPrint('[YouTubeRepo] Muxed stream: ${info.qualityLabel}, '
        '${info.size.totalMegaBytes.toStringAsFixed(1)} MB');
    return info;
  }

  /// Returns the direct CDN URL from a pre-fetched [streamInfo].
  String getDirectUrl(StreamInfo streamInfo) {
    return streamInfo.url.toString();
  }

  /// Proxy via youtube_explode's authenticated stream client.
  Future<String> getProxiedStreamUrl(StreamInfo streamInfo) async {
    final url = await _streamServer.serve(_yt, streamInfo);
    debugPrint('[YouTubeRepo] Proxy URL (yt_explode): $url');
    return url;
  }

  /// Proxy via manual HTTP download with YouTube headers.
  /// Bypasses youtube_explode's stream client entirely.
  Future<String> getManualProxiedStreamUrl(StreamInfo streamInfo) async {
    final url =
        await _streamServer.serveFromUrl(streamInfo.url, streamInfo);
    debugPrint('[YouTubeRepo] Proxy URL (manual HTTP): $url');
    return url;
  }

  /// Refreshes the internal YoutubeExplode client (clears stale state).
  void refreshClient() {
    _yt.close();
    _yt = YoutubeExplode();
    debugPrint('[YouTubeRepo] Client refreshed');
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s*\(Official\s*(Music\s*)?Video\)',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[Official\s*(Music\s*)?Video\]',
            caseSensitive: false), '')
        .replaceAll(
            RegExp(r'\s*\(Official\s*Audio\)', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'\s*\[Official\s*Audio\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(Lyrics?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[Lyrics?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\(Audio\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\|.*$'), '')
        .trim();
  }

  void dispose() {
    _streamServer.stop();
    _yt.close();
  }
}
