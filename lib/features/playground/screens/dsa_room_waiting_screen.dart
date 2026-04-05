import '../../settings/theme_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/dsa_service.dart';
import 'dsa_battle_screen.dart';

class DsaRoomWaitingScreen extends StatefulWidget {
  final String roomId;
  final String roomCode;
  final bool isHost;
  final String difficulty;

  const DsaRoomWaitingScreen({
    Key? key,
    required this.roomId,
    required this.roomCode,
    required this.isHost,
    required this.difficulty,
  }) : super(key: key);

  @override
  State<DsaRoomWaitingScreen> createState() => _DsaRoomWaitingScreenState();
}

class _DsaRoomWaitingScreenState extends State<DsaRoomWaitingScreen> {
  final supabase = Supabase.instance.client;
  String? _myId;
  List<String> _playerIds = [];
  String? _hostId;
  Map<String, String> _names = {};
  bool _isStarting = false;
  bool _navigated = false;

  StreamSubscription? _roomSub;
  Timer? _pollTimer;

  static const _kPurple = Color(0xFF6C63FF);
  static const _kTeal   = Color(0xFF00B8A3);
  static const int _kMaxPlayers = 3;

  @override
  void initState() {
    super.initState();
    // currentUser may be null briefly on web before auth rehydrates — wait for it
    _myId = supabase.auth.currentUser?.id;
    if (_myId == null) {
      supabase.auth.onAuthStateChange.first.then((event) {
        if (mounted) setState(() => _myId = event.session?.user.id);
      });
    }
    _subscribeRoom();
    _startPoll();
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _subscribeRoom() {
    _roomSub = supabase
        .from('dsa_battle_rooms')
        .stream(primaryKey: ['id'])
        .eq('id', widget.roomId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      _handleRoomData(Map<String, dynamic>.from(rows[0]));
    });
  }

