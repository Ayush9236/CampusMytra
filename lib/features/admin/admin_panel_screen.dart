import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../buzz/image_viewer.dart';
import '../../services/app_icon_service.dart';
import 'admin_secrets.dart';

final supabase = Supabase.instance.client;

enum AdminRole { owner, college, branch }

AdminRole _roleFromString(String? s) {
  switch (s) {
    case 'college': return AdminRole.college;
    case 'branch':  return AdminRole.branch;
    default:        return AdminRole.owner;
  }
}

// ── ADMIN GATE ──
class AdminGateScreen extends StatefulWidget {
  const AdminGateScreen({Key? key}) : super(key: key);
  @override
  State<AdminGateScreen> createState() => _AdminGateScreenState();
}

class _AdminGateScreenState extends State<AdminGateScreen> {
  bool _isAdmin = false;
  bool _checking = true;
  AdminRole _role = AdminRole.owner;
  String? _adminCollegeId;
  String? _adminBranchId;
  String? _adminBranchName;
  DateTime? _adminExpiresAt; // ← NEW: track expiry

  @override
  void initState() { super.initState(); _checkAdminStatus(); }

  Future<void> _checkAdminStatus() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) { setState(() => _checking = false); return; }
    if (uid == kOwnerUserId) {
      setState(() { _isAdmin = true; _role = AdminRole.owner; _checking = false; });
      return;
    }
    try {
      final row = await supabase.from('admins')
          .select('is_owner, expires_at, role, college_id, branch_id, branch_name')
          .eq('user_id', uid).maybeSingle();
      if (row != null) {
        final expiresAt = row['expires_at'] != null
            ? DateTime.parse(row['expires_at'].toString()).toLocal() : null;
        final isValid = expiresAt == null || expiresAt.isAfter(DateTime.now());
        if (isValid) {
          setState(() {
            _isAdmin = true;
            _role = _roleFromString(row['role']?.toString());
            _adminCollegeId = row['college_id']?.toString();
            _adminBranchId = row['branch_id']?.toString();
            _adminBranchName = row['branch_name']?.toString();
            _adminExpiresAt = expiresAt; // ← NEW
            _checking = false;
          });
          return;
        }
      }
    } catch (_) {}
    setState(() => _checking = false);
  }

  bool get _isOwner => supabase.auth.currentUser?.id == kOwnerUserId;

  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(
      backgroundColor: Color(0xFF0A0E1A),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))));

    // Only the owner can interact; others see a locked overlay over the screen
    if (!_isOwner) {
      return Material(color: Colors.transparent, child: Stack(children: [
        // Background: admin screen visible but non-interactive
        IgnorePointer(
          ignoring: true,
          child: AdminLoginScreen(onLoginSuccess: (_, __, ___, ____, _) {}),
        ),
        // Foreground: frosted lock overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0A0E1A).withValues(alpha: 0.85),
                  const Color(0xFF0A0E1A).withValues(alpha: 0.92),
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                    border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.4), width: 2),
                  ),
                  child: const Icon(Icons.lock_rounded, color: Color(0xFF6C63FF), size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Coming Soon',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.4), width: 1),
                    ),
                    child: const Text(
                      'Go Back',
                      style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]));
    }

    if (_isAdmin) return AdminPanelScreen(
      role: _role, adminCollegeId: _adminCollegeId,
      adminBranchId: _adminBranchId, adminBranchName: _adminBranchName,
      expiresAt: _adminExpiresAt);
    return AdminLoginScreen(onLoginSuccess: (role, collegeId, branchId, branchName, expiresAt) {
      setState(() {
        _isAdmin = true; _role = role;
        _adminCollegeId = collegeId; _adminBranchId = branchId;
        _adminBranchName = branchName;
        _adminExpiresAt = expiresAt;
      });
    });
  }
}  

// ══════════════════════════════════════════════
// 🔐 ADMIN LOGIN SCREEN
// ══════════════════════════════════════════════
class AdminLoginScreen extends StatefulWidget {
  final void Function(AdminRole role, String? collegeId, String? branchId, String? branchName, DateTime? expiresAt) onLoginSuccess;
  const AdminLoginScreen({Key? key, required this.onLoginSuccess}) : super(key: key);
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {
  final _passCtrl = TextEditingController();
  final _otpCtrl  = TextEditingController();
  bool _obscure = true, _loading = false, _otpSent = false;
  String? _error;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween(begin: 0.0, end: 1.0).animate(_shakeCtrl);
  }

  @override
  void dispose() { _passCtrl.dispose(); _otpCtrl.dispose(); _shakeCtrl.dispose(); super.dispose(); }

  void _shake() { _shakeCtrl.forward(from: 0); HapticFeedback.heavyImpact(); }
  String _generateOtp() => (100000 + Random().nextInt(900000)).toString();
  bool get _isOwner => supabase.auth.currentUser?.id == kOwnerUserId;

  Future<void> _verifyOwnerPassword() async {
    if (_passCtrl.text.trim() != kOwnerPassword) {
      setState(() => _error = 'Incorrect password'); _shake(); return;
    }
    setState(() => _loading = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      final otp = _generateOtp();
      final expires = DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String();
      await supabase.from('admin_otps').upsert({
        'user_id': uid, 'otp_code': otp, 'expires_at': expires, 'used': false });
      setState(() { _otpSent = true; _error = null; _loading = false; });
    } catch (e) { setState(() { _error = 'Error: $e'; _loading = false; }); }
  }

  Future<void> _verifyOwnerOtp() async {
    setState(() => _loading = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      final row = await supabase.from('admin_otps').select()
          .eq('user_id', uid!).eq('used', false)
          .order('created_at', ascending: false).limit(1).maybeSingle();
      if (row == null || row['otp_code'] != _otpCtrl.text.trim()) {
        setState(() { _error = 'Invalid OTP'; _loading = false; }); _shake(); return;
      }
      final expires = DateTime.parse(row['expires_at'].toString());
      if (DateTime.now().isAfter(expires)) {
        setState(() { _error = 'OTP expired. Try again.'; _loading = false; }); _shake(); return;
      }
      await supabase.from('admin_otps').update({'used': true}).eq('id', row['id']);
      setState(() => _loading = false);
      widget.onLoginSuccess(AdminRole.owner, null, null, null, null);
    } catch (e) { setState(() { _error = 'Error: $e'; _loading = false; }); }
  }

  Future<void> _verifyGrantedAdmin() async {
    setState(() => _loading = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      final req = await supabase.from('admin_requests').select()
          .eq('user_id', uid!).eq('generated_password', _passCtrl.text.trim())
          .eq('generated_otp', _otpCtrl.text.trim()).eq('status', 'approved').maybeSingle();
      if (req == null) {
        setState(() { _error = 'Invalid credentials'; _loading = false; }); _shake(); return;
      }
      final expires = DateTime.parse(req['otp_expires_at'].toString());
      if (DateTime.now().isAfter(expires)) {
        setState(() { _error = 'OTP expired. Request new access.'; _loading = false; }); _shake(); return;
      }
      final role = _roleFromString(req['requested_role']?.toString());
      final accessExpires = req['access_expires_at'] != null
          ? DateTime.tryParse(req['access_expires_at'].toString()) : null;
      await supabase.from('admins').upsert({
        'user_id': uid, 'is_owner': false,
        'role': req['requested_role'] ?? 'branch',
        'college_id': req['college_id'],
        'branch_id': req['branch_id'],
        'branch_name': req['branch_name'],
        // Use the access_expires_at set when request was approved — NOT now()+30
        // This prevents tenure from resetting on every login
        'expires_at': accessExpires?.toUtc().toIso8601String()
            ?? req['access_expires_at'],
        'granted_at': DateTime.now().toUtc().toIso8601String(),
      });
      setState(() => _loading = false);
      widget.onLoginSuccess(role, req['college_id']?.toString(),
          req['branch_id']?.toString(), req['branch_name']?.toString(), accessExpires);
    } catch (e) { setState(() { _error = 'Error: $e'; _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 40),
          Container(width: 88, height: 88,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B37C8)]),
              boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.5),
                blurRadius: 32, spreadRadius: 4)]),
            child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 44)),
          const SizedBox(height: 24),
          const Text('Admin Access', style: TextStyle(fontSize: 28,
            fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text(_isOwner ? 'Welcome back, Owner 👑' : 'Enter your credentials',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
          const SizedBox(height: 40),

          if (_error != null) AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(sin(_shakeAnim.value * pi * 8) * 8, 0), child: child),
            child: Container(width: double.infinity, padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.4))),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
              ]))),

          if (!_otpSent) ...[
            _AdminField(controller: _passCtrl, label: 'Admin Password',
              icon: Icons.lock_outline, obscure: _obscure,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure)),
              onChanged: (_) => setState(() => _error = null)),
            const SizedBox(height: 16),

            if (!_isOwner) ...[
              _AdminField(controller: _otpCtrl, label: 'OTP Code',
                icon: Icons.pin_outlined, keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _error = null)),
              const SizedBox(height: 8),
              Text('Enter credentials shared by the owner',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
                textAlign: TextAlign.center),
            ] else ...[
              Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2))),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: Color(0xFF6C63FF), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'OTP will be saved to Supabase → admin_otps table. Check it there.',
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), height: 1.5))),
                ])),
            ],
            const SizedBox(height: 24),
            _AdminButton(label: _isOwner ? 'Generate OTP' : 'Login',
              loading: _loading,
              onTap: _isOwner ? _verifyOwnerPassword : _verifyGrantedAdmin),
          ] else ...[
            Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.withOpacity(0.3))),
              child: Column(children: [
                const Row(children: [
                  Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('OTP Generated!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text('Go to Supabase → Table Editor → admin_otps\nCopy the latest otp_code. Expires in 10 mins.',
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5), height: 1.6)),
              ])),
            _AdminField(controller: _otpCtrl, label: '6-Digit OTP',
              icon: Icons.pin_outlined, keyboardType: TextInputType.number, maxLength: 6,
              onChanged: (_) => setState(() => _error = null)),
            const SizedBox(height: 24),
            _AdminButton(label: 'Verify OTP', loading: _loading, onTap: _verifyOwnerOtp),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() { _otpSent = false; _otpCtrl.clear(); _error = null; }),
              child: Text('← Back', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
          ],

          const SizedBox(height: 32),
          if (!_isOwner) _RequestAccessSection(),
        ]),
      )),
    );
  }
}

