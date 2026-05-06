import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/friends_provider.dart';
import '../../providers/groups_provider.dart';
import '../../services/local_storage.dart';
import '../../widgets/chat_tile.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/app_logo.dart';
import '../../../main.dart' show routeObserver;

/// Main home screen with bottom navigation: Chats, Friends, Groups.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatProvider>().loadFromStorage();
      context.read<FriendsProvider>().fetchFriends();
      context.read<GroupsProvider>().fetchGroups();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Called when the user pops back to this screen from ChatScreen (or any
  /// pushed route). Fires after the route is fully active, so Provider's
  /// notifyListeners() will now reach all widgets correctly.
  @override
  void didPopNext() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const AppLogo(radius: 18),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SlipSpace',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  auth.username,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: () async {
              // Clear all in-memory state and close user DB before logout
              context.read<ChatProvider>().clear();
              context.read<FriendsProvider>().clear();
              context.read<GroupsProvider>().clear();
              await LocalStorage.close();
              await auth.logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _ChatsTab(),
          _FriendsTab(),
          _GroupsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: context.watch<FriendsProvider>().pendingCount > 0,
              label: Text('${context.watch<FriendsProvider>().pendingCount}'),
              child: const Icon(Icons.people_outline_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: context.watch<FriendsProvider>().pendingCount > 0,
              label: Text('${context.watch<FriendsProvider>().pendingCount}'),
              child: const Icon(Icons.people_rounded),
            ),
            label: 'Friends',
          ),
          const NavigationDestination(
            icon: Icon(Icons.group_work_outlined),
            selectedIcon: Icon(Icons.group_work_rounded),
            label: 'Groups',
          ),
        ],
      ),
    );
  }
}

// ---- Chats Tab ----

class _ChatsTab extends StatelessWidget {
  const _ChatsTab();

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final convs = chat.conversations;
    final cs = Theme.of(context).colorScheme;

    final sortedKeys = convs.keys.toList()
      ..sort((a, b) {
        final tsA = convs[a]!['last_timestamp'] ?? '';
        final tsB = convs[b]!['last_timestamp'] ?? '';
        return tsB.compareTo(tsA);
      });

    return RefreshIndicator(
      color: cs.primary,
      backgroundColor: cs.surfaceContainerHighest,
      onRefresh: () => context.read<ChatProvider>().loadFromStorage(),
      child: convs.isEmpty
          ? ListView(
              // Must be scrollable so the pull gesture is recognised when empty.
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.55,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text('No conversations yet',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Text('Add a friend and start chatting!',
                            style: TextStyle(
                                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sortedKeys.length,
              itemBuilder: (context, i) {
                final id = sortedKeys[i];
                final conv = convs[id]!;
                return ChatTile(
                  name: conv['name'] ?? id,
                  lastMessage: conv['last_message'] ?? '',
                  timestamp: conv['last_timestamp'],
                  isGroup: conv['type'] == 'group',
                  unreadCount: chat.unreadCount(id),
                  onTap: () {
                    chat.markRead(id);
                    Navigator.pushNamed(context, '/chat', arguments: {
                      'id': id,
                      'name': conv['name'] ?? id,
                      'type': conv['type'] ?? 'direct',
                    });
                  },
                  onDismissed: () {
                    chat.deleteConversation(id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Deleted chat with ${conv['name'] ?? id}')),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ---- Friends Tab ----

class _FriendsTab extends StatelessWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendsProvider>();
    final cs = Theme.of(context).colorScheme;

    // Show error/success snackbar reactively
    if (friends.lastError.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friends.lastError),
            backgroundColor: cs.error,
          ),
        );
        friends.clearMessages();
      });
    } else if (friends.lastSuccess.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friends.lastSuccess)),
        );
        friends.clearMessages();
      });
    }

    return Column(
      children: [
        // Add friend bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: const _AddFriendBar(),
        ),

        // Pending requests
        if (friends.pendingRequests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Pending Requests',
                  style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
            ),
          ),
          ...friends.pendingRequests.map((user) => ListTile(
                leading: UserAvatar(username: user, radius: 20),
                title: Text(user),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.check_circle_rounded, color: cs.primary),
                      onPressed: () => friends.acceptFriendRequest(user),
                    ),
                    IconButton(
                      icon: Icon(Icons.block_rounded, color: cs.error),
                      onPressed: () => friends.blockUser(user),
                    ),
                  ],
                ),
              )),
          const Divider(indent: 16, endIndent: 16),
        ],

        // Friends list
        Expanded(
          child: friends.friends.isEmpty
              ? Center(
                  child: Text('No friends yet. Add someone above!',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                )
              : ListView.builder(
                  itemCount: friends.friends.length,
                  itemBuilder: (context, i) {
                    final friend = friends.friends[i];
                    return ListTile(
                      leading: UserAvatar(username: friend, radius: 22),
                      title: Text(friend, style: const TextStyle(fontWeight: FontWeight.w500)),
                      trailing: IconButton(
                        icon: const Icon(Icons.chat_rounded),
                        onPressed: () {
                          context.read<ChatProvider>().openConversation(friend, 'direct', friend);
                          Navigator.pushNamed(context, '/chat', arguments: {
                            'id': friend,
                            'name': friend,
                            'type': 'direct',
                          });
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AddFriendBar extends StatefulWidget {
  const _AddFriendBar();

  @override
  State<_AddFriendBar> createState() => _AddFriendBarState();
}

class _AddFriendBarState extends State<_AddFriendBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Add friend by username...',
              prefixIcon: const Icon(Icons.person_add_alt_1_rounded),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            context.read<FriendsProvider>().sendFriendRequest(name);
            _controller.clear();
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// ---- Groups Tab ----

class _GroupsTab extends StatelessWidget {
  const _GroupsTab();

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupsProvider>();
    final cs = Theme.of(context).colorScheme;

    if (groups.lastError.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(groups.lastError), backgroundColor: cs.error),
        );
        groups.clearMessages();
      });
    } else if (groups.lastSuccess.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(groups.lastSuccess)),
        );
        groups.clearMessages();
      });
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: const _CreateGroupBar(),
        ),
        Expanded(
          child: groups.groupIds.isEmpty
              ? Center(
                  child: Text('No groups yet. Create one above!',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                )
              : ListView.builder(
                  itemCount: groups.groupIds.length,
                  itemBuilder: (context, i) {
                    final gid = groups.groupIds[i];
                    final meta = groups.groups[gid]!;
                    return ListTile(
                      leading: const GroupAvatar(radius: 22),
                      title: Text(gid, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text('Created by ${meta['created_by']}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      trailing: IconButton(
                        icon: const Icon(Icons.chat_rounded),
                        onPressed: () {
                          context.read<ChatProvider>().openConversation(gid, 'group', gid);
                          Navigator.pushNamed(context, '/chat', arguments: {
                            'id': gid,
                            'name': gid,
                            'type': 'group',
                          });
                        },
                      ),
                      onTap: () => Navigator.pushNamed(context, '/group_detail', arguments: gid),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CreateGroupBar extends StatefulWidget {
  const _CreateGroupBar();

  @override
  State<_CreateGroupBar> createState() => _CreateGroupBarState();
}

class _CreateGroupBarState extends State<_CreateGroupBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'New group name...',
              prefixIcon: const Icon(Icons.group_add_rounded),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            context.read<GroupsProvider>().createGroup(name);
            _controller.clear();
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
