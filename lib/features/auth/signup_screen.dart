import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';
import 'otp_verification_screen.dart';

final supabase = Supabase.instance.client;

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with TickerProviderStateMixin {
  final _nameController     = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _collegeSearchController = TextEditingController();
  int _selectedYear = 2;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // College / branch from DB
  List<Map<String,dynamic>> _collegeSuggestions = [];
  String? _selectedCollegeId;
  String? _selectedCollegeName;
  bool _showSuggestions = false;

  final List<int> _years = [1, 2, 3, 4];

  // Username availability
  bool? _usernameAvailable;   // null = unchecked, true = free, false = taken
  bool _checkingUsername = false;
  Timer? _usernameDebounce;
  List<String> _usernameSuggestions = [];

  // Validation errors
  String? _nameError;
  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _collegeError;

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
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _bgAnimation = CurvedAnimation(parent: _bgController, curve: Curves.easeInOut);

    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _floatAnimation = CurvedAnimation(parent: _floatController, curve: Curves.easeInOut);

    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.2, 1.0, curve: Curves.easeOut)));
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.1, 1.0, curve: Curves.easeOut)));

    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _bgController.dispose(); _floatController.dispose();
    _entryController.dispose(); _shakeController.dispose();
    _nameController.dispose(); _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose(); _studentIdController.dispose();
    _collegeSearchController.dispose();
    super.dispose();
  }

  // ── COLLEGE SEARCH ──
  Future<void> _searchColleges(String query) async {
    if (query.length < 2) {
      setState(() { _collegeSuggestions = []; _showSuggestions = false; });
      return;
    }
    try {
      final data = await supabase.from('colleges')
          .select().ilike('name', '%$query%').limit(6);
      setState(() {
        _collegeSuggestions = List<Map<String,dynamic>>.from(data);
        _showSuggestions = true;
      });
    } catch (_) {}
  }



  // ── USERNAME AVAILABILITY CHECK ──
  void _onUsernameChanged(String val) {
    final clean = val.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (clean != val) {
      _usernameController.value = _usernameController.value.copyWith(
        text: clean,
        selection: TextSelection.collapsed(offset: clean.length));
    }
    setState(() {
      _usernameError = null;
      _usernameAvailable = null;
      _usernameSuggestions = [];
    });
    _usernameDebounce?.cancel();
    if (clean.length < 3) return;
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _checkingUsername = true);
      final available = await _isUsernameAvailable(clean);
      if (!mounted) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = available;
        if (!available) _usernameSuggestions = _generateSuggestions(clean);
      });
    });
  }

  List<String> _generateSuggestions(String base) {
    final rng = Random();
    final fullName = _nameController.text.trim().toLowerCase();
    final parts = fullName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

    // Build name parts: first, last, firstlast, first initial + last
    final first = parts.isNotEmpty ? parts.first.replaceAll(RegExp(r'[^a-z0-9]'), '') : '';
    final last  = parts.length > 1  ? parts.last.replaceAll(RegExp(r'[^a-z0-9]'), '')  : '';
    final firstLast = '$first$last';
    final initLast  = first.isNotEmpty && last.isNotEmpty ? '${first[0]}$last' : '';

    final candidates = <String>{};

    for (final nameBase in [first, last, firstLast, initLast]
        .where((n) => n.length >= 3)) {
      candidates.add('$nameBase${rng.nextInt(999)}');
      candidates.add('${nameBase}_${rng.nextInt(99)}');
      candidates.add('$nameBase${DateTime.now().year % 100}');
      if (last.isNotEmpty) candidates.add('${nameBase}_$last');
    }

    // Fallback to base if name not filled
    if (candidates.isEmpty) {
      candidates.add('$base${rng.nextInt(999)}');
      candidates.add('${base}_${rng.nextInt(99)}');
    }

    final valid = candidates
        .where((u) => u.length >= 3 && u.length <= 20)
        .toSet()
        .toList()
      ..shuffle();
    return valid.take(4).toList();
  }

  void _selectCollege(String id, String name) {
    setState(() {
      _selectedCollegeId = id; _selectedCollegeName = name;
      _collegeSearchController.text = name;
      _showSuggestions = false; _collegeSuggestions = [];
      _collegeError = null;
    });
  }

  Future<void> _addAndSelectCollege(String name) async {
    if (name.trim().isEmpty) return;
    final trimmed = name.trim();

    // DO NOT insert into colleges table — owner must verify first
    // Just save the typed name locally as pending
    setState(() {
      _selectedCollegeId = 'new_${trimmed.hashCode}'; // marks as unverified
      _selectedCollegeName = trimmed;
      _collegeSearchController.text = trimmed;
      _showSuggestions = false;
      _collegeSuggestions = [];
      _collegeError = null;
    });
  }

  // ── VALIDATION ──
  bool _validateInputs() {
    String? nameErr, usernameErr, emailErr, passErr, collegeErr;

    if (_nameController.text.trim().isEmpty) nameErr = 'Name is required';
    else if (_nameController.text.trim().length < 3) nameErr = 'At least 3 characters';

    final uname = _usernameController.text.trim().toLowerCase();
    if (uname.isEmpty) usernameErr = 'Username is required';
    else if (uname.length < 3) usernameErr = 'At least 3 characters';
    else if (uname.length > 20) usernameErr = 'Max 20 characters';
    else if (!RegExp(r'^[a-z0-9_]+$').hasMatch(uname))
      usernameErr = 'Only letters, numbers and _';

    if (_emailController.text.trim().isEmpty) emailErr = 'Email is required';
    else if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(_emailController.text.trim())) emailErr = 'Enter a valid email';

    if (_passwordController.text.isEmpty) {
      passErr = 'Password is required';
    } else if (_passwordController.text.length < 8) {
      passErr = 'Min 8 characters';
    } else if (!RegExp(r'(?=.*[A-Za-z])(?=.*\d)').hasMatch(_passwordController.text)) {
      passErr = 'Must contain letters and numbers';
    }

    if (_selectedCollegeId == null && _collegeSearchController.text.trim().isEmpty)
      collegeErr = 'Tap a college from the list below';

    setState(() {
      _nameError = nameErr; _usernameError = usernameErr;
      _emailError = emailErr; _passwordError = passErr; _collegeError = collegeErr;
    });

    return nameErr == null && usernameErr == null && emailErr == null
        && passErr == null && collegeErr == null;
  }

  Future<bool> _isUsernameAvailable(String username) async {
    try {
      final result = await supabase.from('profiles')
          .select('id').eq('username', username).maybeSingle();
      return result == null;
    } catch (_) { return true; }
  }

  // ── SIGNUP ──
  Future<void> _signup() async {
    // If user typed a college name but didn't tap a suggestion, auto-resolve it
    final typedCollege = _collegeSearchController.text.trim();
    if (_selectedCollegeId == null && typedCollege.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        // FIRST: check already-loaded suggestions (no DB call needed)
        if (_collegeSuggestions.isNotEmpty) {
          final best = _collegeSuggestions.first;
          _selectCollege(best['id'].toString(), best['name'].toString());
          await Future.delayed(const Duration(milliseconds: 700));
        } else {
          // SECOND: search DB for existing college before trying to insert
          final results = await supabase.from('colleges')
              .select().ilike('name', '%$typedCollege%').limit(1).maybeSingle();
          if (results != null) {
            _selectCollege(results['id'].toString(), results['name'].toString());
            await Future.delayed(const Duration(milliseconds: 600));
          } else {
            // Truly new college — insert only if nothing found
            await _addAndSelectCollege(typedCollege);
            if (_selectedCollegeId != null) {
              await Future.delayed(const Duration(milliseconds: 600));
            }
          }
        }
      } catch (_) {}
      setState(() => _isLoading = false);
    }

    if (!_validateInputs()) {
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _isLoading = true);
    // Check username uniqueness before signing up
    final uname = _usernameController.text.trim().toLowerCase();
    final available = await _isUsernameAvailable(uname);
    if (!available) {
      setState(() { _isLoading = false; _usernameError = 'Username already taken'; });
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.mediumImpact();

    try {
      // Sign up with email+password — Supabase sends confirmation OTP automatically
      await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        emailRedirectTo: null,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Navigate to OTP screen — profile is only created after OTP verification
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OtpVerificationScreen(
          email:       _emailController.text.trim(),
          password:    _passwordController.text,
          name:        _nameController.text.trim(),
          username:    uname,
          collegeId:   _selectedCollegeId,
          collegeName: _selectedCollegeName ?? '',
          studentId:   _studentIdController.text.trim().isEmpty
              ? null : _studentIdController.text.trim(),
          year:        _selectedYear,
        ),
      ));
    } on AuthException catch (e) {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      final msg = e.message.contains('already registered')
          ? 'Email already taken! Try logging in 👀' : e.message;
      _showSnack('❌ $msg', Colors.red.shade800);
    } catch (e) {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      _showSnack('❌ Something went wrong: $e', Colors.red.shade800);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Stack(children: [
        _AnimatedBg(animation: _bgAnimation),
        _Particles(animation: _floatAnimation),
        SafeArea(child: Column(children: [
          // ── TOP BAR ──
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
            child: FadeTransition(opacity: _fadeIn, child: Row(children: [
              IconButton(
                onPressed: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
                icon: Icon(Icons.arrow_back_ios_rounded, color: AppColors.textSecondary(context))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.3))),
                child: const Text('✨ Free 100 coins on signup!',
                  style: TextStyle(color: Color(0xFFFFB800), fontSize: 11, fontWeight: FontWeight.w700))),
            ])),
          ),

          Expanded(child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const SizedBox(height: 16),

              // ── LOGO ──
              FadeTransition(opacity: _fadeIn, child: AnimatedBuilder(
                animation: _floatAnimation,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, sin(_floatAnimation.value * pi) * 6), child: child),
                child: Container(width: 70, height: 70,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00B8A3), Color(0xFF6C63FF)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                      blurRadius: 24, spreadRadius: 2)]),
                  child: const Center(child: Text('🚀', style: TextStyle(fontSize: 36)))),
              )),
              const SizedBox(height: 16),

              FadeTransition(opacity: _fadeIn, child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF00B8A3), Colors.white, Color(0xFF6C63FF)]).createShader(bounds),
                child: const Text('Join the squad 🔥', style: TextStyle(color: Colors.white,
                  fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)))),
              const SizedBox(height: 4),
              FadeTransition(opacity: _fadeIn, child: Text('Create your CampusMytra account',
                style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13))),
              const SizedBox(height: 28),

              // ── FORM CARD ──
              SlideTransition(position: _slideUp, child: FadeTransition(opacity: _fadeIn,
                child: AnimatedBuilder(animation: _shakeAnimation,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(sin(_shakeAnimation.value * pi * 6) * 8 * (1 - _shakeAnimation.value), 0),
                    child: child),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFF00B8A3).withValues(alpha: 0.2)),
                      boxShadow: [BoxShadow(color: const Color(0xFF00B8A3).withValues(alpha: 0.06),
                        blurRadius: 40, spreadRadius: 10)]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                      // Name
                      _SignupTextField(controller: _nameController, hint: 'Full Name',
                        icon: Icons.person_outline_rounded, accentColor: const Color(0xFF00B8A3),
                        errorText: _nameError, onChanged: (_) => setState(() => _nameError = null)),
                      const SizedBox(height: 14),

                      // Username
                      _SignupTextField(
                        controller: _usernameController,
                        hint: 'Username (e.g. ayush_01)',
                        icon: Icons.alternate_email_rounded,
                        accentColor: const Color(0xFF818CF8),
                        errorText: _usernameError,
                        suffixIcon: _checkingUsername
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8))))
                            : _usernameAvailable == true
                                ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20)
                                : _usernameAvailable == false
                                    ? const Icon(Icons.cancel_rounded, color: Colors.red, size: 20)
                                    : null,
                        onChanged: _onUsernameChanged),

                      // Availability message
                      if (_usernameAvailable == false) ...[
                        const SizedBox(height: 4),
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text('❌ Username already taken',
                              style: TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      ] else if (_usernameAvailable == true) ...[
                        const SizedBox(height: 4),
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text('✅ Username is available!',
                              style: TextStyle(color: Colors.green, fontSize: 12)),
                        ),
                      ],

                      // Suggestions
                      if (_usernameSuggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 6),
                          child: Text('Try one of these:',
                              style: TextStyle(color: Color(0xFF7B8DB7), fontSize: 12)),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _usernameSuggestions.map((s) => GestureDetector(
                            onTap: () {
                              _usernameController.text = s;
                              _onUsernameChanged(s);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF818CF8).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.4)),
                              ),
                              child: Text(s, style: const TextStyle(
                                  color: Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          )).toList(),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Email
                      _SignupTextField(controller: _emailController, hint: 'Email Address',
                        icon: Icons.alternate_email_rounded, accentColor: const Color(0xFF6C63FF),
                        keyboardType: TextInputType.emailAddress,
                        errorText: _emailError, onChanged: (_) => setState(() => _emailError = null)),
                      const SizedBox(height: 14),

                      // Password
                      _SignupTextField(controller: _passwordController, hint: 'Password (min 8 chars)',
                        icon: Icons.lock_outline_rounded,
                        accentColor: const Color.fromARGB(255, 55, 255, 62),
                        obscureText: _obscurePassword,
                        errorText: _passwordError,
                        onChanged: (_) => setState(() => _passwordError = null),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: AppColors.textSecondary(context), size: 20),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword))),
                      const SizedBox(height: 14),

                      // Student ID (optional)
                      _SignupTextField(controller: _studentIdController,
                        hint: 'Student ID (optional)',
                        icon: Icons.badge_outlined,
                        accentColor: const Color(0xFFFFB800)),
                      const SizedBox(height: 20),

                      // ── COLLEGE SECTION ──
                      Text('Your College', style: TextStyle(color: AppColors.textSecondary(context),
                        fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      const SizedBox(height: 10),

                      // College search field
                      _CollegeSearchField(
                        controller: _collegeSearchController,
                        errorText: _collegeError,
                        onChanged: (val) {
                          setState(() => _collegeError = null);
                          if (_selectedCollegeId != null && val != _selectedCollegeName) {
                            setState(() {
                              _selectedCollegeId = null; _selectedCollegeName = null;
                            });
                          }
                          _searchColleges(val);
                        },
                        onSubmitted: (val) {
                          if (_collegeSuggestions.length == 1 && _selectedCollegeId == null) {
                            final c = _collegeSuggestions.first;
                            _selectCollege(c['id'].toString(), c['name'].toString());
                          } else if (_collegeSuggestions.isEmpty && val.isNotEmpty) {
                            _addAndSelectCollege(val);
                          }
                        },
                      ),

                      // Suggestions dropdown
                      if (_showSuggestions && _collegeSuggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surface(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12)]),
                          child: Column(children: [
                            ..._collegeSuggestions.map((c) => InkWell(
                              onTap: () => _selectCollege(c['id'].toString(), c['name'].toString()),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(children: [
                                  const Text('🏫', style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(c['name'].toString(), style: TextStyle(
                                      color: AppColors.text(context), fontSize: 13, fontWeight: FontWeight.w600)),
                                    Text(c['code'].toString(), style: TextStyle(
                                      color: AppColors.textSecondary(context), fontSize: 11)),
                                  ])),
                                ])))),
                            // Add new college option — only when no suggestions found
                            if (_collegeSuggestions.isEmpty)
                              InkWell(
                                onTap: () => _addAndSelectCollege(_collegeSearchController.text.trim()),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(children: [
                                    const Icon(Icons.add_circle_outline, color: Color(0xFF00B8A3), size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(
                                      'Add "${_collegeSearchController.text.trim()}"',
                                      style: const TextStyle(color: Color(0xFF00B8A3),
                                        fontSize: 13, fontWeight: FontWeight.w600))),
                                  ]))),
                          ])),

                      // Selected college badge
                      if (_selectedCollegeId != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00B8A3).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF00B8A3).withValues(alpha: 0.3))),
                          child: Row(children: [
                            const Icon(Icons.check_circle, color: Color(0xFF00B8A3), size: 14),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_selectedCollegeName ?? '',
                              style: const TextStyle(color: Color(0xFF00B8A3),
                                fontSize: 12, fontWeight: FontWeight.w600))),
                          ])),
                      ],

                      if (_collegeError != null) ...[
                        const SizedBox(height: 5),
                        Row(children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 13),
                          const SizedBox(width: 4),
                          Text(_collegeError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ]),
                      ],

                      const SizedBox(height: 16),

                      // ── BRANCH PICKER ──
                      Text('Your Branch', style: TextStyle(color: AppColors.textSecondary(context),
                        fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      const SizedBox(height: 10),



                      // ── YEAR ──
                      Text('Academic Year', style: TextStyle(color: AppColors.textSecondary(context),
                        fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      const SizedBox(height: 10),
                      Row(children: _years.map((y) {
                        final isSelected = _selectedYear == y;
                        return Expanded(child: Padding(
                          padding: EdgeInsets.only(right: y < 4 ? 8 : 0),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedYear = y),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFFFB800).withValues(alpha: 0.15) : AppColors.surfaceVariant(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFFB800) : const Color(0xFFFFB800).withValues(alpha: 0.2),
                                  width: isSelected ? 2 : 1)),
                              child: Center(child: Text('Y$y', style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800,
                                color: isSelected ? const Color(0xFFFFB800) : AppColors.textHint(context))))))));
                      }).toList()),

                      const SizedBox(height: 24),

                      // Signup button
                      _SignupButton(onTap: _isLoading ? null : _signup, isLoading: _isLoading),
                      const SizedBox(height: 16),

                      Center(child: Text('By signing up you agree to our Terms & Privacy Policy',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textHint(context).withValues(alpha: 0.6), fontSize: 11))),
                    ]),
                  ),
                ),
              )),

              const SizedBox(height: 24),
              FadeTransition(opacity: _fadeIn, child: GestureDetector(
                onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
                child: RichText(text: TextSpan(children: [
                  TextSpan(text: 'Already have an account? ',
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
                  const TextSpan(text: 'Login fr 🔑',
                    style: TextStyle(color: Color(0xFF6C63FF), fontSize: 14, fontWeight: FontWeight.w700)),
                ])))),
              const SizedBox(height: 32),
            ]),
          )),
        ])),
      ]),
    );
  }
}

