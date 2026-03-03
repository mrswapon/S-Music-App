import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/repositories/music_repository.dart';
import '../../data/repositories/youtube_repository.dart';
import 'music_player_event.dart';
import 'music_player_state.dart';

class MusicPlayerBloc extends Bloc<MusicPlayerEvent, MusicPlayerState> {
  final MusicRepository _repository;
  final YouTubeRepository _youtubeRepository;
  final AudioPlayer _audioPlayer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  MusicPlayerBloc({
    required MusicRepository repository,
    required YouTubeRepository youtubeRepository,
    AudioPlayer? audioPlayer,
  })  : _repository = repository,
        _youtubeRepository = youtubeRepository,
        _audioPlayer = audioPlayer ?? AudioPlayer(),
        super(const MusicPlayerState()) {
    on<LoadSongs>(_onLoadSongs);
    on<PlaySong>(_onPlaySong);
    on<PauseSong>(_onPauseSong);
    on<ResumeSong>(_onResumeSong);
    on<StopSong>(_onStopSong);
    on<SeekTo>(_onSeekTo);
    on<NextSong>(_onNextSong);
    on<PreviousSong>(_onPreviousSong);
    on<ToggleShuffle>(_onToggleShuffle);
    on<ToggleRepeat>(_onToggleRepeat);
    on<UpdatePosition>(_onUpdatePosition);

    _listenToPlayerStreams();
  }

