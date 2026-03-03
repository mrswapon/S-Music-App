import 'package:equatable/equatable.dart';

import '../../domain/entities/song.dart';

sealed class MusicPlayerEvent extends Equatable {
  const MusicPlayerEvent();

  @override
  List<Object?> get props => [];
}

class LoadSongs extends MusicPlayerEvent {
  const LoadSongs();
}

class PlaySong extends MusicPlayerEvent {
  final Song song;
  final List<Song>? playlist;

  const PlaySong(this.song, {this.playlist});

  @override
  List<Object?> get props => [song, playlist];
}

class PauseSong extends MusicPlayerEvent {
  const PauseSong();
}

class ResumeSong extends MusicPlayerEvent {
  const ResumeSong();
}

class StopSong extends MusicPlayerEvent {
  const StopSong();
}

class SeekTo extends MusicPlayerEvent {
  final Duration position;

  const SeekTo(this.position);

  @override
  List<Object?> get props => [position];
}

class NextSong extends MusicPlayerEvent {
  const NextSong();
}

class PreviousSong extends MusicPlayerEvent {
  const PreviousSong();
}

class ToggleShuffle extends MusicPlayerEvent {
  const ToggleShuffle();
}

class ToggleRepeat extends MusicPlayerEvent {
  const ToggleRepeat();
}

class UpdatePosition extends MusicPlayerEvent {
  final Duration position;
  final Duration? duration;

  const UpdatePosition(this.position, {this.duration});

  @override
  List<Object?> get props => [position, duration];
}