// ── REQUEST ACCESS ──
class _RequestAccessSection extends StatefulWidget {
  @override
  State<_RequestAccessSection> createState() => _RequestAccessSectionState();
}

class _RequestAccessSectionState extends State<_RequestAccessSection> {
  bool _loading = false;
  String? _existingStatus;
  String? _myCollegeId;
  String? _myCollegeName;
  String? _myBranchName;
  bool _myCollegeVerified = false;
  List<Map<String,dynamic>> _colleges = [];
  List<String> _branches = [];
  String? _selectedCollegeId;
  String? _selectedCollegeName;
  String? _selectedBranchName;
  String _requestedRole = 'branch';

  @override
  void initState() { super.initState(); _loadMyProfile(); _loadColleges(); }

  Future<void> _loadMyProfile() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final p = await supabase.from('profiles')
          .select('college_id, college_name, branch_name, college_status')
          .eq('id', uid).maybeSingle();
      final existing = await supabase.from('admin_requests').select('status')
          .eq('user_id', uid).order('created_at', ascending: false).limit(1).maybeSingle();
      setState(() {
        _myCollegeId      = p?['college_id']?.toString();
        _myCollegeName    = p?['college_name']?.toString();
        _myBranchName     = p?['branch_name']?.toString();
        _myCollegeVerified = p?['college_status']?.toString() == 'verified';
        if (existing != null) _existingStatus = existing['status'].toString();
        if (_myCollegeId != null) {
          _selectedCollegeId   = _myCollegeId;
          _selectedCollegeName = _myCollegeName;
        }
      });
      if (_myCollegeId != null) _loadBranches(_myCollegeId!);
    } catch (_) {}
  }

  Future<void> _loadColleges() async {
    try {
      final data = await supabase.from('colleges').select('id, name').order('name');
      setState(() => _colleges = List<Map<String,dynamic>>.from(data));
    } catch (_) {}
  }

  Future<void> _loadBranches(String collegeId) async {
    try {
      final data = await supabase.from('profiles')
          .select('branch_name')
          .eq('college_id', collegeId)
          .not('branch_name', 'is', null);
      final names = (data as List)
          .map((r) => r['branch_name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      setState(() {
        _branches = names;
        if (_myBranchName != null && names.contains(_myBranchName) &&
            collegeId == _myCollegeId) {
          _selectedBranchName = _myBranchName;
        } else {
          _selectedBranchName = null;
        }
      });
    } catch (_) {}
  }

  Future<void> _requestAccess() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    if (!_myCollegeVerified) return;
    if (_selectedCollegeId == null) return;
    if (_requestedRole == 'branch' && _selectedBranchName == null) return;

    setState(() => _loading = true);
    try {
      final email = supabase.auth.currentUser?.email ?? '';
      final p = await supabase.from('profiles').select('name').eq('id', uid).maybeSingle();
      await supabase.from('admin_requests').insert({
        'user_id':        uid,
        'user_name':      p?['name']?.toString() ?? 'Unknown',
        'user_email':     email,
        'status':         'pending',
        'requested_role': _requestedRole,
        'college_id':     _selectedCollegeId,
        'college_name':   _selectedCollegeName,
        'branch_name':    _requestedRole == 'branch' ? _selectedBranchName : null,
        'branch_id':      null,
      });
      setState(() { _existingStatus = 'pending'; _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final canRequest = _myCollegeVerified;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Want Admin Access?', style: TextStyle(
          color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 4),
        Text('Request access from the owner. Your college must be verified.',
          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35), height: 1.5)),
        const SizedBox(height: 12),

        if (!canRequest) ...[
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.2))),
            child: const Text(
              '🔒 Your college must be verified before requesting admin access.',
              style: TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.5))),
        ]
        else if (_existingStatus == 'pending') ...[
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: const Text('⏳ Request pending — waiting for owner approval',
              style: TextStyle(color: Colors.orange, fontSize: 12))),
        ]
        else if (_existingStatus == null) ...[
          Row(children: [
            _RoleChip(label: '🏫 College Admin', selected: _requestedRole == 'college',
              onTap: () => setState(() { _requestedRole = 'college'; _selectedBranchName = null; })),
            const SizedBox(width: 8),
            _RoleChip(label: '🎓 Branch Admin', selected: _requestedRole == 'branch',
              onTap: () => setState(() => _requestedRole = 'branch')),
          ]),
          const SizedBox(height: 10),
          _DropdownField(
            hint: 'Select College', value: _selectedCollegeId,
            items: _colleges.map((c) => DropdownMenuItem(
              value: c['id'].toString(),
              child: Row(children: [
                if (c['id'].toString() == _myCollegeId)
                  const Text('🏠 ', style: TextStyle(fontSize: 13)),
                Expanded(child: Text(c['name'].toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              ]))).toList(),
            onChanged: (val) {
              final col = _colleges.firstWhere((c) => c['id'].toString() == val,
                orElse: () => {});
              setState(() {
                _selectedCollegeId   = val;
                _selectedCollegeName = col['name']?.toString();
                _selectedBranchName  = null;
              });
              if (val != null) _loadBranches(val);
            }),
          const SizedBox(height: 8),
          if (_requestedRole == 'branch' && _selectedCollegeId != null) ...[
            _branches.isEmpty
              ? Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: const Text('No branches found for this college yet.',
                    style: TextStyle(color: Colors.white38, fontSize: 12)))
              : _DropdownField(
                  hint: 'Select Branch', value: _selectedBranchName,
                  items: _branches.map((name) => DropdownMenuItem(
                    value: name,
                    child: Row(children: [
                      if (name == _myBranchName)
                        const Text('🏠 ', style: TextStyle(fontSize: 13)),
                      Expanded(child: Text(name,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis)),
                    ]))).toList(),
                  onChanged: (val) => setState(() => _selectedBranchName = val)),
            const SizedBox(height: 8),
          ],
          if (_selectedCollegeName != null) ...[
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('📋 Your request summary:',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10,
                    letterSpacing: 0.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('Role: ${_requestedRole == 'college' ? '🏫 College Admin' : '🎓 Branch Admin'}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                Text('College: $_selectedCollegeName',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (_requestedRole == 'branch' && _selectedBranchName != null)
                  Text('Branch: $_selectedBranchName',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('⏱️ Access valid for 1 month after approval.',
                  style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10)),
              ])),
            const SizedBox(height: 10),
          ],
          GestureDetector(
            onTap: (_loading || (_requestedRole == 'branch' && _selectedBranchName == null)
                || _selectedCollegeId == null) ? null : _requestAccess,
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: (_selectedCollegeId != null &&
                    (_requestedRole == 'college' || _selectedBranchName != null))
                  ? const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B37C8)])
                  : null,
                color: (_selectedCollegeId == null ||
                    (_requestedRole == 'branch' && _selectedBranchName == null))
                  ? Colors.white.withOpacity(0.05) : null,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Center(child: _loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Request Access', style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))))),
        ] else if (_existingStatus == 'approved')
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: const Text('✅ Approved! Enter password & OTP above.',
              style: TextStyle(color: Colors.green, fontSize: 12)))
        else if (_existingStatus == 'rejected')
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: const Text('❌ Request rejected by owner',
              style: TextStyle(color: Colors.red, fontSize: 12))),
      ]),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _RoleChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFF6C63FF).withOpacity(0.15) : Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: selected ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.1))),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
      color: selected ? const Color(0xFF6C63FF) : Colors.white54))));
}

class _DropdownField extends StatelessWidget {
  final String hint; final String? value;
  final List<DropdownMenuItem<String>> items;
  final void Function(String?)? onChanged;
  const _DropdownField({required this.hint, this.value, required this.items, this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.1))),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      value: value, hint: Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 13)),
      isExpanded: true, dropdownColor: const Color(0xFF1A1F35),
      iconEnabledColor: Colors.white38, items: items, onChanged: onChanged)));
}

