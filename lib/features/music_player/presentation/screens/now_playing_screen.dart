import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/widgets/animated_icon_btn.dart';
import '../../../../core/widgets/pulse_widget.dart';
import '../bloc/music_player_bloc.dart';
import '../bloc/music_player_event.dart';
import '../bloc/music_player_state.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return BlocBuilder<MusicPlayerBloc, MusicPlayerState>(
      builder: (context, state) {
        final song = state.currentSong;
        if (song == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Now Playing'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: const Center(child: Text('No song selected')),
          );
        }

        final isPlaying = state.status == PlayerStatus.playing;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.keyboard_arrow_down, size: 32),
            ),
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                'NOW PLAYING',
                key: const ValueKey('np'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: Theme.of(context).appBarTheme.foregroundColor,
                ),
              ),
            ),
            centerTitle: true,
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.3),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 80 : 32,
                ),
                child: Column(
                  children: [
                    SizedBox(height: screenHeight * 0.02),
                    // Video player or album art
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: _buildMediaArea(context, state, song,
                            isPlaying, isTablet),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.03),
                    // Song info with animated text changes
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(song.id),
                        children: [
                          Text(
                            song.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color,
                            ),
                          ),
                          if (song.viewCount != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                FormatUtils.formatViewCount(song.viewCount),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.025),
                    // Seek bar
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: state.duration.inMilliseconds > 0
                            ? state.position.inMilliseconds
                                .toDouble()
                                .clamp(
                                    0,
                                    state.duration.inMilliseconds
                                        .toDouble())
                            : 0,
                        max: state.duration.inMilliseconds > 0
                            ? state.duration.inMilliseconds.toDouble()
                            : 1,
                        onChanged: (value) {
                          context.read<MusicPlayerBloc>().add(
                                SeekTo(
                                    Duration(milliseconds: value.toInt())),
                              );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            FormatUtils.formatDuration(state.position),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color,
                            ),
                          ),
                          Text(
                            FormatUtils.formatDuration(state.duration),
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
                    SizedBox(height: screenHeight * 0.015),
                    // Playback controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Shuffle — bouncing toggle
                        _ToggleButton(
                          icon: Icons.shuffle,
                          isActive: state.isShuffleOn,
                          onPressed: () => context
                              .read<MusicPlayerBloc>()
                              .add(const ToggleShuffle()),
                        ),
                        // Previous
                        AnimatedIconBtn(
                          icon: Icons.skip_previous,
                          size: 36,
                          onPressed: () => context
                              .read<MusicPlayerBloc>()
                              .add(const PreviousSong()),
                        ),
                        // Main play/pause with pulse
                        _MainPlayButton(
                          status: state.status,
                          onPressed: () {
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
                        // Next
                        AnimatedIconBtn(
                          icon: Icons.skip_next,
                          size: 36,
                          onPressed: () => context
                              .read<MusicPlayerBloc>()
                              .add(const NextSong()),
                        ),
                        // Repeat — bouncing toggle
                        _ToggleButton(
                          icon: state.repeatMode == RepeatMode.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                          isActive: state.repeatMode != RepeatMode.off,
                          onPressed: () => context
                              .read<MusicPlayerBloc>()
                              .add(const ToggleRepeat()),
                        ),
                      ],
                    ),
                    SizedBox(height: screenHeight * 0.04),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaArea(BuildContext context, MusicPlayerState state,
      dynamic song, bool isPlaying, bool isTablet) {
    final controller =
        context.read<MusicPlayerBloc>().videoController;

    if (state.isVideoMode &&
        controller != null &&
        controller.value.isInitialized) {
      // Video mode — show actual video
      return AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor
                  .withValues(alpha: isPlaying ? 0.5 : 0.25),
              blurRadius: isPlaying ? 40 : 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }

    // Audio mode — show album art with pulse animation
    return PulseWidget(
      animate: isPlaying,
      minScale: 0.97,
      maxScale: 1.03,
      duration: const Duration(milliseconds: 2000),
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor
                    .withValues(alpha: isPlaying ? 0.5 : 0.25),
                blurRadius: isPlaying ? 40 : 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: song.thumbnailUrl != null
                ? Hero(
                    tag: 'now_playing_thumb_${song.id}',
                    child: Image.network(
                      song.thumbnailUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) =>
                          progress == null
                              ? child
                              : _defaultArt(isTablet),
                      errorBuilder: (_, __, ___) =>
                          _defaultArt(isTablet),
                    ),
                  )
                : _defaultArt(isTablet),
          ),
        ),
      ),
    );
  }

  Widget _defaultArt(bool isTablet) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note,
          size: isTablet ? 120 : 80,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

// ─── Main play/pause circle button with bounce + pulse ───────

class _MainPlayButton extends StatefulWidget {
  final PlayerStatus status;
  final VoidCallback onPressed;

  const _MainPlayButton({required this.status, required this.onPressed});

  @override
  State<_MainPlayButton> createState() => _MainPlayButtonState();
}

class _MainPlayButtonState extends State<_MainPlayButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceCtrl;
  late Animation<double> _bounceScale;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _bounceScale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.status == PlayerStatus.playing;
    final isLoading = widget.status == PlayerStatus.loading;

    return PulseWidget(
      animate: isPlaying,
      minScale: 0.95,
      maxScale: 1.05,
      duration: const Duration(milliseconds: 1500),
      child: ScaleTransition(
        scale: _bounceScale,
        child: GestureDetector(
          onTapDown: (_) => _bounceCtrl.forward(),
          onTapUp: (_) {
            _bounceCtrl.reverse();
            widget.onPressed();
          },
          onTapCancel: () => _bounceCtrl.reverse(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor
                      .withValues(alpha: isPlaying ? 0.6 : 0.3),
                  blurRadius: isPlaying ? 24 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                : Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        key: ValueKey(isPlaying),
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Toggle button (shuffle / repeat) with bounce + glow ─────

class _ToggleButton extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;

  const _ToggleButton({
    required this.icon,
    required this.isActive,
    required this.onPressed,
  });

  @override
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.7), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.15), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
          _ctrl.forward(from: 0.0);
          widget.onPressed();
        },
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              RotationTransition(turns: anim, child: child),
          child: Icon(
            widget.icon,
            key: ValueKey('${widget.icon.hashCode}_${widget.isActive}'),
            color: widget.isActive ? AppTheme.primaryColor : null,
            size: 24,
          ),
        ),
      ),
    );
  }
}
