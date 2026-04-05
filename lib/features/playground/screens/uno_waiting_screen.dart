import '../../settings/theme_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/uno_services.dart';
import '../models/uno_card.dart';
import 'uno_game_screen.dart';
import '../../home/home_screen.dart';

final _sb = Supabase.instance.client;

class UnoWaitingScreen extends StatefulWidget {
  final String roomId;
  final String roomCode;
  final bool isHost;
  final bool isQuickMatch;

  const UnoWaitingScreen({
    Key? key,
    required this.roomId,
    required this.roomCode,
    required this.isHost,
    required this.isQuickMatch,
  }) : super(key: key);

  @override
  State<UnoWaitingScreen> createState() => _UnoWaitingScreenState();
}

class _UnoWaitingScreenState extends State<UnoWaitingScreen>
    with TickerProviderStateMixin {

  // ── Room state ──
  List<String> _playerIds = [];
  String? _hostId;
  Map<String, String> _names = {};
  bool _amHost = false;
  bool _isLaunching = false;
  bool _launchAttempted = false; // never resets — prevents countdown loop

  // ── Navigation guard: prevents stream + poll both navigating simultaneously ──
  bool _navigated = false;

  // ── Quick-match countdown ──
  Timer? _countdownTimer;
  int _countdown = 60;
  bool _countdownRunning = false;

  // ── Join time tracking (playerId → when they joined) ──
  final Map<String, DateTime> _joinTimes = {};
  Timer? _joinTimerTicker; // fires every second to refresh elapsed display

  // ── Subscriptions ──
  StreamSubscription? _roomSub;
  StreamSubscription? _handsSub;
  Timer? _pollTimer;

  // ── Animations ──
  late final AnimationController _pulseCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
  late final Animation<double> _pulse =
      Tween<double>(begin: 0.96, end: 1.04).animate(
          CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  late final AnimationController _shimmerCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void initState() {
    super.initState();
    _amHost = widget.isHost;
    _subscribeRoom();
    _subscribeHands();
    _startPoll();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _countdownTimer?.cancel();
    _joinTimerTicker?.cancel();
    _roomSub?.cancel();
    _handsSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  DATA
  // ─────────────────────────────────────────────

  void _subscribeRoom() {
    _roomSub = _sb
        .from('multi_game_rooms')
        .stream(primaryKey: ['id'])
        .eq('id', widget.roomId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      _handleRoomData(rows[0]);
    });
  }

  void _subscribeHands() {
    _handsSub = _sb
        .from('multi_player_hands')
        .stream(primaryKey: ['room_id', 'player_id'])
        .eq('room_id', widget.roomId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      // Sort by seat_index so order is deterministic
      rows.sort((a, b) =>
          (a['seat_index'] as int? ?? 0).compareTo(b['seat_index'] as int? ?? 0));
      _handleHandsData(rows);
    });
  }

  void _handleHandsData(List<Map<String, dynamic>> rows) {
    if (!mounted) return;
    final ids = rows.map<String>((r) => r['player_id'].toString()).toList();
    final now = DateTime.now();
    for (final id in ids) {
      _joinTimes.putIfAbsent(id, () => now);
    }
    setState(() => _playerIds = ids);
    _fetchNames(ids);

    // Drive quick-match countdown from hands count
    if (widget.isQuickMatch && !_launchAttempted) {
      if (ids.length >= 2 && !_countdownRunning) {
        _startCountdown(launchOnEnd: _amHost);
      } else if (ids.length < 2 && _countdownRunning) {
        _resetCountdown();
      }
    }
  }

  void _startPoll() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      // Poll room for status changes (playing → navigate to game)
      try {
        final row = await _sb
            .from('multi_game_rooms')
            .select()
            .eq('id', widget.roomId)
            .single();
        if (mounted) _handleRoomData(row);
      } catch (_) {}
      // Poll hands as fallback in case realtime subscription misses updates
      try {
        final hands = await _sb
            .from('multi_player_hands')
            .select('player_id, seat_index')
            .eq('room_id', widget.roomId)
            .order('seat_index');
        if (mounted && hands.isNotEmpty) _handleHandsData(hands);
      } catch (_) {}
    });
  }

  // Handles room-level changes: host, status, navigation.
  // Player list is driven by _handleHandsData (from multi_player_hands).
  void _handleRoomData(Map<String, dynamic> room) {
    if (!mounted) return;

    final hId = room['host_id']?.toString();
    final uid = _sb.auth.currentUser?.id;
    final nowHost = hId != null ? (hId == uid) : widget.isHost;

    setState(() {
      _hostId = hId;
      _amHost = nowHost;
    });

    if (room['status'] == 'playing') {
      _navigateToGame();
    }
  }

  // ─────────────────────────────────────────────
  //  NAVIGATION  — guarded so it fires exactly once
  // ─────────────────────────────────────────────

  void _navigateToGame() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _stopCountdown();
    _pollTimer?.cancel();
    _roomSub?.cancel();
    // addPostFrameCallback avoids calling Navigator mid-build / mid-setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => UnoGameScreen(roomId: widget.roomId)),
      );
    });
  }

  // ─────────────────────────────────────────────
  //  COUNTDOWN
  // ─────────────────────────────────────────────

  void _startCountdown({bool launchOnEnd = false}) {
    if (_countdownRunning) return;
    setState(() { _countdownRunning = true; _countdown = 60; });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        if (mounted && launchOnEnd) _launchGame();
      }
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownRunning = false;
  }

  void _resetCountdown() {
    _stopCountdown();
    if (mounted) setState(() { _countdown = 60; _countdownRunning = false; });
  }

  // ─────────────────────────────────────────────
  //  NAMES
  // ─────────────────────────────────────────────

  Future<void> _fetchNames(List<String> ids) async {
    final missing = ids.where((id) => !_names.containsKey(id)).toList();
    if (missing.isEmpty) return;
    try {
      final rows = await _sb
          .from('profiles')
          .select('id, username')
          .inFilter('id', missing);
      if (!mounted) return;
      final map = <String, String>{};
      for (final r in rows) {
        final un = r['username']?.toString().trim() ?? '';
        map[r['id'].toString()] = un.isNotEmpty ? un : 'Player';
      }
      setState(() => _names.addAll(map));
    } catch (_) {}
  }

  // ─────────────────────────────────────────────
  //  LAUNCH GAME
  // ─────────────────────────────────────────────

  Future<void> _launchGame() async {
    if (_isLaunching || !mounted) return;
    if (!_amHost) { _snack('DEBUG: not host, ignoring'); return; }

    _launchAttempted = true;
    _isLaunching = true;
    HapticFeedback.heavyImpact();
    _stopCountdown();

    // Ensure host always goes first
    final ids = List<String>.from(_playerIds);
    if (_hostId != null && ids.contains(_hostId!) && ids[0] != _hostId) {
      ids.remove(_hostId!);
      ids.insert(0, _hostId!);
    }
    if (ids.length < 2) {
      _isLaunching = false;
      _snack('Need at least 2 players to start.');
      return;
    }

    try {
      final deck = UnoService.shuffle(UnoService.buildDeck());
      final allJson = UnoService.deckToJson(deck);

      final hands = <String, List<Map<String, dynamic>>>{};
      for (final id in ids) hands[id] = [];
      int idx = 0;
      for (int round = 0; round < 7; round++) {
        for (final id in ids) hands[id]!.add(allJson[idx++]);
      }

      final remaining = List<Map<String, dynamic>>.from(allJson.sublist(idx));

      // First card must be a plain number — CardValue is stored as enum name string
      const actionValues = {'skip','reverse','drawTwo','wild','wildDrawFour'};
      Map<String, dynamic>? firstCard;
      for (int i = 0; i < remaining.length; i++) {
        final v = remaining[i]['value']?.toString() ?? '';
        if (!actionValues.contains(v)) {
          firstCard = remaining.removeAt(i);
          break;
        }
      }
      firstCard ??= remaining.removeAt(0);

      // Step 1: update hands directly (simpler than RPC, host RLS allows it)
      await _sb.from('multi_player_hands')
          .delete()
          .eq('room_id', widget.roomId);

      for (int i = 0; i < ids.length; i++) {
        await _sb.from('multi_player_hands').upsert({
          'room_id': widget.roomId,
          'player_id': ids[i],
          'cards': hands[ids[i]],
          'seat_index': i,
        }, onConflict: 'room_id,player_id');
      }

      // Step 2: set room to playing — triggers realtime on all clients
      await _sb.from('multi_game_rooms').update({
        'status': 'playing',
        'player_order': ids,
        'current_player_id': ids[0],
        'top_card': firstCard,
        'draw_pile': remaining,
        'active_wild_color': null,
        'direction': 1,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.roomId);

      if (!mounted) return;
      _navigated = false;
      _navigateToGame();

    } catch (e, st) {
      if (!mounted) return;
      _isLaunching = false;
      // Show full error as dialog so it's visible even if snack dismisses
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface(context),
          title: Text('Launch Error', style: TextStyle(color: Colors.red)),
          content: Text(e.toString(), style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('OK'))],
        ),
      );
    }
  }

  // ─────────────────────────────────────────────
  //  LEAVE
  // ─────────────────────────────────────────────

  Future<void> _leaveRoom() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    _stopCountdown();
    _pollTimer?.cancel();
    _roomSub?.cancel();

    // Fire and forget — don't await before navigating
    if (uid != null) {
      _sb.rpc('leave_multi_room', params: {
        'p_room_id': widget.roomId,
        'p_user_id': uid,
      }).catchError((_) {});
    }

    // Use postFrameCallback + popUntil to guarantee we exit regardless of canPop
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      } else {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      }
    });
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final uid = _sb.auth.currentUser?.id;
    final canStart = _amHost && _playerIds.length >= 2 && !_isLaunching;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        body: Stack(children: [
          _GridBg(isDark: AppColors.isDark(context)),

          if (_countdownRunning)
            Positioned(
              top: 0, left: 0, right: 0,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) {
                  final c = _countdown > 20
                      ? const Color(0xFF34D399)
                      : _countdown > 10
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFE11D48);
                  return Container(
                    height: 180,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          c.withOpacity(0.08 * _pulse.value),
                          Colors.transparent,
                        ],
                        radius: 0.8,
                      ),
                    ),
                  );
                },
              ),
            ),

          SafeArea(
            child: Column(children: [
              _buildHeader(),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildRoomCode(),
              ),
              const SizedBox(height: 12),

              if (widget.isQuickMatch)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildCountdownBar(),
                ),
              if (widget.isQuickMatch) const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Text('PLAYERS',
                      style: TextStyle(
                          color: AppColors.textHint(context), fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _playerIds.length >= 2
                          ? const Color(0xFF34D399).withOpacity(0.12)
                          : const Color(0xFF818CF8).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${_playerIds.length} / 7',
                        style: TextStyle(
                          color: _playerIds.length >= 2
                              ? const Color(0xFF34D399)
                              : const Color(0xFF818CF8),
                          fontSize: 12, fontWeight: FontWeight.w700,
                        )),
                  ),
                ]),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const BouncingScrollPhysics(),
                  itemCount: 7,
                  itemBuilder: (_, i) {
                    final filled = i < _playerIds.length;
                    final pid = filled ? _playerIds[i] : null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PlayerSlot(
                        index: i,
                        playerId: pid,
                        name: pid != null
                            ? (_names[pid] ?? 'Player ${i + 1}')
                            : null,
                        isMe: pid == uid,
                        isHost: pid == _hostId,
                        shimmer: _shimmerCtrl,
                        joinTime: pid != null ? _joinTimes[pid] : null,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _buildBottomAction(canStart),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  WIDGETS
  // ─────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(children: [
        GestureDetector(
          onTap: _confirmLeave,
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.icon(context), size: 16),
          ),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Waiting Room',
              style: TextStyle(color: AppColors.text(context), fontSize: 20,
                  fontWeight: FontWeight.w800)),
          Text(widget.isQuickMatch ? '⚡ Quick Match' : '🏠 Private Room',
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
        ]),
        const Spacer(),
        if (!widget.isQuickMatch)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.roomCode));
              _snack('✅ Room code copied!');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF7C3AED).withOpacity(0.35)),
              ),
              child: Row(children: [
                Icon(Icons.share_rounded, color: Color(0xFF818CF8), size: 14),
                SizedBox(width: 6),
                Text('Invite',
                    style: TextStyle(color: Color(0xFF818CF8),
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _buildRoomCode() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFF7C3AED).withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.08),
            blurRadius: 20)],
      ),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ROOM CODE',
                style: TextStyle(color: AppColors.textSecondary(context), fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 2.5)),
            const SizedBox(height: 6),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                  colors: [Color(0xFF818CF8), Color(0xFFE879F9)])
                  .createShader(b),
              child: Text(widget.roomCode,
                  style: TextStyle(color: AppColors.text(context),
                      fontSize: 30, fontWeight: FontWeight.w900,
                      letterSpacing: 8)),
            ),
            const SizedBox(height: 3),
            Text('Share with friends',
                style: TextStyle(color: AppColors.textHint(context), fontSize: 11)),
          ],
        )),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Clipboard.setData(ClipboardData(text: widget.roomCode));
            _snack('✅ Copied!');
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF7C3AED).withOpacity(0.3)),
            ),
            child: Icon(Icons.copy_rounded,
                color: Color(0xFF818CF8), size: 20),
          ),
        ),
      ]),
    );
  }

  Widget _buildCountdownBar() {
    if (_playerIds.length < 2) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(children: [
          Text('⏳', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text('Waiting for a 2nd player…',
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13))),
          Text('${_playerIds.length}/7',
              style: TextStyle(color: AppColors.textHint(context), fontSize: 12)),
        ]),
      );
    }

    final col = _countdown > 20
        ? const Color(0xFF34D399)
        : _countdown > 10
            ? const Color(0xFFF59E0B)
            : const Color(0xFFE11D48);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: col.withOpacity(0.1), blurRadius: 14)],
      ),
      child: Column(children: [
        Row(children: [
          Text(_countdown > 10 ? '🚀' : '🔥',
              style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text('Game starts in ${_countdown}s',
              style: TextStyle(color: col, fontSize: 14,
                  fontWeight: FontWeight.w700))),
          Text('${_playerIds.length}/7',
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _countdown / 60.0,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation<Color>(col),
            minHeight: 6,
          ),
        ),
      ]),
    );
  }

  Widget _buildBottomAction(bool canStart) {
    if (widget.isQuickMatch) {
      if (_playerIds.length < 2) {
        return const _StatusBanner(
          icon: '⏳',
          color: Color(0xFF818CF8),
          text: 'Waiting for more players…',
          sub: 'Game auto-starts 60s after a 2nd player joins',
        );
      }
      // All players see the live countdown
      final col = _countdown > 20
          ? const Color(0xFF34D399)
          : _countdown > 10
              ? const Color(0xFFF59E0B)
              : const Color(0xFFE11D48);
      return _StatusBanner(
        icon: null,
        color: col,
        text: 'Game starting in ${_countdown}s — get ready!',
        sub: _amHost
            ? 'More players can still join before countdown ends'
            : 'Host will launch when the countdown ends',
      );
    }

    if (!_amHost) {
      return const _StatusBanner(
        icon: '🎮',
        color: Color(0xFF818CF8),
        text: 'Waiting for host to start…',
        sub: 'The host decides when the game begins',
      );
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) =>
          Transform.scale(scale: canStart ? _pulse.value : 1.0, child: child),
      child: SizedBox(
        width: double.infinity, height: 58,
        child: ElevatedButton(
          onPressed: canStart ? _launchGame : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: canStart
                ? const Color(0xFF34D399)
                : AppColors.surfaceVariant(context),
            disabledBackgroundColor: AppColors.surfaceVariant(context),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            elevation: 0,
          ),
          child: _isLaunching
              ? const SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : Text(
                  _playerIds.length < 2
                      ? '⏳  Waiting for players…'
                      : '🎮  Start Game   (${_playerIds.length} players)',
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800,
                    color: canStart
                        ? const Color(0xFF072210)
                        : AppColors.textHint(context),
                  ),
                ),
        ),
      ),
    );
  }

  void _confirmLeave() {
    // Capture navigator before async gap
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        title: Text('Leave room?',
            style: TextStyle(color: AppColors.text(context),
                fontWeight: FontWeight.w800)),
        content: Text(
          _amHost
              ? 'If you leave, the next player becomes host.'
              : 'You will be removed from this room.',
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => nav.pop(), // close dialog only
            child: Text('Stay',
                style: TextStyle(color: Color(0xFF818CF8))),
          ),
          TextButton(
            onPressed: () {
              nav.pop(); // close dialog
              _leaveRoom(); // handles its own navigation via postFrameCallback
            },
            child: Text('Leave',
                style: TextStyle(color: Color(0xFFE11D48))),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.surface(context),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    ));
  }
}