// ── COLLEGE SEARCH FIELD ──

// ── BRANCH CHIP ──
// ── BRANCH GROUPED PICKER ──
// ── ANIMATED BACKGROUND ──
// ── COLLEGE SEARCH FIELD ──
class _CollegeSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final Function(String) onChanged;
  final Function(String)? onSubmitted;

  const _CollegeSearchField({
    required this.controller,
    this.errorText,
    required this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: errorText != null
                ? Colors.red.withValues(alpha: 0.6)
                : const Color(0xFF6C63FF).withValues(alpha: 0.3))),
        child: TextField(
          controller: controller,
          style: TextStyle(color: AppColors.text(context), fontSize: 14),
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: 'Search your college...',
            hintStyle: TextStyle(color: AppColors.textHint(context), fontSize: 13),
            prefixIcon: const Icon(Icons.school_outlined,
              color: Color(0xFF6C63FF), size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
        ),
      ),
      if (errorText != null) ...[
        const SizedBox(height: 5),
        Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 13),
          const SizedBox(width: 4),
          Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ]),
      ],
    ]);
  }
}


class _AnimatedBg extends StatelessWidget {
  final Animation<double> animation;
  const _AnimatedBg({required this.animation});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (ctx, child) => Container(decoration: BoxDecoration(gradient: RadialGradient(
      center: Alignment(0.5 - animation.value * 0.4, -0.8 + animation.value * 0.3),
      radius: 1.2,
      colors: const [Color(0xFF00251F), Color(0xFF080B14), Color(0xFF080B14)],
      stops: const [0.0, 0.5, 1.0]))));
}

