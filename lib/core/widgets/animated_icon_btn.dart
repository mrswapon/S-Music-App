import 'package:flutter/material.dart';

/// An icon button that bounces on tap and optionally spins.
class AnimatedIconBtn extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final VoidCallback? onPressed;
  final String? tooltip;

  const AnimatedIconBtn({
    super.key,
    required this.icon,
    this.size = 24,
    this.color,
    this.onPressed,
    this.tooltip,
  });

  @override
  State<AnimatedIconBtn> createState() => _AnimatedIconBtnState();
}

class _AnimatedIconBtnState extends State<AnimatedIconBtn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward().then((_) {
      _controller.reverse();
    });
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: IconButton(
        onPressed: _handleTap,
        icon: Icon(widget.icon, size: widget.size, color: widget.color),
        tooltip: widget.tooltip,
      ),
    );
  }
}