// ══════════════════════════════════════════════
// 🛡️ ADMIN PANEL SCREEN
// ══════════════════════════════════════════════
class AdminPanelScreen extends StatefulWidget {
  final AdminRole role;
  final String? adminCollegeId;
  final String? adminBranchId;
  final String? adminBranchName;
  final DateTime? expiresAt; // ← NEW

  const AdminPanelScreen({Key? key, required this.role,
    this.adminCollegeId, this.adminBranchId, this.adminBranchName,
    this.expiresAt}) : super(key: key); // ← NEW
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  String get _roleLabel {
    switch (widget.role) {
      case AdminRole.owner: return 'Owner Panel 👑';
      case AdminRole.college: return 'College Admin 🏫';
      case AdminRole.branch: return 'Branch Admin 🎓';
    }
  }

  Color get _roleColor {
    switch (widget.role) {
      case AdminRole.owner: return const Color(0xFF6C63FF);
      case AdminRole.college: return const Color(0xFF00B8A3);
      case AdminRole.branch: return const Color(0xFFFFB800);
    }
  }

  // ── membership days remaining helper ──
  Widget? _membershipBadge() {
    if (widget.role == AdminRole.owner || widget.expiresAt == null) return null;
    return _tenureBadge(widget.expiresAt!);
  }

  static Widget _tenureBadge(DateTime expiresAt) {
    final diff      = expiresAt.difference(DateTime.now());
    final totalHours = diff.inHours;
    final daysLeft   = diff.inDays;
    final hoursLeft  = totalHours % 24; // remaining hours after full days

    final isExpired      = totalHours <= 0;
    final isExpiringSoon = daysLeft < 3;

    final badgeColor = isExpired    ? Colors.red
        : daysLeft == 0             ? Colors.red
        : daysLeft <= 3             ? Colors.orange
        : Colors.green;

    String label;
    if (isExpired) {
      label = 'Expired';
    } else if (daysLeft == 0) {
      label = '${totalHours}h left';
    } else if (hoursLeft == 0) {
      label = '${daysLeft}d left';
    } else {
      label = '${daysLeft}d ${hoursLeft}h left';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isExpiringSoon ? Icons.timer_outlined : Icons.verified_user_outlined,
          color: badgeColor, size: 12),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          color: badgeColor, fontSize: 10, fontWeight: FontWeight.w800)),
      ]));
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: widget.role == AdminRole.owner ? 8 : 3, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.role == AdminRole.owner;
    final tabs = [
      const Tab(icon: Icon(Icons.flag, size: 18), text: 'Posts'),
      const Tab(icon: Icon(Icons.people, size: 18), text: 'Users'),
      const Tab(icon: Icon(Icons.campaign, size: 18), text: 'Announce'),
      if (isOwner) const Tab(icon: Icon(Icons.manage_accounts, size: 18), text: 'Requests'),
      if (isOwner) const Tab(icon: Icon(Icons.school, size: 18), text: 'Colleges'),
      if (isOwner) const Tab(icon: Icon(Icons.verified_outlined, size: 18), text: 'Verify'),
      if (isOwner) const Tab(icon: Icon(Icons.app_shortcut_outlined, size: 18), text: 'App Icon'),
      if (isOwner) const Tab(icon: Icon(Icons.style_outlined, size: 18), text: 'DSA Cards'),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A), elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              // No route to pop — go to root
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          }),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _roleColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _roleColor.withOpacity(0.5))),
            child: Text(
              widget.role == AdminRole.owner ? 'OWNER'
                : widget.role == AdminRole.college ? 'COLLEGE' : 'BRANCH',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                color: _roleColor, letterSpacing: 1.5))),
          const SizedBox(width: 10),
          Text(_roleLabel, style: const TextStyle(fontSize: 16,
            fontWeight: FontWeight.w800, color: Colors.white)),
          // ── NEW: membership badge ──
          if (_membershipBadge() != null) ...[
            const SizedBox(width: 8),
            _membershipBadge()!,
          ],
        ]),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _roleColor,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: _roleColor,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          tabs: tabs,
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _PostsTab(role: widget.role,
          collegeId: widget.adminCollegeId, branchId: widget.adminBranchId,
          branchName: widget.adminBranchName),
        _UsersTab(role: widget.role,
          collegeId: widget.adminCollegeId, branchId: widget.adminBranchId,
          branchName: widget.adminBranchName),
        _AnnouncementsTab(role: widget.role,
          collegeId: widget.adminCollegeId, branchId: widget.adminBranchId,
          branchName: widget.adminBranchName),
        if (isOwner) _RequestsTab(),
        if (isOwner) _CollegesTab(),
        if (isOwner) _CollegeVerifyTab(),
        if (isOwner) const _AppIconTab(),
        if (isOwner) const _DsaCardsTab(),
      ]),
    );
  }
}

// ══════════════════════════════════════════════
// 📋 POSTS TAB
// ══════════════════════════════════════════════
class _PostsTab extends StatefulWidget {
  final AdminRole role; final String? collegeId, branchId, branchName;
  const _PostsTab({required this.role, this.collegeId, this.branchId, this.branchName});
  @override State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab> {
  List<Map<String,dynamic>> _posts = [];
  bool _loading = true; String _filter = 'all';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      List<Map<String,dynamic>> data = [];

      // Always re-fetch college_id from DB for branch admin — widget.collegeId
      // can be stale or null on some login paths
      String? effectiveBranchName = widget.branchName;
      String? effectiveCollegeId  = widget.collegeId;
      if (widget.role == AdminRole.branch) {
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          final row = await supabase.from('admins')
              .select('branch_name, college_id')
              .eq('user_id', uid).maybeSingle();
          final dbBranch  = row?['branch_name']?.toString();
          final dbCollege = row?['college_id']?.toString();
          if (dbBranch  != null && dbBranch.isNotEmpty)  effectiveBranchName = dbBranch;
          if (dbCollege != null && dbCollege.isNotEmpty) effectiveCollegeId  = dbCollege;
        }
      }

      if (widget.role == AdminRole.branch && effectiveCollegeId != null) {
        // Branch admin: show ALL posts from their college
        // (posts are tagged with college_id; branch_name is only set for branch-visibility posts)
        // Filtering by user_ids of branch members was wrong — owner posts have no branch_name set
        final raw = await supabase.from('buzz_posts')
            .select()
            .eq('college_id', effectiveCollegeId)
            .order('created_at', ascending: false)
            .limit(200);
        data = List<Map<String,dynamic>>.from(raw);

      } else if (widget.role == AdminRole.college && effectiveCollegeId != null) {
        final raw = await supabase.from('buzz_posts')
            .select()
            .eq('college_id', effectiveCollegeId)
            .order('created_at', ascending: false)
            .limit(200);
        data = List<Map<String,dynamic>>.from(raw);

      } else if (widget.role == AdminRole.owner) {
        final raw = await supabase.from('buzz_posts')
            .select()
            .order('created_at', ascending: false)
            .limit(200);
        data = List<Map<String,dynamic>>.from(raw);
      }

      // Fetch images for all posts and merge in
      if (data.isNotEmpty) {
        try {
          final postIds = data.map((p) => p['id'].toString()).toList();
          final images = await supabase.from('buzz_images')
              .select('post_id, image_url')
              .inFilter('post_id', postIds);
          final imageMap = <String, String>{};
          for (final img in images as List) {
            imageMap[img['post_id'].toString()] = img['image_url'].toString();
          }
          data = data.map((p) {
            final imgUrl = imageMap[p['id'].toString()];
            if (imgUrl != null) return {...p, 'image_url': imgUrl};
            return p;
          }).toList();
        } catch (_) {}
      }

      setState(() { _posts = data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _deletePost(String id) async {
    try {
      await supabase.from('buzz_posts').delete().eq('id', id);
      try { await supabase.from('buzz_reports').delete().eq('post_id', id); } catch (_) {}
      try { await supabase.from('post_likes').delete().eq('post_id', id); } catch (_) {}
      if (mounted) {
        setState(() => _posts.removeWhere((p) => p['id'].toString() == id));
        _snack('🗑️ Post deleted', Colors.red);
      }
    } catch (e) {
      if (mounted) _snack('❌ Delete failed: $e', Colors.red);
    }
  }

  Future<void> _clearReports(String id) async {
    await supabase.from('buzz_posts').update({'reports': 0, 'status': 'active'}).eq('id', id);
    await supabase.from('buzz_reports').delete().eq('post_id', id);
    setState(() {
      final idx = _posts.indexWhere((p) => p['id'] == id);
      if (idx != -1) _posts[idx] = Map.from(_posts[idx])..['reports'] = 0;
    });
    _snack('✅ Reports cleared', Colors.green);
  }

  void _snack(String msg, Color c) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: c, behavior: SnackBarBehavior.floating));

  List<Map<String,dynamic>> get _filtered =>
    _filter == 'reported'
      ? _posts.where((p) => (p['reports'] ?? 0) > 0).toList()
      : _posts;

