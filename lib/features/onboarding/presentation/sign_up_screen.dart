import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../auth/presentation/providers/auth_provider.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _homeserverController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _showTokenField = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _homeserverController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (password != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    final homeserver = _homeserverController.text.trim();
    if (homeserver.isEmpty) {
      setState(() => _error = 'Please enter a homeserver address');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      await ref.read(authProvider.notifier).register(
            homeserver: homeserver,
            username: _usernameController.text.trim(),
            password: password,
            registrationToken: _tokenController.text.trim().isNotEmpty
                ? _tokenController.text.trim()
                : null,
          );
      if (mounted) context.go('/');
    } catch (e) {
      final msg = e.toString();
      // Detect if the server requires a registration token
      if (msg.contains('registration_token') ||
          msg.contains('M_FORBIDDEN') ||
          msg.contains('Registration is not enabled')) {
        setState(() {
          _showTokenField = true;
          _error = 'This server requires a registration token';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = msg.replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.gloam;
    return Scaffold(
      backgroundColor: g.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GloamSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: g.bgSurface,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
                border: Border.all(color: g.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: g.accentDim,
                      borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
                    ),
                    child: Center(
                      child: Text(
                        'G',
                        style: GoogleFonts.spectral(
                          fontSize: 28, fontWeight: FontWeight.w300,
                          fontStyle: FontStyle.italic, color: g.accentBright,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'create account',
                    style: GoogleFonts.spectral(
                      fontSize: 24, fontWeight: FontWeight.w300,
                      fontStyle: FontStyle.italic, color: g.accent,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Homeserver (always visible for sign-up)
                  _FieldLabel('// homeserver'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _homeserverController,
                    decoration: const InputDecoration(
                      hintText: 'your-server.com',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Username
                  _FieldLabel('// username'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(hintText: 'username'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  _FieldLabel('// password'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Confirm password
                  _FieldLabel('// confirm password'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022'),
                    textInputAction: _showTokenField ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: _showTokenField ? null : (_) => _handleSignUp(),
                  ),
                  const SizedBox(height: 16),

                  // Registration token (shown when server requires it)
                  if (_showTokenField) ...[
                    _FieldLabel('// registration token'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tokenController,
                      decoration: InputDecoration(
                        hintText: 'paste your invite token',
                        hintStyle: GoogleFonts.jetBrainsMono(
                          fontSize: 12, color: g.textTertiary,
                        ),
                      ),
                      style: GoogleFonts.jetBrainsMono(fontSize: 13, color: g.textPrimary),
                      onSubmitted: (_) => _handleSignUp(),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Your server admin should have provided this.',
                        style: GoogleFonts.inter(fontSize: 11, color: g.textTertiary),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Error
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(fontSize: 12, color: g.danger),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Sign Up button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignUp,
                      child: _isLoading
                          ? SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: g.bg,
                              ),
                            )
                          : const Text('create account'),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Back to sign in
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'already have an account? ',
                        style: GoogleFonts.inter(fontSize: 12, color: g.textTertiary),
                      ),
                      GestureDetector(
                        onTap: () => context.go('/sign-in'),
                        child: Text(
                          'sign in',
                          style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w500, color: g.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10, color: context.gloam.textTertiary, letterSpacing: 1,
        ),
      ),
    );
  }
}