  void _listenToPlayerStreams() {
    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      add(UpdatePosition(position, duration: _audioPlayer.duration));
    });

    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        add(UpdatePosition(state.position, duration: duration));
      }
    });

    _playerStateSubscription =
        _audioPlayer.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _onTrackComplete();
      }
    });
  }

  void _onTrackComplete() {
    final playlist = state.activePlaylist;
    if (state.repeatMode == RepeatMode.one) {
      if (state.currentSong != null) {
        add(PlaySong(state.currentSong!, playlist: playlist));
      }
    } else if (state.repeatMode == RepeatMode.all ||
        _getCurrentIndex() < playlist.length - 1) {
      add(const NextSong());
    } else {
      add(const StopSong());
    }
  }

  Future<void> _onLoadSongs(
      LoadSongs event, Emitter<MusicPlayerState> emit) async {
    emit(state.copyWith(status: PlayerStatus.loading));
    try {
      final songs = await _repository.getAllSongs();
      emit(state.copyWith(
        songs: songs,
        status: PlayerStatus.loaded,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Failed to load songs: ${e.toString()}',
      ));
    }
  }

  Future<void> _onPlaySong(
      PlaySong event, Emitter<MusicPlayerState> emit) async {
    final playlist = event.playlist ?? state.activePlaylist;
    emit(state.copyWith(
      currentSong: event.song,
      activePlaylist: playlist.isNotEmpty ? playlist : [event.song],
      status: PlayerStatus.loading,
      position: Duration.zero,
      duration: Duration.zero,
    ));

    try {
      if (event.song.isLocal) {
        debugPrint('[Player] Playing local: ${event.song.path}');
        await _audioPlayer.setFilePath(event.song.path);
      } else if (event.song.isYouTube) {
        await _setYouTubeSource(event.song.videoId!);
      } else {
        debugPrint('[Player] Playing URL: ${event.song.path}');
        await _audioPlayer.setUrl(event.song.path);
      }

      await _audioPlayer.play();

      emit(state.copyWith(
        status: PlayerStatus.playing,
        duration: _audioPlayer.duration ?? Duration.zero,
      ));
    } catch (e) {
      debugPrint('[Player] FINAL ERROR: $e');
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Failed to play: ${e.toString()}',
      ));
    }
  }

  /// Tries multiple strategies to set up a YouTube audio source.
  /// Strategy 1: Direct CDN URL → ExoPlayer (fastest, uses native HTTP)
  /// Strategy 2: Proxy via youtube_explode's stream client
  /// Strategy 3: Refresh client + direct CDN URL (fresh session)
  Future<void> _setYouTubeSource(String videoId) async {
    // Strategy 1: Direct CDN URL to ExoPlayer
    try {
      debugPrint('[Player] Strategy 1: Direct CDN URL');
      final directUrl =
          await _youtubeRepository.getDirectStreamUrl(videoId);
      await _audioPlayer.setUrl(directUrl);
      debugPrint('[Player] Strategy 1 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Strategy 1 failed: $e');
    }

    // Strategy 2: Localhost proxy (youtube_explode downloads)
    try {
      debugPrint('[Player] Strategy 2: Proxy via youtube_explode');
      final proxyUrl =
          await _youtubeRepository.getProxiedStreamUrl(videoId);
      await _audioPlayer.setUrl(proxyUrl);
      debugPrint('[Player] Strategy 2 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Strategy 2 failed: $e');
    }

    // Strategy 3: Fresh client + direct URL with browser headers
    try {
      debugPrint('[Player] Strategy 3: Fresh client + headers');
      _youtubeRepository.refreshClient();
      await Future.delayed(const Duration(seconds: 1));
      final freshUrl =
          await _youtubeRepository.getDirectStreamUrl(videoId);
      await _audioPlayer.setUrl(
        freshUrl,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
      );
      debugPrint('[Player] Strategy 3 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Strategy 3 failed: $e');
    }

    throw Exception('All playback strategies failed for $videoId');
  }

  Future<void> _onPauseSong(
      PauseSong event, Emitter<MusicPlayerState> emit) async {
    await _audioPlayer.pause();
    emit(state.copyWith(status: PlayerStatus.paused));
  }

  Future<void> _onResumeSong(
      ResumeSong event, Emitter<MusicPlayerState> emit) async {
    await _audioPlayer.play();
    emit(state.copyWith(status: PlayerStatus.playing));
  }

  Future<void> _onStopSong(
      StopSong event, Emitter<MusicPlayerState> emit) async {
    await _audioPlayer.stop();
    emit(state.copyWith(
      status: PlayerStatus.stopped,
      position: Duration.zero,
    ));
  }

  Future<void> _onSeekTo(
      SeekTo event, Emitter<MusicPlayerState> emit) async {
    await _audioPlayer.seek(event.position);
    emit(state.copyWith(position: event.position));
  }

  Future<void> _onNextSong(
      NextSong event, Emitter<MusicPlayerState> emit) async {
    final playlist = state.activePlaylist;
    if (playlist.isEmpty) return;

    int nextIndex;
    if (state.isShuffleOn) {
      nextIndex = Random().nextInt(playlist.length);
    } else {
      nextIndex = (_getCurrentIndex() + 1) % playlist.length;
    }

    add(PlaySong(playlist[nextIndex]));
  }

  Future<void> _onPreviousSong(
      PreviousSong event, Emitter<MusicPlayerState> emit) async {
    final playlist = state.activePlaylist;
    if (playlist.isEmpty) return;

    if (state.position.inSeconds > 3) {
      add(SeekTo(Duration.zero));
      return;
    }

    int prevIndex;
    if (state.isShuffleOn) {
      prevIndex = Random().nextInt(playlist.length);
    } else {
      prevIndex = _getCurrentIndex() - 1;
      if (prevIndex < 0) prevIndex = playlist.length - 1;
    }

    add(PlaySong(playlist[prevIndex]));
  }

  void _onToggleShuffle(
      ToggleShuffle event, Emitter<MusicPlayerState> emit) {
    emit(state.copyWith(isShuffleOn: !state.isShuffleOn));
  }

  void _onToggleRepeat(
      ToggleRepeat event, Emitter<MusicPlayerState> emit) {
    final nextMode = switch (state.repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    emit(state.copyWith(repeatMode: nextMode));
  }

  void _onUpdatePosition(
      UpdatePosition event, Emitter<MusicPlayerState> emit) {
    emit(state.copyWith(
      position: event.position,
      duration: event.duration ?? state.duration,
    ));
  }

  int _getCurrentIndex() {
    if (state.currentSong == null) return 0;
    final playlist = state.activePlaylist;
    final index = playlist.indexOf(state.currentSong!);
    return index >= 0 ? index : 0;
  }

  @override
  Future<void> close() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    return super.close();
  }
}