  @override
  Widget build(BuildContext context) {
    final reported = _posts.where((p) => (p['reports'] ?? 0) >= 10).length;

    return Column(children: [
      _StatsBar(items: [
        _StatItem('Total', '${_posts.length}', const Color(0xFF6C63FF)),
        _StatItem('Reported', '$reported', Colors.orange),
        _StatItem('Hidden', '${_posts.where((p) => (p['reports']??0) >= 20).length}', Colors.red),
      ]),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          _FilterBtn('All', _filter == 'all', () => setState(() => _filter = 'all')),
          const SizedBox(width: 8),
          _FilterBtn('🚩 Reported ($reported)', _filter == 'reported',
            () => setState(() => _filter = 'reported'), color: Colors.orange),
        ])),
      const SizedBox(height: 8),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
        : _filtered.isEmpty
          ? _EmptyAdmin('📭', _filter == 'reported' ? 'No posts with 10+ reports' : 'No posts yet')
          : RefreshIndicator(onRefresh: _load, color: const Color(0xFF6C63FF),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16,8,16,24),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final p = _filtered[i];
                  final reports = p['reports'] ?? 0;
                  final visibility = p['visibility']?.toString() ?? 'public';
                  return _PostAdminCard(
                    post: p, reports: reports, visibility: visibility,
                    onClearReports: reports > 0 ? () => _clearReports(p['id'].toString()) : null,
                    onDelete: () => _confirmDelete(p['id'].toString()));
                }))),
    ]);
  }

  void _confirmDelete(String id) => showDialog(context: context, builder: (_) => _ConfirmDialog(
    title: 'Delete Post?', message: 'This cannot be undone.',
    onConfirm: () { Navigator.pop(context); _deletePost(id); }));
}

class _PostAdminCard extends StatelessWidget {
  final Map<String,dynamic> post; final int reports;
  final String visibility;
  final VoidCallback? onClearReports; final VoidCallback onDelete;
  const _PostAdminCard({required this.post, required this.reports,
    required this.visibility, this.onClearReports, required this.onDelete});

  Color _visColor() {
    switch (visibility) {
      case 'college': return const Color(0xFF00B8A3);
      case 'branch': return const Color(0xFFFFB800);
      default: return const Color(0xFF6C63FF);
    }
  }

  String _visLabel() {
    switch (visibility) {
      case 'college': return '🏫 College';
      case 'branch': return '🎓 Branch';
      default: return '🌍 Public';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: const Color(0xFF141828),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reports >= 20 ? Colors.red.withOpacity(0.4)
            : reports >= 10 ? Colors.orange.withOpacity(0.3)
            : Colors.white.withOpacity(0.06))),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _MiniTag(label: post['is_anonymous'] == true ? '🎭 Anon' : '👤 ${post['poster_name'] ?? "Named"}',
            color: Colors.grey),
          const SizedBox(width: 6),
          _MiniTag(label: _visLabel(), color: _visColor()),
          const Spacer(),
          if (reports >= 10) _MiniTag(
            label: '🚩 $reports${reports >= 20 ? " • HIDDEN" : ""}',
            color: reports >= 20 ? Colors.red : Colors.orange),
        ]),
        const SizedBox(height: 10),
        Text(post['content']?.toString() ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
          maxLines: 3, overflow: TextOverflow.ellipsis),
        if ((post['image_url'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => openImageViewer(
              context,
              imageUrl: post['image_url'].toString(),
              heroTag: 'admin_img_${post['id']}',
            ),
            child: Hero(
              tag: 'admin_img_${post['id']}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  post['image_url'].toString(),
                  width: double.infinity, height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: Icon(Icons.broken_image_outlined,
                      color: Colors.white24, size: 24))),
                )),
            )),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.favorite, size: 13, color: Colors.white30),
          const SizedBox(width: 4),
          Text('${post['likes'] ?? 0}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const Spacer(),
          if (onClearReports != null)
            _ActionBtn('Clear Reports', Colors.green, onClearReports!),
          const SizedBox(width: 8),
          _ActionBtn('Delete', Colors.red, onDelete),
        ]),
      ])));
  }
}

// ══════════════════════════════════════════════
// 👥 USERS TAB
// ══════════════════════════════════════════════
class _UsersTab extends StatefulWidget {
  final AdminRole role; final String? collegeId, branchId, branchName;
  const _UsersTab({required this.role, this.collegeId, this.branchId, this.branchName});
  @override State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<Map<String,dynamic>> _users = [];
  Set<String> _bannedIds = {};
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // ── DEBUG: print exactly what Anurag's session sees ──────────────────
      debugPrint('=== _UsersTab._load() DEBUG ===');
      debugPrint('widget.role: \${widget.role}');
      debugPrint('widget.collegeId: \${widget.collegeId}');
      debugPrint('widget.branchName: \${widget.branchName}');

      String? effectiveBranchName = widget.branchName;
      String? effectiveCollegeId  = widget.collegeId;

      if (widget.role == AdminRole.branch) {
        final uid = supabase.auth.currentUser?.id;
        debugPrint('current uid: \$uid');
        if (uid != null) {
          final row = await supabase.from('admins')
              .select('branch_name, college_id')
              .eq('user_id', uid).maybeSingle();
          debugPrint('admins row: \$row');
          final dbBranch  = row?['branch_name']?.toString();
          final dbCollege = row?['college_id']?.toString();
          if (dbBranch  != null && dbBranch.isNotEmpty)  effectiveBranchName = dbBranch;
          if (dbCollege != null && dbCollege.isNotEmpty) effectiveCollegeId  = dbCollege;
        }
      }

      debugPrint('effectiveCollegeId: \$effectiveCollegeId');
      debugPrint('effectiveBranchName: \$effectiveBranchName');

      List users;

      if (widget.role == AdminRole.branch &&
          effectiveCollegeId != null &&
          effectiveBranchName != null &&
          effectiveBranchName.isNotEmpty) {
        final exact = await supabase.from('profiles')
            .select()
            .eq('college_id', effectiveCollegeId)
            .eq('branch_name', effectiveBranchName)
            .order('created_at', ascending: false);
        debugPrint('exact match count: \${(exact as List).length}');
        for (final u in exact) {
          debugPrint("user: \${u['name']} | branch_name: \${u['branch_name']} | college_id: \${u['college_id']}");
        }
        if ((exact as List).isNotEmpty) {
          users = exact;
        } else {
          users = await supabase.from('profiles')
              .select()
              .eq('college_id', effectiveCollegeId)
              .ilike('branch_name', effectiveBranchName)
              .order('created_at', ascending: false);
          debugPrint('ilike match count: \${(users as List).length}');
        }
      } else if (widget.role == AdminRole.branch && effectiveCollegeId != null) {
        debugPrint('WARNING: effectiveBranchName is null/empty — fetching all college users');
        users = await supabase.from('profiles')
            .select()
            .eq('college_id', effectiveCollegeId)
            .order('created_at', ascending: false);
      } else if (widget.role == AdminRole.college && effectiveCollegeId != null) {
        users = await supabase.from('profiles')
            .select()
            .eq('college_id', effectiveCollegeId)
            .order('created_at', ascending: false);
      } else {
        debugPrint('WARNING: fell through to all-users query!');
        users = await supabase.from('profiles')
            .select()
            .order('created_at', ascending: false);
      }

      debugPrint('total users before admin exclusion: \${(users as List).length}');

      List adminUserIds = [];
      // Owner sees everyone including admins; college/branch roles exclude admins
      if (widget.role != AdminRole.owner) {
        try {
          final adminRows = await supabase.from('admins').select('user_id');
          adminUserIds = (adminRows as List).map((a) => a['user_id'].toString()).toList();
          debugPrint('adminUserIds to exclude: \$adminUserIds');
        } catch (_) {}
      }
      final filteredUsers = (users as List).where(
          (u) => !adminUserIds.contains(u['id'].toString())).toList();
      debugPrint('filteredUsers count: \${filteredUsers.length}');
      debugPrint('=== END DEBUG ===');

      final userIds = filteredUsers.map((u) => u['id'].toString()).toList();
      List bannedRaw = [];
      if (userIds.isNotEmpty) {
        bannedRaw = await supabase.from('banned_users')
            .select('user_id').inFilter('user_id', userIds);
      }

