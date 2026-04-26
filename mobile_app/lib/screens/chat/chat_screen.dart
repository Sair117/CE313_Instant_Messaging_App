import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/groups_provider.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/input_bar.dart';
import '../../widgets/avatar_widget.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  late String _convId, _convName, _convType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    _convId = args['id'] as String;
    _convName = args['name'] as String;
    _convType = args['type'] as String;
    // Mark this conversation as active and reset unread count
    context.read<ChatProvider>().markRead(_convId);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Check if the user is still a member of the group.
  bool _isGroupMember() {
    if (_convType != 'group') return true;
    final groups = context.read<GroupsProvider>();
    return groups.groupIds.contains(_convId);
  }

  /// Determine if this message should show an avatar
  /// (first in a consecutive group from same sender).
  bool _shouldShowAvatar(int index, List messages) {
    if (index >= messages.length) return true;
    final msg = messages[index];
    if (msg.isMine) return false; // No avatars on own messages

    // Show avatar if this is the last message OR next message is from a different sender
    if (index == messages.length - 1) return true;
    return messages[index + 1].sender != msg.sender || messages[index + 1].isMine;
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final messages = chat.getMessages(_convId);
    final cs = Theme.of(context).colorScheme;
    // Also watch groups so we rebuild when the user leaves
    context.watch<GroupsProvider>();
    final isMember = _isGroupMember();
    _scrollToBottom();

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          chat.clearActiveConversation();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            _convType == 'group'
                ? const GroupAvatar(radius: 18)
                : UserAvatar(username: _convName, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_convName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  if (_convType == 'group')
                    Text('Group chat',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
          actions: [
            if (_convType == 'group')
              IconButton(
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: () => Navigator.pushNamed(
                  context,
                  '/group_detail',
                  arguments: _convId,
                ),
              ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.waving_hand_rounded, size: 48,
                            color: cs.primary.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text('Say hello!',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => MessageBubble(
                      message: messages[i],
                      showAvatar: _shouldShowAvatar(i, messages),
                    ),
                  ),
          ),
          if (_convType == 'group' && !isMember)
            Container(
              padding: const EdgeInsets.all(16),
              color: cs.surfaceContainerHighest,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block_rounded, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'You left this group',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            InputBar(onSend: (content) {
              _convType == 'group'
                  ? chat.sendGroupMessage(_convId, content)
                  : chat.sendDirectMessage(_convId, content);
            }),
        ]),
      ),
    );
  }
}
