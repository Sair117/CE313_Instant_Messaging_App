import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/groups_provider.dart';
import '../../widgets/avatar_widget.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _addCtrl = TextEditingController();
  late final String _groupId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Safe to call repeatedly — route args don't change after push.
    _groupId = ModalRoute.of(context)!.settings.arguments as String;
  }

  @override
  void initState() {
    super.initState();
    // Fetch the member list as soon as the screen is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GroupsProvider>().fetchGroupMembers(_groupId);
    });
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupsProvider>();
    final auth = context.read<AuthProvider>();
    final cs = Theme.of(context).colorScheme;

    final meta = groups.groups[_groupId];
    final isCreator = groups.isCreator(_groupId, auth.username);
    final members = groups.getGroupMembers(_groupId);

    // Show server feedback as a snackbar.
    if (groups.lastError.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(groups.lastError), backgroundColor: cs.error),
          );
          groups.clearMessages();
        }
      });
    } else if (groups.lastSuccess.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(groups.lastSuccess)),
          );
          groups.clearMessages();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(_groupId)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Group info card ────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const GroupAvatar(radius: 40),
                const SizedBox(height: 16),
                Text(
                  _groupId,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Created by ${meta?['created_by'] ?? 'unknown'}',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Add member (creator only) ──────────────────────────────
          if (isCreator) ...[
            Text('Manage Members',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _addCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Username to add...',
                    prefixIcon: Icon(Icons.person_add_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () {
                  final name = _addCtrl.text.trim();
                  if (name.isEmpty) return;
                  groups.addMember(_groupId, name);
                  _addCtrl.clear();
                },
                child: const Text('Add'),
              ),
            ]),
            const SizedBox(height: 16),
          ],

          // ── Member list ────────────────────────────────────────────
          Text(
            members.isEmpty
                ? 'Members'
                : 'Members (${members.length})',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: cs.primary),
          ),
          const SizedBox(height: 8),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('Loading members…',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            ...members.map((member) {
              final isOwner = member == meta?['created_by'];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(username: member, radius: 20),
                title: Text(member),
                subtitle: isOwner
                    ? Text('Creator',
                        style: TextStyle(
                            color: cs.primary, fontSize: 12))
                    : null,
                trailing: isCreator && member != auth.username
                    ? IconButton(
                        icon: Icon(Icons.remove_circle_outline_rounded,
                            color: cs.error),
                        tooltip: 'Remove member',
                        onPressed: () =>
                            groups.removeMember(_groupId, member),
                      )
                    : null,
              );
            }),

          const SizedBox(height: 16),

          // ── Leave group ───────────────────────────────────────────
          OutlinedButton.icon(
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('Leave Group'),
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            onPressed: () {
              groups.leaveGroup(_groupId,
                  chatProvider: context.read<ChatProvider>());
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
