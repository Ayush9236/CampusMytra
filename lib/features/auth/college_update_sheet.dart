import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';

final supabase = Supabase.instance.client;

/// Call this from profile screen:
/// showModalBottomSheet(context: context, isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => const UpdateCollegeSheet());
class UpdateCollegeSheet extends StatefulWidget {
  const UpdateCollegeSheet({Key? key}) : super(key: key);
  @override
  State<UpdateCollegeSheet> createState() => _UpdateCollegeSheetState();
}

class _UpdateCollegeSheetState extends State<UpdateCollegeSheet> {
  final _collegeCtrl   = TextEditingController();
  final _studentIdCtrl = TextEditingController();

  List<Map<String,dynamic>> _suggestions = [];
  List<Map<String,dynamic>> _branches    = [];
  String? _selectedCollegeId;
  String? _selectedCollegeName;
  String? _selectedBranchId;
  String? _selectedBranchName;
  String? _selectedBranchCode;
  bool _showCustomBranch = false;
  final _customBranchCtrl = TextEditingController();
  final _branchSearchCtrl = TextEditingController();
  String _branchQuery = '';
  bool _showSuggestions  = false;
  bool _loadingBranches  = false;
  bool _saving           = false;
  bool _loaded           = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _collegeCtrl.dispose();
    _studentIdCtrl.dispose();
    _customBranchCtrl.dispose();
    _branchSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final p = await supabase.from('profiles')
          .select('college_id, college_name, branch_id, branch_name, branch, student_id, college_status')
          .eq('id', uid).maybeSingle();
      if (p != null && mounted) {
        // ── If college was REJECTED, clear old selection so user must pick fresh ──
        // This prevents the old rejected college from re-submitting as "verified"
        final isRejected = p['college_status']?.toString() == 'rejected';
        setState(() {
          // Rejected: clear college so they can't accidentally re-submit the same one
          _selectedCollegeId   = isRejected ? null : p['college_id']?.toString();
          _selectedCollegeName = isRejected ? null : p['college_name']?.toString();
          _selectedBranchId    = isRejected ? null : p['branch_id']?.toString();
          _selectedBranchName  = isRejected ? null : p['branch_name']?.toString();
          _selectedBranchCode  = isRejected ? null : p['branch']?.toString();
          // Keep text field empty for rejected so user sees a clean slate
          _collegeCtrl.text    = isRejected ? '' : (p['college_name']?.toString() ?? '');
          _studentIdCtrl.text  = p['student_id']?.toString() ?? '';
          _loaded = true;
        });
        if (_selectedCollegeId != null) _loadBranches(_selectedCollegeId!);
      }
    } catch (_) { setState(() => _loaded = true); }
  }

  Future<void> _searchColleges(String query) async {
    if (query.length < 2) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    try {
      final data = await supabase.from('colleges')
          .select().ilike('name', '%$query%').limit(6);
      setState(() {
        _suggestions    = List<Map<String,dynamic>>.from(data);
        _showSuggestions = true;
      });
    } catch (_) {}
  }

  Future<void> _loadBranches(String collegeId) async {
    setState(() { _loadingBranches = true; _branches = []; });
    try {
      final data = await supabase.from('branches')
          .select().eq('college_id', collegeId).order('name');
      setState(() { _branches = List<Map<String,dynamic>>.from(data); _loadingBranches = false; });
    } catch (_) { setState(() => _loadingBranches = false); }
  }

  void _selectCollege(String id, String name) {
    setState(() {
      _selectedCollegeId   = id;
      _selectedCollegeName = name;
      _collegeCtrl.text    = name;
      _showSuggestions     = false;
      _suggestions         = [];
      _selectedBranchId    = null;
      _selectedBranchName  = null;
      _selectedBranchCode  = null;
      _branches            = [];
    });
    _loadBranches(id);
  }

  Future<void> _addAndSelectCollege(String name) async {
    if (name.trim().isEmpty) return;
    try {
      // Simple: if college is in our DB → select it as verified
      // If not → store as pending (owner must approve)
      final existing = await supabase.from('colleges')
          .select('id, name').ilike('name', name.trim()).limit(1).maybeSingle();
      if (existing != null) {
        _selectCollege(existing['id'].toString(), existing['name'].toString());
        return;
      }
      // Not in colleges table → pending verification
      setState(() {
        _selectedCollegeId   = null;
        _selectedCollegeName = name.trim();
        _collegeCtrl.text    = name.trim();
        _showSuggestions     = false;
        _suggestions         = [];
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _save() async {
    // ── Step 0: Resolve college from text field ──
    // Always do a fresh DB lookup against whatever is in the text field.
    // This is the single source of truth for whether a college is "verified".
    final typedCollege = _collegeCtrl.text.trim();
    if (typedCollege.isNotEmpty) {
      try {
        final existing = await supabase.from('colleges')
            .select('id, name').ilike('name', typedCollege).limit(1).maybeSingle();
        if (existing != null) {
          // College is in our verified colleges table → verified immediately, no review needed
          _selectedCollegeId   = existing['id'].toString();
          _selectedCollegeName = existing['name'].toString();
          _collegeCtrl.text    = existing['name'].toString();
        } else {
          // Not in colleges table → needs owner verification
          _selectedCollegeId   = null;
          _selectedCollegeName = typedCollege;
        }
      } catch (_) {
        // On error keep whatever was already set
        if (_selectedCollegeName == null) _selectedCollegeName = typedCollege;
      }
    }

    // Sync custom branch text → state if active
    if (_showCustomBranch) {
      final txt = _customBranchCtrl.text.trim();
      if (txt.isNotEmpty) {
        final normalized = txt.split(' ')
            .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join(' ');
        _selectedBranchName = normalized;
        _selectedBranchCode = normalized.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).join();
        _selectedBranchId   = 'custom';
      }
    }

    if (_selectedCollegeName == null || _selectedCollegeName!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⚠️ Please enter your college name'),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
      return;
    }
    if (_selectedBranchId == null || (_selectedBranchName?.trim().isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⚠️ Please select or type your branch'),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) { setState(() => _saving = false); return; }

      final isRealBranchId = _selectedBranchId != null &&
          _selectedBranchId != 'custom' &&
          !(_selectedBranchId!.startsWith('preset_'));

      // Fetch profile for name/email (used in verification request if needed)
      final currentProfile = await supabase.from('profiles')
          .select('name, email').eq('id', uid).maybeSingle();

      // SIMPLE RULE:
      //   _selectedCollegeId != null → college exists in our DB → VERIFIED, no review
      //   _selectedCollegeId == null → new/unknown college → PENDING, owner must approve
      // No other conditions. Status in DB is irrelevant to this decision.
      final isExistingCollege = _selectedCollegeId != null;
      final collegeStatus = isExistingCollege ? 'verified' : 'pending';

      // ── Update profile ──
      final updateResult = await supabase.from('profiles').update({
        'college_id':     isExistingCollege ? _selectedCollegeId : null,
        'college_name':   _selectedCollegeName!.trim(),
        'branch_id':      isRealBranchId ? _selectedBranchId : null,
        'branch_name':    _selectedBranchName,
        'branch':         _selectedBranchCode,
        'student_id':     _studentIdCtrl.text.trim().isEmpty
                              ? null : _studentIdCtrl.text.trim(),
        'college_status': collegeStatus,
        'rejection_deadline': null,   // clear rejection deadline on resubmit
      }).eq('id', uid).select('id, college_name, college_status').maybeSingle();

      // If RLS blocked the update, show a clear error
      if (updateResult == null) {
        setState(() => _saving = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Save failed — RLS policy blocked profile update. Contact support.'),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 6)));
        return;
      }

      // New college or rejected resubmit → create verification request for owner
      if (!isExistingCollege) {
        try {
          await supabase.from('college_verification_requests').insert({
            'user_id':      uid,
            'user_name':    currentProfile?['name']?.toString() ?? '',
            'user_email':   currentProfile?['email']?.toString() ??
                            supabase.auth.currentUser?.email ?? '',
            'college_name': _selectedCollegeName!.trim(),
            'branch_name':  _selectedBranchName ?? '',
            'status':       'pending',
            'expires_at':   DateTime.now()
                                .add(const Duration(hours: 48))
                                .toIso8601String(),
          });
        } catch (e) {
          // Don't block save if verification request insert fails
          debugPrint('Verification request insert failed: $e');
        }
      }

      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isExistingCollege
            ? '✅ Profile updated!'
            : '📋 College submitted for verification!'),
        backgroundColor: isExistingCollege
            ? const Color(0xFF00B8A3) : const Color(0xFFFFB800),
        behavior: SnackBarBehavior.floating));
      Navigator.pop(context, true); // return true = refresh needed
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = AppColors.surfaceVariant(context);
    final border  = AppColors.border(context);
    final textColor    = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    const primary = Color(0xFF6C63FF);

    return Container(
      decoration: BoxDecoration(color: AppColors.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Handle
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.textHint(context),
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),

          // Title
          Row(children: [
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.school, color: Color(0xFF6C63FF), size: 22)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Update College Info', style: TextStyle(
                color: textColor, fontWeight: FontWeight.w900, fontSize: 18)),
              Text('Set your college & branch for Buzz feeds',
                style: TextStyle(color: textSecondary, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 24),

          if (!_loaded)
            const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          else ...[

            // ── COLLEGE SEARCH ──
            Text('College', style: TextStyle(color: textSecondary,
              fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _selectedCollegeId != null
                    ? const Color(0xFF00B8A3).withOpacity(0.5) : border)),
              child: TextField(
                controller: _collegeCtrl,
                style: TextStyle(color: textColor, fontSize: 14),
                onChanged: (val) {
                  if (_selectedCollegeId != null && val != _selectedCollegeName) {
                    setState(() { _selectedCollegeId = null; _selectedCollegeName = null;
                      _branches = []; _selectedBranchId = null; });
                  }
                  _searchColleges(val);
                },
                decoration: InputDecoration(
                  hintText: 'Search college name...',
                  hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                  prefixIcon: Icon(Icons.school_outlined, color: textSecondary, size: 20),
                  suffixIcon: _selectedCollegeId != null
                      ? const Icon(Icons.check_circle, color: Color(0xFF00B8A3), size: 20)
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                  filled: true, fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)))),

            // Suggestions
            if (_showSuggestions && _suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primary.withOpacity(0.3)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)]),
                child: Column(children: [
                  ..._suggestions.map((c) => ListTile(dense: true,
                    leading: const Text('🏫', style: TextStyle(fontSize: 16)),
                    title: Text(c['name'].toString(),
                      style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(c['code'].toString(),
                      style: TextStyle(color: textSecondary, fontSize: 11)),
                    onTap: () => _selectCollege(c['id'].toString(), c['name'].toString()))),
                ])),

            // "Add new" when no suggestions and 2+ chars typed
            if (_showSuggestions && _suggestions.isEmpty && _collegeCtrl.text.trim().length >= 2)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primary.withOpacity(0.3))),
                child: ListTile(dense: true,
                  leading: const Icon(Icons.add_circle_outline,
                    color: Color(0xFF00B8A3), size: 18),
                  title: Text('Add "${_collegeCtrl.text.trim()}"',
                    style: const TextStyle(color: Color(0xFF00B8A3),
                      fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Requires owner verification',
                    style: TextStyle(color: Color(0xFF7B8DB7), fontSize: 11)),
                  onTap: () => _addAndSelectCollege(_collegeCtrl.text.trim()))),

            const SizedBox(height: 16),

            // ── BRANCH PICKER ──
            Text('Branch', style: TextStyle(color: textSecondary,
              fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _UpdateBranchPicker(
              branches: _branches,
              useDbBranches: _branches.isNotEmpty,
              isLoading: _loadingBranches,
              selectedBranchId: _selectedBranchId,
              selectedBranchCode: _selectedBranchCode,
              showCustom: _showCustomBranch,
              customCtrl: _customBranchCtrl,
              searchCtrl: _branchSearchCtrl,
              onSelectDb: (id, name, code) {
                HapticFeedback.lightImpact();
                setState(() {
                  _selectedBranchId = id;
                  _selectedBranchName = name;
                  _selectedBranchCode = code;
                  _showCustomBranch = false;
                  _customBranchCtrl.clear();
                });
              },
              onSelectPreset: (name, code) {
                if (code == 'OTHER') {
                  setState(() {
                    _showCustomBranch = true;
                    _selectedBranchId = 'custom';
                    _selectedBranchCode = 'OTHER';
                    _selectedBranchName = '';
                  });
                } else {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _selectedBranchId = 'preset_$code';
                    _selectedBranchName = name;
                    _selectedBranchCode = code;
                    _showCustomBranch = false;
                    _customBranchCtrl.clear();
                  });
                }
              },
              onCustomChanged: (normalized, code) {
                setState(() {
                  _selectedBranchName = normalized;
                  _selectedBranchCode = code;
                });
              },
              onQueryChanged: (q) => setState(() => _branchQuery = q),
            ),
            const SizedBox(height: 16),

            // ── STUDENT ID ──
            Text('Student ID (optional)', style: TextStyle(color: textSecondary,
              fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border)),
              child: TextField(
                controller: _studentIdCtrl,
                style: TextStyle(color: textColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. 22100140',
                  hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                  prefixIcon: Icon(Icons.badge_outlined, color: textSecondary, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                  filled: true, fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)))),

            const SizedBox(height: 24),

            // ── SAVE BUTTON ──
            GestureDetector(
              onTap: _saving ? null : _save,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity, height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3B37C8)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: primary.withOpacity(0.4), blurRadius: 16)]),
                child: Center(child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.save_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Save Changes', style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w800, fontSize: 16)),
                    ])))),
          ],
        ]),
      )),
    );
  }
}

