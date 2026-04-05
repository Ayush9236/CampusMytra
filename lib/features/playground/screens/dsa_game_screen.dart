import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dsa_problem.dart';
import '../services/dsa_service.dart';

class DsaGameScreen extends StatefulWidget {
  final String roomId;
  final String problemId;

  const DsaGameScreen({
    Key? key,
    required this.roomId,
    required this.problemId,
  }) : super(key: key);

  @override
  State<DsaGameScreen> createState() => _DsaGameScreenState();
}

class _DsaGameScreenState extends State<DsaGameScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  DsaProblem? _problem;
  Map<String, dynamic>? _room;
  String? _myId;
  String _selectedLanguage = 'Python';
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSolved = false;
  bool _opponentSolved = false;
  String _opponentName = '';

  // Timer
  Timer? _timer;
  int _elapsedSeconds = 0;

  // Test results
  List<Map<String, dynamic>> _testResults = [];
  bool _showResults = false;

  // Tab controller
  late TabController _tabController;

  StreamSubscription? _roomSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _myId = supabase.auth.currentUser?.id;
    _loadGame();
  }

  Future<void> _loadGame() async {
    try {
      final problems = await DsaService.fetchProblems();
      final problem = problems.firstWhere((p) => p.id == widget.problemId);

      // Fetch opponent username
      try {
        final room = await supabase
            .from('dsa_rooms')
            .select('player1_id, player2_id')
            .eq('id', widget.roomId)
            .single();
        final oppId = room['player1_id'] == _myId
            ? room['player2_id']?.toString()
            : room['player1_id']?.toString();
        if (oppId != null && oppId.isNotEmpty) {
          final prof = await supabase
              .from('profiles')
              .select('username')
              .eq('id', oppId)
              .maybeSingle();
          if (mounted) setState(() => _opponentName = prof?['username']?.toString() ?? '');
        }
      } catch (_) {}

      setState(() {
        _problem = problem;
        _codeController.text = DsaService.getStarterCode(_selectedLanguage, problem);
        _isLoading = false;
      });

      _startTimer();
      _listenToRoom();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _listenToRoom() {
    _roomSub = supabase
        .from('dsa_rooms')
        .stream(primaryKey: ['id'])
        .eq('id', widget.roomId)
        .listen((data) {
          if (!mounted || data.isEmpty) return;
          final room = Map<String, dynamic>.from(data[0]);
          setState(() => _room = room);

          final isPlayer1 = room['player1_id'] == _myId;
          final oppSolved = isPlayer1
              ? room['player2_solved'] == true
              : room['player1_solved'] == true;

          if (oppSolved && !_opponentSolved) {
            setState(() => _opponentSolved = true);
            if (!_isSolved) _showOpponentSolvedBanner();
          }

          if (room['status'] == 'finished') {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _showResultDialog(room['winner_id'] == _myId);
            });
          }
        });
  }

  void _showOpponentSolvedBanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Text('⚡', style: TextStyle(fontSize: 18)),
          SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_opponentName.isNotEmpty ? '@$_opponentName submitted!' : 'Opponent submitted!',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 14)),
              Text('Hurry — finish before they get accepted!',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          )),
        ]),
        backgroundColor: const Color(0xFF1A0F00),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.orange, width: 1.5),
        ),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _quitGame() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        title: const Text('Quit Game?', style: TextStyle(color: Colors.white)),
        content: const Text(
          '⚠️ Quitting mid-battle will cost you 30 coins and your opponent wins automatically.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Quit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final currentRoom = Map<String, dynamic>.from(_room ?? {});
      final String player1Id = (currentRoom['player1_id'] ?? '') as String;
      final String player2Id = (currentRoom['player2_id'] ?? '') as String;
      final bool isPlayer1 = player1Id == _myId;
      final String opponentId = isPlayer1 ? player2Id : player1Id;

      // Mark opponent as winner
      await supabase.from('dsa_rooms').update({
        'status': 'finished',
        'winner_id': opponentId.isNotEmpty ? opponentId : null,
      }).eq('id', widget.roomId);

      // Deduct coins from quitter
      await supabase.rpc('update_user_coins', params: {
        'p_user_id': _myId,
        'p_amount': -30,
        'p_game_type': 'dsa_quit',
        'p_description': 'Quit DSA Combat',
      });

      // Give coins to opponent
      if (opponentId.isNotEmpty) {
        await supabase.rpc('update_user_coins', params: {
          'p_user_id': opponentId,
          'p_amount': 50,
          'p_game_type': 'dsa_win',
          'p_description': 'Won by opponent quit',
        });
      }

      // Record to match_history
      await supabase.rpc('record_game_result', params: {
        'p_winner_id': opponentId.isNotEmpty ? opponentId : _myId,
        'p_loser_id': _myId,
        'p_room_id': widget.roomId,
        'p_was_quit': true,
        'p_game_type': 'dsa_win',
      });

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

    Future<void> _submitSolution() async {
    if (_isSubmitting || _isSolved || _problem == null) return;

    setState(() {
      _isSubmitting = true;
      _showResults = false;
      _testResults = [];
    });

    try {
      final results = await DsaService.runTestCases(
        code: _codeController.text,
        language: _selectedLanguage,
        testCases: _problem!.testCases,
      );

      setState(() {
        _testResults = List<Map<String, dynamic>>.from(results['results']);
        _showResults = true;
        _tabController.animateTo(1);
      });

      if (results['allPass'] == true) {
        setState(() => _isSolved = true);
        _timer?.cancel();

        // Track this problem as solved for the user
        if (_problem != null && _myId != null) {
          await DsaService.markProblemSolved(
            userId: _myId!,
            problemId: _problem!.id,
            language: _selectedLanguage,
          );
        }

        // Store room data locally — avoids null-safety issues
        final currentRoom = Map<String, dynamic>.from(_room ?? {});
        final String player1Id = (currentRoom['player1_id'] ?? '') as String;
        final String player2Id = (currentRoom['player2_id'] ?? '') as String;
        final bool isPlayer1 = player1Id == _myId;
        final String opponentId = isPlayer1 ? player2Id : player1Id;

        await DsaService.markSolved(
          roomId: widget.roomId,
          playerId: _myId!,
          isPlayer1: isPlayer1,
        );

        // Winner coins
        await supabase.rpc('update_user_coins', params: {
          'p_user_id': _myId,
          'p_amount': 50,
          'p_game_type': 'dsa_win',
          'p_description': 'Won DSA Combat',
        });

        // Loser coins
        if (opponentId.isNotEmpty) {
          await supabase.rpc('update_user_coins', params: {
            'p_user_id': opponentId,
            'p_amount': -20,
            'p_game_type': 'dsa_loss',
            'p_description': 'Lost DSA Combat',
          });
        }

        // Record to match_history
        await supabase.rpc('record_game_result', params: {
          'p_winner_id': _myId,
          'p_loser_id': opponentId.isNotEmpty ? opponentId : _myId,
          'p_room_id': widget.roomId,
          'p_was_quit': false,
          'p_game_type': 'dsa_win',
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ All test cases passed! You win!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        final passed = results['passed'];
        final total = results['total'];
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ $passed/$total test cases passed. Keep trying!'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showResultDialog(bool iWon) {
    _timer?.cancel();
    if (!mounted) return;

    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    final timeStr = '${minutes}m ${seconds}s';

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: iWon
                  ? [const Color(0xFF0A2A1A), const Color(0xFF0D1F35)]
                  : [const Color(0xFF2A0A0A), const Color(0xFF1A0D2E)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: iWon ? const Color(0xFF00E676) : const Color(0xFFFF375F),
              width: 1.5,
            ),
            boxShadow: [BoxShadow(
              color: (iWon ? const Color(0xFF00E676) : const Color(0xFFFF375F))
                  .withOpacity(0.25),
              blurRadius: 40, spreadRadius: 4,
            )],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(iWon ? '🏆' : '💀',
                style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 12),
            Text(
              iWon ? 'VICTORY!' : 'DEFEATED',
              style: TextStyle(
                color: iWon ? const Color(0xFF00E676) : const Color(0xFFFF375F),
                fontSize: 32, fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              iWon ? 'Fastest solution wins the battle' : 'Opponent solved it faster',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Coins row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: iWon
                      ? const Color(0xFF00E676).withOpacity(0.3)
                      : const Color(0xFFFF375F).withOpacity(0.3),
                ),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  iWon ? '+50' : '-20',
                  style: TextStyle(
                    fontSize: 40, fontWeight: FontWeight.w900,
                    color: iWon ? const Color(0xFFFFD700) : const Color(0xFFFF375F),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('🪙', style: TextStyle(fontSize: 36)),
              ]),
            ),
            const SizedBox(height: 16),
            // Time badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.timer_outlined, color: Colors.white38, size: 14),
                const SizedBox(width: 6),
                Text('Time: $timeStr',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context)..pop()..pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: iWon
                      ? const Color(0xFF00E676)
                      : const Color(0xFF6C63FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: Text(
                  iWon ? '🎉  Back to Lobby' : '🔄  Try Again',
                  style: TextStyle(
                    color: iWon ? Colors.black : Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _formatTime() {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F1117),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
        ),
      );
    }

    final diffColor = _problem?.difficultyColor ?? const Color(0xFF6C63FF);
    final isUrgent = _elapsedSeconds > 300;

    return WillPopScope(
      onWillPop: () async {
        await _quitGame();
        return false;
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF080B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1020),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D1020), Color(0xFF131830)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            border: Border(
              bottom: BorderSide(color: Color(0xFF6C63FF), width: 0.5),
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 22),
          onPressed: _quitGame,
          tooltip: 'Quit Game',
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: diffColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: diffColor.withOpacity(0.5)),
            ),
            child: Text(
              (_problem?.difficulty ?? '').toUpperCase(),
              style: TextStyle(
                color: diffColor, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _problem?.title ?? 'DSA Combat',
              style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        actions: [
          // Opponent solved warning
          if (_opponentSolved)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('⚡', style: TextStyle(fontSize: 11)),
                SizedBox(width: 3),
                Text('Hurry!', style: TextStyle(
                    color: Colors.orange, fontSize: 11,
                    fontWeight: FontWeight.w700)),
              ]),
            ),
          // Timer
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: isUrgent
                  ? Colors.red.withOpacity(0.2)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isUrgent
                    ? Colors.red.withOpacity(0.6)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.timer_outlined,
                  color: isUrgent ? Colors.red : Colors.white38, size: 12),
              const SizedBox(width: 4),
              Text(
                _formatTime(),
                style: TextStyle(
                  color: isUrgent ? Colors.red : Colors.white,
                  fontWeight: FontWeight.w800, fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ]),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6C63FF),
          indicatorWeight: 2,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: '📝 Problem'),
            Tab(text: '💻 Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProblemTab(),
          _buildCodeTab(),
        ],
      ),
    ),);
  }

  Widget _buildProblemTab() {
    if (_problem == null) return const SizedBox();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          Text(
            _problem!.description,
            style: const TextStyle(
                color: Color(0xFFCDD5E0), fontSize: 14, height: 1.75),
          ),
          const SizedBox(height: 24),

          // Examples header
          Row(children: [
            Container(width: 3, height: 16,
                decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('Examples',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),

          ..._problem!.examples.asMap().entries.map((entry) {
            final i = entry.key;
            final ex = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                    border: const Border(
                        bottom: BorderSide(color: Color(0xFF6C63FF), width: 0.3)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: Color(0xFF6C63FF),
                                fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Example',
                        style: TextStyle(color: Color(0xFF6C63FF),
                            fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _buildIORow('Input', ex['input'].toString(), const Color(0xFF818CF8)),
                    const SizedBox(height: 8),
                    _buildIORow('Output', ex['output'].toString(), const Color(0xFF00E676)),
                    if (ex['explanation'] != null) ...[
                      const SizedBox(height: 10),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 8),
                      RichText(text: TextSpan(children: [
                        const TextSpan(text: 'Explanation  ',
                            style: TextStyle(color: Colors.white38,
                                fontSize: 11, fontWeight: FontWeight.w600)),
                        TextSpan(text: ex['explanation'].toString(),
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12, height: 1.5)),
                      ])),
                    ],
                  ]),
                ),
              ]),
            );
          }),

          const SizedBox(height: 8),
          // Constraints
          Row(children: [
            Container(width: 3, height: 16,
                decoration: BoxDecoration(
                    color: const Color(0xFFFFB800),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('Constraints',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.2)),
            ),
            child: Text(
              _problem!.constraints,
              style: const TextStyle(
                  color: Color(0xFFFFB800),
                  fontFamily: 'monospace', fontSize: 12, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIORow(String label, String value, Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(color: color,
                fontSize: 10, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(value,
            style: TextStyle(
                color: color.withOpacity(0.9),
                fontFamily: 'monospace', fontSize: 12, height: 1.4)),
      ),
    ]);
  }

  Widget _buildCodeTab() {
    return Column(
      children: [
        // Language selector bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1020),
            border: Border(bottom: BorderSide(color: Color(0xFF1E2440))),
          ),
          child: Row(children: [
            const Icon(Icons.code_rounded, color: Colors.white24, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: DsaService.languageIds.keys.map((lang) {
                    final isSelected = lang == _selectedLanguage;
                    return GestureDetector(
                      onTap: () {
                        if (!isSelected && _problem != null) {
                          setState(() {
                            _selectedLanguage = lang;
                            _codeController.text =
                                DsaService.getStarterCode(lang, _problem!);
                          });
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6C63FF)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6C63FF)
                                : Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Text(lang,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white38,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            )),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
        ),

        // Code editor
        // Code editor
Expanded(
  child: Container(
    color: const Color(0xFF1E1E1E),  // keep dark always — it's a code editor
    child: TextField(
      controller: _codeController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(
        color: Color(0xFFD4D4D4),
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
      ),
              keyboardType: TextInputType.multiline,
            ),
          ),
        ),

        // Test results
        if (_showResults && _testResults.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: const BoxDecoration(
              color: Color(0xFF080B14),
              border: Border(
                top: BorderSide(color: Color(0xFF1E2440)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(children: [
                    const Icon(Icons.science_outlined,
                        color: Colors.white38, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Test Results',
                      style: const TextStyle(color: Colors.white70,
                          fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _testResults.every((r) => r['passed'] == true)
                            ? const Color(0xFF00E676).withOpacity(0.15)
                            : Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_testResults.where((r) => r['passed'] == true).length}/${_testResults.length} passed',
                        style: TextStyle(
                          color: _testResults.every((r) => r['passed'] == true)
                              ? const Color(0xFF00E676)
                              : Colors.red,
                          fontSize: 11, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    itemCount: _testResults.length,
                    itemBuilder: (context, i) {
                      final r = _testResults[i];
                      final passed = r['passed'] == true;
                      final hasError =
                          (r['error'] as String?)?.isNotEmpty == true;
                      final isExecError = r['actual'] == '' && hasError;
                      final color = passed
                          ? const Color(0xFF00E676)
                          : Colors.red;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: color.withOpacity(0.3), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(
                                passed
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                color: color, size: 15,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  passed
                                      ? 'Case ${i + 1}  ·  Passed'
                                      : isExecError
                                          ? 'Case ${i + 1}  ·  Runtime error'
                                          : 'Case ${i + 1}  ·  Wrong answer',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ]),
                            if (!passed) ...[
                              const SizedBox(height: 6),
                              if (!isExecError) ...[
                                _buildTestDetail('Expected',
                                    r['expected'].toString(),
                                    const Color(0xFF00E676)),
                                const SizedBox(height: 3),
                                _buildTestDetail('Got',
                                    r['actual'].toString(), Colors.red),
                              ],
                              if (hasError) ...[
                                const SizedBox(height: 3),
                                Text(
                                  r['error'].toString().length > 100
                                      ? '${r['error'].toString().substring(0, 100)}…'
                                      : r['error'].toString(),
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

        // Submit button
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1020),
            border: Border(top: BorderSide(color: Color(0xFF1E2440))),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_isSubmitting || _isSolved) ? null : _submitSolution,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.white.withOpacity(0.04),
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding: EdgeInsets.zero,
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: _isSolved
                      ? const LinearGradient(
                          colors: [Color(0xFF00C853), Color(0xFF00E676)])
                      : _isSubmitting
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight),
                  color: _isSubmitting
                      ? Colors.white.withOpacity(0.04)
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: (_isSolved || _isSubmitting)
                      ? null
                      : [BoxShadow(
                          color: const Color(0xFF6C63FF).withOpacity(0.4),
                          blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: Container(
                  alignment: Alignment.center,
                  child: _isSubmitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white54, strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text('Running tests…',
                                style: TextStyle(color: Colors.white54,
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                          ])
                      : Text(
                          _isSolved ? '✅  Solved!' : '🚀  Submit Solution',
                          style: TextStyle(
                            color: _isSolved ? Colors.black : Colors.white,
                            fontSize: 16, fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTestDetail(String label, String value, Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label  ',
          style: TextStyle(color: color.withOpacity(0.6),
              fontSize: 10, fontWeight: FontWeight.w600)),
      Expanded(
        child: Text(value,
            style: TextStyle(
                color: color.withOpacity(0.85),
                fontSize: 10, fontFamily: 'monospace'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _roomSub?.cancel();
    _codeController.dispose();
    _tabController.dispose();
    super.dispose();
  }
}