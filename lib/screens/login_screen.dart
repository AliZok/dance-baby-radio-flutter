import 'package:flutter/material.dart';
import 'dart:async';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_widgets.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final AudioService audioService;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.audioService,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    String? emailError;
    String? passwordError;

    if (email.isEmpty) {
      emailError = 'Please enter your email.';
    } else if (!email.contains('@') || !email.contains('.')) {
      emailError = 'Please enter a valid email.';
    }

    if (password.isEmpty) {
      passwordError = 'Please enter your password.';
    } else if (password.length < 6) {
      passwordError = 'Password must be at least 6 characters.';
    }

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });

    return emailError == null && passwordError == null;
  }

  Future<void> _submit() async {
    widget.authService.clearAuthError();
    if (!_validate()) return;

    final result = await widget.authService.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    // Nuxt `login.vue` handleLogin: nothing is toasted on success. When the
    // radio is silent, the sign-in itself releases the "Let's GO" gate
    // (`skipLetsGo` + `autoPlayAfterLogin`) and playback starts on the home page.
    if (result.success) {
      if (!widget.audioService.isPlaying) {
        unawaited(widget.audioService.skipIntroGateAndAutoplay());
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    // Nuxt surfaces the failure inline through `authError` only — the message
    // is already rendered below the password field.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.authService,
      builder: (context, _) {
        final auth = widget.authService;
        return AuthScaffold(
          child: AuthCard(
            title: 'Sign in',
            subtitle: 'Enter your email and password to continue',
            child: Column(
              children: [
                AuthTextField(
                  label: 'Email',
                  controller: _emailController,
                  hint: 'example@email.com',
                  keyboardType: TextInputType.emailAddress,
                  errorText: _emailError,
                ),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Password',
                  controller: _passwordController,
                  obscure: true,
                  errorText: _passwordError,
                ),
                if (auth.authError.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    auth.authError,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AuthPrimaryButton(
                  label: auth.loading ? 'Signing in' : 'Sign in',
                  loading: auth.loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => RegisterScreen(
                          authService: widget.authService,
                          audioService: widget.audioService,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    "Don't have an account? Sign up",
                    style: TextStyle(color: AppColors.primary, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
