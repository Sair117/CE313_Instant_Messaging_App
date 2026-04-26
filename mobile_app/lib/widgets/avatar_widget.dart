import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:multiavatar/multiavatar.dart';

/// A deterministic avatar widget that generates a unique character face
/// from any username string. Same name = same avatar, every time.
class UserAvatar extends StatelessWidget {
  final String username;
  final double radius;

  const UserAvatar({
    super.key,
    required this.username,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final svgCode = multiavatar(username);
    final cs = Theme.of(context).colorScheme;

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
      child: ClipOval(
        child: SvgPicture.string(
          svgCode,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// A composed avatar for groups — shows overlapping member icons.
class GroupAvatar extends StatelessWidget {
  final double radius;

  const GroupAvatar({super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.tertiaryContainer,
      child: Icon(
        Icons.group_rounded,
        size: radius * 1.1,
        color: cs.onTertiaryContainer,
      ),
    );
  }
}
