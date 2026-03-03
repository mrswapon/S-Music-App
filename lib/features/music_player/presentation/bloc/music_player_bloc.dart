import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

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

  VideoPlayerController? _videoController;
  VideoPlayerController? get videoController => _videoController;
  bool _videoCompleted = false;

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
      if (!state.isVideoMode) {
        add(UpdatePosition(position, duration: _audioPlayer.duration));
      }
    });

    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (!state.isVideoMode && duration != null) {
        add(UpdatePosition(state.position, duration: duration));
      }
    });

    _playerStateSubscription =
        _audioPlayer.playerStateStream.listen((playerState) {
      if (!state.isVideoMode &&
          playerState.processingState == ProcessingState.completed) {
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
      isVideoMode: false,
    ));

    try {
      if (event.song.isLocal) {
        // Local file — audio only
        await _disposeVideoController();
        debugPrint('[Player] Playing local: ${event.song.path}');
        await _audioPlayer.setFilePath(event.song.path);
        await _audioPlayer.play();
        emit(state.copyWith(
          status: PlayerStatus.playing,
          duration: _audioPlayer.duration ?? Duration.zero,
          isVideoMode: false,
        ));
      } else if (event.song.isYouTube) {
        // YouTube — try video first
        await _audioPlayer.stop();
        await _setYouTubeVideoSource(event.song.videoId!, emit);
      } else {
        await _disposeVideoController();
        debugPrint('[Player] Playing URL: ${event.song.path}');
        await _audioPlayer.setUrl(event.song.path);
        await _audioPlayer.play();
        emit(state.copyWith(
          status: PlayerStatus.playing,
          duration: _audioPlayer.duration ?? Duration.zero,
          isVideoMode: false,
        ));
      }
    } catch (e) {
      debugPrint('[Player] FINAL ERROR: $e');
      emit(state.copyWith(
        status: PlayerStatus.error,
        errorMessage: 'Failed to play: ${e.toString()}',
      ));
    }
  }

  /// Tries multiple strategies to set up a YouTube video source.
  ///
  /// Strategy 1: Piped muxed video stream
  /// Strategy 2: Invidious muxed video stream
  /// Strategy 3: youtube_explode muxed proxy
  ///
  /// If all video strategies fail, falls back to audio-only.
  Future<void> _setYouTubeVideoSource(
      String videoId, Emitter<MusicPlayerState> emit) async {
    // Strategy 1: Piped muxed video stream
    try {
      debugPrint('[Player] Video Strategy 1: Piped muxed');
      final url = await _youtubeRepository.getPipedVideoStreamUrl(videoId);
      await _initVideoController(Uri.parse(url), emit);
      debugPrint('[Player] Video Strategy 1 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Video Strategy 1 failed: $e');
    }

    // Strategy 2: Invidious muxed video stream
    try {
      debugPrint('[Player] Video Strategy 2: Invidious muxed');
      final url =
          await _youtubeRepository.getInvidiousVideoStreamUrl(videoId);
      await _initVideoController(Uri.parse(url), emit);
      debugPrint('[Player] Video Strategy 2 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Video Strategy 2 failed: $e');
    }

    // Strategy 3: youtube_explode muxed proxy
    try {
      debugPrint('[Player] Video Strategy 3: youtube_explode muxed proxy');
      _youtubeRepository.refreshClient();
      final streamInfo =
          await _youtubeRepository.getMuxedStreamInfo(videoId);
      final proxyUrl =
          await _youtubeRepository.getProxiedStreamUrl(streamInfo);
      await _initVideoController(Uri.parse(proxyUrl), emit);
      debugPrint('[Player] Video Strategy 3 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Video Strategy 3 failed: $e');
    }

    // Fallback: audio-only via original strategies
    debugPrint('[Player] All video strategies failed, falling back to audio');
    await _setYouTubeAudioSource(videoId, emit);
  }

  /// Audio-only fallback for YouTube.
  Future<void> _setYouTubeAudioSource(
      String videoId, Emitter<MusicPlayerState> emit) async {
    await _disposeVideoController();

    // Strategy 1: Piped audio
    try {
      debugPrint('[Player] Audio Strategy 1: Piped API');
      final pipedUrl = await _youtubeRepository.getPipedStreamUrl(videoId);
      await _audioPlayer.setUrl(pipedUrl);
      await _audioPlayer.play();
      emit(state.copyWith(
        status: PlayerStatus.playing,
        duration: _audioPlayer.duration ?? Duration.zero,
        isVideoMode: false,
      ));
      debugPrint('[Player] Audio Strategy 1 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Audio Strategy 1 failed: $e');
    }

    // Strategy 2: Invidious audio
    try {
      debugPrint('[Player] Audio Strategy 2: Invidious API');
      final invUrl =
          await _youtubeRepository.getInvidiousStreamUrl(videoId);
      await _audioPlayer.setUrl(invUrl);
      await _audioPlayer.play();
      emit(state.copyWith(
        status: PlayerStatus.playing,
        duration: _audioPlayer.duration ?? Duration.zero,
        isVideoMode: false,
      ));
      debugPrint('[Player] Audio Strategy 2 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Audio Strategy 2 failed: $e');
    }

    // Strategy 3: youtube_explode proxy
    try {
      debugPrint('[Player] Audio Strategy 3: youtube_explode proxy');
      _youtubeRepository.refreshClient();
      final streamInfo = await _youtubeRepository.getStreamInfo(videoId);
      final proxyUrl =
          await _youtubeRepository.getProxiedStreamUrl(streamInfo);
      await _audioPlayer.setUrl(proxyUrl);
      await _audioPlayer.play();
      emit(state.copyWith(
        status: PlayerStatus.playing,
        duration: _audioPlayer.duration ?? Duration.zero,
        isVideoMode: false,
      ));
      debugPrint('[Player] Audio Strategy 3 SUCCESS');
      return;
    } catch (e) {
      debugPrint('[Player] Audio Strategy 3 failed: $e');
    }

    throw Exception('All playback strategies failed for $videoId');
  }

  /// Creates and initializes a VideoPlayerController from a network URI.
  Future<void> _initVideoController(
      Uri uri, Emitter<MusicPlayerState> emit) async {
    await _disposeVideoController();

    _videoCompleted = false;
    _videoController = VideoPlayerController.networkUrl(uri);
    await _videoController!.initialize();
    _videoController!.addListener(_onVideoControllerUpdate);
    await _videoController!.play();

    emit(state.copyWith(
      status: PlayerStatus.playing,
      duration: _videoController!.value.duration,
      isVideoMode: true,
    ));
  }

  void _onVideoControllerUpdate() {
    final controller = _videoController;
    if (controller == null) return;

    final value = controller.value;
    if (value.hasError) {
      debugPrint('[Player] Video error: ${value.errorDescription}');
      return;
    }

    add(UpdatePosition(value.position, duration: value.duration));

    // Track completion (guard against double-fire)
    if (!_videoCompleted &&
        value.position >= value.duration &&
        value.duration > Duration.zero &&
        !value.isPlaying) {
      _videoCompleted = true;
      _onTrackComplete();
    }
  }

  Future<void> _disposeVideoController() async {
    if (_videoController != null) {
      _videoController!.removeListener(_onVideoControllerUpdate);
      await _videoController!.dispose();
      _videoController = null;
    }
  }

  Future<void> _onPauseSong(
      PauseSong event, Emitter<MusicPlayerState> emit) async {
    if (state.isVideoMode && _videoController != null) {
      await _videoController!.pause();
    } else {
      await _audioPlayer.pause();
    }
    emit(state.copyWith(status: PlayerStatus.paused));
  }

  Future<void> _onResumeSong(
      ResumeSong event, Emitter<MusicPlayerState> emit) async {
    if (state.isVideoMode && _videoController != null) {
      await _videoController!.play();
    } else {
      await _audioPlayer.play();
    }
    emit(state.copyWith(status: PlayerStatus.playing));
  }

  Future<void> _onStopSong(
      StopSong event, Emitter<MusicPlayerState> emit) async {
    if (state.isVideoMode && _videoController != null) {
      await _videoController!.pause();
      await _videoController!.seekTo(Duration.zero);
    } else {
      await _audioPlayer.stop();
    }
    emit(state.copyWith(
      status: PlayerStatus.stopped,
      position: Duration.zero,
    ));
  }

  Future<void> _onSeekTo(
      SeekTo event, Emitter<MusicPlayerState> emit) async {
    if (state.isVideoMode && _videoController != null) {
      await _videoController!.seekTo(event.position);
    } else {
      await _audioPlayer.seek(event.position);
    }
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
  Future<void> close() async {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    await _disposeVideoController();
    return super.close();
  }
}
