import '../../settings/theme_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/dsa_service.dart';
import '../models/dsa_problem.dart';

class DsaDailyScreen extends StatefulWidget {
  const DsaDailyScreen({Key? key}) : super(key: key);

  @override
  State<DsaDailyScreen> createState() => _DsaDailyScreenState();
}

class _DsaDailyScreenState extends State<DsaDailyScreen> {
  final supabase = Supabase.instance.client;
  String? _myId;

  Map<String, dynamic>? _challenge;
  DsaProblem? _problem;
  bool _loading = true;
  String? _error;

  Timer? _countdownTimer;
  Duration _timeUntilNext = Duration.zero;

  static const _kPurple = Color(0xFF6C63FF);
  static const _kTeal   = Color(0xFF00B8A3);
  static const _kAmber  = Color(0xFFFFB800);

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser?.id;
    _load();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_myId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final challenge = await DsaService.fetchDailyChallenge(userId: _myId!);
      // Fetch the full problem using the problem_id from the challenge
      final problemId = challenge['problem_id']?.toString() ?? '';
      final allProblems = await DsaService.fetchAllProblems();
      final problem = allProblems.firstWhere(
        (p) => p.id == problemId,
        orElse: () => allProblems.first,
      );
      if (mounted) setState(() {
        _challenge = challenge;
        _problem = problem;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startCountdown() {
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateCountdown();
    });
  }

  void _updateCountdown() {
    final now = DateTime.now().toUtc();
    final nextMidnight = DateTime.utc(now.year, now.month, now.day + 1);
    setState(() => _timeUntilNext = nextMidnight.difference(now));
  }

  String _formatCountdown(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _onSolved() async {
    if (_myId == null || _challenge == null || _problem == null) return;
    try {
      await DsaService.markDailySolved(
        userId: _myId!,
        problemId: _problem!.id,
        challengeDate: _challenge!['challenge_date']?.toString() ??
            DateTime.now().toUtc().toIso8601String().substring(0, 10),
      );
      await _load(); // refresh to show updated streak + solver count
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Daily challenge completed! Streak updated.'),
          backgroundColor: Color(0xFF00B8A3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _kPurple));
    }
    if (_error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('⚠️', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('Could not load daily challenge',
            style: TextStyle(color: AppColors.text(context), fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(_error!, textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textHint(context), fontSize: 12)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _load,
          style: ElevatedButton.styleFrom(backgroundColor: _kPurple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text('Retry', style: TextStyle(color: AppColors.text(context))),
        ),
      ]));
    }

    final challenge  = _challenge!;
    final problem    = _problem!;
    final isComplete = challenge['is_completed'] == true;
    final streak     = (challenge['streak'] as num?)?.toInt() ?? 0;
    final solvers    = (challenge['total_solvers_today'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      color: _kPurple,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          // ── Header ──
          _buildHeader(streak, solvers, isComplete),

          const SizedBox(height: 20),

          // ── Countdown ──
          _buildCountdown(isComplete),

          const SizedBox(height: 20),

          // ── Problem card ──
          _buildProblemCard(problem, isComplete),

          const SizedBox(height: 20),

          // ── Solve button ──
          if (!isComplete)
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => _DailySolveScreen(
                    problem: problem,
                    onSolved: _onSolved,
                  )),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kTeal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('⚡', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text('Solve Today\'s Challenge',
                      style: TextStyle(color: AppColors.text(context),
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _kTeal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kTeal.withOpacity(0.4)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('✅', style: TextStyle(fontSize: 20)),
                SizedBox(width: 10),
                Text('Challenge Completed Today!',
                    style: TextStyle(color: Color(0xFF00B8A3),
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(int streak, int solvers, bool isComplete) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kAmber.withOpacity(0.15), _kPurple.withOpacity(0.1)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAmber.withOpacity(0.3), width: 1.5),
      ),
      child: Row(children: [
        // Streak
        Column(children: [
          Text(streak > 0 ? '🔥' : '💤',
              style: TextStyle(fontSize: 32)),
          const SizedBox(height: 4),
          Text('$streak day${streak == 1 ? '' : 's'}',
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.w900, fontSize: 16)),
          Text('streak',
              style: TextStyle(color: AppColors.textHint(context), fontSize: 10)),
        ]),
        const SizedBox(width: 20),
        Container(width: 1, height: 56, color: AppColors.border(context)),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Daily Challenge',
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text('$solvers solver${solvers == 1 ? '' : 's'} today',
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
          if (streak >= 7)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kAmber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kAmber.withOpacity(0.4)),
              ),
              child: Text('🏅 ${streak ~/ 7}-week streak',
                  style: TextStyle(color: _kAmber,
                      fontSize: 10, fontWeight: FontWeight.w700)),
            ),
        ])),
        if (isComplete)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kTeal.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: _kTeal.withOpacity(0.4)),
            ),
            child: Icon(Icons.check_rounded, color: _kTeal, size: 22),
          ),
      ]),
    );
  }

  Widget _buildCountdown(bool isComplete) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(children: [
        Icon(Icons.timer_outlined, color: AppColors.textHint(context), size: 18),
        const SizedBox(width: 10),
        Text('Next challenge in',
            style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
        const Spacer(),
        Text(_formatCountdown(_timeUntilNext),
            style: TextStyle(
                color: AppColors.text(context), fontWeight: FontWeight.w800,
                fontSize: 16, fontFamily: 'monospace')),
      ]),
    );
  }

  Widget _buildProblemCard(DsaProblem problem, bool isComplete) {
    final diffColor = problem.difficultyColor;
    final diff = problem.difficulty[0].toUpperCase() + problem.difficulty.substring(1);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: diffColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(diff,
                style: TextStyle(color: diffColor,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          if (problem.topics.isNotEmpty)
            Wrap(spacing: 6, children: problem.topics.take(3).map((t) =>
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(t,
                    style: TextStyle(color: Color(0xFF818CF8),
                        fontSize: 10, fontWeight: FontWeight.w600)),
              )
            ).toList()),
        ]),
        const SizedBox(height: 12),
        Text(problem.title,
            style: TextStyle(color: AppColors.text(context),
                fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 8),
        Text(
          problem.description.length > 180
              ? '${problem.description.substring(0, 180)}…'
              : problem.description,
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13, height: 1.5),
        ),
        if (problem.examples.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Example',
                  style: TextStyle(color: AppColors.textHint(context),
                      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 6),
              Text('Input: ${problem.examples[0]['input'] ?? ''}',
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12,
                      fontFamily: 'monospace')),
              Text('Output: ${problem.examples[0]['output'] ?? ''}',
                  style: TextStyle(color: Color(0xFF00B8A3), fontSize: 12,
                      fontFamily: 'monospace')),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// DAILY SOLVE SCREEN  (solo code editor)
