import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/spin_button.dart';
import '../../domain/entities/song.dart';
import '../bloc/music_player_bloc.dart';
import '../bloc/music_player_event.dart';
import '../bloc/music_player_state.dart';
import '../bloc/theme_cubit.dart';
import '../bloc/youtube_cubit.dart';
import '../widgets/mini_player.dart';
import '../widgets/shimmer_list.dart';
import '../widgets/song_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentTab = 0;
  late AnimationController _tabAnimCtrl;
  late Animation<double> _tabFade;

  static const _tabs = [
    _TabInfo(Icons.trending_up, 'Trending'),
    _TabInfo(Icons.local_fire_department, 'Viral'),
    _TabInfo(Icons.phone_android, 'My Music'),
  ];

  @override
  void initState() {
    super.initState();
    _tabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _tabFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _tabAnimCtrl, curve: Curves.easeOut),
    );
    _tabAnimCtrl.forward();
  }

  @override
  void dispose() {
    _tabAnimCtrl.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    if (index == _currentTab) return;
    _tabAnimCtrl.reverse().then((_) {
      setState(() => _currentTab = index);
      _tabAnimCtrl.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MusicPlayerBloc, MusicPlayerState>(
      listenWhen: (prev, curr) =>
          curr.status == PlayerStatus.error &&
          prev.status != PlayerStatus.error,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              state.errorMessage ?? 'Failed to play song',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      },
      child: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: FadeTransition(
              opacity: _tabFade,
              child: IndexedStack(
                index: _currentTab,
                children: const [
                  _TrendingTab(),
                  _ViralTab(),
                  _DeviceMusicTab(),
                ],
              ),
            ),
          ),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: _switchTab,
        animationDuration: const Duration(milliseconds: 400),
        indicatorColor: AppTheme.primaryColor.withValues(alpha: 0.2),
        destinations: _tabs
            .map((tab) => NavigationDestination(
                  icon: Icon(tab.icon),
                  selectedIcon:
                      Icon(tab.icon, color: AppTheme.primaryColor),
                  label: tab.label,
                ))
            .toList(),
      ),
    ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo(this.icon, this.label);
}

// ─── Trending Tab ────────────────────────────────────────────

class _TrendingTab extends StatelessWidget {
  const _TrendingTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<YouTubeCubit, YouTubeState>(
      builder: (context, ytState) {
        return CustomScrollView(
          slivers: [
            _buildAppBar(
              context,
              title: 'Trending',
              subtitle: 'Hot tracks right now',
              icon: Icons.trending_up,
              onRefresh: () => context.read<YouTubeCubit>().loadTrending(),
            ),
            _buildYouTubeList(
              context,
              songs: ytState.trendingSongs,
              status: ytState.trendingStatus,
              onRetry: () => context.read<YouTubeCubit>().loadTrending(),
              emptyMessage: 'No trending songs found',
            ),
          ],
        );
      },
    );
  }
}

// ─── Viral Tab ───────────────────────────────────────────────

class _ViralTab extends StatelessWidget {
  const _ViralTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<YouTubeCubit, YouTubeState>(
      builder: (context, ytState) {
        return CustomScrollView(
          slivers: [
            _buildAppBar(
              context,
              title: 'Viral',
              subtitle: 'Going viral everywhere',
              icon: Icons.local_fire_department,
              onRefresh: () => context.read<YouTubeCubit>().loadViral(),
            ),
            _buildYouTubeList(
              context,
              songs: ytState.viralSongs,
              status: ytState.viralStatus,
              onRetry: () => context.read<YouTubeCubit>().loadViral(),
              emptyMessage: 'No viral songs found',
            ),
          ],
        );
      },
    );
  }
}

// ─── Device Music Tab ────────────────────────────────────────

class _DeviceMusicTab extends StatelessWidget {
  const _DeviceMusicTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MusicPlayerBloc, MusicPlayerState>(
      builder: (context, state) {
        return CustomScrollView(
          slivers: [
            _buildAppBar(
              context,
              title: 'My Music',
              subtitle: 'From your device',
              icon: Icons.library_music,
              onRefresh: () =>
                  context.read<MusicPlayerBloc>().add(const LoadSongs()),
            ),
            _buildDeviceList(context, state),
          ],
        );
      },
    );
  }
}

// ─── Shared Widgets ──────────────────────────────────────────