// ══════════════════════════════════════════════
//  PLAYER SLOT
// ══════════════════════════════════════════════

class _PlayerSlot extends StatelessWidget {
  final int index;
  final String? playerId;
  final String? name;
  final bool isMe, isHost;
  final AnimationController shimmer;
  final DateTime? joinTime;

  const _PlayerSlot({
    required this.index,
    required this.playerId,
    required this.name,
    required this.isMe,
    required this.isHost,
    required this.shimmer,
    this.joinTime,
  });

  String _elapsed() {
    if (joinTime == null) return '';
    final s = DateTime.now().difference(joinTime!).inSeconds;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final rem = s % 60;
    return '${m}m ${rem}s';
  }

  static const _palette = [
    Color(0xFF818CF8), Color(0xFF34D399), Color(0xFFE11D48),
    Color(0xFFF59E0B), Color(0xFFE879F9), Color(0xFF60A5FA),
    Color(0xFF4ADE80),
  ];

  @override
  Widget build(BuildContext context) {
    final col = _palette[index % _palette.length];

    if (playerId != null) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutBack,
        builder: (_, v, child) => Transform.scale(
            scale: v, alignment: Alignment.centerLeft, child: child),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMe ? col.withOpacity(0.55) : col.withOpacity(0.18),
              width: isMe ? 1.5 : 1,
            ),
            boxShadow: isMe
                ? [BoxShadow(color: col.withOpacity(0.12), blurRadius: 14)]
                : null,
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: col.withOpacity(0.13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: col.withOpacity(0.3)),
              ),
              child: Center(child: Text(
                isHost ? '👑'
                    : (name?.isNotEmpty == true
                        ? name![0].toUpperCase() : '?'),
                style: TextStyle(
                    fontSize: isHost ? 20 : 18,
                    fontWeight: FontWeight.w800,
                    color: col),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(
                    (name ?? 'Player ${index + 1}') + (isMe ? ' (You)' : ''),
                    style: TextStyle(color: AppColors.text(context),
                        fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  )),
                  if (isHost) ...[
                    const SizedBox(width: 7),
                    _Badge('HOST', const Color(0xFFFFD700)),
                  ],
                ]),
                Text('Seat ${index + 1}',
                    style: TextStyle(
                        color: AppColors.textHint(context), fontSize: 11)),
              ],
            )),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Badge('✅ Ready', const Color(0xFF34D399)),
                if (joinTime != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _elapsed(),
                    style: TextStyle(
                      color: AppColors.textHint(context),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ]),
        ),
      );
    }

    // Empty slot shimmer
    return AnimatedBuilder(
      animation: shimmer,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Center(child: Text('➕',
                style: TextStyle(fontSize: 17, color: AppColors.border(context)))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 10, width: 90,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant(context),
                    borderRadius: BorderRadius.circular(5),
                  )),
              const SizedBox(height: 6),
              Text('Seat ${index + 1} — open',
                  style: TextStyle(
                      color: AppColors.textHint(context), fontSize: 11)),
            ],
          )),
          _Badge('⏳ Empty', AppColors.textHint(context)),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label,
        style: TextStyle(color: color, fontSize: 10,
            fontWeight: FontWeight.w700)),
  );
}

// ══════════════════════════════════════════════
//  STATUS BANNER
// ══════════════════════════════════════════════

class _StatusBanner extends StatelessWidget {
  final String? icon;
  final Color color;
  final String text, sub;

  const _StatusBanner({
    this.icon,
    required this.color,
    required this.text,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        if (icon != null)
          Text(icon!, style: TextStyle(fontSize: 24))
        else
          SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(
                  color: color, strokeWidth: 2.5)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(color: color, fontSize: 13,
                fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(
                color: AppColors.textHint(context), fontSize: 11)),
          ],
        )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════
//  BACKGROUND
// ══════════════════════════════════════════════

class _GridBg extends StatelessWidget {
  final bool isDark;
  const _GridBg({required this.isDark});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _GridPainter(isDark: isDark));
}

class _GridPainter extends CustomPainter {
  final bool isDark;
  const _GridPainter({required this.isDark});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.028)
          : Colors.black.withOpacity(0.05)
      ..strokeWidth = 0.6;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}