// ══════════════════════════════════════════════════════════

class _DailySolveScreen extends StatefulWidget {
  final DsaProblem problem;
  final Future<void> Function() onSolved;

  const _DailySolveScreen({required this.problem, required this.onSolved});

  @override
  State<_DailySolveScreen> createState() => _DailySolveScreenState();
}

class _DailySolveScreenState extends State<_DailySolveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _codeCtrl = TextEditingController();

  String _lang = 'Python';
  bool _running = false;
  bool _submitting = false;
  bool _solved = false;

  List<Map<String, dynamic>> _testResults = [];
  String? _runError;

  static const _kPurple = Color(0xFF6C63FF);
  static const _kTeal   = Color(0xFF00B8A3);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _codeCtrl.text = DsaService.getStarterCode(_lang, widget.problem);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _runTests() async {
    setState(() { _running = true; _runError = null; _testResults = []; });
    HapticFeedback.lightImpact();
    try {
      final res = await DsaService.runTestCases(
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
    if (_submitting || _solved) return;
    setState(() { _submitting = true; _runError = null; });
    HapticFeedback.mediumImpact();
    try {
      final res = await DsaService.runTestCases(
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Some test cases failed. Keep trying!'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('🎉', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text('Challenge Complete!',
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 6),
          Text('Your streak has been updated.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context)..pop()..pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kTeal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Back to Daily',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
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
        backgroundColor: AppColors.background(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppColors.icon(context), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.problem.title,
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.ellipsis),
          Text('Daily Challenge • $diff',
              style: TextStyle(color: widget.problem.difficultyColor,
                  fontSize: 11)),
        ]),
        actions: [
          // Language picker
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _lang,
                dropdownColor: AppColors.surface(context),
                style: TextStyle(color: AppColors.text(context), fontSize: 12),
                items: DsaService.languageConfig.keys
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _lang = v;
                    _codeCtrl.text = DsaService.getStarterCode(v, widget.problem);
                  });
                },
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _kPurple,
          indicatorWeight: 3,
          labelColor: AppColors.text(context),
          unselectedLabelColor: AppColors.textHint(context),
          labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            const Tab(text: '📝 Problem'),
            Tab(text: _testResults.isEmpty
                ? '🧪 Tests'
                : '🧪 ${_testResults.where((r) => r['passed'] == true).length}/${_testResults.length}'),
          ],
        ),
      ),
      body: Column(children: [
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            // ── Problem + Code ──
            Column(children: [
              // Problem description (scrollable, ~35% height)
              Flexible(
                flex: 4,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.problem.description,
                        style: TextStyle(color: AppColors.textSecondary(context),
                            fontSize: 13, height: 1.6)),
                    if (widget.problem.examples.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ...widget.problem.examples.map((ex) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Input: ${ex['input'] ?? ''}',
                              style: TextStyle(color: AppColors.textSecondary(context),
                                  fontSize: 12, fontFamily: 'monospace')),
                          Text('Output: ${ex['output'] ?? ''}',
                              style: TextStyle(color: Color(0xFF00B8A3),
                                  fontSize: 12, fontFamily: 'monospace')),
                          if (ex['explanation'] != null)
                            Text('// ${ex['explanation']}',
                                style: TextStyle(color: AppColors.textHint(context),
                                    fontSize: 11, fontStyle: FontStyle.italic)),
                        ]),
                      )),
                    ],
                    if (widget.problem.constraints.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Constraints: ${widget.problem.constraints}',
                          style: TextStyle(color: AppColors.textHint(context), fontSize: 11)),
                    ],
                  ]),
                ),
              ),
              Container(height: 1, color: AppColors.border(context)),
              // Code editor (~65% height)
              Flexible(
                flex: 6,
                child: Container(
                  color: const Color(0xFF0D1117),
                  child: TextField(
                    controller: _codeCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                        color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
            ]),

            // ── Test Results ──
            _testResults.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text('🧪', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text('Run your code to see results',
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
                  if (_runError != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(_runError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                ]))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: _testResults.asMap().entries.map((e) {
                      final i = e.key; final r = e.value;
                      final passed = r['passed'] == true;
                      final color  = passed ? _kTeal : Colors.red;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withOpacity(0.3)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Text(passed ? '✅' : '❌',
                                style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text('Test ${i + 1}',
                                style: TextStyle(color: color,
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                          ]),
                          const SizedBox(height: 6),
                          Text('Input: ${r['input'] ?? ''}',
                              style: TextStyle(color: AppColors.textHint(context),
                                  fontSize: 12, fontFamily: 'monospace')),
                          Text('Expected: ${r['expected'] ?? ''}',
                              style: TextStyle(color: AppColors.textHint(context),
                                  fontSize: 12, fontFamily: 'monospace')),
                          Text('Got: ${r['actual'] ?? ''}',
                              style: TextStyle(color: passed ? _kTeal : Colors.red,
                                  fontSize: 12, fontFamily: 'monospace')),
                          if (r['error'] != null && r['error'].toString().isNotEmpty)
                            Text('Error: ${r['error']}',
                                style: TextStyle(color: Colors.orange,
                                    fontSize: 11)),
                        ]),
                      );
                    }).toList(),
                  ),
          ]),
        ),

        // ── Bottom action bar ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            border: Border(top: BorderSide(color: AppColors.border(context))),
          ),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _running ? null : _runTests,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _kPurple.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _running
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2))
                    : Text('▶ Run',
                        style: TextStyle(color: _kPurple, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_submitting || _solved) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _solved ? Colors.white12 : _kTeal,
                  disabledBackgroundColor: AppColors.surfaceVariant(context),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_solved ? '✅ Solved' : '⚡ Submit',
                        style: TextStyle(
                          color: _solved ? Colors.white38 : Colors.white,
                          fontWeight: FontWeight.w800, fontSize: 14,
                        )),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
