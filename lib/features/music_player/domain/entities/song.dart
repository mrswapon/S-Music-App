import 'package:equatable/equatable.dart';

class Song extends Equatable {
  final int id;
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;
  final String path;
  final bool isLocal;
  final String? thumbnailUrl;
  final int? viewCount;
  final String? videoId;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    required this.path,
    required this.isLocal,
    this.thumbnailUrl,
    this.viewCount,
    this.videoId,
  });

  bool get isYouTube => videoId != null;

  @override
  List<Object?> get props => [
        id,
        title,
        artist,
        album,
        duration,
        path,
        isLocal,
        thumbnailUrl,
        viewCount,
        videoId,
      ];
}
