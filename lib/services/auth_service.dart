import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthUser {
  final String id;
  final String email;

  const AuthUser({required this.id, required this.email});
}

/// Mirrors Nuxt `composables/useSupabase.js` auth flows.
class AuthService extends ChangeNotifier {
  AuthUser? _currentUser;
  bool _authReady = false;
  bool _loading = false;
  String _authError = '';

  AuthUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get authReady => _authReady;
  bool get loading => _loading;
  String get authError => _authError;

  void clearAuthError() {
    _authError = '';
    notifyListeners();
  }

  String _translateAuthError(String message) {
    final msg = message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Invalid email or password.';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered')) {
      return 'This email is already registered.';
    }
    if (msg.contains('password should be at least')) {
      return 'Password must be at least 6 characters.';
    }
    if (msg.contains('unable to validate email') || msg.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Your signup is not complete yet. Please check your email and confirm your account. The confirmation email is sent by Supabase.';
    }
    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return 'Too many requests. Please try again in a moment.';
    }
    return message.isNotEmpty ? message : 'Something went wrong. Please try again.';
  }

  void _setUser(User? user) {
    if (user == null) {
      _currentUser = null;
    } else {
      _currentUser = AuthUser(id: user.id, email: user.email ?? '');
    }
    notifyListeners();
  }

  Future<void> init() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      _setUser(session?.user);
    } catch (e) {
      debugPrint('AuthService.init failed: $e');
      _setUser(null);
    } finally {
      _authReady = true;
      notifyListeners();
    }

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      _setUser(data.session?.user);
    });
  }

  Future<({bool success, String? error})> signIn({
    required String email,
    required String password,
  }) async {
    _loading = true;
    _authError = '';
    notifyListeners();

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      // Block unconfirmed accounts (matches Nuxt email_confirmed_at check)
      if (user != null && user.emailConfirmedAt == null) {
        await Supabase.instance.client.auth.signOut();
        _authError =
            'Your signup is not complete yet. Please check your email and confirm your account. The confirmation email is sent by Supabase.';
        return (success: false, error: _authError);
      }

      _setUser(user);
      return (success: true, error: null);
    } on AuthException catch (e) {
      _authError = _translateAuthError(e.message);
      return (success: false, error: _authError);
    } catch (e) {
      _authError = _translateAuthError(e.toString());
      return (success: false, error: _authError);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<({bool success, String? error})> signUp({
    required String email,
    required String password,
  }) async {
    _loading = true;
    _authError = '';
    notifyListeners();

    try {
      await Supabase.instance.client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      return (success: true, error: null);
    } on AuthException catch (e) {
      _authError = _translateAuthError(e.message);
      return (success: false, error: _authError);
    } catch (e) {
      _authError = _translateAuthError(e.toString());
      return (success: false, error: _authError);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    _setUser(null);
  }
}
