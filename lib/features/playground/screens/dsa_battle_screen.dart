import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dsa_problem.dart';
import '../services/dsa_service.dart';
import 'dsa_lobby_screen.dart';

class DsaBattleScreen extends StatefulWidget {
  final String roomId;
  final String problemId;
  final List<String> playerIds;

  const DsaBattleScreen({
    Key? key,
    required this.roomId,
    required this.problemId,
    required this.playerIds,
  }) : super(key: key);

  @override
  State<DsaBattleScreen> createState() => _DsaBattleScreenState();
}

class _DsaBattleScreenState extends State<DsaBattleScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  DsaProblem? _problem;
  String? _myId;
  String _selectedLanguage = 'Python';
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSolved = false;
  bool _gameOver = false;
  bool _coinsProcessed = false;

  Timer? _timer;
  int _elapsedSeconds = 0;

  List<Map<String, dynamic>> _testResults = [];
  bool _showResults = false;

  late TabController _tabController;
  StreamSubscription? _roomSub;

  Map<String, String> _playerNames = {};
  String? _winnerId;
  List<String> _playerIds = [];

  static const _kPurple = Color(0xFF6C63FF);
  static const _kTeal   = Color(0xFF00B8A3);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _myId      = supabase.auth.currentUser?.id;
    _playerIds = List<String>.from(widget.playerIds);
    _loadGame();
    _listenToRoom();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _roomSub?.cancel();
    _codeController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGame() async {
    try {
      final problems = await DsaService.fetchProblems();
      final problem  = problems.firstWhere((p) => p.id == widget.problemId);
      final names    = await DsaService.fetchPlayerProfiles(_playerIds);
      if (!mounted) return;
      setState(() {
        _problem      = problem;
        _playerNames  = names;
        _codeController.text = DsaService.getStarterCode(_selectedLanguage, problem);
        _isLoading    = false;
      });
      _startTimer();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _listenToRoom() {
    _roomSub = supabase
        .from('dsa_battle_rooms')
        .stream(primaryKey: ['id'])
        .eq('id', widget.roomId)
        .listen((data) {
      if (!mounted || data.isEmpty) return;
      final room     = Map<String, dynamic>.from(data[0]);
      final winnerId = room['winner_id']?.toString();
      final ids      = List<String>.from(room['player_ids'] ?? []);
      final prevCount = _playerIds.length;

      // Always sync player list
      if (mounted) setState(() => _playerIds = ids);

      // Opponent quit — someone left but no winner set yet
      if (!_gameOver && ids.length < prevCount && winnerId == null && prevCount > 1) {
        setState(() => _gameOver = true);
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _showOpponentQuitDialog();
        });
        return;
      }

      if (winnerId != null && !_gameOver) {
        setState(() {
          _winnerId = winnerId;
          _gameOver = true;
        });
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _showResultDialog(winnerId == _myId);
        });
      }
    });
  }

  void _showOpponentQuitDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1D2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Opponent Left', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          content: const Text('Your opponent quit the battle.\nNo coins were awarded or deducted.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.5)),
          actions: [
            Center(child: ElevatedButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const DsaLobbyScreen()),
                (_) => false,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Back to Lobby',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _submitSolution() async {
    if (_isSubmitting || _isSolved || _problem == null) return;
    setState(() { _isSubmitting = true; _showResults = false; _testResults = []; });

    try {
      final results = await DsaService.runTestCases(
        code: _codeController.text,
        language: _selectedLanguage,
        testCases: _problem!.testCases,
      );

      if (!mounted) return;
      setState(() {
        _testResults = List<Map<String, dynamic>>.from(results['results']);
        _showResults = true;
        _tabController.animateTo(1);
      });

      if (results['allPass'] == true) {
        setState(() => _isSolved = true);
        _timer?.cancel();

        if (_myId != null) {
          await DsaService.markProblemSolved(
            userId: _myId!,
            problemId: _problem!.id,
            language: _selectedLanguage,
          );
        }

        final isWinner = await DsaService.markBattleSolved(
          roomId: widget.roomId,
          playerId: _myId!,
        );

        if (isWinner && !_coinsProcessed) {
          _coinsProcessed = true;
          // Award winner
          await supabase.rpc('update_user_coins', params: {
            'p_user_id': _myId,
            'p_amount': 50,
            'p_game_type': 'dsa_battle_win',
            'p_description': 'Won DSA Battle Room',
          });
          // Deduct from others
          for (final pid in _playerIds) {
            if (pid != _myId) {
              await supabase.rpc('update_user_coins', params: {
                'p_user_id': pid,
                'p_amount': -20,
                'p_game_type': 'dsa_battle_loss',
                'p_description': 'Lost DSA Battle Room',
              });
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Correct! But someone already solved it first.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ));
          }
        }
      } else {
        final passed = results['passed'];
        final total  = results['total'];
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$passed/$total test cases passed. Keep trying!'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _quitBattle() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Quit Battle?', style: TextStyle(color: Colors.white)),
        content: const Text('⚠️ Quitting costs you 30 coins. The battle continues for remaining players.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Quit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Fetch fresh player list from DB
      final roomSnap = await supabase
          .from('dsa_battle_rooms')
          .select('player_ids')
          .eq('id', widget.roomId)
          .single();
      final freshIds = List<String>.from(roomSnap['player_ids'] ?? []);
      final remaining = List<String>.from(freshIds)..remove(_myId);

      if (remaining.isEmpty) {
        await supabase.from('dsa_battle_rooms').delete().eq('id', widget.roomId);
      } else {
        // Just remove the quitter — no winner declared, no coins awarded
        await supabase.from('dsa_battle_rooms').update({
          'player_ids': remaining,
        }).eq('id', widget.roomId);
      }
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DsaLobbyScreen()),
        (_) => false,
      );
    }
  }

  void _showResultDialog(bool iWon) {
    if (!mounted) return;
    _timer?.cancel();
    final m          = _elapsedSeconds ~/ 60;
    final s          = _elapsedSeconds % 60;
    final timeStr    = '${m}m ${s}s';
    final winnerName = _winnerId != null
        ? (_playerNames[_winnerId!] ?? 'Unknown')
        : '?';

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          iWon ? 'You Won!' : 'You Lost!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: iWon ? Colors.green : Colors.red,
            fontSize: 24, fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            iWon ? 'Fastest in the room!' : '$winnerName solved it first!',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (iWon ? Colors.green : Colors.red).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iWon ? Colors.green : Colors.red, width: 2),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(iWon ? '+50' : '-20',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                      color: iWon ? Colors.green : Colors.red)),
              const SizedBox(width: 8),
              const Text('🪙', style: TextStyle(fontSize: 32)),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Your time: $timeStr',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ]),
        actions: [
          Center(child: ElevatedButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const DsaLobbyScreen()),
              (_) => false,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: iWon ? Colors.green : _kPurple,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Back to Lobby',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          )),
        ],
      )),
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
        body: Center(child: CircularProgressIndicator(color: _kPurple)),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (_gameOver) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DsaLobbyScreen()),
            (_) => false,
          );
          return false;
        }
        await _quitBattle();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1D2E),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _problem?.difficultyColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _problem?.difficultyColor ?? Colors.grey),
              ),
              child: Text((_problem?.difficulty ?? '').toUpperCase(),
                  style: TextStyle(color: _problem?.difficultyColor,
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(_problem?.title ?? 'Battle',
                style: const TextStyle(color: Colors.white, fontSize: 15),
                overflow: TextOverflow.ellipsis)),
          ]),
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _elapsedSeconds > 300
                    ? Colors.red.withValues(alpha: 0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: Text('${_formatTime()}',
                  style: TextStyle(
                    color: _elapsedSeconds > 300 ? Colors.red : Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 13,
                  ))),
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              tooltip: 'Quit Battle',
              onPressed: _quitBattle,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(88),
            child: Column(children: [
              // ── Player status bar ──
              Container(
                height: 40,
                color: const Color(0xFF0E1320),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: _playerIds.map((pid) {
                    final isMe     = pid == _myId;
                    final isWinner = pid == _winnerId;
                    final name     = _playerNames[pid] ?? 'P';
                    final initial  = name[0].toUpperCase();
                    return Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Row(children: [
                        Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color: isWinner
                                ? Colors.green.withValues(alpha: 0.2)
                                : (isMe
                                    ? _kPurple.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.08)),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: isWinner
                                  ? Colors.green
                                  : (isMe ? _kPurple : Colors.white24),
                            ),
                          ),
                          child: Center(child: Text(
                            isWinner ? '🏆' : initial,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold,
                                color: Colors.white),
                          )),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isWinner ? 'Won!' : (isMe ? 'You' : name.split(' ').first),
                          style: TextStyle(
                            color: isWinner
                                ? Colors.green
                                : (isMe ? Colors.white : Colors.white54),
                            fontSize: 11, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
              ),
              // ── Tab bar ──
              TabBar(
                controller: _tabController,
                indicatorColor: _kPurple,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                tabs: const [Tab(text: 'Problem'), Tab(text: 'Code')],
              ),
            ]),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [_buildProblemTab(), _buildCodeTab()],
        ),
      ),
    );
  }

  Widget _buildProblemTab() {
    if (_problem == null) return const SizedBox();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_problem!.description,
            style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6)),
        const SizedBox(height: 20),
        const Text('Examples:',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ..._problem!.examples.map((ex) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Input: ${ex['input']}',
                style: const TextStyle(color: Color(0xFF6C63FF), fontFamily: 'monospace')),
            const SizedBox(height: 4),
            Text('Output: ${ex['output']}',
                style: const TextStyle(color: Color(0xFF00B8A3), fontFamily: 'monospace')),
            if (ex['explanation'] != null) ...[
              const SizedBox(height: 4),
              Text('Explanation: ${ex['explanation']}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ]),
        )),
        const SizedBox(height: 16),
        const Text('Constraints:',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_problem!.constraints,
            style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13)),
      ]),
    );
  }

  Widget _buildCodeTab() {
    return Column(children: [
      // Language selector
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFF1A1D2E),
        child: Row(children: [
          const Text('Language: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _selectedLanguage,
            dropdownColor: const Color(0xFF1A1D2E),
            style: const TextStyle(color: Colors.white),
            underline: const SizedBox(),
            items: DsaService.languageIds.keys
                .map((lang) => DropdownMenuItem(value: lang, child: Text(lang)))
                .toList(),
            onChanged: (val) {
              if (val != null && _problem != null) {
                setState(() {
                  _selectedLanguage = val;
                  _codeController.text = DsaService.getStarterCode(val, _problem!);
                });
              }
            },
          ),
        ]),
      ),

      // Code editor
      Expanded(
        child: Container(
          color: const Color(0xFF1E1E1E),
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

      // Test results panel
      if (_showResults && _testResults.isNotEmpty)
        Container(
          height: 160,
          color: const Color(0xFF1A1D2E),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(
                'Test Results: ${_testResults.where((r) => r['passed'] == true).length}/${_testResults.length} passed',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _testResults.length,
                itemBuilder: (_, i) {
                  final r          = _testResults[i];
                  final passed     = r['passed'] == true;
                  final hasError   = (r['error'] as String?)?.isNotEmpty == true;
                  final isExecErr  = r['actual'] == '' && hasError;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (passed ? Colors.green : Colors.red).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: passed ? Colors.green : Colors.red),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(passed ? '✅' : '❌', style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          passed
                              ? 'Test ${i + 1}: Passed'
                              : isExecErr
                                  ? 'Test ${i + 1}: Execution failed'
                                  : 'Test ${i + 1}: Expected "${r['expected']}" got "${r['actual']}"',
                          style: TextStyle(
                            color: passed ? Colors.green : Colors.red,
                            fontSize: 12, fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        )),
                      ]),
                      if (!passed && hasError) ...[
                        const SizedBox(height: 4),
                        Text(
                          r['error'].toString().length > 120
                              ? '${r['error'].toString().substring(0, 120)}...'
                              : r['error'].toString(),
                          style: TextStyle(color: Colors.red[300],
                              fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ]),
                  );
                },
              ),
            ),
          ]),
        ),

      // Submit button
      Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF1A1D2E),
        child: SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: (_isSubmitting || _isSolved || _gameOver) ? null : _submitSolution,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isSolved ? Colors.green : _kPurple,
              disabledBackgroundColor: Colors.white10,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isSubmitting
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Running test cases…', style: TextStyle(color: Colors.white)),
                  ])
                : Text(
                    _gameOver && !_isSolved
                        ? 'Battle Over'
                        : _isSolved
                            ? 'Solved!'
                            : 'Submit Solution',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    ]);
  }
}
