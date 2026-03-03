import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'features/music_player/data/repositories/music_repository.dart';
import 'features/music_player/data/repositories/youtube_repository.dart';
import 'features/music_player/presentation/bloc/music_player_bloc.dart';
import 'features/music_player/presentation/bloc/music_player_event.dart';
import 'features/music_player/presentation/bloc/theme_cubit.dart';
import 'features/music_player/presentation/bloc/youtube_cubit.dart';
import 'features/music_player/presentation/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SMusicApp());
}

class SMusicApp extends StatelessWidget {
  const SMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final youtubeRepository = YouTubeRepository();

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => MusicPlayerBloc(
            repository: MusicRepository(),
            youtubeRepository: youtubeRepository,
          )..add(const LoadSongs()),
        ),
        BlocProvider(
          create: (_) => YouTubeCubit(
            repository: youtubeRepository,
          )..loadAll(),
        ),
        BlocProvider(
          create: (_) => ThemeCubit(),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: 'S Music',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            themeAnimationDuration: const Duration(milliseconds: 300),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
