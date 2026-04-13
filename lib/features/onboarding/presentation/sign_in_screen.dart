import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/gloam_theme_ext.dart';
import '../../../app/theme/spacing.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../domain/mxid_parser.dart';

/// Default homeserver when the input is a plain username with no `:` or `@`.
const _defaultHomeserver = 'https://matrix.org';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _mxidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _homeserverController =
      TextEditingController(text: _defaultHomeserver);
  final _mxidFocus = FocusNode();

  /// True once the user has typed in the homeserver field themselves — after
  /// which auto-extract never overwrites their value.
  bool _homeserverManuallyEdited = false;

  bool _showServerField = false;
  bool _isLoading = false;
  String? _error;

  /// Stored extracted server for the error message CTA copy.
  String? _lastExtractedHomeserver;

  @override
  void initState() {
    super.initState();
    _mxidFocus.addListener(() {
      if (!_mxidFocus.hasFocus) _syncHomeserverFromMxid();
    });
  }

  @override
  void dispose() {
    _mxidController.dispose();
    _passwordController.dispose();
    _homeserverController.dispose();
    _mxidFocus.dispose();
    super.dispose();
  }

  /// On MXID blur, prefill the (usually hidden) homeserver field with the
  /// extracted server so if the user later opens the advanced panel, it's
  /// already correct. Skipped when the user has taken manual control.
  void _syncHomeserverFromMxid() {
    if (_homeserverManuallyEdited) return;
    final parsed = parseMxid(_mxidController.text);
    final target = parsed.homeserver != null
        ? 'https://${parsed.homeserver}'
        : _defaultHomeserver;
    if (_homeserverController.text != target) {
      _homeserverController.text = target;
    }
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final parsed = parseMxid(_mxidController.text);
    if (!parsed.isValid) {
      setState(() {
        _error = 'Enter a Matrix ID like @you:server.xyz';
        _isLoading = false;
      });
      return;
    }

    // The homeserver controller is the authoritative source: either the
    // user typed it (advanced panel), or blur auto-filled it from the MXID,
    // or it's the matrix.org default. No branching needed.
    final homeserver = _homeserverController.text.trim().isEmpty
        ? _defaultHomeserver
        : _homeserverController.text.trim();

    _lastExtractedHomeserver = parsed.homeserver;

    try {
      await ref.read(authProvider.notifier).login(
            homeserver: homeserver,
            username: parsed.localpart,
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
      backgroundColor: context.gloam.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GloamSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: context.gloam.bgSurface,
                borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
                border: Border.all(color: context.gloam.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: context.gloam.accentDim,
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
                          color: context.gloam.accentBright,
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
                      color: context.gloam.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'tune in to the conversation',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: context.gloam.textTertiary,
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
                      Expanded(
                          child: Divider(color: context.gloam.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: context.gloam.textTertiary,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: context.gloam.border)),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Matrix ID field
                  _FieldLabel('// matrix id'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _mxidController,
                    focusNode: _mxidFocus,
                    decoration: const InputDecoration(
                      hintText: '@you:server.xyz',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  _FieldLabel('// password'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText:
                          '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                      suffixIcon: Icon(
                        Icons.visibility_off_outlined,
                        size: 16,
                        color: context.gloam.textTertiary,
                      ),
                    ),
                    onSubmitted: (_) => _handleSignIn(),
                  ),
                  const SizedBox(height: 16),

                  // Homeserver field (collapsed by default, always available)
                  if (_showServerField) ...[
                    _FieldLabel('// homeserver'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _homeserverController,
                      onChanged: (_) => _homeserverManuallyEdited = true,
                      decoration: const InputDecoration(
                        hintText: 'https://matrix.org',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Error
                  if (_error != null) ...[
                    _ErrorBlock(
                      error: _error!,
                      extractedHomeserver: _lastExtractedHomeserver,
                      showServerCTA: !_showServerField,
                      onOpenServerField: () =>
                          setState(() => _showServerField = true),
                    ),
                    const SizedBox(height: 12),
                  ] else
                    const SizedBox(height: 8),

                  // Sign In button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignIn,
                      child: _isLoading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.gloam.bg,
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
                          color: context.gloam.textTertiary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.go('/sign-up'),
                        child: Text(
                          'create one',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.gloam.accent,
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
                          : 'advanced: set a custom server \u2192',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: context.gloam.textTertiary,
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

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.error,
    required this.extractedHomeserver,
    required this.showServerCTA,
    required this.onOpenServerField,
  });

  final String error;
  final String? extractedHomeserver;
  final bool showServerCTA;
  final VoidCallback onOpenServerField;

  @override
  Widget build(BuildContext context) {
    final looksLikeHostFailure = _looksLikeHostFailure(error);
    final friendly = looksLikeHostFailure && extractedHomeserver != null
        ? "Couldn't reach $extractedHomeserver. Check the server part of your Matrix ID."
        : error;

    return Column(
      children: [
        Text(
          friendly,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: context.gloam.danger,
          ),
          textAlign: TextAlign.center,
        ),
        if (looksLikeHostFailure && showServerCTA) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onOpenServerField,
            child: Text(
              'set a custom server URL',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: context.gloam.accent,
                decoration: TextDecoration.underline,
                decorationColor: context.gloam.accentDim,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Heuristic: the SDK's errors for unreachable hosts tend to mention
  /// host/DNS/connection failures. Anything else (wrong password, etc.)
  /// keeps the original message and no CTA.
  static bool _looksLikeHostFailure(String error) {
    final lower = error.toLowerCase();
    return lower.contains('host') ||
        lower.contains('dns') ||
        lower.contains('unreachable') ||
        lower.contains('socket') ||
        lower.contains('no address associated') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection') ||
        lower.contains('timeout') ||
        lower.contains('well-known') ||
        lower.contains('not a valid');
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
          backgroundColor: context.gloam.bgElevated,
          side: BorderSide(color: context.gloam.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: context.gloam.textPrimary,
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
          color: context.gloam.textTertiary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
