import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config/theme.dart';
import 'config/smooth_page_route.dart';
import 'services/connection_service.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/groups_provider.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/welcome/welcome_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/groups/group_detail_screen.dart';
import 'screens/settings/settings_screen.dart';

/// Shared route observer — lets any screen detect when it regains focus.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prevent crash if device has no internet — use system font as fallback
  GoogleFonts.config.allowRuntimeFetching = false;

  final conn = ConnectionService();
  await conn.loadSettings();

  runApp(IMApp(conn: conn));
}

class IMApp extends StatelessWidget {
  final ConnectionService conn;
  const IMApp({super.key, required this.conn});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: conn),
        ChangeNotifierProvider(create: (_) => AuthProvider(conn)),
        ChangeNotifierProvider(create: (_) => ChatProvider(conn)),
        ChangeNotifierProvider(create: (_) => FriendsProvider(conn)),
        ChangeNotifierProvider(create: (_) => GroupsProvider(conn)),
      ],
      child: _AppShell(conn: conn),
    );
  }
}

class _AppShell extends StatefulWidget {
  final ConnectionService conn;
  const _AppShell({required this.conn});

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  bool _hasShownWelcome = false;

  @override
  void initState() {
    super.initState();
    // Wire up the central message dispatcher
    widget.conn.onMessage = _dispatch;
  }

  void _dispatch(Map<String, dynamic> msg) {
    if (!mounted) return;
    try {
      final type = msg['type'] as String? ?? '';
      final auth = context.read<AuthProvider>();
      final chat = context.read<ChatProvider>();
      final friends = context.read<FriendsProvider>();
      final groups = context.read<GroupsProvider>();

      // Auth responses
      if (type == 'auth_res') {
        auth.handleMessage(msg);
        return;
      }

      // Chat messages, receipts, and delivery status sync
      if (type == 'direct_msg' || type == 'group_msg' || type == 'receipt' || type == 'outbound_status') {
        chat.handleMessage(msg, auth.username);
        return;
      }

      // Friends
      if (type == 'friends_list' || type == 'friend_notif' || type == 'friend_res') {
        friends.handleMessage(msg);
        return;
      }

      // Groups
      if (type == 'groups_list' || type == 'group_res' || type == 'group_notif' || type == 'group_members') {
        groups.handleMessage(msg);
        return;
      }

      // Errors (e.g., friend request to non-existent user)
      if (type == 'error') {
        friends.handleMessage(msg);
        debugPrint('[SERVER ERROR] ${msg['message']}');
      }
    } catch (e) {
      debugPrint('[DISPATCH ERROR] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SlipSpace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.system,
      navigatorObservers: [routeObserver],
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.state == AuthState.authenticated) {
            // Show welcome screen once per login session
            if (!_hasShownWelcome) {
              _hasShownWelcome = true;
              // Use addPostFrameCallback to navigate after build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.of(context).pushReplacementNamed('/welcome');
                }
              });
              // Show a blank scaffold while navigating
              return const Scaffold();
            }
            return const HomeScreen();
          }
          // Reset welcome flag on logout
          _hasShownWelcome = false;
          return const AuthScreen();
        },
      ),
      onGenerateRoute: (settings) {
        Widget page;
        switch (settings.name) {
          case '/welcome':
            page = const WelcomeScreen();
            break;
          case '/home':
            page = const HomeScreen();
            break;
          case '/chat':
            page = const ChatScreen();
            break;
          case '/group_detail':
            page = const GroupDetailScreen();
            break;
          case '/settings':
            page = const SettingsScreen();
            break;
          default:
            return null;
        }
        return SmoothPageRoute(page: page, routeSettings: settings);
      },
    );
  }
}