// ── FLOATING PARTICLES ──
class _Particles extends StatelessWidget {
  final Animation<double> animation;
  const _Particles({required this.animation});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final particles = [
      {'emoji': '🎓', 'x': 0.08, 'y': 0.12}, {'emoji': '💻', 'x': 0.88, 'y': 0.06},
      {'emoji': '🃏', 'x': 0.05, 'y': 0.55}, {'emoji': '⚡', 'x': 0.92, 'y': 0.42},
      {'emoji': '🌟', 'x': 0.78, 'y': 0.78}, {'emoji': '🔥', 'x': 0.12, 'y': 0.82},
    ];
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, child) => Stack(children: particles.asMap().entries.map((e) {
        final offset = sin((animation.value + e.key * 0.4) * pi) * 10;
        return Positioned(
          left: (e.value['x'] as double) * size.width,
          top: (e.value['y'] as double) * size.height + offset,
          child: Opacity(opacity: 0.12,
            child: Text(e.value['emoji'] as String, style: const TextStyle(fontSize: 18))));
      }).toList()));
  }
}

// ── SIGNUP TEXT FIELD ──
class _SignupTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color accentColor;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final Function(String)? onChanged;
  final String? errorText;

  const _SignupTextField({required this.controller, required this.hint,
    required this.icon, required this.accentColor, this.obscureText = false,
    this.suffixIcon, this.keyboardType, this.onChanged, this.errorText});

  @override
  State<_SignupTextField> createState() => _SignupTextFieldState();
}

