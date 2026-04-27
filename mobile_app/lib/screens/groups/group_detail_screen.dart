import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/groups_provider.dart';
import '../../widgets/avatar_widget.dart';

class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groupId = ModalRoute.of(context)!.settings.arguments as String;
    final groups = context.watch<GroupsProvider>();
    final auth = context.read<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final meta = groups.groups[groupId];
    final isCreator = groups.isCreator(groupId, auth.username);
    final addCtrl = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: Text(groupId)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Group info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const GroupAvatar(radius: 40),
                const SizedBox(height: 16),
                Text(groupId, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline_rounded, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('Created by ${meta?['created_by'] ?? 'unknown'}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Add member (creator only)
          if (isCreator) ...[
            Text('Manage Members', style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: addCtrl,
                  decoration: const InputDecoration(hintText: 'Username to add...', prefixIcon: Icon(Icons.person_add_rounded)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () {
                  final name = addCtrl.text.trim();
                  if (name.isEmpty) return;
                  groups.addMember(groupId, name);
                  addCtrl.clear();
                },
                child: const Text('Add'),
              ),
            ]),
            const SizedBox(height: 16),
          ],

          // Leave group
          OutlinedButton.icon(
            icon: const Icon(Icons.exit_to_app_rounded),
            label: const Text('Leave Group'),
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            onPressed: () {
              groups.leaveGroup(groupId, chatProvider: context.read<ChatProvider>());
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