      setState(() {
        _users = List<Map<String,dynamic>>.from(filteredUsers);
        _bannedIds = Set<String>.from(bannedRaw.map((b) => b['user_id'].toString()));
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _toggleBan(String uid, String name, bool isBanned) async {
    if (isBanned) {
      await supabase.from('banned_users').delete().eq('user_id', uid);
      await supabase.from('profiles').update({'is_banned': false}).eq('id', uid);
      setState(() => _bannedIds.remove(uid));
      _snack('✅ $name unbanned', Colors.green);
    } else {
      await supabase.from('banned_users').upsert({'user_id': uid,
        'banned_by': supabase.auth.currentUser?.id, 'reason': 'Admin action'});
      await supabase.from('profiles').update({'is_banned': true}).eq('id', uid);
      setState(() => _bannedIds.add(uid));
      _snack('🚫 $name banned', Colors.orange);
    }
  }

  void _snack(String msg, Color c) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: c, behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) => Column(children: [
    _StatsBar(items: [
      _StatItem('Total', '${_users.length}', const Color(0xFF6C63FF)),
      _StatItem('Banned', '${_bannedIds.length}', Colors.red),
    ]),
    Expanded(child: _loading
      ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
      : RefreshIndicator(onRefresh: _load, color: const Color(0xFF6C63FF),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16,0,16,24),
            itemCount: _users.length,
            itemBuilder: (_, i) {
              final u = _users[i];
              final uid = u['id'].toString();
              final isBanned = _bannedIds.contains(uid);
              final isOwnerUser = uid == kOwnerUserId;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFF141828),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isOwnerUser
                    ? const Color(0xFF6C63FF).withOpacity(0.4)
                    : isBanned ? Colors.red.withOpacity(0.3) : Colors.white.withOpacity(0.06))),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.15),
                      shape: BoxShape.circle),
                    child: Center(child: Text(u['avatar_emoji']?.toString() ?? '🎓',
                      style: const TextStyle(fontSize: 22)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(u['name']?.toString() ?? 'Unknown',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(width: 6),
                      if (isOwnerUser) _MiniTag(label: '👑 Owner', color: const Color(0xFF6C63FF))
                      else if (isBanned) _MiniTag(label: '🚫 Banned', color: Colors.red),
                    ]),
                    if ((u['branch_name'] ?? '').toString().isNotEmpty)
                      Text(u['branch_name'].toString(),
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    if ((u['college_name'] ?? '').toString().isNotEmpty)
                      Text(u['college_name'].toString(),
                        style: const TextStyle(color: Colors.white24, fontSize: 10)),
                  ])),
                  if (!isOwnerUser) GestureDetector(
                    onTap: () => showDialog(context: context, builder: (_) => _ConfirmDialog(
                      title: isBanned ? 'Unban ${u['name']}?' : 'Ban ${u['name']}?',
                      message: isBanned ? 'Restore posting ability.' : 'Block from posting.',
                      onConfirm: () { Navigator.pop(context); _toggleBan(uid, u['name']?.toString() ?? '', isBanned); },
                      confirmColor: isBanned ? Colors.green : Colors.red,
                      confirmLabel: isBanned ? 'Unban' : 'Ban')),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isBanned ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isBanned ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3))),
                      child: Text(isBanned ? 'Unban' : 'Ban',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: isBanned ? Colors.green : Colors.red)))),
                ]),
              );
            }))),
  ]);
}

// ══════════════════════════════════════════════
// 📢 ANNOUNCEMENTS TAB
// ══════════════════════════════════════════════
class _AnnouncementsTab extends StatefulWidget {
  final AdminRole role; final String? collegeId, branchId, branchName;
  const _AnnouncementsTab({required this.role, this.collegeId, this.branchId, this.branchName});
  @override State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  List<Map<String,dynamic>> _announcements = [];
  bool _loading = true;
  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _titleCtrl.dispose(); _msgCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = supabase.from('announcements').select();
      if (widget.role == AdminRole.branch &&
          widget.collegeId != null && widget.branchName != null) {
        q = q.eq('college_id', widget.collegeId!)
             .ilike('branch_name', widget.branchName!);
      } else if (widget.role == AdminRole.college && widget.collegeId != null) {
        q = q.eq('college_id', widget.collegeId!);
      }
      final data = await q.order('created_at', ascending: false);
      setState(() { _announcements = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _post() async {
    if (_titleCtrl.text.trim().isEmpty || _msgCtrl.text.trim().isEmpty) return;
    await supabase.from('announcements').insert({
      'title': _titleCtrl.text.trim(),
      'message': _msgCtrl.text.trim(),
      'created_by': supabase.auth.currentUser?.id,
      'is_active': true,
      'college_id': widget.collegeId,
      'branch_id': widget.role == AdminRole.branch ? widget.branchId : null,
      'branch_name': widget.role == AdminRole.branch ? widget.branchName : null,
    });
    _titleCtrl.clear(); _msgCtrl.clear();
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('📢 Announcement sent!'),
      backgroundColor: Color(0xFF6C63FF), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final scopeLabel = widget.role == AdminRole.branch ? 'your branch'
      : widget.role == AdminRole.college ? 'your college' : 'all users';
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF141828),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.campaign, color: Color(0xFF6C63FF), size: 20),
            SizedBox(width: 8),
            Text('New Announcement', style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 15))]),
          const SizedBox(height: 4),
          Text('Will be sent to $scopeLabel',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
          const SizedBox(height: 14),
          TextField(controller: _titleCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco('Title')),
          const SizedBox(height: 10),
          TextField(controller: _msgCtrl, maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco('Message...')),
          const SizedBox(height: 12),
          GestureDetector(onTap: _post, child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B37C8)]),
              borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('Send Announcement 📢',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))))),
        ])),
      const SizedBox(height: 20),
      Text('Past (${_announcements.length})',
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 10),
      if (_loading) const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
      else ..._announcements.map((a) => Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF141828), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: (a['is_active'] as bool? ?? true)
            ? const Color(0xFF6C63FF).withOpacity(0.2) : Colors.white.withOpacity(0.05))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(a['title']?.toString() ?? '',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
            _MiniTag(label: (a['is_active'] as bool? ?? true) ? '● Active' : '○ Off',
              color: (a['is_active'] as bool? ?? true) ? Colors.green : Colors.grey),
          ]),
          const SizedBox(height: 6),
          Text(a['message']?.toString() ?? '',
            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _ActionBtn((a['is_active'] as bool? ?? true) ? 'Deactivate' : 'Activate',
              Colors.grey, () async {
                await supabase.from('announcements')
                  .update({'is_active': !(a['is_active'] as bool? ?? true)})
                  .eq('id', a['id']);
                await _load();
              }),
            const SizedBox(width: 8),
            _ActionBtn('Delete', Colors.red, () async {
              await supabase.from('announcements').delete().eq('id', a['id']); await _load(); }),
          ]),
        ]))),
    ]));
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
    filled: true, fillColor: Colors.white.withOpacity(0.05),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.all(12));
}