  void _startPoll() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        final row = await supabase
            .from('dsa_battle_rooms')
            .select()
            .eq('id', widget.roomId)
            .single();
        if (mounted) _handleRoomData(Map<String, dynamic>.from(row));
      } catch (_) {}
    });
  }

  void _handleRoomData(Map<String, dynamic> room) {
    if (!mounted) return;
    final ids = List<String>.from(room['player_ids'] ?? []);
    setState(() {
      _playerIds = ids;
      _hostId = room['host_id']?.toString();
    });
    _fetchNames(ids);

    if (room['status'] == 'active' && room['problem_id'] != null) {
      _navigateToGame(room['problem_id'].toString(), ids);
    }
  }

  void _navigateToGame(String problemId, List<String> playerIds) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _roomSub?.cancel();
    _pollTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DsaBattleScreen(
            roomId: widget.roomId,
            problemId: problemId,
            playerIds: playerIds,
          ),
        ),
      );
    });
  }

  Future<void> _fetchNames(List<String> ids) async {
    final missing = ids.where((id) => !_names.containsKey(id)).toList();
    if (missing.isEmpty) return;
    final fetched = await DsaService.fetchPlayerProfiles(missing);
    if (mounted) setState(() => _names.addAll(fetched));
  }

  Future<bool> _useCard() async {
    if (_myId == null) return false;
    try {
      final result = await supabase.rpc('use_dsa_card', params: {'p_user_id': _myId});
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
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startGame() async {
    if (_isStarting || _playerIds.length < 2) return;
    setState(() => _isStarting = true);
    HapticFeedback.mediumImpact();
    // Deduct card only when game actually starts
    final ok = await _useCard();
    if (!ok) {
      if (mounted) setState(() => _isStarting = false);
      return;
    }
    try {
      await DsaService.startBattleRoom(
        roomId: widget.roomId,
        hostId: _myId!,
        difficulty: widget.difficulty,
      );
      // Realtime stream detects status == 'active' and navigates
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _leaveRoom() async {
    _roomSub?.cancel();
    _pollTimer?.cancel();
    if (_myId != null) {
      await DsaService.leaveBattleRoom(roomId: widget.roomId, playerId: _myId!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
    });
  }

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Leave Room?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('You will be removed from the room.',
            style: TextStyle(color: AppColors.textHint(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Stay', style: TextStyle(color: AppColors.textHint(context))),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _leaveRoom(); },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Leave', style: TextStyle(color: AppColors.text(context))),
          ),
        ],
      ),
    );
  }

  void _copyCode() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: widget.roomCode));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Room code copied!'),
      backgroundColor: Color(0xFF1C1F2E),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isAmHost = widget.isHost || _hostId == _myId;
    final canStart = isAmHost && _playerIds.length >= 2 && !_isStarting;
    final diffLabel = widget.difficulty[0].toUpperCase() + widget.difficulty.substring(1);

    return WillPopScope(
      onWillPop: () async { _confirmLeave(); return false; },
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        appBar: AppBar(
          backgroundColor: AppColors.background(context),
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: _confirmLeave,
          ),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Battle Room',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
            Text('$diffLabel • Private • max $_kMaxPlayers',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
          actions: [
            GestureDetector(
              onTap: _copyCode,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _kPurple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kPurple.withOpacity(0.35)),
                ),
                child: Row(children: [
                  Icon(Icons.copy_rounded, color: Color(0xFF818CF8), size: 14),
                  SizedBox(width: 5),
                  Text('Copy', style: TextStyle(
                      color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(children: [
            // ── Room code card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kPurple.withOpacity(0.18), const Color(0xFF1A3A6E).withOpacity(0.3)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kPurple.withOpacity(0.35), width: 1.5),
              ),
              child: Column(children: [
                Text('ROOM CODE',
                    style: TextStyle(color: Colors.white30, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                const SizedBox(height: 8),
                Text(widget.roomCode,
                    style: TextStyle(
                        color: Colors.white, fontSize: 34,
                        fontWeight: FontWeight.w900, letterSpacing: 10)),
                const SizedBox(height: 4),
                Text('Share this code with friends to join',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),

            const SizedBox(height: 20),

            // ── Players header ──
            Row(children: [
              Text('PLAYERS',
                  style: TextStyle(color: Colors.white24, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 2.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _playerIds.length >= 2
                      ? _kTeal.withOpacity(0.12)
                      : _kPurple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_playerIds.length} / $_kMaxPlayers',
                    style: TextStyle(
                      color: _playerIds.length >= 2 ? _kTeal : _kPurple,
                      fontSize: 12, fontWeight: FontWeight.w700,
                    )),
              ),
            ]),

            const SizedBox(height: 10),

            // ── Player slots ──
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _kMaxPlayers,
                itemBuilder: (_, i) {
                  final filled = i < _playerIds.length;
                  final pid    = filled ? _playerIds[i] : null;
                  final isMe   = pid == _myId;
                  final isHost = pid == _hostId;
                  final name   = pid != null ? (_names[pid] ?? 'Player ${i + 1}') : null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: filled
                            ? (isMe ? _kPurple.withOpacity(0.08) : AppColors.surface(context))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: filled
                              ? (isMe
                                  ? _kPurple.withOpacity(0.4)
                                  : Colors.white.withOpacity(0.08))
                              : Colors.white.withOpacity(0.04),
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: filled
                                ? _kPurple.withOpacity(0.15)
                                : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(child: Text(
                            filled
                                ? (isHost ? '👑'
                                    : (name?.isNotEmpty == true
                                        ? name![0].toUpperCase() : '?'))
                                : '➕',
                            style: TextStyle(
                              color: filled ? Colors.white : Colors.white12,
                              fontSize: isHost ? 20 : 16,
                              fontWeight: FontWeight.bold,
                            ),
                          )),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              filled
                                  ? '${name ?? 'Player ${i + 1}'}${isMe ? ' (You)' : ''}'
                                  : 'Slot ${i + 1} — open',
                              style: TextStyle(
                                color: filled ? Colors.white : Colors.white24,
                                fontWeight: FontWeight.w600, fontSize: 13,
                              ),
                            ),
                            if (filled && isHost)
                              Text('Host',
                                  style: TextStyle(color: Colors.amber, fontSize: 10)),
                          ],
                        )),
                        if (filled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _kTeal.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Ready',
                                style: TextStyle(color: Color(0xFF00B8A3),
                                    fontSize: 10, fontWeight: FontWeight.w700)),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Empty',
                                style: TextStyle(color: Colors.white24, fontSize: 10)),
                          ),
                      ]),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // ── Bottom action ──
            if (!isAmHost)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kPurple.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kPurple.withOpacity(0.25)),
                ),
                child: Row(children: [
                  SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: _kPurple, strokeWidth: 2.5)),
                  SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Waiting for host to start…',
                          style: TextStyle(color: _kPurple, fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text('Host decides when the battle begins',
                          style: TextStyle(color: Colors.white30, fontSize: 11)),
                    ],
                  )),
                ]),
              )
            else
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  onPressed: canStart ? _startGame : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canStart ? _kTeal : Colors.white.withOpacity(0.06),
                    disabledBackgroundColor: Colors.white.withOpacity(0.06),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isStarting
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text(
                          _playerIds.length < 2
                              ? 'Waiting for players…'
                              : 'Start Battle  (${_playerIds.length} players)',
                          style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: canStart ? Colors.white : Colors.white24,
                          ),
                        ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