SliverAppBar _buildAppBar(
  BuildContext context, {
  required String title,
  required String subtitle,
  required IconData icon,
  required VoidCallback onRefresh,
}) {
  return SliverAppBar(
    expandedHeight: 130,
    floating: false,
    pinned: true,
    backgroundColor: AppTheme.primaryColor,
    flexibleSpace: FlexibleSpaceBar(
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontSize: 20,
        ),
      ),
      background: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryColor,
              AppTheme.primaryColor.withValues(alpha: 0.7),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: 20,
              child: Icon(icon, color: Colors.white12, size: 120),
            ),
            Positioned(
              left: 16,
              bottom: 52,
              child: Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return IconButton(
            onPressed: () => context.read<ThemeCubit>().toggleTheme(),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  RotationTransition(turns: animation, child: child),
              child: Icon(
                themeMode == ThemeMode.dark
                    ? Icons.light_mode
                    : Icons.dark_mode,
                key: ValueKey(themeMode),
                color: Colors.white,
              ),
            ),
            tooltip: 'Toggle theme',
          );
        },
      ),
      SpinButton(
        icon: Icons.refresh,
        size: 24,
        color: Colors.white,
        onPressed: onRefresh,
        tooltip: 'Refresh',
      ),
    ],
  );
}

Widget _buildYouTubeList(
  BuildContext context, {
  required List<Song> songs,
  required YouTubeLoadingStatus status,
  required VoidCallback onRetry,
  required String emptyMessage,
}) {
  if (status == YouTubeLoadingStatus.loading ||
      status == YouTubeLoadingStatus.initial) {
    return const SliverToBoxAdapter(child: ShimmerSongList());
  }

  if (status == YouTubeLoadingStatus.error) {
    return SliverFillRemaining(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Failed to load songs.\nCheck your internet connection.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  if (songs.isEmpty) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  return BlocBuilder<MusicPlayerBloc, MusicPlayerState>(
    builder: (context, playerState) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = songs[index];
            final isCurrentSong = playerState.currentSong == song;
            final isPlaying =
                isCurrentSong && playerState.status == PlayerStatus.playing;
            final isLoading =
                isCurrentSong && playerState.status == PlayerStatus.loading;

            return SongTile(
              song: song,
              index: index,
              isPlaying: isPlaying,
              isCurrentSong: isCurrentSong,
              isLoading: isLoading,
              onTap: () => _playSong(context, song, songs),
              onPlayPause: () {
                if (isCurrentSong && isPlaying) {
                  context.read<MusicPlayerBloc>().add(const PauseSong());
                } else if (isCurrentSong) {
                  context.read<MusicPlayerBloc>().add(const ResumeSong());
                } else {
                  _playSong(context, song, songs);
                }
              },
            );
          },
          childCount: songs.length,
        ),
      );
    },
  );
}

Widget _buildDeviceList(BuildContext context, MusicPlayerState state) {
  if (state.status == PlayerStatus.initial) {
    return const SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off, size: 56, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Tap refresh to scan your device',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  if (state.status == PlayerStatus.loading && state.songs.isEmpty) {
    return const SliverToBoxAdapter(child: ShimmerSongList());
  }

  if (state.status == PlayerStatus.error && state.songs.isEmpty) {
    return SliverFillRemaining(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                state.errorMessage ?? 'An error occurred',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () =>
                    context.read<MusicPlayerBloc>().add(const LoadSongs()),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  if (state.songs.isEmpty) {
    return const SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off, size: 56, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No music files found on this device',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  return SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, index) {
        final song = state.songs[index];
        final isCurrentSong = state.currentSong == song;
        final isPlaying =
            isCurrentSong && state.status == PlayerStatus.playing;
        final isLoading =
            isCurrentSong && state.status == PlayerStatus.loading;

        return SongTile(
          song: song,
          index: index,
          isPlaying: isPlaying,
          isCurrentSong: isCurrentSong,
          isLoading: isLoading,
          onTap: () => _playSong(context, song, state.songs),
          onPlayPause: () {
            if (isCurrentSong && isPlaying) {
              context.read<MusicPlayerBloc>().add(const PauseSong());
            } else if (isCurrentSong) {
              context.read<MusicPlayerBloc>().add(const ResumeSong());
            } else {
              _playSong(context, song, state.songs);
            }
          },
        );
      },
      childCount: state.songs.length,
    ),
  );
}

void _playSong(BuildContext context, Song song, List<Song> playlist) {
  context.read<MusicPlayerBloc>().add(PlaySong(song, playlist: playlist));
}