// ══════════════════════════════════════════════
// 📥 REQUESTS TAB
// ══════════════════════════════════════════════
class _RequestsTab extends StatefulWidget {
  @override State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  List<Map<String,dynamic>> _requests = [];
  List<Map<String,dynamic>> _activeAdmins = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);

    // ── 1. Load requests (original query — untouched) ──────────
    try {
      final data = await supabase.from('admin_requests')
          .select().order('created_at', ascending: false);
      setState(() => _requests = List<Map<String,dynamic>>.from(data));
    } catch (_) {}

    // ── 2. Load active admins separately so a failure here
    //       never breaks the requests list above ──────────────
    try {
      final adminsData = await supabase.from('admins')
          .select('id, user_id, role, college_id, branch_name, expires_at, granted_at')
          .neq('role', 'owner')
          .order('expires_at', ascending: true);
      final adminRows = List<Map<String,dynamic>>.from(adminsData);
      for (final admin in adminRows) {
        try {
          final profile = await supabase.from('profiles')
              .select('name, college_name')
              .eq('id', admin['user_id']).maybeSingle();
          admin['user_name']    = profile?['name']         ?? 'Unknown';
          admin['college_name'] = profile?['college_name'] ?? '';
        } catch (_) {
          admin['user_name']    = 'Unknown';
          admin['college_name'] = '';
        }
      }
      setState(() => _activeAdmins = adminRows);
    } catch (_) {}

    setState(() => _loading = false);
  }

  Future<void> _revokeAdmin(String adminId, String name) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF141828),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Revoke Access', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Text('Remove admin access for $name? They will be logged out immediately.',
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800))),
      ]));
    if (confirm != true) return;
    try {
      await supabase.from('admins').delete().eq('id', adminId);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Admin access revoked'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: \$e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    }
  }

  String _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789@#!';
    return List.generate(12, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  String _generateOtp() => (100000 + Random().nextInt(900000)).toString();

  Future<void> _approve(Map<String,dynamic> req) async {
    final pass = _generatePassword(); final otp = _generateOtp();
    final otpExpires      = DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String();
    final accessExpires   = DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String();
    await supabase.from('admin_requests').update({
      'status':           'approved',
      'generated_password': pass,
      'generated_otp':    otp,
      'otp_expires_at':   otpExpires,
      'access_expires_at': accessExpires,
    }).eq('id', req['id']);
    await _load();
    if (mounted) _showCredentials(
      req['user_name']?.toString()     ?? 'User',
      req['requested_role']?.toString() ?? 'branch',
      req['college_name']?.toString()   ?? '',
      req['branch_name']?.toString()    ?? '',
      pass, otp);
  }

  Future<void> _reject(String id) async {
    await supabase.from('admin_requests').update({'status': 'rejected'}).eq('id', id);
    await _load();
  }

  void _showCredentials(String name, String role, String college, String branch, String pass, String otp) {
    final roleLabel = role == 'college' ? '🏫 College Admin' : '🎓 Branch Admin';
    showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF141828),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('✅ Credentials Generated', style: TextStyle(
        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Share with $name privately:', style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.1))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Role: $roleLabel', style: const TextStyle(color: Colors.white, fontSize: 12)),
            if (college.isNotEmpty)
              Text('College: $college', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (branch.isNotEmpty)
              Text('Branch: $branch', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
        const SizedBox(height: 12),
        _CredBox(label: 'Password', value: pass),
        const SizedBox(height: 10),
        _CredBox(label: 'OTP (valid 7 days)', value: otp),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.3))),
          child: const Text(
            '⏱️ Admin access expires in 30 days.\n⚠️ Share via private message only.',
            style: TextStyle(fontSize: 11, color: Colors.orange, height: 1.5))),
      ]),
      actions: [ElevatedButton(onPressed: () => Navigator.pop(context),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: const Text('Done', style: TextStyle(color: Colors.white)))],
    ));
  }

  // ── helper: build one admin tenure card ──────────────────
  Widget _adminCard(Map<String,dynamic> a) {
    final role = a['role']?.toString() ?? 'branch';
    final expiresAt = a['expires_at'] != null
        ? DateTime.tryParse(a['expires_at'].toString())?.toLocal() : null;
    final roleColor = role == 'college'
        ? const Color(0xFF00B8A3) : const Color(0xFFFFB800);
    final diff = expiresAt != null
        ? expiresAt.difference(DateTime.now()) : null;
    final isExpired  = diff != null && diff.inHours <= 0;
    final daysLeft   = diff?.inDays ?? 0;
    final hoursLeft  = diff != null ? (diff.inHours % 24) : 0;
    final totalHours = diff?.inHours ?? 0;
    final tenureColor = isExpired ? Colors.red
        : daysLeft == 0 ? Colors.red
        : daysLeft <= 3 ? Colors.orange
        : Colors.green;
    String tenureLabel;
    if (expiresAt == null)     tenureLabel = 'No expiry';
    else if (isExpired)        tenureLabel = 'EXPIRED';
    else if (daysLeft == 0)    tenureLabel = '${totalHours}h left';
    else if (hoursLeft == 0)   tenureLabel = '${daysLeft}d left';
    else                       tenureLabel = '${daysLeft}d ${hoursLeft}h left';

    return GestureDetector(
      onLongPress: () => _revokeAdmin(
          a['id'].toString(), a['user_name']?.toString() ?? 'Admin'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF141828),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isExpired
              ? Colors.red.withOpacity(0.5)
              : roleColor.withOpacity(0.35))),
        child: Row(children: [
          // Role icon
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(
              role == 'college' ? '🏫' : '🎓',
              style: const TextStyle(fontSize: 20)))),
          const SizedBox(width: 12),
          // Name + college/branch
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a['user_name']?.toString() ?? 'Unknown',
              style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w800, fontSize: 13)),
            if ((a['college_name'] ?? '').toString().isNotEmpty)
              Text(a['college_name'].toString(),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            if ((a['branch_name'] ?? '').toString().isNotEmpty)
              Text(a['branch_name'].toString(),
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ])),
          const SizedBox(width: 8),
          // Tenure badge
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tenureColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tenureColor.withOpacity(0.45))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isExpired || daysLeft <= 3
                    ? Icons.timer_outlined : Icons.check_circle_outline,
                    color: tenureColor, size: 11),
                const SizedBox(width: 4),
                Text(tenureLabel, style: TextStyle(
                  color: tenureColor, fontSize: 10,
                  fontWeight: FontWeight.w800)),
              ])),
            const SizedBox(height: 4),
            Text('hold to revoke',
              style: TextStyle(
                color: Colors.white.withOpacity(0.2), fontSize: 8)),
          ]),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _requests.where((r) => r['status'] == 'pending').length;

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
    }

    // Build items list for a single unified scrollable
    final List<Widget> items = [];

    // ── Pending banner ──
    if (pending > 0)
      items.add(Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 4), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3))),
        child: Row(children: [
          const Icon(Icons.notifications_active, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Text('$pending pending request${pending > 1 ? 's' : ''}',
            style: const TextStyle(color: Colors.orange,
              fontWeight: FontWeight.w700, fontSize: 13)),
        ])));

    // ── Active Admins section ──
    if (_activeAdmins.isNotEmpty) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(children: [
          const Icon(Icons.admin_panel_settings,
            color: Color(0xFF6C63FF), size: 18),
          const SizedBox(width: 8),
          Text('Active Admins (${_activeAdmins.length})',
            style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 14)),
        ])));
      for (final a in _activeAdmins) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _adminCard(a)));
      }
      items.add(const SizedBox(height: 4));
    }

    // ── Access Requests header ──
    items.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        const Icon(Icons.inbox_outlined, color: Colors.white38, size: 16),
        const SizedBox(width: 6),
        const Text('Access Requests',
          style: TextStyle(color: Colors.white70,
            fontWeight: FontWeight.w800, fontSize: 13)),
      ])));

    if (_requests.isEmpty) {
      items.add(_EmptyAdmin('📥', 'No requests yet'));
    } else {
      for (final r in _requests) {
        final status = r['status']?.toString() ?? 'pending';
        final role   = r['requested_role']?.toString() ?? 'branch';
        final statusColor = status == 'approved' ? Colors.green
            : status == 'rejected' ? Colors.red : Colors.orange;
        items.add(Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF141828),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: statusColor.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['user_name']?.toString() ?? 'Unknown',
                  style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 14)),
                Text(r['user_email']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
                Row(children: [
                  _MiniTag(label: role == 'college'
                      ? '🏫 College Admin' : '🎓 Branch Admin',
                    color: role == 'college'
                        ? const Color(0xFF00B8A3) : const Color(0xFFFFB800)),
                ]),
                if ((r['college_name'] ?? '').toString().isNotEmpty)
                  Text('🏫 ${r['college_name']}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                if ((r['branch_name'] ?? '').toString().isNotEmpty)
                  Text('🎓 ${r['branch_name']}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ])),
              _MiniTag(label: status.toUpperCase(), color: statusColor),
            ]),
            if (status == 'approved') ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _showCredentials(
                  r['user_name']?.toString()    ?? 'User',
                  role,
                  r['college_name']?.toString() ?? '',
                  r['branch_name']?.toString()  ?? '',
                  r['generated_password'].toString(),
                  r['generated_otp'].toString()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3))),
                  child: const Text('👁️ View Credentials',
                    style: TextStyle(color: Colors.green,
                      fontSize: 12, fontWeight: FontWeight.w600)))),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => _reject(r['id'].toString()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3))),
                    child: const Center(child: Text('Reject',
                      style: TextStyle(color: Colors.red,
                        fontWeight: FontWeight.w700)))))),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => _approve(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF3B37C8)]),
                      borderRadius: BorderRadius.all(Radius.circular(8))),
                    child: const Center(child: Text('Approve & Generate',
                      style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700)))))),
              ]),
            ],
          ])));
      }
    }

    items.add(const SizedBox(height: 24));

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF6C63FF),
      child: ListView(
        padding: EdgeInsets.zero,
        children: items));
  }
}

// ══════════════════════════════════════════════
// 🏫 COLLEGES TAB
// ══════════════════════════════════════════════
class _CollegesTab extends StatefulWidget {
  @override State<_CollegesTab> createState() => _CollegesTabState();
}

class _CollegesTabState extends State<_CollegesTab> {
  List<Map<String,dynamic>> _colleges = [];
  bool _loading = true;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _nameCtrl.dispose(); _codeCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase.from('colleges').select().order('name');
      setState(() { _colleges = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _addCollege() async {
    if (_nameCtrl.text.trim().isEmpty || _codeCtrl.text.trim().isEmpty) return;
    try {
      await supabase.from('colleges').insert({
        'name': _nameCtrl.text.trim(), 'code': _codeCtrl.text.trim().toUpperCase()});
      _nameCtrl.clear(); _codeCtrl.clear();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('🏫 College added!'), backgroundColor: Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF141828),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00B8A3).withOpacity(0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.add_business, color: Color(0xFF00B8A3), size: 20),
            SizedBox(width: 8),
            Text('Add New College', style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 15))]),
          const SizedBox(height: 14),
          TextField(controller: _nameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco('College full name (e.g. IIT Delhi)')),
          const SizedBox(height: 10),
          TextField(controller: _codeCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textCapitalization: TextCapitalization.characters,
            decoration: _inputDeco('Short code (e.g. IITD)')),
          const SizedBox(height: 12),
          GestureDetector(onTap: _addCollege, child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF00B8A3),
              borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('Add College 🏫',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))))),
        ])),
      const SizedBox(height: 20),
      Text('All Colleges (${_colleges.length})',
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
      const SizedBox(height: 10),
      if (_loading) const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
      else ..._colleges.map((c) => Container(
        margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF141828),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(color: const Color(0xFF00B8A3).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
            child: const Center(child: Text('🏫', style: TextStyle(fontSize: 20)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name'].toString(), style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w700, fontSize: 14)),
            Text(c['code'].toString(), style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
        ]))),
    ]));
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
    filled: true, fillColor: Colors.white.withOpacity(0.05),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.all(12));
}

