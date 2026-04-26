import 'package:flutter/material.dart';
import '../models/message.dart';
import '../widgets/avatar_widget.dart';
import 'message_status_icon.dart';

/// A single chat message bubble with WhatsApp-style avatar for received messages.
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool showAvatar;

  const MessageBubble({
    super.key,
    required this.message,
    this.showAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMine = message.isMine;

    if (isMine) return _buildMineBubble(cs);
    return _buildTheirBubble(cs);
  }

  /// Right-aligned bubble for the current user's messages.
  Widget _buildMineBubble(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 64, right: 12, top: 3, bottom: 3),
      child: Align(
        alignment: Alignment.centerRight,
        child: _bubble(cs, isMine: true),
      ),
    );
  }

  /// Left-aligned bubble with optional avatar for received messages.
  Widget _buildTheirBubble(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 64, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar column — show avatar or empty space for alignment
          SizedBox(
            width: 34,
            child: showAvatar
                ? UserAvatar(username: message.sender, radius: 14)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 6),
          // Bubble
          Flexible(child: _bubble(cs, isMine: false)),
        ],
      ),
    );
  }

  /// The actual bubble container.
  Widget _bubble(ColorScheme cs, {required bool isMine}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: isMine ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: (isMine ? cs.primary : cs.shadow).withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sender name (only for received messages with avatar)
          if (!isMine && showAvatar)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                message.sender,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _senderColor(message.sender, cs),
                ),
              ),
            ),
          Text(
            message.content,
            style: TextStyle(
              color: isMine ? cs.onPrimaryContainer : cs.onSurface,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: (isMine ? cs.onPrimaryContainer : cs.onSurfaceVariant)
                      .withValues(alpha: 0.6),
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 4),
                MessageStatusIcon(
                  status: message.status,
                  size: 14,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Deterministic color for each sender name in group chats.
  Color _senderColor(String sender, ColorScheme cs) {
    final colors = [
      cs.primary,
      cs.tertiary,
      cs.error,
      Colors.teal,
      Colors.orange,
      Colors.indigo,
      Colors.pink,
    ];
    return colors[sender.hashCode.abs() % colors.length];
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
