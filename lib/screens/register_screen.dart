import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_widgets.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  final AuthService authService;

  const RegisterScreen({super.key, required this.authService});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    String? emailError;
    String? passwordError;
    String? confirmError;

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

    if (confirm.isEmpty) {
      confirmError = 'Please confirm your password.';
    } else if (confirm != password) {
      confirmError = 'Passwords do not match.';
    }

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = confirmError;
    });

    return emailError == null && passwordError == null && confirmError == null;
  }

  Future<void> _submit() async {
    widget.authService.clearAuthError();
    if (!_validate()) return;

    final result = await widget.authService.signUp(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (!result.success) {
      AppToast.error(
        context,
        result.error ?? 'Registration failed. Please try again.',
        title: 'Sign up failed',
      );
      setState(() {});
      return;
    }

    AppToast.info(
      context,
      'Please check your inbox and confirm your signup. The confirmation email is sent by Supabase.',
      title: 'Check your email',
    );

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(authService: widget.authService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.authService,
      builder: (context, _) {
        final auth = widget.authService;
        return AuthScaffold(
          child: AuthCard(
            title: 'Sign up',
            subtitle: 'Create an account with your email and password',
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
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Confirm password',
                  controller: _confirmController,
                  obscure: true,
                  errorText: _confirmError,
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
                  label: auth.loading ? 'Creating account' : 'Sign up',
                  loading: auth.loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => LoginScreen(authService: widget.authService),
                      ),
                    );
                  },
                  child: const Text(
                    'Already have an account? Sign in',
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
