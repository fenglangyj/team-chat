import 'package:flutter/material.dart';

import '../../core/utils.dart';

class ProfileAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.radius = 22,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? scheme.primaryContainer;
    final fg = foregroundColor ?? scheme.onPrimaryContainer;
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: icon != null
          ? Icon(icon, color: fg, size: radius)
          : Text(
              avatarText(name),
              style: TextStyle(
                color: fg,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
