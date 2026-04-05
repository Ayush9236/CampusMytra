import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_screen.dart';
import '../settings/theme_provider.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Animation controllers
  late AnimationController _bgController;
  late AnimationController _floatController;
  late AnimationController _entryController;
  late AnimationController _shakeController;

  late Animation<double> _bgAnimation;
  late Animation<double> _floatAnimation;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();

    // Background gradient animation
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _bgAnimation = CurvedAnimation(parent: _bgController, curve: Curves.easeInOut);

    // Floating particles
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _floatAnimation = CurvedAnimation(parent: _floatController, curve: Curves.easeInOut);

    // Entry animations
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.2, 1.0, curve: Curves.easeOut)),
    );

    // Shake animation for errors
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _floatController.dispose();
    _entryController.dispose();
    _shakeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _emailError;
  String? _passwordError;

  bool _validateInputs() {
    String? emailErr;
    String? passErr;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Email validation
    if (email.isEmpty) {
      emailErr = 'Email is required';
    } else if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      emailErr = 'Enter a valid email address';
    }

    // Password validation
    if (password.isEmpty) {
      passErr = 'Password is required';
    } else if (password.length < 8) {
      passErr = 'Password must be at least 8 characters';
    }

    setState(() {
      _emailError = emailErr;
      _passwordError = passErr;
    });

    return emailErr == null && passErr == null;
  }

  Future<void> _login() async {
    if (!_validateInputs()) {
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);

      // Get the raw error string for matching
      final raw = e.toString().toLowerCase();
      final String msg;

      if (raw.contains('invalid login') ||
          raw.contains('invalid credentials') ||
          raw.contains('wrong password') ||
          raw.contains('invalid email or password')) {
        msg = 'Wrong email or password 🔐';
      } else if (raw.contains('email not confirmed') ||
                 raw.contains('not confirmed')) {
        msg = 'Please confirm your email first — check your inbox 📧';
      } else if (raw.contains('too many requests') ||
                 raw.contains('rate limit')) {
        msg = 'Too many attempts — wait a moment and try again ⏳';
      } else if (raw.contains('network') ||
                 raw.contains('socket') ||
                 raw.contains('connection')) {
        msg = 'No internet connection — check your network 📶';
      } else if (raw.contains('user not found') ||
                 raw.contains('not found')) {
        msg = 'No account with this email — sign up first 👇';
      } else {
        // Show actual error in debug — helps diagnose unknown issues
        msg = 'Login failed: ${e.toString().replaceAll('AuthException: ', '')}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Text('❌  '),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: AppColors.surface(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Stack(
        children: [
          // ── ANIMATED BACKGROUND ──
          _AnimatedBackground(animation: _bgAnimation),

          // ── FLOATING PARTICLES ──
          _FloatingParticles(animation: _floatAnimation),

          // ── MAIN CONTENT ──
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    // ── LOGO SECTION ──
                    FadeTransition(
                      opacity: _fadeIn,
                      child: Column(
                        children: [
                          // Logo container with glow
                          AnimatedBuilder(
                            animation: _floatAnimation,
                            builder: (_, child) => Transform.translate(
                              offset: Offset(0, sin(_floatAnimation.value * pi) * 8),
                              child: child,
                            ),
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6C63FF).withOpacity(0.6),
                                    blurRadius: 30,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text('🎓', style: TextStyle(fontSize: 48)),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // App name with gradient
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF9D8FFF), Colors.white, Color(0xFF6C63FF)],
                            ).createShader(bounds),
                            child: const Text(
                              'CampusMytra',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // Tagline
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF6C63FF).withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Image.network(
                                    'https://iukxnbifojobmerspvxn.supabase.co/storage/v1/object/public/buzz-images/kaarma_techis_logo.png',
                                    height: 16,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Powered by KA-arma Techis',
                                  style: TextStyle(
                                    color: Color(0xFF9D8FFF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),

                    // ── FORM CARD ──
                    SlideTransition(
                      position: _slideUp,
                      child: FadeTransition(
                        opacity: _fadeIn,
                        child: AnimatedBuilder(
                          animation: _shakeAnimation,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(
                              sin(_shakeAnimation.value * pi * 6) * 8 *
                                  (1 - _shakeAnimation.value),
                              0,
                            ),
                            child: child,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: AppColors.surface(context),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: const Color(0xFF6C63FF).withOpacity(0.2),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C63FF).withOpacity(0.08),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Welcome text
                                Text(
                                  'Welcome back 👋',
                                  style: TextStyle(
                                    color: AppColors.text(context),
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Login to your account',
                                  style: TextStyle(
                                    color: AppColors.textSecondary(context),
                                    fontSize: 14,
                                  ),
                                ),

                                const SizedBox(height: 28),

                                // Email field
                                _NeonTextField(
                                  controller: _emailController,
                                  hint: 'your@email.com',
                                  icon: Icons.alternate_email_rounded,
                                  accentColor: const Color(0xFF6C63FF),
                                  keyboardType: TextInputType.emailAddress,
                                  errorText: _emailError,
                                  onChanged: (_) => setState(() => _emailError = null),
                                ),

                                const SizedBox(height: 16),

                                // Password field
                                _NeonTextField(
                                  controller: _passwordController,
                                  hint: 'Password',
                                  icon: Icons.lock_outline_rounded,
                                  accentColor: const Color.fromARGB(255, 108, 80, 235),
                                  obscureText: _obscurePassword,
                                  errorText: _passwordError,
                                  onChanged: (_) => setState(() => _passwordError = null),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      color: AppColors.textSecondary(context),
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword),
                                  ),
                                  onSubmitted: (_) => _login(),
                                ),

                                const SizedBox(height: 28),

                                // Login button
                                _GlowButton(
                                  onTap: _isLoading ? null : _login,
                                  isLoading: _isLoading,
                                ),

                                const SizedBox(height: 20),

                                // Divider
                                Row(
                                  children: [
                                    Expanded(child: Divider(color: AppColors.border(context))),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text('or',
                                        style: TextStyle(
                                          color: AppColors.textHint(context),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Expanded(child: Divider(color: AppColors.border(context))),
                                  ],
                                ),

                                const SizedBox(height: 20),

                                // Sign up link
                                Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.push(
                                        context,
                                        PageRouteBuilder(
                                          pageBuilder: (_, __, ___) => const SignupScreen(),
                                          transitionsBuilder: (_, anim, __, child) =>
                                              SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(1, 0),
                                              end: Offset.zero,
                                            ).animate(CurvedAnimation(
                                              parent: anim,
                                              curve: Curves.easeOut,
                                            )),
                                            child: child,
                                          ),
                                        ),
                                      );
                                    },
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: "No account? ",
                                            style: TextStyle(
                                              color: AppColors.textSecondary(context),
                                              fontSize: 14,
                                            ),
                                          ),
                                          const TextSpan(
                                            text: "Sign up 🔥",
                                            style: TextStyle(
                                              color: Color(0xFF6C63FF),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── SOCIAL PROOF ──
                    FadeTransition(
                      opacity: _fadeIn,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '🔥 ',
                            style: TextStyle(fontSize: 14),
                          ),
                          //Text(
                            //'Joined by 100+ AKGEC students',
                            //style: TextStyle(
                              //color: Colors.white.withOpacity(0.4),
                              //fontSize: 12,
                           // ),
                          //),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ANIMATED BACKGROUND
// ============================================================
class _AnimatedBackground extends StatelessWidget {
  final Animation<double> animation;
  const _AnimatedBackground({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(
              -0.5 + animation.value * 0.4,
              -0.8 + animation.value * 0.3,
            ),
            radius: 1.2,
            colors: const [
              Color(0xFF1A0533),
              Color(0xFF080B14),
              Color(0xFF080B14),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FLOATING PARTICLES
// ============================================================
class _FloatingParticles extends StatelessWidget {
  final Animation<double> animation;
  const _FloatingParticles({required this.animation});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final particles = [
      {'emoji': '⚡', 'x': 0.1, 'y': 0.15, 'size': 20.0},
      {'emoji': '🎓', 'x': 0.85, 'y': 0.08, 'size': 18.0},
      {'emoji': '🃏', 'x': 0.05, 'y': 0.6, 'size': 16.0},
      {'emoji': '⚔️', 'x': 0.9, 'y': 0.45, 'size': 18.0},
      {'emoji': '🌟', 'x': 0.75, 'y': 0.75, 'size': 14.0},
      {'emoji': '💻', 'x': 0.15, 'y': 0.85, 'size': 16.0},
    ];

    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => Stack(
        children: particles.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final offset = sin((animation.value + i * 0.3) * pi) * 10;
          return Positioned(
            left: (p['x'] as double) * size.width,
            top: (p['y'] as double) * size.height + offset,
            child: Opacity(
              opacity: 0.15,
              child: Text(
                p['emoji'] as String,
                style: TextStyle(fontSize: p['size'] as double),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================
// NEON TEXT FIELD
// ============================================================
class _NeonTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color accentColor;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final Function(String)? onSubmitted;
  final Function(String)? onChanged;
  final String? errorText;

  const _NeonTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.accentColor,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.onSubmitted,
    this.onChanged,
    this.errorText,
  });

  @override
  State<_NeonTextField> createState() => _NeonTextFieldState();
}

class _NeonTextFieldState extends State<_NeonTextField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError
                  ? Colors.red.withOpacity(0.8)
                  : _focused
                      ? widget.accentColor.withOpacity(0.8)
                      : AppColors.border(context),
              width: (_focused || hasError) ? 1.5 : 1,
            ),
            boxShadow: hasError
                ? [BoxShadow(color: Colors.red.withOpacity(0.1), blurRadius: 8)]
                : _focused
                    ? [BoxShadow(color: widget.accentColor.withOpacity(0.15), blurRadius: 12, spreadRadius: 1)]
                    : [],
            color: AppColors.surfaceVariant(context),
          ),
          child: Focus(
            onFocusChange: (v) => setState(() => _focused = v),
            child: TextField(
              controller: widget.controller,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: AppColors.textHint(context),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  widget.icon,
                  color: hasError
                      ? Colors.red
                      : _focused
                          ? widget.accentColor
                          : AppColors.textHint(context),
                  size: 20,
                ),
                suffixIcon: widget.suffixIcon,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 13),
                const SizedBox(width: 4),
                Text(
                  widget.errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// GLOW BUTTON
// ============================================================
class _GlowButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isLoading;

  const _GlowButton({required this.onTap, required this.isLoading});

  @override
  State<_GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<_GlowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _pressController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Let\'s Go',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('🚀', style: TextStyle(fontSize: 16)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
