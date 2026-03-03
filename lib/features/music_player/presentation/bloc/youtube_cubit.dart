import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/youtube_repository.dart';
import '../../domain/entities/song.dart';

enum YouTubeLoadingStatus { initial, loading, loaded, error }

class YouTubeState extends Equatable {
  final List<Song> trendingSongs;
  final List<Song> viralSongs;
  final YouTubeLoadingStatus trendingStatus;
  final YouTubeLoadingStatus viralStatus;
  final String? errorMessage;

  const YouTubeState({
    this.trendingSongs = const [],
    this.viralSongs = const [],
    this.trendingStatus = YouTubeLoadingStatus.initial,
    this.viralStatus = YouTubeLoadingStatus.initial,
    this.errorMessage,
  });

  YouTubeState copyWith({
    List<Song>? trendingSongs,
    List<Song>? viralSongs,
    YouTubeLoadingStatus? trendingStatus,
    YouTubeLoadingStatus? viralStatus,
    String? errorMessage,
  }) {
    return YouTubeState(
      trendingSongs: trendingSongs ?? this.trendingSongs,
      viralSongs: viralSongs ?? this.viralSongs,
      trendingStatus: trendingStatus ?? this.trendingStatus,
      viralStatus: viralStatus ?? this.viralStatus,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        trendingSongs,
        viralSongs,
        trendingStatus,
        viralStatus,
        errorMessage,
      ];
}

class YouTubeCubit extends Cubit<YouTubeState> {
  final YouTubeRepository _repository;

  YouTubeCubit({required YouTubeRepository repository})
      : _repository = repository,
        super(const YouTubeState());

  Future<void> loadTrending() async {
    emit(state.copyWith(trendingStatus: YouTubeLoadingStatus.loading));
    try {
      final songs = await _repository.getTrendingSongs();
      emit(state.copyWith(
        trendingSongs: songs,
        trendingStatus: YouTubeLoadingStatus.loaded,
      ));
    } catch (e) {
      emit(state.copyWith(
        trendingStatus: YouTubeLoadingStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> loadViral() async {
    emit(state.copyWith(viralStatus: YouTubeLoadingStatus.loading));
    try {
      final songs = await _repository.getViralSongs();
      emit(state.copyWith(
        viralSongs: songs,
        viralStatus: YouTubeLoadingStatus.loaded,
      ));
    } catch (e) {
      emit(state.copyWith(
        viralStatus: YouTubeLoadingStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> loadAll() async {
    await Future.wait([loadTrending(), loadViral()]);
  }
}
