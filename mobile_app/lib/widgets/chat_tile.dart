import 'package:flutter/material.dart';
import 'avatar_widget.dart';

/// A conversation list tile for the home screen.
class ChatTile extends StatelessWidget {
  final String name;
  final String lastMessage;
  final String? timestamp;
  final bool isGroup;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback? onDismissed;

  const ChatTile({
    super.key,
    required this.name,
    required this.lastMessage,
    this.timestamp,
    this.isGroup = false,
    this.unreadCount = 0,
    required this.onTap,
    this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final tile = ListTile(
      leading: isGroup
          ? const GroupAvatar(radius: 24)
          : UserAvatar(username: name, radius: 24),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: unreadCount > 0
          ? Text(
              '$unreadCount new message${unreadCount > 1 ? 's' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            )
          : Text(
              lastMessage.isEmpty ? 'No messages yet' : lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timestamp != null && timestamp!.isNotEmpty)
            Text(
              _formatTimestamp(timestamp!),
              style: TextStyle(
                fontSize: 11,
                color: unreadCount > 0 ? cs.primary : cs.onSurfaceVariant,
                fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          if (unreadCount > 0)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.elasticOut,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unreadCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimary,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    if (onDismissed != null) {
      return Dismissible(
        key: ValueKey(name),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDismissed!(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
        ),
        child: tile,
      );
    }

    return tile;
  }

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}/${dt.month}';
    } catch (_) {
      return '';
    }
  }
}
