import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/widgets/bounce_tap.dart';
import '../../../../core/widgets/slide_fade_widget.dart';
import '../../domain/entities/song.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final int index;
  final bool isPlaying;
  final bool isCurrentSong;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;

  const SongTile({
    super.key,
    required this.song,
    required this.index,
    required this.isPlaying,
    required this.isCurrentSong,
    this.isLoading = false,
    required this.onTap,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SlideFadeWidget(
      index: index,
      child: BounceTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isCurrentSong
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(12),
            border: isCurrentSong
                ? Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.4),
                    width: 1.5,
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _buildLeading(theme),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrentSong
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 14,
                          color:
                              isCurrentSong ? AppTheme.primaryColor : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      if (song.viewCount != null || song.duration != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              if (song.viewCount != null) ...[
                                Icon(Icons.visibility,
                                    size: 12,
                                    color:
                                        theme.textTheme.bodyMedium?.color),
                                const SizedBox(width: 4),
                                Text(
                                  FormatUtils.formatViewCount(
                                      song.viewCount),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                              if (song.viewCount != null &&
                                  song.duration != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                  child: Text('·',
                                      style: TextStyle(
                                          color: theme.textTheme.bodyMedium
                                              ?.color)),
                                ),
                              if (song.duration != null)
                                Text(
                                  FormatUtils.formatDuration(
                                      song.duration!),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _PlayPauseButton(
                  isPlaying: isCurrentSong && isPlaying,
                  isLoading: isCurrentSong && isLoading,
                  onPressed: onPlayPause,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(ThemeData theme) {
    if (song.thumbnailUrl != null) {
      return Hero(
        tag: 'thumb_${song.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  song.thumbnailUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : Container(
                          color: AppTheme.primaryColor.withValues(alpha: 0.15),
                          child: const Icon(Icons.music_note,
                              color: AppTheme.primaryColor, size: 24),
                        ),
                  errorBuilder: (_, __, ___) => Container(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    child: const Icon(Icons.music_note,
                        color: AppTheme.primaryColor, size: 24),
                  ),
                ),
                if (isCurrentSong && isPlaying)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    color: Colors.black45,
                    child: const Center(
                      child: Icon(Icons.equalizer,
                          color: Colors.white, size: 24),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isCurrentSong
            ? AppTheme.primaryColor
            : AppTheme.primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: isCurrentSong && isPlaying
              ? const Icon(Icons.equalizer,
                  color: Colors.white, size: 24, key: ValueKey('eq'))
              : Text(
                  '${index + 1}',
                  key: ValueKey('idx_$index'),
                  style: TextStyle(
                    color: isCurrentSong
                        ? Colors.white
                        : AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Play/Pause button with its own bounce animation.
class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward().then((_) => _controller.reverse());
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primaryColor,
          ),
        ),
      );
    }

    return ScaleTransition(
      scale: _scale,
      child: IconButton(
        onPressed: _handleTap,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: child,
          ),
          child: Icon(
            widget.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            key: ValueKey(widget.isPlaying),
            color: AppTheme.primaryColor,
            size: 40,
          ),
        ),
      ),
    );
  }
}
