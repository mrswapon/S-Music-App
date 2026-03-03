import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

import 'package:s_music/features/music_player/data/repositories/music_repository.dart';
import 'package:s_music/features/music_player/data/repositories/youtube_repository.dart';
import 'package:s_music/features/music_player/domain/entities/song.dart';
import 'package:s_music/features/music_player/presentation/bloc/music_player_bloc.dart';
import 'package:s_music/features/music_player/presentation/bloc/music_player_event.dart';
import 'package:s_music/features/music_player/presentation/bloc/music_player_state.dart';
import 'package:s_music/features/music_player/presentation/bloc/theme_cubit.dart';

class MockMusicRepository extends Mock implements MusicRepository {}

class MockYouTubeRepository extends Mock implements YouTubeRepository {}

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMusicRepository mockRepository;
  late MockYouTubeRepository mockYouTubeRepository;
  late MockAudioPlayer mockAudioPlayer;

  const testSongs = [
    Song(
      id: 1,
      title: 'Test Song 1',
      artist: 'Test Artist 1',
      path: 'https://example.com/song1.mp3',
      isLocal: false,
    ),
    Song(
      id: 2,
      title: 'Test Song 2',
      artist: 'Test Artist 2',
      path: 'https://example.com/song2.mp3',
      isLocal: false,
    ),
  ];

  MusicPlayerBloc buildBloc() => MusicPlayerBloc(
        repository: mockRepository,
        youtubeRepository: mockYouTubeRepository,
        audioPlayer: mockAudioPlayer,
      );

  setUp(() {
    mockRepository = MockMusicRepository();
    mockYouTubeRepository = MockYouTubeRepository();
    mockAudioPlayer = MockAudioPlayer();

    when(() => mockAudioPlayer.positionStream)
        .thenAnswer((_) => Stream<Duration>.empty());
    when(() => mockAudioPlayer.durationStream)
        .thenAnswer((_) => Stream<Duration?>.empty());
    when(() => mockAudioPlayer.playerStateStream)
        .thenAnswer((_) => Stream<PlayerState>.empty());
    when(() => mockAudioPlayer.duration).thenReturn(null);
    when(() => mockAudioPlayer.dispose()).thenAnswer((_) async {});
  });

  group('MusicPlayerBloc', () {
    test('initial state is correct', () {
      final bloc = buildBloc();

      expect(bloc.state, const MusicPlayerState());
      expect(bloc.state.status, PlayerStatus.initial);
      expect(bloc.state.songs, isEmpty);
      expect(bloc.state.currentSong, isNull);

      bloc.close();
    });

    blocTest<MusicPlayerBloc, MusicPlayerState>(
      'emits [loading, loaded] when LoadSongs succeeds',
      setUp: () {
        when(() => mockRepository.getAllSongs())
            .thenAnswer((_) async => testSongs);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const LoadSongs()),
      expect: () => [
        const MusicPlayerState(status: PlayerStatus.loading),
        const MusicPlayerState(
          status: PlayerStatus.loaded,
          songs: testSongs,
        ),
      ],
      verify: (_) {
        verify(() => mockRepository.getAllSongs()).called(1);
      },
    );

    blocTest<MusicPlayerBloc, MusicPlayerState>(
      'emits [loading, error] when LoadSongs fails',
      setUp: () {
        when(() => mockRepository.getAllSongs())
            .thenThrow(Exception('Network error'));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const LoadSongs()),
      expect: () => [
        const MusicPlayerState(status: PlayerStatus.loading),
        isA<MusicPlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.error)
            .having(
                (s) => s.errorMessage, 'errorMessage', contains('Network')),
      ],
    );

    blocTest<MusicPlayerBloc, MusicPlayerState>(
      'toggleShuffle toggles shuffle state',
      build: buildBloc,
      act: (bloc) {
        bloc.add(const ToggleShuffle());
        bloc.add(const ToggleShuffle());
      },
      expect: () => [
        const MusicPlayerState(isShuffleOn: true),
        const MusicPlayerState(isShuffleOn: false),
      ],
    );

    blocTest<MusicPlayerBloc, MusicPlayerState>(
      'toggleRepeat cycles through repeat modes',
      build: buildBloc,
      act: (bloc) {
        bloc.add(const ToggleRepeat());
        bloc.add(const ToggleRepeat());
        bloc.add(const ToggleRepeat());
      },
      expect: () => [
        const MusicPlayerState(repeatMode: RepeatMode.all),
        const MusicPlayerState(repeatMode: RepeatMode.one),
        const MusicPlayerState(repeatMode: RepeatMode.off),
      ],
    );

    blocTest<MusicPlayerBloc, MusicPlayerState>(
      'PauseSong pauses playback',
      seed: () => const MusicPlayerState(
        status: PlayerStatus.playing,
        currentSong: Song(
          id: 1,
          title: 'Test',
          artist: 'Artist',
          path: 'test.mp3',
          isLocal: false,
        ),
      ),
      setUp: () {
        when(() => mockAudioPlayer.pause()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const PauseSong()),
      expect: () => [
        isA<MusicPlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.paused),
      ],
    );

    blocTest<MusicPlayerBloc, MusicPlayerState>(
      'ResumeSong resumes playback',
      seed: () => const MusicPlayerState(
        status: PlayerStatus.paused,
        currentSong: Song(
          id: 1,
          title: 'Test',
          artist: 'Artist',
          path: 'test.mp3',
          isLocal: false,
        ),
      ),
      setUp: () {
        when(() => mockAudioPlayer.play()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const ResumeSong()),
      expect: () => [
        isA<MusicPlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.playing),
      ],
    );

    blocTest<MusicPlayerBloc, MusicPlayerState>(
      'StopSong stops playback and resets position',
      seed: () => const MusicPlayerState(
        status: PlayerStatus.playing,
        position: Duration(seconds: 30),
        currentSong: Song(
          id: 1,
          title: 'Test',
          artist: 'Artist',
          path: 'test.mp3',
          isLocal: false,
        ),
      ),
      setUp: () {
        when(() => mockAudioPlayer.stop()).thenAnswer((_) async {});
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StopSong()),
      expect: () => [
        isA<MusicPlayerState>()
            .having((s) => s.status, 'status', PlayerStatus.stopped)
            .having((s) => s.position, 'position', Duration.zero),
      ],
    );

    test('YouTube song has correct isYouTube flag', () {
      const ytSong = Song(
        id: 100,
        title: 'YouTube Song',
        artist: 'Artist',
        path: '',
        isLocal: false,
        videoId: 'abc123',
        thumbnailUrl: 'https://img.youtube.com/vi/abc123/hqdefault.jpg',
        viewCount: 1000000,
      );
      expect(ytSong.isYouTube, isTrue);
      expect(ytSong.viewCount, 1000000);
      expect(ytSong.thumbnailUrl, isNotNull);
    });
  });

  group('ThemeCubit', () {
    blocTest<ThemeCubit, ThemeMode>(
      'toggleTheme switches between dark and light',
      build: () => ThemeCubit(),
      act: (cubit) {
        cubit.toggleTheme();
        cubit.toggleTheme();
      },
      expect: () => [
        ThemeMode.light,
        ThemeMode.dark,
      ],
    );

    test('initial state is dark', () {
      final cubit = ThemeCubit();
      expect(cubit.state, ThemeMode.dark);
      expect(cubit.isDark, isTrue);
      cubit.close();
    });
  });

  group('Song entity', () {
    test('equality works correctly', () {
      const song1 = Song(
        id: 1,
        title: 'Test',
        artist: 'Artist',
        path: '/test.mp3',
        isLocal: true,
      );
      const song2 = Song(
        id: 1,
        title: 'Test',
        artist: 'Artist',
        path: '/test.mp3',
        isLocal: true,
      );
      const song3 = Song(
        id: 2,
        title: 'Different',
        artist: 'Artist',
        path: '/test2.mp3',
        isLocal: false,
      );

      expect(song1, equals(song2));
      expect(song1, isNot(equals(song3)));
    });

    test('local song is not YouTube', () {
      const song = Song(
        id: 1,
        title: 'Local',
        artist: 'Artist',
        path: '/music/song.mp3',
        isLocal: true,
      );
      expect(song.isYouTube, isFalse);
      expect(song.videoId, isNull);
    });
  });
}