// ══════════════════════════════════════════════
// ✅ COLLEGE VERIFICATION TAB
// ══════════════════════════════════════════════
class _CollegeVerifyTab extends StatefulWidget {
  @override State<_CollegeVerifyTab> createState() => _CollegeVerifyTabState();
}

class _CollegeVerifyTabState extends State<_CollegeVerifyTab> {
  List<Map<String,dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('college_verification_requests')
          .select()
          .order('created_at', ascending: false);
      setState(() { _requests = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
      _snack('Failed to load: $e', Colors.red);
    }
  }

  Future<void> _approve(Map<String,dynamic> req) async {
    try {
      final collegeName = req['college_name']?.toString() ?? '';
      String? collegeId;
      try {
        final existing = await supabase
            .from('colleges').select('id').ilike('name', collegeName).maybeSingle();
        if (existing != null) {
          collegeId = existing['id']?.toString();
        } else {
          final inserted = await supabase.from('colleges').insert({
            'name': collegeName,
            'code': collegeName.split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join(),
          }).select('id').single();
          collegeId = inserted['id']?.toString();
        }
      } catch (_) {}

      final profileUpdate = await supabase.from('profiles').update({
        'college_status':             'verified',
        'college_id':                 collegeId,
        'college_name':               req['college_name']?.toString() ?? '',
        'branch_name':                req['branch_name']?.toString() ?? '',
        'college_verified_notified':  false,
      }).eq('id', req['user_id'].toString()).select('id, college_status').maybeSingle();

      if (profileUpdate == null) {
        _snack('❌ RLS error: could not update profile. Run fix_rls_and_rejection.sql first.', Colors.red);
        return;
      }

      await supabase.from('college_verification_requests').update({
        'status': 'approved',
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', req['id'].toString());

      _snack('✅ ${req['user_name']} verified! College set.', Colors.green);
      _load();
    } catch (e) { _snack('Error: $e', Colors.red); }
  }

  Future<void> _reject(Map<String,dynamic> req) async {
    try {
      final userId = req['user_id'].toString();
      final rejectionDeadline = DateTime.now().add(const Duration(hours: 72)).toIso8601String();

      final profileUpdate = await supabase.from('profiles').update({
        'college_status':     'rejected',
        'rejection_deadline': rejectionDeadline,
      }).eq('id', userId).select('id, college_status').maybeSingle();

      if (profileUpdate == null) {
        _snack('❌ RLS error: could not update profile. Run fix_rls_and_rejection.sql first.', Colors.red);
        return;
      }

      await supabase.from('college_verification_requests').update({
        'status':      'rejected',
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', req['id'].toString());

      _snack('❌ Rejected. ${req['user_name']} has 72h to re-verify before auto-deletion.', Colors.orange);
      _load();
    } catch (e) { _snack('Reject error: $e', Colors.red); }
  }

  Future<void> _block(Map<String,dynamic> req) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Block User?',
        message: 'Block ${req['user_name']} for not verifying their college?',
        confirmLabel: 'Block',
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    if (confirm != true) return;
    try {
      await supabase.from('profiles')
          .update({'college_status': 'blocked', 'is_blocked': true})
          .eq('id', req['user_id'].toString());
      await supabase.from('college_verification_requests')
          .update({'status': 'blocked'})
          .eq('id', req['id'].toString());
      _snack('🚫 User blocked.', Colors.red);
      _load();
    } catch (e) { _snack('Error: $e', Colors.red); }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.orange;
      case 'blocked': return Colors.red;
      default: return const Color(0xFFFFB800);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'approved': return Icons.verified;
      case 'rejected': return Icons.cancel_outlined;
      case 'blocked': return Icons.block;
      default: return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)));

    final pending = _requests.where((r) => r['status'] == 'pending').toList();
    final resolved = _requests.where((r) => r['status'] != 'pending').toList();

    if (_requests.isEmpty) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('✅', style: TextStyle(fontSize: 48)),
        SizedBox(height: 12),
        Text('No college verification requests', style: TextStyle(color: Colors.white38, fontSize: 14)),
      ]));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF6C63FF),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pending.isNotEmpty) ...[
            Row(children: [
              Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: Color(0xFFFFB800), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('Pending Verification (${pending.length})',
                style: const TextStyle(color: Color(0xFFFFB800),
                  fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ]),
            const SizedBox(height: 10),
            ...pending.map((req) => _VerifyCard(
              req: req, isPending: true,
              onApprove: () => _approve(req),
              onReject: () => _reject(req),
              onBlock: () => _block(req),
              statusColor: _statusColor(req['status'] ?? 'pending'),
              statusIcon: _statusIcon(req['status'] ?? 'pending'),
            )),
            const SizedBox(height: 20),
          ],
          if (resolved.isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.history, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Text('Resolved (${resolved.length})',
                style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            ...resolved.map((req) => _VerifyCard(
              req: req, isPending: false,
              onApprove: () {}, onReject: () {}, onBlock: () {},
              statusColor: _statusColor(req['status'] ?? ''),
              statusIcon: _statusIcon(req['status'] ?? ''),
            )),
          ],
        ],
      ),
    );
  }
}

class _VerifyCard extends StatelessWidget {
  final Map<String,dynamic> req;
  final bool isPending;
  final VoidCallback onApprove, onReject, onBlock;
  final Color statusColor;
  final IconData statusIcon;

  const _VerifyCard({required this.req, required this.isPending,
    required this.onApprove, required this.onReject, required this.onBlock,
    required this.statusColor, required this.statusIcon});

  @override
  Widget build(BuildContext context) {
    final createdAt = req['created_at'] != null
        ? DateTime.tryParse(req['created_at'].toString())?.toLocal() : null;
    final expiresAt = req['expires_at'] != null
        ? DateTime.tryParse(req['expires_at'].toString())?.toLocal() : null;
    final hoursLeft = expiresAt != null
        ? expiresAt.difference(DateTime.now()).inHours : null;
    final isExpiringSoon = hoursLeft != null && hoursLeft < 6 && hoursLeft >= 0;
    final isExpired = hoursLeft != null && hoursLeft < 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141828),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpiringSoon ? Colors.orange.withOpacity(0.5)
              : isExpired ? Colors.red.withOpacity(0.3)
              : isPending ? const Color(0xFFFFB800).withOpacity(0.2)
              : statusColor.withOpacity(0.15),
          width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, color: statusColor, size: 12),
                const SizedBox(width: 4),
                Text((req['status'] ?? 'pending').toString().toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w800)),
              ])),
            const Spacer(),
            if (createdAt != null)
              Text('${createdAt.day}/${createdAt.month} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2,'0')}',
                style: const TextStyle(color: Colors.white30, fontSize: 11)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('🏫', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(child: Text(req['college_name']?.toString() ?? 'Unknown',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.person_outline, color: Colors.white38, size: 14),
            const SizedBox(width: 6),
            Text(req['user_name']?.toString() ?? '', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 12),
            const Icon(Icons.mail_outline, color: Colors.white38, size: 14),
            const SizedBox(width: 4),
            Expanded(child: Text(req['user_email']?.toString() ?? '',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              overflow: TextOverflow.ellipsis)),
          ]),
          if (isPending && expiresAt != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isExpired ? Colors.red.withOpacity(0.1)
                    : isExpiringSoon ? Colors.orange.withOpacity(0.1)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(isExpired ? Icons.timer_off : Icons.timer_outlined,
                  color: isExpired ? Colors.red : isExpiringSoon ? Colors.orange : Colors.white38,
                  size: 13),
                const SizedBox(width: 6),
                Text(
                  isExpired ? 'Deadline passed — block or extend'
                      : isExpiringSoon ? '$hoursLeft hours left to verify'
                      : '$hoursLeft hours remaining',
                  style: TextStyle(
                    fontSize: 11,
                    color: isExpired ? Colors.red : isExpiringSoon ? Colors.orange : Colors.white38)),
              ])),
          ],
          if (isPending) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: onApprove,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withOpacity(0.4))),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.verified, color: Colors.green, size: 15),
                    SizedBox(width: 6),
                    Text('Approve', style: TextStyle(color: Colors.green,
                      fontSize: 12, fontWeight: FontWeight.w700)),
                  ])))),
              const SizedBox(width: 8),
              Expanded(child: GestureDetector(
                onTap: onReject,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.4))),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.cancel_outlined, color: Colors.orange, size: 15),
                    SizedBox(width: 6),
                    Text('Reject', style: TextStyle(color: Colors.orange,
                      fontSize: 12, fontWeight: FontWeight.w700)),
                  ])))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onBlock,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.3))),
                  child: const Row(children: [
                    Icon(Icons.block, color: Colors.red, size: 15),
                    SizedBox(width: 4),
                    Text('Block', style: TextStyle(color: Colors.red,
                      fontSize: 12, fontWeight: FontWeight.w700)),
                  ]))),
            ]),
          ],
        ])));
  }
}

// ══════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════
class _StatItem { final String label, value; final Color color;
  const _StatItem(this.label, this.value, this.color); }

