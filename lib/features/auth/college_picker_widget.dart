import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';

final supabase = Supabase.instance.client;

/// Drop this widget into your signup/profile completion screen.
/// It auto-suggests colleges as user types and loads branches after selection.
class CollegePickerWidget extends StatefulWidget {
  final void Function(String collegeId, String collegeName,
      String branchId, String branchName) onSelected;
  final String? initialCollegeId;
  final String? initialBranchId;

  const CollegePickerWidget({Key? key, required this.onSelected,
    this.initialCollegeId, this.initialBranchId}) : super(key: key);

  @override
  State<CollegePickerWidget> createState() => _CollegePickerWidgetState();
}

class _CollegePickerWidgetState extends State<CollegePickerWidget> {
  final _collegeCtrl = TextEditingController();
  List<Map<String,dynamic>> _suggestions = [];
  List<Map<String,dynamic>> _branches = [];
  String? _selectedCollegeId;
  String? _selectedCollegeName;
  String? _selectedBranchId;
  String? _selectedBranchName;
  bool _showSuggestions = false;
  bool _loadingBranches = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCollegeId != null) _loadInitial();
  }

  @override
  void dispose() { _collegeCtrl.dispose(); super.dispose(); }

  Future<void> _loadInitial() async {
    try {
      final c = await supabase.from('colleges')
          .select().eq('id', widget.initialCollegeId!).maybeSingle();
      if (c != null) {
        _collegeCtrl.text = c['name'].toString();
        _selectedCollegeId = c['id'].toString();
        _selectedCollegeName = c['name'].toString();
        await _loadBranches(c['id'].toString());
      }
    } catch (_) {}
  }

  Future<void> _searchColleges(String query) async {
    if (query.length < 2) { setState(() { _suggestions = []; _showSuggestions = false; }); return; }
    try {
      final data = await supabase.from('colleges')
          .select().ilike('name', '%$query%').limit(6);
      setState(() { _suggestions = List<Map<String,dynamic>>.from(data); _showSuggestions = true; });
    } catch (_) {}
  }

  Future<void> _loadBranches(String collegeId) async {
    setState(() { _loadingBranches = true; _branches = []; _selectedBranchId = null; _selectedBranchName = null; });
    try {
      final data = await supabase.from('branches')
          .select().eq('college_id', collegeId).order('name');
      setState(() { _branches = List<Map<String,dynamic>>.from(data); _loadingBranches = false; });
    } catch (_) { setState(() => _loadingBranches = false); }
  }

  Future<void> _addAndSelectCollege(String name) async {
    // Auto-create college if not exists
    try {
      final code = name.split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
      final result = await supabase.from('colleges')
          .upsert({'name': name, 'code': code}, onConflict: 'name').select().single();
      _selectCollege(result['id'].toString(), result['name'].toString());
    } catch (_) {}
  }

  void _selectCollege(String id, String name) {
    setState(() {
      _selectedCollegeId = id; _selectedCollegeName = name;
      _collegeCtrl.text = name; _showSuggestions = false; _suggestions = [];
    });
    _loadBranches(id);
  }

  void _selectBranch(String id, String name) {
    setState(() { _selectedBranchId = id; _selectedBranchName = name; });
    if (_selectedCollegeId != null && _selectedCollegeName != null) {
      widget.onSelected(_selectedCollegeId!, _selectedCollegeName!, id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.surfaceVariant(context);
    final border = AppColors.border(context);
    final textColor = AppColors.text(context);
    final hintColor = AppColors.textHint(context);
    final primary = Theme.of(context).primaryColor;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── College search field ──
      Stack(children: [
        TextField(
          controller: _collegeCtrl,
          style: TextStyle(color: textColor, fontSize: 14),
          onChanged: (val) {
            if (_selectedCollegeId != null && val != _selectedCollegeName) {
              setState(() { _selectedCollegeId = null; _selectedCollegeName = null;
                _branches = []; _selectedBranchId = null; _selectedBranchName = null; });
            }
            _searchColleges(val);
          },
          decoration: InputDecoration(
            labelText: 'College Name',
            labelStyle: TextStyle(color: hintColor, fontSize: 13),
            hintText: 'Type to search or add new...',
            hintStyle: TextStyle(color: hintColor, fontSize: 13),
            prefixIcon: Icon(Icons.school_outlined, color: hintColor, size: 20),
            suffixIcon: _selectedCollegeId != null
              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
              : null,
            filled: true, fillColor: bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: primary, width: 2))),
        ),
      ]),

      // ── Suggestions dropdown ──
      if (_showSuggestions && _suggestions.isNotEmpty) Container(
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12)]),
        child: Column(children: [
          ..._suggestions.map((c) => ListTile(
            dense: true,
            leading: const Text('🏫', style: TextStyle(fontSize: 18)),
            title: Text(c['name'].toString(), style: TextStyle(color: textColor,
              fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(c['code'].toString(), style: TextStyle(color: hintColor, fontSize: 11)),
            onTap: () => _selectCollege(c['id'].toString(), c['name'].toString()),
          )),
          // "Add this college" option if no exact match
          if (!_suggestions.any((c) =>
              c['name'].toString().toLowerCase() == _collegeCtrl.text.toLowerCase()))
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_circle_outline, color: Color(0xFF6C63FF), size: 20),
              title: Text('Add "${_collegeCtrl.text}" as new college',
                style: const TextStyle(color: Color(0xFF6C63FF),
                  fontSize: 13, fontWeight: FontWeight.w600)),
              onTap: () => _addAndSelectCollege(_collegeCtrl.text.trim()),
            ),
        ]),
      ),

      const SizedBox(height: 14),

      // ── Branch picker (shows after college is selected) ──
      if (_selectedCollegeId != null) ...[
        if (_loadingBranches)
          Center(child: Padding(padding: const EdgeInsets.all(8),
            child: CircularProgressIndicator(color: primary, strokeWidth: 2)))
        else if (_branches.isEmpty)
          Text('No branches found for this college.',
            style: TextStyle(color: hintColor, fontSize: 12))
        else ...[
          Text('Select Your Branch', style: TextStyle(color: hintColor,
            fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _branches.map((b) {
            final isSelected = _selectedBranchId == b['id'].toString();
            return GestureDetector(
              onTap: () => _selectBranch(b['id'].toString(), b['name'].toString()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? primary.withOpacity(0.15) : bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? primary : border, width: isSelected ? 2 : 1)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isSelected) ...[
                    Icon(Icons.check, color: primary, size: 14),
                    const SizedBox(width: 4),
                  ],
                  Text(b['code'].toString(), style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: isSelected ? primary : textColor)),
                ])));
          }).toList()),
          if (_selectedBranchId != null) ...[
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '$_selectedCollegeName • $_selectedBranchName',
                  style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600))),
              ])),
          ],
        ],
      ],
    ]);
  }
}

/// Helper: saves college+branch to user profile
Future<void> saveCollegeBranchToProfile({
  required String userId,
  required String collegeId,
  required String collegeName,
  required String branchId,
  required String branchName,
}) async {
  await supabase.from('profiles').update({
    'college_id': collegeId,
    'college_name': collegeName,
    'branch_id': branchId,
    'branch_name': branchName,
  }).eq('id', userId);
}
