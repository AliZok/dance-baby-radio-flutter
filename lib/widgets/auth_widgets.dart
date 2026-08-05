import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Shared auth page chrome matching Nuxt login/register pages.
class AuthScaffold extends StatelessWidget {
  final Widget child;

  const AuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Matches Nuxt `.back-img { filter: blur(8px) }`
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Image.asset(
              'assets/images/background-dance-1.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.overlayTop, AppColors.overlayBottom],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const AuthCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.authCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DANCE BABY RADIO',
            textAlign: TextAlign.center,
            style: GoogleFonts.daysOne(
              fontSize: 26,
              color: AppColors.brand,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.brandSoft.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class AuthTextField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? errorText;

  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.errorText,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscure;
  }

  @override
  void didUpdateWidget(covariant AuthTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.obscure && widget.obscure) {
      _obscured = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          obscureText: widget.obscure && _obscured,
          keyboardType: widget.keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
            filled: true,
            fillColor: AppColors.inputBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary.withOpacity(0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.primary.withOpacity(0.55)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.danger),
            ),
            errorText: widget.errorText,
            errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12),
            suffixIcon: widget.obscure
                ? IconButton(
                    onPressed: () => setState(() => _obscured = !_obscured),
                    tooltip: _obscured ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.brandSoft.withOpacity(0.85),
                      size: 22,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.loading,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary.withOpacity(0.28),
          disabledBackgroundColor: AppColors.primary.withOpacity(0.14),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(
          loading ? '$label...' : label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
