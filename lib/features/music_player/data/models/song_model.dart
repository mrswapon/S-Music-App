import '../../domain/entities/song.dart';

class SongModel extends Song {
  const SongModel({
    required super.id,
    required super.title,
    required super.artist,
    super.album,
    super.duration,
    required super.path,
    required super.isLocal,
    super.thumbnailUrl,
    super.viewCount,
    super.videoId,
  });

  factory SongModel.fromOnlineMap(Map<String, String> map, int id) {
    return SongModel(
      id: id,
      title: map['title'] ?? 'Unknown Title',
      artist: map['artist'] ?? 'Unknown Artist',
      album: map['album'],
      path: map['url'] ?? '',
      isLocal: false,
    );
  }

  factory SongModel.fromDeviceAudio({
    required int id,
    required String title,
    required String artist,
    String? album,
    int? durationMs,
    required String data,
  }) {
    return SongModel(
      id: id,
      title: title.isNotEmpty ? title : 'Unknown Title',
      artist: artist.isNotEmpty ? artist : 'Unknown Artist',
      album: album,
      duration:
          durationMs != null ? Duration(milliseconds: durationMs) : null,
      path: data,
      isLocal: true,
    );
  }

  factory SongModel.fromYouTube({
    required String videoId,
    required String title,
    required String artist,
    Duration? duration,
    required String thumbnailUrl,
    int? viewCount,
  }) {
    return SongModel(
      id: videoId.hashCode,
      title: title,
      artist: artist,
      duration: duration,
      path: '', // Resolved at play time via youtube_explode
      isLocal: false,
      thumbnailUrl: thumbnailUrl,
      viewCount: viewCount,
      videoId: videoId,
    );
  }
}
