import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/spacing.dart';
import '../../auth/presentation/providers/auth_provider.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _homeserverController =
      TextEditingController(text: 'https://matrix.org');
  bool _showServerField = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _homeserverController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).login(
            homeserver: _homeserverController.text.trim(),
            username: _emailController.text.trim(),
            password: _passwordController.text,
          );
      if (mounted) context.go('/');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GloamColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GloamSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: GloamColors.bgSurface,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
                border: Border.all(color: GloamColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: GloamColors.accentDim,
                      borderRadius:
                          BorderRadius.circular(GloamSpacing.radiusLg),
                    ),
                    child: Center(
                      child: Text(
                        'G',
                        style: GoogleFonts.spectral(
                          fontSize: 28,
                          fontWeight: FontWeight.w300,
                          fontStyle: FontStyle.italic,
                          color: GloamColors.accentBright,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'gloam',
                    style: GoogleFonts.spectral(
                      fontSize: 32,
                      fontWeight: FontWeight.w300,
                      fontStyle: FontStyle.italic,
                      color: GloamColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'tune in to the conversation',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: GloamColors.textTertiary,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // SSO Buttons
                  _SsoButton(label: 'continue with google', onTap: () {}),
                  const SizedBox(height: 10),
                  _SsoButton(label: 'continue with apple', onTap: () {}),
                  const SizedBox(height: 10),
                  _SsoButton(label: 'continue with github', onTap: () {}),
                  const SizedBox(height: 32),

                  // Divider
                  Row(
                    children: [
                      const Expanded(
                          child: Divider(color: GloamColors.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: GloamColors.textTertiary,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const Expanded(
                          child: Divider(color: GloamColors.border)),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Homeserver field (hidden by default)
                  if (_showServerField) ...[
                    _FieldLabel('// homeserver'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _homeserverController,
                      decoration: const InputDecoration(
                        hintText: 'https://matrix.org',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email field
                  _FieldLabel('// username or email'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailController,
                    decoration:
                        const InputDecoration(hintText: 'you@example.com'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  _FieldLabel('// password'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText:
                          '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                      suffixIcon: Icon(
                        Icons.visibility_off_outlined,
                        size: 16,
                        color: GloamColors.textTertiary,
                      ),
                    ),
                    onSubmitted: (_) => _handleSignIn(),
                  ),
                  const SizedBox(height: 8),

                  // Error
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: GloamColors.danger,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Sign In button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignIn,
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: GloamColors.bg,
                              ),
                            )
                          : const Text('sign in'),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'no account? ',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: GloamColors.textTertiary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {},
                        child: Text(
                          'create one',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: GloamColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showServerField = !_showServerField),
                    child: Text(
                      _showServerField
                          ? 'hide server settings'
                          : 'advanced: use your own server \u2192',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: GloamColors.textTertiary,
                        letterSpacing: 0.5,
                      ),
                    ),
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

class _SsoButton extends StatelessWidget {
  const _SsoButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: GloamColors.bgElevated,
          side: const BorderSide(color: GloamColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: GloamColors.textPrimary,
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
          fontSize: 10,
          color: GloamColors.textTertiary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