class _StatsBar extends StatelessWidget {
  final List<_StatItem> items;
  const _StatsBar({required this.items});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF141828),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.06))),
    child: Row(children: items.expand((item) => [
      Expanded(child: Container(padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: item.color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: item.color.withOpacity(0.2))),
        child: Column(children: [
          Text(item.value, style: TextStyle(color: item.color, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(item.label, style: TextStyle(color: item.color.withOpacity(0.7),
            fontSize: 10, fontWeight: FontWeight.w600)),
        ]))),
      if (item != items.last) const SizedBox(width: 12),
    ]).toList()));
}

class _FilterBtn extends StatelessWidget {
  final String label; final bool selected;
  final VoidCallback onTap; final Color? color;
  const _FilterBtn(this.label, this.selected, this.onTap, {this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF6C63FF);
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? c.withOpacity(0.15) : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? c : Colors.white.withOpacity(0.08))),
      child: Text(label, style: TextStyle(
        color: selected ? c : Colors.white38, fontWeight: FontWeight.w700, fontSize: 12))));
  }
}

class _ActionBtn extends StatelessWidget {
  final String label; final Color color; final VoidCallback onTap;
  const _ActionBtn(this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600))));
}

class _MiniTag extends StatelessWidget {
  final String label; final Color color;
  const _MiniTag({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)));
}

class _AdminField extends StatelessWidget {
  final TextEditingController controller; final String label; final IconData icon;
  final bool obscure; final Widget? suffixIcon; final TextInputType? keyboardType;
  final int? maxLength; final void Function(String)? onChanged;
  const _AdminField({required this.controller, required this.label, required this.icon,
    this.obscure = false, this.suffixIcon, this.keyboardType, this.maxLength, this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller, obscureText: obscure, keyboardType: keyboardType,
    maxLength: maxLength, onChanged: onChanged,
    style: const TextStyle(color: Colors.white, fontSize: 15),
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20), suffixIcon: suffixIcon,
      filled: true, fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6C63FF))),
      counterStyle: const TextStyle(color: Colors.white24)));
}

class _AdminButton extends StatelessWidget {
  final String label; final bool loading; final VoidCallback onTap;
  const _AdminButton({required this.label, required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: loading ? null : onTap,
    child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B37C8)]),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.5), blurRadius: 20)]),
      child: Center(child: loading
        ? const SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : Text(label, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.w900, fontSize: 16)))));
}

class _CredBox extends StatelessWidget {
  final String label, value;
  const _CredBox({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withOpacity(0.1))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(child: Text(value, style: const TextStyle(color: Colors.white,
          fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
        GestureDetector(onTap: () => Clipboard.setData(ClipboardData(text: value)),
          child: const Icon(Icons.copy, color: Colors.white38, size: 18)),
      ]),
    ]));
}

class _EmptyAdmin extends StatelessWidget {
  final String icon, label;
  const _EmptyAdmin(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Text(icon, style: const TextStyle(fontSize: 48)),
    const SizedBox(height: 12),
    Text(label, style: const TextStyle(color: Colors.white38, fontSize: 14))]));
}

class _ConfirmDialog extends StatelessWidget {
  final String title, message; final VoidCallback onConfirm;
  final Color confirmColor; final String confirmLabel;
  const _ConfirmDialog({required this.title, required this.message,
    required this.onConfirm, this.confirmColor = Colors.red, this.confirmLabel = 'Confirm'});
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF141828),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    content: Text(message, style: const TextStyle(color: Colors.white54)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
      ElevatedButton(onPressed: onConfirm,
        style: ElevatedButton.styleFrom(backgroundColor: confirmColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: Text(confirmLabel, style: const TextStyle(color: Colors.white))),
    ]);
}

// ─────────────────────────────────────────────
// App Icon Tab (Owner only)
// ─────────────────────────────────────────────
class _AppIconTab extends StatefulWidget {
  const _AppIconTab();
  @override
  State<_AppIconTab> createState() => _AppIconTabState();
}

class _AppIconTabState extends State<_AppIconTab> {
  AppIconVariant _current = AppIconVariant.defaultIcon;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    AppIconService.getCurrentIcon().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  Future<void> _applyIcon(AppIconVariant variant) async {
    setState(() => _loading = true);
    final ok = await AppIconService.changeIcon(variant);
    if (!mounted) return;
    if (ok) {
      // Save to Supabase so all users pick it up on next launch
      try {
        await supabase.from('app_settings').upsert(
          {'key': 'active_icon', 'value': variant.aliasName},
          onConflict: 'key',
        );
      } catch (e) {
        debugPrint('[AppIcon] Failed to save to Supabase: $e');
      }
      setState(() { _loading = false; _current = variant; });
    } else {
      setState(() => _loading = false);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'App icon changed to ${variant.label} for all users'
          : 'Failed to change icon'),
      backgroundColor: ok ? const Color(0xFF6C63FF) : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('App Icon', style: TextStyle(
          color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Change the launcher icon for all users.\nTakes effect after app restart.',
          style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 20),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: Color(0xFF6C63FF)))),
        if (!_loading)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: AppIconVariant.values.length,
            itemBuilder: (ctx, i) {
              final variant = AppIconVariant.values[i];
              final isActive = variant == _current;
              return GestureDetector(
                onTap: isActive ? null : () => _applyIcon(variant),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF6C63FF).withOpacity(0.15)
                        : const Color(0xFF141828),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFF6C63FF)
                          : Colors.white12,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          variant.assetPath,
                          width: 64, height: 64, fit: BoxFit.cover,
                          errorBuilder: (context2, err, stack) => Container(
                            width: 64, height: 64,
                            color: Colors.white10,
                            child: const Icon(Icons.image_not_supported,
                              color: Colors.white38)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(variant.label,
                        style: TextStyle(
                          color: isActive ? const Color(0xFF6C63FF) : Colors.white70,
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isActive) ...[
                        const SizedBox(height: 4),
                        const Icon(Icons.check_circle,
                          color: Color(0xFF6C63FF), size: 16),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════
// 🎴 DSA CARDS TAB (owner-only)
// ══════════════════════════════════════════════
class _DsaCardsTab extends StatefulWidget {
  const _DsaCardsTab();
  @override
  State<_DsaCardsTab> createState() => _DsaCardsTabState();
}

class _DsaCardsTabState extends State<_DsaCardsTab> {
  final _supabase = Supabase.instance.client;
  final _usernameCtrl = TextEditingController();
  int _cardCount = 3;
  bool _granting = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _grant() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) return;
    setState(() { _granting = true; _message = null; });
    try {
      final result = await _supabase.rpc('grant_dsa_cards', params: {
        'p_username': username,
        'p_cards': _cardCount,
      });
      final res = result?.toString() ?? '';
      if (res == 'ok') {
        setState(() {
          _isError = false;
          _message = 'Granted $_cardCount card${_cardCount > 1 ? 's' : ''} to @$username';
          _usernameCtrl.clear();
        });
      } else if (res == 'error:user_not_found') {
        setState(() { _isError = true; _message = 'User "@$username" not found.'; });
      } else if (res == 'error:not_authorized') {
        setState(() { _isError = true; _message = 'You are not authorized.'; });
      } else {
        setState(() { _isError = true; _message = 'Error: $res'; });
      }
    } catch (e) {
      setState(() { _isError = true; _message = 'Error: $e'; });
    } finally {
      if (mounted) setState(() => _granting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF6C63FF);
    const cardColor = Color(0xFF141828);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Info card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [purple.withValues(alpha: 0.15), Colors.transparent],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: purple.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🎴 DSA Room Cards',
                style: TextStyle(color: Colors.white,
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Each user gets 3 free cards per day.\nEvery Quick Match, Create Room, or Join Room costs 1 card.\nGrant extra cards to a user by their username.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13, height: 1.5),
            ),
          ]),
        ),

        const SizedBox(height: 28),

        const Text('Grant Extra Cards',
            style: TextStyle(color: Colors.white,
                fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),

        // Username field
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: TextField(
            controller: _usernameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter username (without @)',
              hintStyle: TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.person_outline, color: Colors.white38),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Card count selector
        Row(children: [
          const Text('Cards to grant:',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 12),
          ...[1, 2, 3, 5, 10].map((n) {
            final sel = _cardCount == n;
            return GestureDetector(
              onTap: () => setState(() => _cardCount = n),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? purple : cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel ? purple : Colors.white24,
                      width: sel ? 2 : 1),
                ),
                child: Text('$n',
                    style: TextStyle(
                        color: sel ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            );
          }),
        ]),

        const SizedBox(height: 20),

        // Grant button
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _granting ? null : _grant,
            style: ElevatedButton.styleFrom(
              backgroundColor: purple,
              disabledBackgroundColor: purple.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _granting
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text('Grant $_cardCount Card${_cardCount > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),

        // Result message
        if (_message != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (_isError ? Colors.red : Colors.green)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (_isError ? Colors.red : Colors.green)
                      .withValues(alpha: 0.4)),
            ),
            child: Text(
              _message!,
              style: TextStyle(
                  color: _isError ? Colors.redAccent : Colors.greenAccent,
                  fontSize: 13),
            ),
          ),
        ],
      ]),
    );
  }
}