import '../../settings/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/dsa_service.dart';
import '../models/dsa_problem.dart';

// ══════════════════════════════════════════════════════════
// DSA PRACTICE SCREEN — Browse, filter, and solve problems
// ══════════════════════════════════════════════════════════

class DsaPracticeScreen extends StatefulWidget {
  const DsaPracticeScreen({Key? key}) : super(key: key);

  @override
  State<DsaPracticeScreen> createState() => _DsaPracticeScreenState();
}

class _DsaPracticeScreenState extends State<DsaPracticeScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  String? _myId;

  List<DsaProblem> _allProblems = [];
  Set<String> _solvedIds = {};
  bool _loading = true;

  String _searchQuery = '';
  String _diffFilter = 'all'; // 'all', 'easy', 'medium', 'hard'
  String? _topicFilter;
  String _sortBy = 'difficulty'; // 'difficulty', 'title', 'solved'

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  static const _kPurple = Color(0xFF6C63FF);
  static const _kTeal   = Color(0xFF00B8A3);
  static const _kAmber  = Color(0xFFFFB800);
  static const _kRed    = Color(0xFFFF375F);

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser?.id;
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await DsaService.fetchAllProblems();
      Set<String> solved = {};
      if (_myId != null) {
        final recs = await DsaService.fetchSolvedProblems(userId: _myId!);
        solved = recs.map((r) => r['problem_id'].toString()).toSet();
      }
      if (mounted) setState(() {
        _allProblems = all;
        _solvedIds = solved;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _allTopics {
    final topics = <String>{};
    for (final p in _allProblems) {
      topics.addAll(p.topics);
    }
    return topics.toList()..sort();
  }

  List<DsaProblem> get _filtered {
    var list = _allProblems.where((p) {
      if (_diffFilter != 'all' && p.difficulty != _diffFilter) return false;
      if (_topicFilter != null && !p.topics.contains(_topicFilter)) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!p.title.toLowerCase().contains(q) &&
            !p.topics.any((t) => t.toLowerCase().contains(q))) return false;
      }
      return true;
    }).toList();

    switch (_sortBy) {
      case 'title':
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'solved':
        list.sort((a, b) {
          final aSolved = _solvedIds.contains(a.id) ? 1 : 0;
          final bSolved = _solvedIds.contains(b.id) ? 1 : 0;
          return bSolved.compareTo(aSolved);
        });
        break;
      default: // difficulty
        const order = {'easy': 0, 'medium': 1, 'hard': 2};
        list.sort((a, b) =>
            (order[a.difficulty] ?? 0).compareTo(order[b.difficulty] ?? 0));
    }
    return list;
  }

  Color _diffColor(String d) {
    switch (d) {
      case 'easy':   return _kTeal;
      case 'medium': return _kAmber;
      default:       return _kRed;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _kPurple));
    }

    final problems = _filtered;
    final solvedCount = _solvedIds.length;
    final topics = _allTopics;

    return Column(children: [
      // ── Stats bar ──
      _buildStatsBar(solvedCount),

      // ── Search bar ──
      _buildSearchBar(),

      // ── Filter chips ──
      _buildFilters(topics),

      // ── Problem list ──
      Expanded(
        child: problems.isEmpty
            ? _buildEmpty()
            : RefreshIndicator(
                onRefresh: _load,
                color: _kPurple,
                child: ListView.builder(
                  controller: _scrollCtrl,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: problems.length,
                  itemBuilder: (ctx, i) =>
                      _buildProblemCard(problems[i], i),
                ),
              ),
      ),
    ]);
  }

  Widget _buildStatsBar(int solved) {
    final total = _allProblems.length;
    final pct = total == 0 ? 0.0 : solved / total;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPurple.withOpacity(0.15), _kTeal.withOpacity(0.08)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPurple.withOpacity(0.2)),
      ),
      child: Row(children: [
        // Progress ring
        SizedBox(
          width: 44, height: 44,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
              value: pct,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(_kPurple),
              strokeWidth: 4,
            ),
            Text('${(pct * 100).round()}%',
                style: TextStyle(color: AppColors.text(context),
                    fontSize: 9, fontWeight: FontWeight.w900)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$solved / $total problems solved',
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 3),
          Stack(children: [
            Container(height: 4,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(4))),
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_kPurple, _kTeal]),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ]),
        ])),
        const SizedBox(width: 12),
        // Sort button
        GestureDetector(
          onTap: _showSortSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sort_rounded, color: Colors.white54, size: 14),
              const SizedBox(width: 4),
              Text(_sortBy[0].toUpperCase() + _sortBy.substring(1),
                  style: TextStyle(color: AppColors.textHint(context),
                      fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search problems or topics...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded,
              color: Colors.white24, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Icon(Icons.close_rounded,
                      color: Colors.white24, size: 18),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }

  Widget _buildFilters(List<String> topics) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          // Difficulty chips
          _FilterChip(
            label: 'All',
            selected: _diffFilter == 'all' && _topicFilter == null,
            color: Colors.white60,
            onTap: () => setState(() {
              _diffFilter = 'all';
              _topicFilter = null;
            }),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Easy',
            selected: _diffFilter == 'easy',
            color: _kTeal,
            onTap: () => setState(() {
              _diffFilter = _diffFilter == 'easy' ? 'all' : 'easy';
              _topicFilter = null;
            }),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Medium',
            selected: _diffFilter == 'medium',
            color: _kAmber,
            onTap: () => setState(() {
              _diffFilter = _diffFilter == 'medium' ? 'all' : 'medium';
              _topicFilter = null;
            }),
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'Hard',
            selected: _diffFilter == 'hard',
            color: _kRed,
            onTap: () => setState(() {
              _diffFilter = _diffFilter == 'hard' ? 'all' : 'hard';
              _topicFilter = null;
            }),
          ),
          if (topics.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              width: 1, height: 24,
              margin: const EdgeInsets.symmetric(vertical: 2),
              color: AppColors.border(context),
            ),
            const SizedBox(width: 10),
            ...topics.map((t) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _FilterChip(
                label: t,
                selected: _topicFilter == t,
                color: _kPurple,
                onTap: () => setState(() {
                  _topicFilter = _topicFilter == t ? null : t;
                  _diffFilter = 'all';
                }),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildProblemCard(DsaProblem problem, int index) {
    final isSolved = _solvedIds.contains(problem.id);
    final dColor = _diffColor(problem.difficulty);
    final diff = problem.difficulty[0].toUpperCase() + problem.difficulty.substring(1);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _PracticeSolveScreen(
              problem: problem,
              isSolved: isSolved,
              onSolved: () async {
                await _load();
              },
            ),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: isSolved
              ? LinearGradient(
                  colors: [dColor.withOpacity(0.08), AppColors.surface(context)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight)
              : LinearGradient(
                  colors: [AppColors.surface(context), AppColors.surface(context)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSolved ? dColor.withOpacity(0.3) : Colors.white.withOpacity(0.06),
          ),
          boxShadow: isSolved ? [BoxShadow(
            color: dColor.withOpacity(0.08),
            blurRadius: 12, offset: const Offset(0, 4))
          ] : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Row(children: [
            // Left accent
            Container(
              width: 3, height: 70,
              color: isSolved ? dColor : Colors.white.withOpacity(0.05),
            ),
            const SizedBox(width: 14),

            // Number
            Text('${index + 1}.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.18),
                    fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),

            // Content
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(problem.title,
                      style: TextStyle(
                          color: isSolved ? Colors.white : Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w700, fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: dColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(diff,
                        style: TextStyle(color: dColor,
                            fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                ]),
                if (problem.topics.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, runSpacing: 4,
                    children: problem.topics.take(4).map((t) =>
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kPurple.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(t,
                            style: TextStyle(color: _kPurple.withOpacity(0.7),
                                fontSize: 9, fontWeight: FontWeight.w600)),
                      )
                    ).toList(),
                  ),
                ],
              ]),
            )),

            // Right — solved badge or arrow
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: isSolved
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('✅', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text('Done',
                          style: TextStyle(color: dColor,
                              fontSize: 8, fontWeight: FontWeight.w900)),
                    ])
                  : Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withOpacity(0.2), size: 20),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('🔍', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      Text('No problems found',
          style: TextStyle(color: AppColors.text(context),
              fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Try different filters or search terms',
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
      const SizedBox(height: 20),
      GestureDetector(
        onTap: () => setState(() {
          _diffFilter = 'all';
          _topicFilter = null;
          _searchQuery = '';
          _searchCtrl.clear();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _kPurple.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kPurple.withOpacity(0.3)),
          ),
          child: Text('Clear Filters',
              style: TextStyle(color: _kPurple, fontWeight: FontWeight.w700)),
        ),
      ),
    ]));
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 38, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          Text('Sort Problems',
              style: TextStyle(color: AppColors.text(context),
                  fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          ...['difficulty', 'title', 'solved'].map((s) {
            final isSelected = _sortBy == s;
            final labels = {
              'difficulty': ('📊 Difficulty', 'Easy → Hard'),
              'title':      ('🔤 Title', 'A → Z'),
              'solved':     ('✅ Solved First', 'Completed on top'),
            };
            final (icon, sub) = labels[s]!;
            return GestureDetector(
              onTap: () {
                setState(() => _sortBy = s);
                Navigator.pop(context);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? _kPurple.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? _kPurple.withOpacity(0.4) : Colors.transparent,
                  ),
                ),
                child: Row(children: [
                  Text(icon, style: TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(icon.split(' ').skip(1).join(' '),
                        style: TextStyle(color: AppColors.text(context),
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(sub, style: TextStyle(
                        color: Colors.white.withOpacity(0.35), fontSize: 11)),
                  ])),
                  if (isSelected)
                    Icon(Icons.check_rounded, color: _kPurple, size: 18),
                ]),
              ),
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// FILTER CHIP WIDGET
// ══════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withOpacity(0.6) : Colors.white.withOpacity(0.08),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? color : Colors.white38,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            )),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// PRACTICE SOLVE SCREEN
// ══════════════════════════════════════════════════════════

class _PracticeSolveScreen extends StatefulWidget {
  final DsaProblem problem;
  final bool isSolved;
  final Future<void> Function() onSolved;

  const _PracticeSolveScreen({
    required this.problem,
    required this.isSolved,
    required this.onSolved,
  });

  @override
  State<_PracticeSolveScreen> createState() => _PracticeSolveScreenState();
}

class _PracticeSolveScreenState extends State<_PracticeSolveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _codeCtrl = TextEditingController();

  String _lang = 'Python';
  bool _running = false;
  bool _submitting = false;
  bool _solved = false;

  List<Map<String, dynamic>> _testResults = [];
  String? _runError;
  bool _showProblem = false;

  static const _kPurple = Color(0xFF6C63FF);
  static const _kTeal   = Color(0xFF00B8A3);
  static const _kAmber  = Color(0xFFFFB800);
  static const _kRed    = Color(0xFFFF375F);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _solved = widget.isSolved;
    _codeCtrl.text = DsaService.getStarterCode(_lang, widget.problem);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Color get _diffColor {
    switch (widget.problem.difficulty) {
      case 'easy':   return _kTeal;
      case 'medium': return _kAmber;
      default:       return _kRed;
    }
  }

  Future<void> _runTests() async {
    setState(() { _running = true; _runError = null; _testResults = []; });
    HapticFeedback.lightImpact();
    try {
      // ⚠️ Uses Piston (free) — never touches RapidAPI
      final res = await DsaService.runTestCasesPiston(
        code: _codeCtrl.text,
        language: _lang,
        testCases: widget.problem.testCases,
      );
      setState(() {
        _testResults = List<Map<String, dynamic>>.from(res['results'] ?? []);
        _running = false;
      });
      _tabs.animateTo(1);
    } catch (e) {
      setState(() { _runError = e.toString(); _running = false; });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() { _submitting = true; _runError = null; });
    HapticFeedback.mediumImpact();
    try {
      // ⚠️ Uses Piston (free) — never touches RapidAPI
      final res = await DsaService.runTestCasesPiston(
        code: _codeCtrl.text,
        language: _lang,
        testCases: widget.problem.testCases,
      );
      final results = List<Map<String, dynamic>>.from(res['results'] ?? []);
      setState(() { _testResults = results; _submitting = false; });
      _tabs.animateTo(1);

      if (res['allPass'] == true) {
        setState(() => _solved = true);
        await widget.onSolved();
        if (mounted) _showSuccessDialog();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Some tests failed — keep going!'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() { _runError = e.toString(); _submitting = false; });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Text('🎯', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 14),
          Text('Problem Solved!',
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 6),
          Text('Great work on "${widget.problem.title}"',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)..pop()..pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kTeal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text('Back to Problems',
                  style: TextStyle(color: AppColors.text(context),
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Keep coding',
                style: TextStyle(color: Colors.white.withOpacity(0.3),
                    fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.problem.difficulty[0].toUpperCase() +
        widget.problem.difficulty.substring(1);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D0A1E), Color(0xFF0A1428)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: Colors.white54, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.problem.title,
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.w800, fontSize: 15),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _diffColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(diff,
                  style: TextStyle(color: _diffColor,
                      fontSize: 9, fontWeight: FontWeight.w800)),
            ),
            if (_solved) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _kTeal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('✓ Solved',
                    style: TextStyle(color: _kTeal,
                        fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
        ]),
        actions: [
          // Language picker
          PopupMenuButton<String>(
            onSelected: (lang) {
              setState(() {
                _lang = lang;
                _codeCtrl.text = DsaService.getStarterCode(lang, widget.problem);
              });
            },
            color: AppColors.surface(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kPurple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kPurple.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_lang,
                    style: TextStyle(color: _kPurple,
                        fontSize: 11, fontWeight: FontWeight.w700)),
                Icon(Icons.expand_more_rounded, color: _kPurple, size: 14),
              ]),
            ),
            itemBuilder: (_) => DsaService.languageConfig.keys
                .map((l) => PopupMenuItem(value: l,
                    child: Text(l,
                        style: TextStyle(color: Colors.white, fontSize: 13))))
                .toList(),
          ),
          // Problem toggle
          IconButton(
            icon: Icon(
              _showProblem ? Icons.code_rounded : Icons.description_outlined,
              color: _showProblem ? _kAmber : Colors.white38,
              size: 20,
            ),
            tooltip: _showProblem ? 'Show editor' : 'Show problem',
            onPressed: () => setState(() => _showProblem = !_showProblem),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _kPurple,
          indicatorWeight: 2,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white30,
          labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: '💻 Code'),
            Tab(text: '🧪 Tests'),
          ],
        ),
      ),
      body: _showProblem
          ? _buildProblemPanel()
          : TabBarView(controller: _tabs, children: [
              _buildCodeTab(),
              _buildTestsTab(),
            ]),
      bottomNavigationBar: _showProblem ? null : _buildActionBar(),
    );
  }

  Widget _buildProblemPanel() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.problem.title,
            style: TextStyle(color: AppColors.text(context),
                fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 10),
        if (widget.problem.topics.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6,
            children: widget.problem.topics.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(t,
                  style: TextStyle(color: Color(0xFF818CF8),
                      fontSize: 11, fontWeight: FontWeight.w600)),
            )).toList(),
          ),
        const SizedBox(height: 14),
        Text(widget.problem.description,
            style: TextStyle(color: AppColors.textSecondary(context),
                fontSize: 14, height: 1.6)),
        if (widget.problem.examples.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Examples',
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          ...widget.problem.examples.map((ex) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Input: ${ex['input'] ?? ''}',
                  style: TextStyle(color: AppColors.textSecondary(context),
                      fontSize: 13, fontFamily: 'monospace')),
              const SizedBox(height: 4),
              Text('Output: ${ex['output'] ?? ''}',
                  style: TextStyle(color: Color(0xFF00B8A3),
                      fontSize: 13, fontFamily: 'monospace')),
              if (ex['explanation'] != null && ex['explanation'].toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('${ex['explanation']}',
                    style: TextStyle(color: Colors.white.withOpacity(0.35),
                        fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ]),
          )),
        ],
      ]),
    );
  }

  Widget _buildCodeTab() {
    return Container(
      color: const Color(0xFF0D1117),
      child: TextField(
        controller: _codeCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          color: AppColors.text(context),
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.6,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildTestsTab() {
    if (_running) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: _kPurple),
          SizedBox(height: 14),
          Text('Running tests…',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ]));
    }
    if (_runError != null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kRed.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kRed.withOpacity(0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('❌ Error', style: TextStyle(color: _kRed,
                fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Text(_runError!,
                style: TextStyle(color: Colors.white60,
                    fontFamily: 'monospace', fontSize: 12, height: 1.5)),
          ]),
        ),
      );
    }
    if (_testResults.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('🧪', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text('No results yet',
            style: TextStyle(color: AppColors.text(context),
                fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Tap Run or Submit to test your code',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13)),
      ]));
    }

    final passed = _testResults.where((r) => r['passed'] == true).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: passed == _testResults.length
                  ? [_kTeal.withOpacity(0.12), _kTeal.withOpacity(0.04)]
                  : [_kRed.withOpacity(0.12), _kRed.withOpacity(0.04)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: passed == _testResults.length
                  ? _kTeal.withOpacity(0.3) : _kRed.withOpacity(0.3),
            ),
          ),
          child: Row(children: [
            Text(passed == _testResults.length ? '🎉' : '⚠️',
                style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$passed / ${_testResults.length} tests passed',
                  style: TextStyle(color: AppColors.text(context),
                      fontWeight: FontWeight.w800, fontSize: 15)),
              Text(passed == _testResults.length
                  ? 'All test cases pass!' : 'Some tests failed',
                  style: TextStyle(
                      color: passed == _testResults.length ? _kTeal : _kRed,
                      fontSize: 12)),
            ])),
          ]),
        ),
        ..._testResults.asMap().entries.map((e) {
          final i = e.key;
          final r = e.value;
          final pass = r['passed'] == true;
          final c = pass ? _kTeal : _kRed;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(pass ? '✅' : '❌', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text('Test ${i + 1}',
                    style: TextStyle(color: c,
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              _TestRow('Input', r['input']?.toString() ?? ''),
              _TestRow('Expected', r['expected']?.toString() ?? ''),
              if (!pass) _TestRow('Got', r['actual']?.toString() ?? ''),
              if (!pass && r['error'] != null && r['error'].toString().isNotEmpty)
                _TestRow('Error', r['error'].toString()),
            ]),
          );
        }),
      ],
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16,
          12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border(top: BorderSide(
            color: Colors.white.withOpacity(0.07))),
      ),
      child: Row(children: [
        // Run
        Expanded(
          flex: 1,
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _running ? null : _runTests,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _kPurple.withOpacity(0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _running
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: _kPurple, strokeWidth: 2))
                  : Text('▶ Run',
                      style: TextStyle(color: _kPurple,
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Submit
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: (_submitting || _solved) ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _solved ? _kTeal.withOpacity(0.3) : _kTeal,
                disabledBackgroundColor: _kTeal.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(_solved ? '✅ Already Solved' : '🚀 Submit',
                      style: TextStyle(color: AppColors.text(context),
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TestRow extends StatelessWidget {
  final String label;
  final String value;
  const _TestRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 60,
          child: Text('$label:',
              style: TextStyle(color: Colors.white.withOpacity(0.35),
                  fontSize: 11, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value,
          style: TextStyle(color: Colors.white60,
              fontSize: 11, fontFamily: 'monospace'))),
    ]),
  );
}
