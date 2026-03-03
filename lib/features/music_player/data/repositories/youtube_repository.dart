import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song_model.dart';
import '../../domain/entities/song.dart';
import 'audio_stream_server.dart';

class YouTubeRepository {
  YoutubeExplode _yt = YoutubeExplode();
  final AudioStreamServer _streamServer = AudioStreamServer();

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

  /// Returns a direct YouTube CDN URL for ExoPlayer.
  /// Uses youtube_explode v3's properly deciphered stream URLs.
  Future<String> getDirectStreamUrl(String videoId) async {
    debugPrint('[YouTubeRepo] Getting manifest for: $videoId');
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    debugPrint('[YouTubeRepo] Manifest received. '
        'Audio: ${manifest.audioOnly.length}, '
        'Muxed: ${manifest.muxed.length}');

    final streamInfo = _pickStream(manifest);
    final url = streamInfo.url.toString();
    debugPrint('[YouTubeRepo] Direct CDN URL ready');
    return url;
  }

  /// Returns a localhost proxy URL that streams via youtube_explode's
  /// authenticated client. Fallback when direct CDN URLs get 403.
  Future<String> getProxiedStreamUrl(String videoId) async {
    debugPrint('[YouTubeRepo] Getting manifest for proxy: $videoId');
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    debugPrint('[YouTubeRepo] Manifest received. '
        'Audio: ${manifest.audioOnly.length}, '
        'Muxed: ${manifest.muxed.length}');

    final streamInfo = _pickStream(manifest);
    final url = await _streamServer.serve(_yt, streamInfo);
    debugPrint('[YouTubeRepo] Proxy URL: $url');
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