// ── UPDATE SHEET BRANCH PICKER (search + scroll) — UNCHANGED ──
class _UpdateBranchPicker extends StatefulWidget {
  final List<Map<String,dynamic>> branches;
  final bool useDbBranches, isLoading, showCustom;
  final String? selectedBranchId, selectedBranchCode;
  final TextEditingController customCtrl, searchCtrl;
  final Function(String id, String name, String code) onSelectDb;
  final Function(String name, String code) onSelectPreset;
  final Function(String normalized, String code) onCustomChanged;
  final Function(String) onQueryChanged;

  const _UpdateBranchPicker({
    required this.branches, required this.useDbBranches, required this.isLoading,
    required this.selectedBranchId, required this.selectedBranchCode,
    required this.showCustom, required this.customCtrl, required this.searchCtrl,
    required this.onSelectDb, required this.onSelectPreset,
    required this.onCustomChanged, required this.onQueryChanged,
  });

  @override
  State<_UpdateBranchPicker> createState() => _UpdateBranchPickerState();
}

class _UpdateBranchPickerState extends State<_UpdateBranchPicker> {
  String _query = '';
  List<Map<String,String>> _dbCustomBranches = [];

  @override
  void initState() {
    super.initState();
    _loadCustomBranches();
  }

  Future<void> _loadCustomBranches() async {
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase
          .from('profiles')
          .select('branch_name, branch')
          .not('branch_name', 'is', null)
          .neq('branch_name', '');
      final seen = <String>{};
      final result = <Map<String,String>>[];
      for (final row in (data as List)) {
        final name = row['branch_name']?.toString().trim() ?? '';
        final code = row['branch']?.toString().trim() ?? '';
        if (name.isNotEmpty && seen.add(name.toLowerCase())) {
          final inPresets = _presets.any((p) =>
            p['name']!.toLowerCase() == name.toLowerCase() ||
            p['code']!.toLowerCase() == code.toLowerCase());
          if (!inPresets) result.add({'name': name, 'code': code.isEmpty ? name[0].toUpperCase() : code});
        }
      }
      if (mounted) setState(() => _dbCustomBranches = result);
    } catch (_) {}
  }

  static const List<Map<String,String>> _presets = [
    {'name': 'Computer Science & Engg',  'code': 'CSE'},
    {'name': 'Computer Science',          'code': 'CS'},
    {'name': 'Information Technology',   'code': 'IT'},
    {'name': 'Electronics & Comm.',       'code': 'ECE'},
    {'name': 'Electrical Engineering',   'code': 'EE'},
    {'name': 'Electrical & Electronics', 'code': 'EEE'},
    {'name': 'Mechanical Engineering',   'code': 'ME'},
    {'name': 'Civil Engineering',         'code': 'CE'},
    {'name': 'AI & Data Science',         'code': 'AIDS'},
    {'name': 'AI & Machine Learning',    'code': 'AIML'},
    {'name': 'Data Science',              'code': 'DS'},
    {'name': 'Cyber Security',            'code': 'CSEC'},
    {'name': 'Cloud Computing',           'code': 'CC'},
    {'name': 'Robotics & Automation',    'code': 'RA'},
    {'name': 'Biotechnology',             'code': 'BT'},
    {'name': 'Chemical Engineering',     'code': 'CHE'},
    {'name': 'Aerospace Engineering',    'code': 'AE'},
    {'name': 'Physics',                   'code': 'PHY'},
    {'name': 'Chemistry',                 'code': 'CHEM'},
    {'name': 'Mathematics',              'code': 'MATH'},
    {'name': 'Statistics',               'code': 'STAT'},
    {'name': 'MBA',                       'code': 'MBA'},
    {'name': 'BBA',                       'code': 'BBA'},
    {'name': 'Commerce (B.Com)',          'code': 'BCOM'},
    {'name': 'Economics',                 'code': 'ECO'},
    {'name': 'BCA',                       'code': 'BCA'},
    {'name': 'MCA',                       'code': 'MCA'},
    {'name': 'MBBS',                      'code': 'MBBS'},
    {'name': 'Pharmacy (B.Pharma)',       'code': 'BPHARMA'},
    {'name': 'Nursing',                   'code': 'NURS'},
    {'name': 'Arts (BA)',                 'code': 'BA'},
    {'name': 'Psychology',               'code': 'PSY'},
    {'name': 'Law (LLB)',                'code': 'LLB'},
  ];

  List<Map<String,String>> get _allBranches {
    final seen = <String>{for (final p in _presets) p['name']!.toLowerCase()};
    return [
      ..._presets,
      ..._dbCustomBranches.where((b) => seen.add(b['name']!.toLowerCase())),
    ];
  }

  List<Map<String,String>> get _filtered {
    final all = _allBranches;
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((p) =>
      p['name']!.toLowerCase().contains(q) || p['code']!.toLowerCase().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF6C63FF);
    final filtered = _filtered;
    final noResults = filtered.isEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Search box
      TextField(
        controller: widget.searchCtrl,
        style: TextStyle(color: AppColors.text(context), fontSize: 14),
        onChanged: (v) {
          setState(() => _query = v.trim());
          widget.onQueryChanged(v.trim());
          if (v.trim().isNotEmpty && _filtered.isEmpty) {
            final normalized = v.trim().split(' ')
                .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
                .join(' ');
            final code = normalized.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).join();
            widget.customCtrl.text = normalized;
            widget.onCustomChanged(normalized, code);
            widget.onSelectPreset('Other', 'OTHER');
          }
        },
        decoration: InputDecoration(
          hintText: 'Search branch...',
          hintStyle: TextStyle(color: AppColors.textHint(context), fontSize: 13),
          prefixIcon: Icon(Icons.search, color: AppColors.textHint(context), size: 18),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
                  onTap: () { widget.searchCtrl.clear(); setState(() => _query = ''); widget.onQueryChanged(''); },
                  child: Icon(Icons.close, color: AppColors.textHint(context), size: 16))
              : null,
          filled: true, fillColor: AppColors.surfaceVariant(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary.withOpacity(0.2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary.withOpacity(0.2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary.withOpacity(0.6), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
      ),
      const SizedBox(height: 8),
      // List
      if (widget.isLoading)
        const Center(child: Padding(padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(color: primary, strokeWidth: 2)))
      else
        Container(
          height: 190,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant(context), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary.withOpacity(0.15))),
          child: widget.useDbBranches
            ? ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: widget.branches.length,
                itemBuilder: (_, i) {
                  final b = widget.branches[i];
                  final isSelected = widget.selectedBranchId == b['id'].toString();
                  return _UpdateBranchTile(
                    name: b['name'].toString(), code: b['code'].toString(),
                    isSelected: isSelected,
                    onTap: () => widget.onSelectDb(b['id'].toString(), b['name'].toString(), b['code'].toString()));
                })
            : noResults
              ? Column(children: [
                  Padding(padding: const EdgeInsets.all(14),
                    child: Text('No branch found for "$_query"',
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13))),
                  _UpdateBranchTile(name: 'Enter manually', code: '✏️',
                    isSelected: widget.showCustom, isOther: true,
                    onTap: () {
                      if (_query.isNotEmpty) {
                        widget.customCtrl.text = _query;
                        final normalized = _query.split(' ')
                            .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
                            .join(' ');
                        final code = normalized.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).join();
                        widget.onCustomChanged(normalized, code);
                      }
                      widget.onSelectPreset('Other', 'OTHER');
                    }),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length + 1,
                  itemBuilder: (_, i) {
                    if (i == filtered.length) {
                      return _UpdateBranchTile(name: 'Other / Not listed', code: '✏️',
                        isSelected: widget.showCustom, isOther: true,
                        onTap: () {
                          if (_query.isNotEmpty) {
                            widget.customCtrl.text = _query;
                            final normalized = _query.split(' ')
                                .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
                                .join(' ');
                            final code = normalized.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).join();
                            widget.onCustomChanged(normalized, code);
                          }
                          widget.onSelectPreset('Other', 'OTHER');
                        });
                    }
                    final p = filtered[i];
                    final isSelected = widget.selectedBranchCode == p['code'] && !widget.showCustom;
                    return _UpdateBranchTile(
                      name: p['name']!, code: p['code']!, isSelected: isSelected,
                      onTap: () => widget.onSelectPreset(p['name']!, p['code']!));
                  }),
        ),
      // Custom input
      if (widget.showCustom) ...[
        const SizedBox(height: 10),
        TextField(
          controller: widget.customCtrl,
          style: TextStyle(color: AppColors.text(context), fontSize: 14),
          textCapitalization: TextCapitalization.words,
          onChanged: (val) {
            final normalized = val.trim().split(' ')
                .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
                .join(' ');
            final code = normalized.isEmpty ? 'OTHER'
                : normalized.split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).join();
            widget.onCustomChanged(normalized, code);
          },
          decoration: InputDecoration(
            hintText: widget.customCtrl.text.isEmpty ? 'Type your branch name...' : 'Edit branch name',
            hintStyle: TextStyle(color: AppColors.textHint(context), fontSize: 13),
            prefixIcon: const Icon(Icons.edit_outlined, color: primary, size: 18),
            filled: true, fillColor: AppColors.surfaceVariant(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primary)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primary.withOpacity(0.3))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
        ),
      ],
      // Selected badge
      if (widget.selectedBranchId != null && !(widget.selectedBranchCode == 'OTHER' && widget.customCtrl.text.isEmpty))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: primary, size: 14),
            const SizedBox(width: 6),
            Text(
              widget.showCustom ? (widget.customCtrl.text.isNotEmpty ? widget.customCtrl.text : 'Custom branch')
                  : (widget.selectedBranchCode ?? ''),
              style: const TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
    ]);
  }
}

class _UpdateBranchTile extends StatelessWidget {
  final String name, code;
  final bool isSelected, isOther;
  final VoidCallback onTap;
  const _UpdateBranchTile({required this.name, required this.code,
    required this.isSelected, required this.onTap, this.isOther = false});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF6C63FF);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primary.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? primary.withOpacity(0.5) : Colors.transparent)),
        child: Row(children: [
          Container(
            width: 44, height: 22,
            decoration: BoxDecoration(
              color: isSelected ? primary.withOpacity(0.2) : AppColors.surface(context),
              borderRadius: BorderRadius.circular(6)),
            child: Center(child: Text(code, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800,
              color: isSelected ? primary : AppColors.textSecondary(context))))),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: TextStyle(
            fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.text(context) : AppColors.textSecondary(context)))),
          if (isSelected) const Icon(Icons.check_circle_rounded, color: primary, size: 16),
        ])));
  }
}
