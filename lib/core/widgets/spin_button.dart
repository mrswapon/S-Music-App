import 'package:flutter/material.dart';

/// An icon button that does a 360-degree spin on every tap.
class SpinButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final VoidCallback? onPressed;
  final String? tooltip;

  const SpinButton({
    super.key,
    required this.icon,
    this.size = 24,
    this.color,
    this.onPressed,
    this.tooltip,
  });

  @override
  State<SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<SpinButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0.0);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      child: IconButton(
        onPressed: _handleTap,
        icon: Icon(widget.icon, size: widget.size, color: widget.color),
        tooltip: widget.tooltip,
      ),
    );
  }
}
