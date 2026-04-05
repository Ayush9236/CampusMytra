import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_screen.dart';
import '../settings/theme_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// OTP VERIFICATION SCREEN
// Verifies email OTP sent by Supabase, then creates the account + profile.
// ══════════════════════════════════════════════════════════════════════════════

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String password;
  final String name;
  final String username;
  final String? collegeId;
  final String collegeName;
  final String? studentId;
  final int year;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.password,
    required this.name,
    required this.username,
    required this.collegeId,
    required this.collegeName,
    required this.studentId,
    required this.year,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _sb = Supabase.instance.client;
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isResending = false;
  int _resendCooldown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    // Auto-focus first box
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 0) {
        t.cancel();
      } else {
        if (mounted) { setState(() => _resendCooldown--); }
      }
    });
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _onDigitEntered(int index, String value) {
    if (value.length > 1) {
      // Handle paste — distribute digits across boxes
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      final nextEmpty = _controllers.indexWhere((c) => c.text.isEmpty);
      if (nextEmpty != -1) {
        _focusNodes[nextEmpty].requestFocus();
      } else {
        _focusNodes[5].requestFocus();
        _verify();
      }
      return;
    }

    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        // All 6 digits entered — auto-verify
        _focusNodes[5].unfocus();
        _verify();
      }
    }
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  Future<void> _verify() async {
    final code = _otpCode;
    if (code.length < 6) {
      _snack('Enter all 6 digits');
      return;
    }
    setState(() => _isVerifying = true);
    try {
      // 1. Verify OTP — this signs in / creates the Supabase Auth user
      await _sb.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: OtpType.signup,
      );

      final uid = _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('Auth failed');

      // 3. Check if profile already exists (safety)
      final existing = await _sb
          .from('profiles')
          .select('id')
          .eq('id', uid)
          .maybeSingle();

      if (existing == null) {
        final isRealCollege = widget.collegeId != null &&
            !widget.collegeId!.startsWith('new_');
        final collegeStatus = isRealCollege ? 'verified' : 'pending';

        // 4. Insert profile
        try {
          await _sb.from('profiles').insert({
            'id':           uid,
            'email':        widget.email,
            'name':         widget.name,
            'username':     widget.username,
            'branch':       '',
            'branch_name':  '',
            'branch_id':    null,
            'college_id':   isRealCollege ? widget.collegeId : null,
            'college_name': widget.collegeName,
            'student_id':   widget.studentId,
            'year':         widget.year,
            'coins':        100,
            'college_status': collegeStatus,
          });
        } catch (e) {
          // Fallback without college_status if column missing
          if (e.toString().contains('college_status') ||
              e.toString().contains('column')) {
            await _sb.from('profiles').insert({
              'id':           uid,
              'email':        widget.email,
              'name':         widget.name,
              'username':     widget.username,
              'branch':       '',
              'branch_name':  '',
              'branch_id':    null,
              'college_id':   isRealCollege ? widget.collegeId : null,
              'college_name': widget.collegeName,
              'student_id':   widget.studentId,
              'year':         widget.year,
              'coins':        100,
            });
          } else {
            rethrow;
          }
        }

        // 5. College verification request if new college
        if (!isRealCollege && widget.collegeName.isNotEmpty) {
          try {
            await _sb.from('college_verification_requests').insert({
              'user_id':     uid,
              'user_name':   widget.name,
              'user_email':  widget.email,
              'college_name': widget.collegeName,
              'branch_name': '',
              'status':      'pending',
              'expires_at':  DateTime.now()
                  .add(const Duration(hours: 24))
                  .toIso8601String(),
            });
          } catch (_) {}
        }
      }

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } on AuthException catch (e) {
      HapticFeedback.heavyImpact();
      _snack('Invalid OTP: ${e.message}');
      // Clear boxes on wrong OTP
      for (final c in _controllers) { c.clear(); }
      _focusNodes[0].requestFocus();
    } catch (e) {
      HapticFeedback.heavyImpact();
      _snack('Verification failed. Try again.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _isResending) return;
    setState(() => _isResending = true);
    try {
      await _sb.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      _snack('New OTP sent to ${widget.email}');
      _startCooldown();
      for (final c in _controllers) { c.clear(); }
      _focusNodes[0].requestFocus();
    } catch (_) {
      _snack('Failed to resend. Try again later.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF6C63FF);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      color: AppColors.textHint(context), size: 18),
                ),
              ),

              const SizedBox(height: 40),

              // Header
              Text('Verify your email',
                  style: TextStyle(
                      color: AppColors.text(context),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: TextStyle(color: AppColors.textHint(context), fontSize: 14, height: 1.5),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to\n'),
                    TextSpan(
                      text: widget.email,
                      style: TextStyle(
                          color: AppColors.textSecondary(context), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // OTP boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _OtpBox(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  onChanged: (v) => _onDigitEntered(i, v),
                  onBackspace: () => _onBackspace(i),
                )),
              ),

              const SizedBox(height: 40),

              // Verify button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: purple,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: purple.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Verify & Create Account',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),

              const SizedBox(height: 24),

              // Resend
              Center(
                child: _isResending
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.textHint(context)))
                    : GestureDetector(
                        onTap: _resendCooldown > 0 ? null : _resend,
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 14),
                            children: [
                              TextSpan(
                                  text: "Didn't receive it? ",
                                  style: TextStyle(color: AppColors.textHint(context))),
                              TextSpan(
                                text: _resendCooldown > 0
                                    ? 'Resend in ${_resendCooldown}s'
                                    : 'Resend',
                                style: TextStyle(
                                  color: _resendCooldown > 0
                                      ? AppColors.textHint(context)
                                      : purple,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              const SizedBox(height: 32),

              // Info note
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                ),
                child: const Row(children: [
                  Text('⏱️', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'OTP expires in 10 minutes. Check your spam folder if you don\'t see it.',
                      style: TextStyle(
                          color: Colors.amber, fontSize: 12, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Individual OTP digit box ──
class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 56,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 6, // allow paste of full 6 digits
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
              color: AppColors.text(context),
              fontSize: 22,
              fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: AppColors.surface(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.border(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.border(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 2),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
