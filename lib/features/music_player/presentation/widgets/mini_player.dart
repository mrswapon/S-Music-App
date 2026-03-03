import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/animated_icon_btn.dart';
import '../../../../core/widgets/pulse_widget.dart';
import '../bloc/music_player_bloc.dart';
import '../bloc/music_player_event.dart';
import '../bloc/music_player_state.dart';
import '../screens/now_playing_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MusicPlayerBloc, MusicPlayerState>(
      builder: (context, state) {
        if (state.currentSong == null ||
            state.status == PlayerStatus.initial ||
            state.status == PlayerStatus.stopped) {
          return const SizedBox.shrink();
        }

        final song = state.currentSong!;
        final progress = state.duration.inMilliseconds > 0
            ? state.position.inMilliseconds / state.duration.inMilliseconds
            : 0.0;
        final isPlaying = state.status == PlayerStatus.playing;

        return AnimatedSlide(
          offset: Offset.zero,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => BlocProvider.value(
                    value: context.read<MusicPlayerBloc>(),
                    child: const NowPlayingScreen(),
                  ),
                  transitionsBuilder: (_, anim, __, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: anim,
                        curve: Curves.easeOutCubic,
                      )),
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 400),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 300),
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor),
                      minHeight: 2,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        // Animated thumbnail
                        PulseWidget(
                          animate: isPlaying,
                          minScale: 0.95,
                          maxScale: 1.0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 46,
                              height: 46,
                              child: song.thumbnailUrl != null
                                  ? Image.network(
                                      song.thumbnailUrl!,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (_, child, progress) =>
                                          progress == null
                                              ? child
                                              : _defaultThumbnail(),
                                      errorBuilder: (_, __, ___) =>
                                          _defaultThumbnail(),
                                    )
                                  : _defaultThumbnail(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedIconBtn(
                          icon: Icons.skip_previous,
                          size: 26,
                          onPressed: () => context
                              .read<MusicPlayerBloc>()
                              .add(const PreviousSong()),
                        ),
                        if (state.status == PlayerStatus.loading)
                          const SizedBox(
                            width: 36,
                            height: 36,
                            child: Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          )
                        else if (state.status == PlayerStatus.error)
                          IconButton(
                            onPressed: () {
                              // Retry playing the same song
                              final s = state.currentSong;
                              if (s != null) {
                                context.read<MusicPlayerBloc>().add(
                                    PlaySong(s,
                                        playlist: state.activePlaylist));
                              }
                            },
                            icon: const Icon(Icons.refresh,
                                color: Colors.red, size: 30),
                          )
                        else
                          _MiniPlayPause(
                            isPlaying: isPlaying,
                            onTap: () {
                              if (isPlaying) {
                                context
                                    .read<MusicPlayerBloc>()
                                    .add(const PauseSong());
                              } else {
                                context
                                    .read<MusicPlayerBloc>()
                                    .add(const ResumeSong());
                              }
                            },
                          ),
                        AnimatedIconBtn(
                          icon: Icons.skip_next,
                          size: 26,
                          onPressed: () => context
                              .read<MusicPlayerBloc>()
                              .add(const NextSong()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _defaultThumbnail() {
    return Container(
      color: AppTheme.primaryColor,
      child: const Icon(Icons.music_note, color: Colors.white, size: 22),
    );
  }
}

/// Play/pause icon in the mini player with its own bounce.
class _MiniPlayPause extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _MiniPlayPause({required this.isPlaying, required this.onTap});

  @override
  State<_MiniPlayPause> createState() => _MiniPlayPauseState();
}

class _MiniPlayPauseState extends State<_MiniPlayPause>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: IconButton(
        onPressed: () {
          _ctrl.forward().then((_) => _ctrl.reverse());
          widget.onTap();
        },
        visualDensity: VisualDensity.compact,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            widget.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            key: ValueKey(widget.isPlaying),
            color: AppTheme.primaryColor,
            size: 36,
          ),
        ),
      ),
    );
  }
}