class _SignupTextFieldState extends State<_SignupTextField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasError ? Colors.red.withValues(alpha: 0.8)
                : _focused ? widget.accentColor.withValues(alpha: 0.8)
                : AppColors.border(context),
            width: (_focused || hasError) ? 1.5 : 1),
          boxShadow: hasError ? [BoxShadow(color: Colors.red.withValues(alpha: 0.1), blurRadius: 8)]
              : _focused ? [BoxShadow(color: widget.accentColor.withValues(alpha: 0.15), blurRadius: 12, spreadRadius: 1)]
              : [],
          color: AppColors.surfaceVariant(context)),
        child: Focus(
          onFocusChange: (v) => setState(() => _focused = v),
          child: TextField(
            controller: widget.controller, obscureText: widget.obscureText,
            keyboardType: widget.keyboardType, onChanged: widget.onChanged,
            style: TextStyle(color: AppColors.text(context), fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(color: AppColors.textHint(context), fontSize: 14),
              prefixIcon: Icon(widget.icon,
                color: hasError ? Colors.red : _focused ? widget.accentColor : AppColors.textHint(context), size: 20),
              suffixIcon: widget.suffixIcon,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              filled: true, fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16))))),
      if (hasError) ...[
        const SizedBox(height: 5),
        Padding(padding: const EdgeInsets.only(left: 4), child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 13),
          const SizedBox(width: 4),
          Text(widget.errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ])),
      ],
    ]);
  }
}

// ── SIGNUP BUTTON ──
class _SignupButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isLoading;
  const _SignupButton({required this.onTap, required this.isLoading});
  @override
  State<_SignupButton> createState() => _SignupButtonState();
}

class _SignupButtonState extends State<_SignupButton> with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _pressController.forward(),
    onTapUp: (_) { _pressController.reverse(); widget.onTap?.call(); },
    onTapCancel: () => _pressController.reverse(),
    child: ScaleTransition(scale: _scaleAnimation,
      child: Container(width: double.infinity, height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF00B8A3), Color(0xFF6C63FF)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: const Color(0xFF00B8A3).withValues(alpha: 0.4),
            blurRadius: 20, offset: const Offset(0, 6))]),
        child: Center(child: widget.isLoading
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Create Account', style: TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              SizedBox(width: 8),
              Text('🎉', style: TextStyle(fontSize: 16)),
            ])))));
}
