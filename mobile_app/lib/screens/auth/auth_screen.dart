import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/connection_service.dart';
import '../../widgets/app_logo.dart';

/// Combined Login + Register screen with animated transitions and gradient background.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  final _loginUser = TextEditingController();
  final _loginPass = TextEditingController();
  final _regUser = TextEditingController();
  final _regPass = TextEditingController();
  final _regConfirm = TextEditingController();

  bool _obscureLogin = true;
  bool _obscureReg = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _fadeController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    _loginUser.dispose();
    _loginPass.dispose();
    _regUser.dispose();
    _regPass.dispose();
    _regConfirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final conn = context.watch<ConnectionService>();
    final isLoading = auth.state == AuthState.connecting ||
        auth.state == AuthState.authenticating;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surface,
              cs.primaryContainer.withValues(alpha: 0.15),
              cs.tertiaryContainer.withValues(alpha: 0.1),
              cs.surface,
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated app logo with pulse
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: const AppLogo(radius: 44),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'SlipSpace',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect with friends instantly',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    // Server info
                    TextButton.icon(
                      icon: const Icon(Icons.dns_rounded, size: 16),
                      label: Text(
                        '${conn.host}:${conn.port}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      onPressed: () => Navigator.pushNamed(context, '/settings'),
                    ),
                    const SizedBox(height: 24),

                    // Tab bar with glass container
                    Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: const EdgeInsets.all(4),
                        labelColor: cs.onPrimaryContainer,
                        unselectedLabelColor: cs.onSurfaceVariant,
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'Login'),
                          Tab(text: 'Register'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tab content
                    SizedBox(
                      height: 280,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildLoginForm(cs, isLoading),
                          _buildRegisterForm(cs, isLoading),
                        ],
                      ),
                    ),

                    // Error message
                    if (auth.state == AuthState.error)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: cs.onErrorContainer, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                auth.error,
                                style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Powered by AWS logo
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Opacity(
                        opacity: 0.7,
                        child: Image.asset(
                          'assets/aws-whitepng.webp',
                          width: 180,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(ColorScheme cs, bool isLoading) {
    return Column(
      children: [
        TextField(
          controller: _loginUser,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          textInputAction: TextInputAction.next,
          enabled: !isLoading,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPass,
          obscureText: _obscureLogin,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(_obscureLogin ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
            ),
          ),
          textInputAction: TextInputAction.done,
          enabled: !isLoading,
          onSubmitted: (_) => _doLogin(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: isLoading ? null : _doLogin,
            child: isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Text('Login'),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterForm(ColorScheme cs, bool isLoading) {
    return Column(
      children: [
        TextField(
          controller: _regUser,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          textInputAction: TextInputAction.next,
          enabled: !isLoading,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPass,
          obscureText: _obscureReg,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(_obscureReg ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureReg = !_obscureReg),
            ),
          ),
          textInputAction: TextInputAction.next,
          enabled: !isLoading,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regConfirm,
          obscureText: _obscureReg,
          decoration: const InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
          textInputAction: TextInputAction.done,
          enabled: !isLoading,
          onSubmitted: (_) => _doRegister(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: isLoading ? null : _doRegister,
            child: isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Text('Create Account'),
          ),
        ),
      ],
    );
  }

  void _doLogin() {
    final user = _loginUser.text.trim();
    final pass = _loginPass.text;
    if (user.isEmpty || pass.isEmpty) return;
    context.read<AuthProvider>().login(user, pass);
  }

  void _doRegister() {
    final user = _regUser.text.trim();
    final pass = _regPass.text;
    final confirm = _regConfirm.text;
    if (user.isEmpty || pass.isEmpty) return;
    if (pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }
    context.read<AuthProvider>().register(user, pass);
  }
}
