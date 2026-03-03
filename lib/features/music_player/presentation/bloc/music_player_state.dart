import 'package:equatable/equatable.dart';

import '../../domain/entities/song.dart';

enum PlayerStatus { initial, loading, loaded, playing, paused, stopped, error }

enum RepeatMode { off, one, all }

class MusicPlayerState extends Equatable {
  final List<Song> songs;
  final List<Song> activePlaylist;
  final Song? currentSong;
  final PlayerStatus status;
  final Duration position;
  final Duration duration;
  final String? errorMessage;
  final bool isShuffleOn;
  final RepeatMode repeatMode;
  final bool isVideoMode;

  const MusicPlayerState({
    this.songs = const [],
    this.activePlaylist = const [],
    this.currentSong,
    this.status = PlayerStatus.initial,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.errorMessage,
    this.isShuffleOn = false,
    this.repeatMode = RepeatMode.off,
    this.isVideoMode = false,
  });

  MusicPlayerState copyWith({
    List<Song>? songs,
    List<Song>? activePlaylist,
    Song? currentSong,
    PlayerStatus? status,
    Duration? position,
    Duration? duration,
    String? errorMessage,
    bool? isShuffleOn,
    RepeatMode? repeatMode,
    bool? isVideoMode,
  }) {
    return MusicPlayerState(
      songs: songs ?? this.songs,
      activePlaylist: activePlaylist ?? this.activePlaylist,
      currentSong: currentSong ?? this.currentSong,
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: errorMessage ?? this.errorMessage,
      isShuffleOn: isShuffleOn ?? this.isShuffleOn,
      repeatMode: repeatMode ?? this.repeatMode,
      isVideoMode: isVideoMode ?? this.isVideoMode,
    );
  }

  @override
  List<Object?> get props => [
        songs,
        activePlaylist,
        currentSong,
        status,
        position,
        duration,
        errorMessage,
        isShuffleOn,
        repeatMode,
        isVideoMode,
      ];
}
