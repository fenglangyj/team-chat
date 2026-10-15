import 'package:flutter/material.dart';

import '../../core/utils.dart';

class ProfileAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final IconData? icon;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.radius = 22,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: icon != null
          ? Icon(icon, color: scheme.onPrimaryContainer, size: radius)
          : Text(
              avatarText(name),
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
