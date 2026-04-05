import '../../settings/theme_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/dsa_service.dart';
import '../models/dsa_problem.dart';
import 'dsa_game_screen.dart';
import 'dsa_room_waiting_screen.dart';
import 'dsa_leaderboard_screen.dart';
import 'dsa_daily_screen.dart';
import 'vibe_coding_screen.dart';

class DsaLobbyScreen extends StatefulWidget {
  const DsaLobbyScreen({Key? key}) : super(key: key);
  @override
  State<DsaLobbyScreen> createState() => _DsaLobbyScreenState();
}

class _DsaLobbyScreenState extends State<DsaLobbyScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  String? _myId;
  bool _isSearching = false;
  bool _isWaiting = false;
  String _selectedDifficulty = 'easy';
  String? _waitingRoomId;
  String? _waitingProblemId;
  Timer? _pollingTimer;
  bool _navigating = false;

  List<Map<String, dynamic>> _solvedRecords = [];
  List<DsaProblem> _allProblems = [];
  bool _loadingSolved = true;

  List<Map<String, dynamic>> _matchHistory = [];
  bool _loadingHistory = true;

  bool _creatingRoom = false;
  String _selectedRoomDifficulty = 'easy';

  int _cardsRemaining = -1; // -1 = loading

  late TabController _tabController;
  final List<String> _difficulties = ['easy', 'medium', 'hard'];

  static const _kPurple  = Color(0xFF6C63FF);
  static const _kTeal    = Color(0xFF00B8A3);
  static const _kAmber   = Color(0xFFFFB800);
  static const _kRed     = Color(0xFFFF375F);

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser?.id;
    _tabController = TabController(length: 6, vsync: this);
    _loadSolvedData();
    _loadMatchHistory();
    _loadCards();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSolvedData() async {
    if (_myId == null) return;
    setState(() => _loadingSolved = true);
    try {
      final solved = await DsaService.fetchSolvedProblems(userId: _myId!);
      final all = await DsaService.fetchAllProblems();
      if (mounted) setState(() {
        _solvedRecords = solved;
        _allProblems = all;
        _loadingSolved = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSolved = false);
    }
  }

  Future<void> _loadMatchHistory() async {
    if (_myId == null) return;
    setState(() => _loadingHistory = true);
    try {
      final history = await DsaService.fetchMatchHistory(userId: _myId!);
      if (mounted) setState(() {
        _matchHistory = history;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadCards() async {
    if (_myId == null) return;
    try {
      final cards = await supabase.rpc('get_or_init_dsa_cards',
          params: {'p_user_id': _myId});
      if (mounted) setState(() => _cardsRemaining = (cards as int?) ?? 3);
    } catch (e) {
      debugPrint('loadCards error: $e');
      if (mounted) setState(() => _cardsRemaining = 3);
    }
  }

  // Returns true if a card was consumed, false if no cards left.
  Future<bool> _useCard() async {
    if (_myId == null) return false;
    try {
      final result = await supabase.rpc('use_dsa_card',
          params: {'p_user_id': _myId});
      final newCount = result as int;
      if (newCount == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('No cards left for today! Come back tomorrow.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
        return false;
      }
      if (mounted) setState(() => _cardsRemaining = newCount);
      return true;
    } catch (e) {
      debugPrint('useCard error: $e');
      return false;
    }
  }

  // ── POLLING using RPC — bypasses RLS ──
  void _startPolling(String roomId, String problemId) {
    _pollingTimer?.cancel();
    _navigating = false;
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      if (_navigating) return;
      try {
        // Use RPC get_dsa_room — runs as SECURITY DEFINER, no RLS block
        final rows = await supabase.rpc('get_dsa_room',
            params: {'p_room_id': roomId});
        if (rows == null || (rows as List).isEmpty) return;
        final room = Map<String, dynamic>.from(rows[0]);
        debugPrint('Poll: status=${room['status']} p2=${room['player2_id']}');
        if (room['status'] == 'active' && room['player2_id'] != null) {
          _navigating = true;
          timer.cancel();
          if (!mounted) return;
          // Game is starting — deduct card for Player 1 (the waiting host)
          await _useCard();
          setState(() => _isWaiting = false);
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => DsaGameScreen(roomId: roomId, problemId: problemId)));
          _navigating = false;
          _loadSolvedData();
        }
      } catch (e) {
        debugPrint('Poll error: $e');
      }
    });
  }

  // ── QUICK MATCH using RPC — bypasses RLS ──
  Future<void> _quickMatch() async {
    if (_myId == null) return;
    // No card check here — card is only deducted when the game actually starts
    setState(() => _isSearching = true);
    HapticFeedback.mediumImpact();
    try {
      // RPC runs SECURITY DEFINER — finds open room OR signals create new
      final result = await supabase.rpc('find_dsa_match', params: {
        'p_player_id': _myId,
        'p_difficulty': _selectedDifficulty,
      });

      final rows = result as List;
      if (rows.isNotEmpty && rows[0]['is_new'] == false) {
        // ── Joined existing room as Player 2 — game starts now, deduct card ──
        final ok = await _useCard();
        if (!ok) return;
        final roomId    = rows[0]['room_id'].toString();
        final problemId = rows[0]['problem_id'].toString();
        if (!mounted) return;
        setState(() => _isSearching = false);
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => DsaGameScreen(roomId: roomId, problemId: problemId)));
        _loadSolvedData();
      } else {
        // ── No room found — create one and wait for opponent ──
        // Card is deducted when opponent joins and game actually starts
        final problem = await DsaService.fetchRandomProblem(
          difficulty: _selectedDifficulty, userId: _myId);
        final roomId = await DsaService.createRoom(
          playerId: _myId!, problemId: problem.id);
        if (!mounted) return;
        setState(() {
          _isWaiting = true;
          _waitingRoomId = roomId;
          _waitingProblemId = problem.id;
        });
        _startPolling(roomId, problem.id);
      }
    } catch (e) {
      debugPrint('QuickMatch error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _cancelWaiting() async {
    _pollingTimer?.cancel();
    if (_waitingRoomId != null) {
      try { await supabase.from('dsa_rooms').delete().eq('id', _waitingRoomId!); }
      catch (_) {}
    }
    if (mounted) setState(() {
      _isWaiting = false;
      _waitingRoomId = null;
      _waitingProblemId = null;
      _navigating = false;
    });
  }

  // ── Back button: if waiting, cancel; else normal pop ──
  Future<bool> _onWillPop() async {
    if (_isWaiting) {
      await _cancelWaiting();
      return false; // stay on screen after cancel
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
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
              border: Border(
                bottom: BorderSide(color: Color(0xFF6C63FF), width: 0.4),
              ),
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new,
                color: Colors.white54, size: 18),
            onPressed: () async {
              if (await _onWillPop()) Navigator.pop(context);
            },
          ),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                  color: _kPurple.withOpacity(0.5),
                  blurRadius: 12, offset: const Offset(0, 3))],
              ),
              child: Text('⚔️', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DSA Combat',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 17,
                      letterSpacing: 0.3)),
              Text('Compete · Solve · Rank',
                  style: TextStyle(color: Colors.white.withOpacity(0.35),
                      fontSize: 10, fontWeight: FontWeight.w500)),
            ]),
          ]),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _cardsRemaining == 0
                    ? Colors.red.withValues(alpha: 0.15)
                    : _cardsRemaining <= 1
                        ? Colors.orange.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _cardsRemaining == 0
                      ? Colors.red.withValues(alpha: 0.5)
                      : _cardsRemaining <= 1
                          ? Colors.orange.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.15),
                  width: 0.8,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('🎴', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text(
                  _cardsRemaining < 0 ? '...' : '$_cardsRemaining',
                  style: TextStyle(
                    color: _cardsRemaining == 0
                        ? Colors.red
                        : _cardsRemaining <= 1
                            ? Colors.orange
                            : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
          ],
          bottom: _isWaiting ? null : TabBar(
            controller: _tabController,
            indicatorColor: _kPurple,
            indicatorWeight: 2,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 12),
            dividerColor: Colors.transparent,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: '⚡ Match'),
              Tab(text: '📅 Daily'),
              Tab(text: '📊 Progress'),
              Tab(text: '⚔️ History'),
              Tab(text: '🏠 Room'),
              Tab(text: '🏆 Ranks'),
            ],
          ),
        ),
        body: _isWaiting
            ? _buildWaitingUI()
            : Stack(children: [
                TabBarView(controller: _tabController,
                    children: [_buildLobbyUI(), const DsaDailyScreen(), _buildProgressUI(), _buildHistoryUI(), _buildRoomTabUI(), _buildRanksTabUI()]),
                _VibeFab(onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const VibeCodingScreen()))),
              ]),
      ),
    );
  }

  // ════════════════════════════════════════
  // WAITING UI
  // ════════════════════════════════════════
  Widget _buildWaitingUI() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.background(context), Color(0xFF0D1530)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Animated radar rings
          Stack(alignment: Alignment.center, children: [
            Container(width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kPurple.withOpacity(0.12), width: 1))),
            Container(width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kPurple.withOpacity(0.2), width: 1))),
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kPurple.withOpacity(0.1),
                border: Border.all(color: _kPurple.withOpacity(0.4), width: 2),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                    color: _kPurple, strokeWidth: 2.5),
              ),
            ),
          ]),
          const SizedBox(height: 32),
          Text('Finding opponent...',
              style: TextStyle(color: AppColors.text(context),
                  fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Room: ${_waitingRoomId?.substring(0, 8) ?? ''}...',
              style: TextStyle(color: AppColors.textHint(context), fontSize: 12)),
          ),
          const SizedBox(height: 6),
          Text('Scanning every 2 seconds',
              style: TextStyle(color: AppColors.textHint(context), fontSize: 11)),
          const SizedBox(height: 48),
          // Cancel button — same as quit flow
          GestureDetector(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppColors.surface(context),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Text('Cancel Search?',
                      style: TextStyle(color: AppColors.text(context),
                          fontWeight: FontWeight.bold)),
                  content: Text('Stop looking for an opponent?',
                      style: TextStyle(color: AppColors.textHint(context))),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Keep Searching',
                          style: TextStyle(color: AppColors.textHint(context)))),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: Text('Cancel',
                          style: TextStyle(color: AppColors.text(context)))),
                  ],
                ),
              );
              if (confirm == true) _cancelWaiting();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Text('✕  Cancel Search',
                  style: TextStyle(color: Colors.red,
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  // ════════════════════════════════════════
  // LOBBY UI
  // ════════════════════════════════════════
  Widget _buildLobbyUI() {
    final solvedCount = _solvedRecords.length;
    final totalCount  = _allProblems.length;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Hero Card ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1060), Color(0xFF0E2050), Color(0xFF0A1830)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _kPurple.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(color: _kPurple.withOpacity(0.3),
                  blurRadius: 32, offset: const Offset(0, 10)),
              BoxShadow(color: Colors.black.withOpacity(0.4),
                  blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                      color: _kPurple.withOpacity(0.5),
                      blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: Center(
                    child: Text('⚔️', style: TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('1v1 Code Battle',
                    style: TextStyle(color: Colors.white,
                        fontSize: 20, fontWeight: FontWeight.w800,
                        letterSpacing: 0.3)),
                const SizedBox(height: 3),
                Text('Fastest correct solution wins the round',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.45), fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 20),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  _kPurple.withOpacity(0.5), Colors.transparent]),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _StatChip(icon: '✅', label: '$solvedCount solved',
                  color: _kTeal),
              const SizedBox(width: 8),
              _StatChip(icon: '📚', label: '$totalCount problems',
                  color: Colors.white24),
              const SizedBox(width: 8),
              _StatChip(icon: '🪙', label: '+50 win', color: Colors.amber),
            ]),
          ]),
        ),

        const SizedBox(height: 24),

        // ── Difficulty ──
        Text('Difficulty',
            style: TextStyle(color: AppColors.text(context),
                fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: _difficulties.map((d) {
            final isSelected = _selectedDifficulty == d;
            final color = _diffColor(d);
            final total = _allProblems.where((p) => p.difficulty == d).length;
            final solvedIds = _solvedRecords.map((r) => r['problem_id'].toString()).toSet();
            final unsolved = _allProblems
                .where((p) => p.difficulty == d && !solvedIds.contains(p.id)).length;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedDifficulty = d);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: isSelected ? color : AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: isSelected ? color : color.withOpacity(0.3),
                        width: isSelected ? 2 : 1),
                    boxShadow: isSelected ? [BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 12, offset: const Offset(0, 4))] : [],
                  ),
                  child: Column(children: [
                    Text(d[0].toUpperCase() + d.substring(1),
                        style: TextStyle(
                          color: isSelected ? Colors.white : color,
                          fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 3),
                    Text('$unsolved left',
                        style: TextStyle(
                          color: (isSelected ? Colors.white : color).withOpacity(0.65),
                          fontSize: 10)),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),

        // ── Rewards ──
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Row(children: [
            Expanded(child: _RewardChip(
                emoji: '🏆', label: 'VICTORY', value: '+50 🪙',
                color: const Color(0xFF00E676))),
            Container(width: 1, height: 40,
                color: AppColors.border(context)),
            Expanded(child: _RewardChip(
                emoji: '💀', label: 'DEFEAT', value: '-20 🪙',
                color: const Color(0xFFFF375F))),
            Container(width: 1, height: 40,
                color: AppColors.border(context)),
            Expanded(child: _RewardChip(
                emoji: '⚡', label: 'SPEED', value: 'Bonus',
                color: _kAmber)),
          ]),
        ),

        const SizedBox(height: 24),

        // ── Match Button ──
        SizedBox(
          width: double.infinity, height: 64,
          child: ElevatedButton(
            onPressed: (_isSearching || _cardsRemaining == 0) ? null : _quickMatch,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: EdgeInsets.zero,
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: _isSearching
                    ? LinearGradient(colors: [
                        _kPurple.withOpacity(0.3),
                        _kPurple.withOpacity(0.3)])
                    : const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE),
                            Color(0xFF00B8A3)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: _isSearching ? [] : [
                  BoxShadow(color: _kPurple.withOpacity(0.5),
                      blurRadius: 24, offset: const Offset(0, 8)),
                  BoxShadow(color: _kTeal.withOpacity(0.2),
                      blurRadius: 40, offset: const Offset(0, 12)),
                ],
              ),
              child: Container(
                alignment: Alignment.center,
                child: _isSearching
                    ? Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white70, strokeWidth: 2.5)),
                          SizedBox(width: 14),
                          Text('Searching for opponent…',
                              style: TextStyle(color: AppColors.textSecondary(context),
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ])
                    : _cardsRemaining == 0
                        ? Row(mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('🎴', style: TextStyle(fontSize: 22)),
                              SizedBox(width: 10),
                              Text('No Cards Left',
                                  style: TextStyle(color: Colors.white38,
                                      fontSize: 19, fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5)),
                            ])
                        : Row(mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('⚡', style: TextStyle(fontSize: 22)),
                              SizedBox(width: 10),
                              Text('Find Match',
                                  style: TextStyle(color: AppColors.text(context),
                                      fontSize: 19, fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5)),
                            ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ════════════════════════════════════════
  // PROGRESS UI
  // ════════════════════════════════════════
  Widget _buildProgressUI() {
    if (_loadingSolved) {
      return Center(child: CircularProgressIndicator(color: _kPurple));
    }
    final solvedIds = _solvedRecords.map((r) => r['problem_id'].toString()).toSet();
    final easy   = _allProblems.where((p) => p.difficulty == 'easy').toList();
    final medium = _allProblems.where((p) => p.difficulty == 'medium').toList();
    final hard   = _allProblems.where((p) => p.difficulty == 'hard').toList();
    final pct = _allProblems.isEmpty ? 0.0
        : solvedIds.length / _allProblems.length;

    return RefreshIndicator(
      onRefresh: _loadSolvedData,
      color: _kPurple,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          // Stats row
          Row(children: [
            Expanded(child: _StatCard(label: 'Solved',
                value: '${solvedIds.length}', color: _kTeal, icon: '✅')),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(label: 'Total',
                value: '${_allProblems.length}', color: _kPurple, icon: '📚')),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(label: 'Left',
                value: '${_allProblems.length - solvedIds.length}',
                color: _kAmber, icon: '🎯')),
          ]),

          const SizedBox(height: 20),

          // Progress bar
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF13102A), Color(0xFF0E1828)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kPurple.withOpacity(0.25)),
              boxShadow: [BoxShadow(
                  color: _kPurple.withOpacity(0.1),
                  blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _kPurple,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                          color: _kPurple.withOpacity(0.6), blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Overall Progress',
                      style: TextStyle(color: AppColors.textSecondary(context),
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kPurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kPurple.withOpacity(0.3)),
                  ),
                  child: Text('${(pct * 100).round()}%',
                      style: TextStyle(color: _kPurple,
                          fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 14),
              Stack(children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF00B8A3)]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(
                          color: _kPurple.withOpacity(0.5), blurRadius: 8)],
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${solvedIds.length} solved',
                    style: TextStyle(color: _kTeal.withOpacity(0.8),
                        fontSize: 11, fontWeight: FontWeight.w600)),
                Text('${_allProblems.length - solvedIds.length} remaining',
                    style: TextStyle(color: AppColors.textHint(context),
                        fontSize: 11)),
              ]),
            ]),
          ),

          const SizedBox(height: 24),

          // ── Topics breakdown ──
          ..._buildTopicsSection(solvedIds),

          if (easy.isNotEmpty) ...[
            _buildSection('Easy', easy, solvedIds, _kTeal),
            const SizedBox(height: 20),
          ],
          if (medium.isNotEmpty) ...[
            _buildSection('Medium', medium, solvedIds, _kAmber),
            const SizedBox(height: 20),
          ],
          if (hard.isNotEmpty)
            _buildSection('Hard', hard, solvedIds, _kRed),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<DsaProblem> problems,
      Set<String> solvedIds, Color color) {
    final solved = problems.where((p) => solvedIds.contains(p.id)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 4, height: 18,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color,
            fontWeight: FontWeight.bold, fontSize: 15)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$solved/${problems.length}',
              style: TextStyle(color: color,
                  fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ]),
      const SizedBox(height: 10),
      ...problems.map((p) {
        final isSolved = solvedIds.contains(p.id);
        final record = _solvedRecords
            .where((r) => r['problem_id'].toString() == p.id).firstOrNull;
        final lang = record?['language']?.toString() ?? '';
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            _showProblemSheet(
              p.id,
              onCreateRoom: () => _createBattleRoomForProblem(p),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isSolved ? color.withOpacity(0.07) : AppColors.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isSolved ? color.withOpacity(0.35) : AppColors.surfaceVariant(context)),
            ),
            child: Row(children: [
              Text(isSolved ? '✅' : '🔒', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, style: TextStyle(
                  color: isSolved ? Colors.white : AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600, fontSize: 13)),
                if (isSolved && lang.isNotEmpty)
                  Text('via $lang', style: TextStyle(
                      color: color.withOpacity(0.65), fontSize: 10)),
              ])),
              if (isSolved)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Done', style: TextStyle(
                      color: color, fontSize: 10, fontWeight: FontWeight.w800)),
                )
              else
                Icon(Icons.chevron_right, color: AppColors.textHint(context), size: 18),
            ]),
          ),
        );
      }),
    ]);
  }

  List<Widget> _buildTopicsSection(Set<String> solvedIds) {
    // Collect all unique topics across all problems
    final topicMap = <String, _TopicStat>{};
    for (final p in _allProblems) {
      for (final topic in p.topics) {
        topicMap.putIfAbsent(topic, () => _TopicStat(topic));
        topicMap[topic]!.total++;
        if (solvedIds.contains(p.id)) topicMap[topic]!.solved++;
      }
    }
    if (topicMap.isEmpty) return [];

    final topics = topicMap.values.toList()
      ..sort((a, b) => b.solved.compareTo(a.solved));

    return [
      Row(children: [
        Container(width: 4, height: 18,
            decoration: BoxDecoration(
                color: _kPurple, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text('Topics',
            style: TextStyle(color: _kPurple,
                fontWeight: FontWeight.bold, fontSize: 15)),
      ]),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: topics.map((t) {
          final pct = t.total == 0 ? 0.0 : t.solved / t.total;
          final color = pct == 1.0 ? _kTeal : (pct > 0 ? _kPurple : AppColors.textHint(context));
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t.name,
                  style: TextStyle(color: color,
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${t.solved}/${t.total}',
                    style: TextStyle(color: color,
                        fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ]),
          );
        }).toList(),
      ),
      const SizedBox(height: 24),
    ];
  }

  // ════════════════════════════════════════
  // HISTORY UI
  // ════════════════════════════════════════
  Widget _buildHistoryUI() {
    if (_loadingHistory) {
      return Center(child: CircularProgressIndicator(color: _kPurple));
    }

    if (_matchHistory.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                _kPurple.withOpacity(0.2), _kTeal.withOpacity(0.1)]),
              shape: BoxShape.circle,
              border: Border.all(color: _kPurple.withOpacity(0.3), width: 1.5),
            ),
            child: Center(
                child: Text('⚔️', style: TextStyle(fontSize: 40))),
          ),
          const SizedBox(height: 20),
          Text('No battles yet',
              style: TextStyle(color: AppColors.text(context),
                  fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Win or lose, your history will appear here',
              style: TextStyle(color: AppColors.textHint(context),
                  fontSize: 13)),
        ]),
      );
    }

    final wins = _matchHistory.where((m) => m['is_win'] == true).length;
    final losses = _matchHistory.length - wins;

    return RefreshIndicator(
      onRefresh: _loadMatchHistory,
      color: _kPurple,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          // ── Summary row ──
          Row(children: [
            Expanded(child: _StatCard(label: 'Wins', value: '$wins', color: _kTeal, icon: '🏆')),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(label: 'Losses', value: '$losses', color: _kRed, icon: '💀')),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(label: 'Battles', value: '${_matchHistory.length}', color: _kPurple, icon: '⚔️')),
          ]),
          const SizedBox(height: 20),

          // ── Match cards ──
          ..._matchHistory.map((m) => _buildMatchCard(m)),
        ],
      ),
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match) {
    final isWin = match['is_win'] == true;
    final isForfeit = match['is_forfeit'] == true;
    final resultColor = isWin ? const Color(0xFF00E676) : const Color(0xFFFF375F);
    final coins = match['coins'] as int;
    final difficulty = match['difficulty'] as String? ?? 'easy';
    final diffColor = _diffColor(difficulty);
    final timeTaken = match['time_taken'] as String?;
    final playedAt = match['played_at'] as String?;

    String dateLabel = '';
    if (playedAt != null) {
      try {
        final dt = DateTime.parse(playedAt).toLocal();
        final diff = DateTime.now().difference(dt);
        if (diff.inDays == 0) dateLabel = 'Today';
        else if (diff.inDays == 1) dateLabel = 'Yesterday';
        else dateLabel = '${diff.inDays}d ago';
      } catch (_) {}
    }

    final problemId = match['problem_id'] as String?;

    return GestureDetector(
      onTap: problemId != null ? () {
        HapticFeedback.selectionClick();
        _showProblemSheet(problemId);
      } : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            resultColor.withOpacity(0.07),
            const Color(0xFF0D1020),
          ],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: resultColor.withOpacity(0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(children: [
          // Left accent bar
          Container(
            width: 4,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [resultColor, resultColor.withOpacity(0.3)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Result badge
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: resultColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: resultColor.withOpacity(0.35)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(isWin ? '🏆' : '💀',
                  style: TextStyle(fontSize: 18)),
              Text(isWin ? 'WIN' : 'LOSS',
                  style: TextStyle(color: resultColor,
                      fontSize: 8, fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
            ]),
          ),
          const SizedBox(width: 12),

          // Problem + opponent
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(match['problem_title'] as String? ?? 'Unknown Problem',
                  style: TextStyle(color: AppColors.text(context),
                      fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: diffColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: diffColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    difficulty[0].toUpperCase() + difficulty.substring(1),
                    style: TextStyle(color: diffColor,
                        fontSize: 9, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                Icon(Icons.person_outline,
                    color: AppColors.textHint(context), size: 11),
                const SizedBox(width: 3),
                Flexible(
                  child: Text('vs ${match['opponent_name']}',
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ]),
          )),

          // Right side
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(coins > 0 ? '+$coins 🪙' : '$coins 🪙',
                  style: TextStyle(
                    color: coins > 0 ? const Color(0xFFFFD700) : _kRed,
                    fontWeight: FontWeight.w900, fontSize: 14,
                  )),
              const SizedBox(height: 4),
              if (isForfeit)
                Text('🏳 Quit',
                    style: TextStyle(color: _kAmber.withOpacity(0.7),
                        fontSize: 10))
              else if (timeTaken != null)
                Text('⏱ $timeTaken',
                    style: TextStyle(color: AppColors.textHint(context),
                        fontSize: 10, fontFamily: 'monospace')),
              if (dateLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(dateLabel,
                    style: TextStyle(
                        color: AppColors.textHint(context), fontSize: 10)),
              ],
            ]),
          ),
        ]),
      ),
    ), // GestureDetector
    );
  }

  void _showProblemSheet(String problemId, {VoidCallback? onCreateRoom}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).pop(),
        child: DraggableScrollableSheet(
          initialChildSize: onCreateRoom != null ? 0.85 : 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, ctrl) => GestureDetector(
            onTap: () {},
            child: _ProblemDetailSheet(
              problemId: problemId,
              scrollCtrl: ctrl,
              onCreateRoom: onCreateRoom,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createBattleRoomForProblem(DsaProblem problem) async {
    if (_myId == null || _creatingRoom) return;
    setState(() => _creatingRoom = true);
    HapticFeedback.mediumImpact();
    try {
      final result = await DsaService.createBattleRoom(
        playerId: _myId!,
        difficulty: problem.difficulty,
        problemId: problem.id,
      );
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => DsaRoomWaitingScreen(
          roomId: result['room_id']!,
          roomCode: result['room_code']!,
          isHost: true,
          difficulty: problem.difficulty,
        ),
      ));
      _loadSolvedData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _creatingRoom = false);
    }
  }

  // ════════════════════════════════════════
  // ROOM TAB UI
  // ════════════════════════════════════════
  Widget _buildRoomTabUI() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Hero card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1040), Color(0xFF0E1A3A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _kPurple.withOpacity(0.35)),
            boxShadow: [BoxShadow(
              color: _kPurple.withOpacity(0.2),
              blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('🏠', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Private Battle Room',
                    style: TextStyle(color: Colors.white,
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Invite up to 3 players • You pick difficulty',
                    style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _StatChip(icon: '👥', label: 'Max 3 players', color: _kTeal),
              const SizedBox(width: 8),
              _StatChip(icon: '🔑', label: 'Room code', color: Colors.white24),
              const SizedBox(width: 8),
              _StatChip(icon: '🪙', label: '+50 win', color: Colors.amber),
            ]),
          ]),
        ),

        const SizedBox(height: 24),

        // Difficulty picker for room
        Text('Difficulty',
            style: TextStyle(color: AppColors.text(context),
                fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: _difficulties.map((d) {
            final isSelected = _selectedRoomDifficulty == d;
            final color = _diffColor(d);
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedRoomDifficulty = d);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: isSelected ? color : AppColors.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: isSelected ? color : color.withOpacity(0.3),
                        width: isSelected ? 2 : 1),
                    boxShadow: isSelected ? [BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 12, offset: const Offset(0, 4))] : [],
                  ),
                  child: Center(child: Text(
                    d[0].toUpperCase() + d.substring(1),
                    style: TextStyle(
                      color: isSelected ? Colors.white : color,
                      fontWeight: FontWeight.bold, fontSize: 13,
                    ),
                  )),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Create Room button
        SizedBox(
          width: double.infinity, height: 58,
          child: ElevatedButton(
            onPressed: (_creatingRoom || _cardsRemaining == 0) ? null : _createBattleRoom,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              disabledBackgroundColor: _kPurple.withOpacity(0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 8,
              shadowColor: _kPurple.withOpacity(0.4),
            ),
            child: _creatingRoom
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Creating room…',
                        style: TextStyle(color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ])
                : _cardsRemaining == 0
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('🎴', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 10),
                        Text('No Cards Left',
                            style: TextStyle(color: Colors.white38, fontSize: 17,
                                fontWeight: FontWeight.bold)),
                      ])
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('🏠', style: TextStyle(fontSize: 20)),
                        SizedBox(width: 10),
                        Text('Create Room',
                            style: TextStyle(color: Colors.white, fontSize: 17,
                                fontWeight: FontWeight.bold)),
                      ]),
          ),
        ),

        const SizedBox(height: 14),

        // Divider
        Row(children: [
          Expanded(child: Divider(color: AppColors.border(context))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('OR', style: TextStyle(
                color: AppColors.textHint(context), fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 2)),
          ),
          Expanded(child: Divider(color: AppColors.border(context))),
        ]),

        const SizedBox(height: 14),

        // Join Room button
        SizedBox(
          width: double.infinity, height: 58,
          child: OutlinedButton(
            onPressed: _showJoinRoomSheet,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _kTeal.withOpacity(0.5), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('🔑', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Text('Join Room',
                  style: TextStyle(color: Color(0xFF00B8A3), fontSize: 17,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _createBattleRoom() async {
    if (_myId == null || _creatingRoom) return;
    setState(() => _creatingRoom = true);
    HapticFeedback.mediumImpact();
    try {
      final result = await DsaService.createBattleRoom(
        playerId: _myId!,
        difficulty: _selectedRoomDifficulty,
      );
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => DsaRoomWaitingScreen(
          roomId: result['room_id']!,
          roomCode: result['room_code']!,
          isHost: true,
          difficulty: _selectedRoomDifficulty,
        ),
      ));
      _loadSolvedData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _creatingRoom = false);
    }
  }

  void _showJoinRoomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DsaJoinSheet(onJoin: _joinBattleRoom),
    );
  }

  Future<void> _joinBattleRoom(String code) async {
    if (_myId == null) return;
    try {
      final result = await DsaService.joinBattleRoom(
        roomCode: code,
        playerId: _myId!,
      );
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => DsaRoomWaitingScreen(
          roomId: result['room_id']!,
          roomCode: result['room_code']!,
          isHost: result['is_host'] == true,
          difficulty: result['difficulty']?.toString() ?? 'easy',
        ),
      ));
      _loadSolvedData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Color _diffColor(String d) {
    switch (d) {
      case 'easy':   return _kTeal;
      case 'medium': return _kAmber;
      default:       return _kRed;
    }
  }

  // ════════════════════════════════════════
  // RANKS TAB UI
  // ════════════════════════════════════════
  Widget _buildRanksTabUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kAmber.withOpacity(0.15), _kPurple.withOpacity(0.15)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _kAmber.withOpacity(0.35), width: 1.5),
              ),
              child: Column(children: [
                Text('🏆', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text('DSA Rankings',
                    style: TextStyle(color: AppColors.text(context),
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('See who solves fastest\nand wins the most battles',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const DsaLeaderboardScreen())),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAmber,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text('View Rankings',
                        style: TextStyle(color: Colors.black,
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── HELPER WIDGETS ──

class _StatChip extends StatelessWidget {
  final String icon, label;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: TextStyle(fontSize: 12)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value, icon;
  final Color color;
  const _StatCard({required this.label, required this.value,
    required this.color, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withOpacity(0.12), color.withOpacity(0.05)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.25)),
      boxShadow: [BoxShadow(
          color: color.withOpacity(0.1),
          blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Column(children: [
      Text(icon, style: TextStyle(fontSize: 22)),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(color: color,
          fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
          color: color.withOpacity(0.6),
          fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
    ]),
  );
}

class _RewardChip extends StatelessWidget {
  final String emoji, label, value;
  final Color color;
  const _RewardChip({required this.emoji, required this.label,
    required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(emoji, style: TextStyle(fontSize: 22)),
    const SizedBox(height: 4),
    Text(label, style: TextStyle(
        color: color.withOpacity(0.6),
        fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
    const SizedBox(height: 2),
    Text(value, style: TextStyle(
        color: color, fontSize: 13, fontWeight: FontWeight.w900)),
  ]);
}

// ── Draggable Vibe FAB ───────────────────────────────────────

class _VibeFab extends StatefulWidget {
  final VoidCallback onTap;
  const _VibeFab({required this.onTap});
  @override
  State<_VibeFab> createState() => _VibeFabState();
}

class _VibeFabState extends State<_VibeFab>
    with SingleTickerProviderStateMixin {
  // Start near bottom-right, offset from edge
  double _x = 0;
  double _y = 0;
  bool _positioned = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (!_positioned) {
      _x = size.width - 80;
      _y = size.height - 200;
      _positioned = true;
    }

    return Positioned(
      left: _x,
      top: _y,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _x = (_x + d.delta.dx).clamp(0, size.width - 64);
            _y = (_y + d.delta.dy).clamp(0, size.height - 120);
          });
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 62, height: 62,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00B8A3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.55),
                    blurRadius: 20, spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: const Color(0xFF00B8A3).withOpacity(0.25),
                    blurRadius: 30, spreadRadius: 4,
                  ),
                ],
              ),
              child: Stack(alignment: Alignment.center, children: [
                // Outer ring
                Container(
                  width: 62, height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25), width: 1.5),
                  ),
                ),
                Text('🤖', style: TextStyle(fontSize: 26)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Topic stat helper ────────────────────────────────────────

class _TopicStat {
  final String name;
  int total = 0;
  int solved = 0;
  _TopicStat(this.name);
}

// ── DSA Join Room Sheet ──────────────────────────────────────

class _DsaJoinSheet extends StatefulWidget {
  final Future<void> Function(String) onJoin;
  const _DsaJoinSheet({required this.onJoin});
  @override
  State<_DsaJoinSheet> createState() => _DsaJoinSheetState();
}

class _DsaJoinSheetState extends State<_DsaJoinSheet> {
  final _ctrl    = TextEditingController();
  bool _loading  = false;

  static const _kPurple = Color(0xFF6C63FF);

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 24, left: 24, right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 38, height: 4,
            decoration: BoxDecoration(
                color: AppColors.border(context), borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 22),
        Text('Join a Battle Room',
            style: TextStyle(color: AppColors.text(context), fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Enter the 6-character room code',
            style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141828),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kPurple.withOpacity(0.4), width: 1.5),
          ),
          child: TextField(
            controller: _ctrl,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 30,
                fontWeight: FontWeight.w900, letterSpacing: 12),
            decoration: InputDecoration(
              hintText: 'ABC123',
              hintStyle: TextStyle(color: Color(0xFF252840),
                  fontSize: 30, letterSpacing: 12),
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.symmetric(vertical: 20),
            ),
            onChanged: (v) => _ctrl.value = TextEditingValue(
                text: v.toUpperCase(), selection: _ctrl.selection),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton(
            onPressed: _loading ? null : () {
              final code = _ctrl.text.trim();
              if (code.length != 6) return;
              setState(() => _loading = true);
              Navigator.pop(context);
              widget.onJoin(code);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              disabledBackgroundColor: Colors.white10,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _loading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : Text('Join Room',
                    style: TextStyle(color: AppColors.text(context),
                        fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

// ── Problem Detail Bottom Sheet ──────────────────────────────

class _ProblemDetailSheet extends StatefulWidget {
  final String problemId;
  final ScrollController scrollCtrl;
  final VoidCallback? onCreateRoom;
  const _ProblemDetailSheet({
    required this.problemId,
    required this.scrollCtrl,
    this.onCreateRoom,
  });
  @override
  State<_ProblemDetailSheet> createState() => _ProblemDetailSheetState();
}

class _ProblemDetailSheetState extends State<_ProblemDetailSheet> {
  DsaProblem? _problem;
  bool _loading = true;

  static const _kPurple = Color(0xFF6C63FF);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await DsaService.fetchProblemById(widget.problemId);
    if (mounted) setState(() { _problem = p; _loading = false; });
  }

  Color _diffColor(String d) {
    switch (d) {
      case 'easy':   return const Color(0xFF00B8A3);
      case 'medium': return const Color(0xFFFFB800);
      default:       return const Color(0xFFFF375F);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D1020),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: _kPurple)),
            )
          else if (_problem == null)
            const Expanded(
              child: Center(
                child: Text('Problem not found',
                    style: TextStyle(color: Colors.white54)),
              ),
            )
          else
            Expanded(child: _buildContent(_problem!)),
          if (widget.onCreateRoom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onCreateRoom!();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🏠', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text('Create Room for this Question',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      );
  }

  Widget _buildContent(DsaProblem p) {
    final dColor = _diffColor(p.difficulty);
    final diff = p.difficulty[0].toUpperCase() + p.difficulty.substring(1);

    return ListView(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(p.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: dColor.withOpacity(0.35)),
            ),
            child: Text(diff,
                style: TextStyle(
                    color: dColor, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        if (p.topics.isNotEmpty) ...[
          Wrap(
            spacing: 6, runSpacing: 6,
            children: p.topics.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _kPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(t,
                  style: const TextStyle(
                      color: Color(0xFF818CF8),
                      fontSize: 11, fontWeight: FontWeight.w600)),
            )).toList(),
          ),
          const SizedBox(height: 14),
        ],
        Text(p.description,
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, height: 1.6)),
        if (p.examples.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Examples',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          ...p.examples.map((ex) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Input: ${ex['input'] ?? ''}',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 13, fontFamily: 'monospace')),
              const SizedBox(height: 4),
              Text('Output: ${ex['output'] ?? ''}',
                  style: const TextStyle(
                      color: Color(0xFF00B8A3),
                      fontSize: 13, fontFamily: 'monospace')),
              if (ex['explanation'] != null &&
                  ex['explanation'].toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('${ex['explanation']}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ]),
          )),
        ],
        if (p.constraints.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Text('Constraints',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Text(p.constraints,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13, fontFamily: 'monospace')),
          ),
        ],
        if (p.solution != null && p.solution!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(children: [
            const Text('💡 ', style: TextStyle(fontSize: 14)),
            const Text('Solution',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1628),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.25)),
            ),
            child: Text(p.solution!,
                style: const TextStyle(
                    color: Color(0xFFB0C4FF),
                    fontSize: 13, fontFamily: 'monospace', height: 1.6)),
          ),
        ],
      ],
    );
  }
}