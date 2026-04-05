import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/uno_services.dart';
import '../services/sound_services.dart';
import '../models/uno_card.dart';
import 'uno_lobby_screen.dart';

final _sb = Supabase.instance.client;

class UnoGameScreen extends StatefulWidget {
  final String roomId;
  const UnoGameScreen({Key? key, required this.roomId}) : super(key: key);
  @override State<UnoGameScreen> createState() => _UnoGameScreenState();
}

class _UnoGameScreenState extends State<UnoGameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  Map<String, dynamic>? _room;
  List<String> _playerOrder = [];
  Map<String, List<UnoCard>> _allHands = {};
  List<UnoCard> _myHand = [];
  Map<String, String> _playerNames = {};
  String? _myId;
  String? _currentPlayerId;
  UnoCard? _topCard;
  CardColor? _activeWildColor;
  int _direction = 1;
  bool _gameOver = false;
  String? _winnerId;
  String? _lastPlaceId;

  bool _unoCalled = false;
  Map<String, bool> _unoCalledBy = {};
  Map<String, int> _wrongCaughtAttempts = {};

  bool _drawnThisTurn = false;
  int _drawnCardIdx = -1; // index in _myHand of the drawn card (-1 = none)

  int _pendingDraw = 0;

  int _selectedIndex = -1;
  UnoCard? _selectedCard;

  bool _amSpectating = false;
  Set<String> _finishedPlayerIds = {};
  int _myFinishRank = 0;

  StreamSubscription? _roomSub;
  final Map<String, StreamSubscription> _handSubs = {};
  Timer? _pollTimer;

  // ── Presence ──
  Timer? _heartbeatTimer;
  final Map<String, DateTime?> _playerLastSeen = {};  // read from multi_player_hands
  Map<String, int> _offlineCountdowns = {};   // playerId → seconds remaining
  Map<String, Timer> _offlineTimers = {};
  Timer? _botMoveTimer;
  DateTime? _currentTurnStartedAt;  // local clock: when current player's turn began
  String? _lastKnownCurrentPlayer;  // to detect turn changes

  // ── Chat ──
  final List<Map<String, dynamic>> _chatMessages = [];
  RealtimeChannel? _chatChannel;
  Timer? _chatPollTimer;
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  bool _showChat = false;
  int _unreadCount = 0;

  late final AnimationController _turnGlowCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..repeat(reverse: true);
  late final Animation<double> _turnGlow =
      Tween<double>(begin: 0.35, end: 1.0).animate(
          CurvedAnimation(parent: _turnGlowCtrl, curve: Curves.easeInOut));

  late final AnimationController _cardPlayCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

  final List<_Particle> _particles = [];
  Timer? _particleTimer;

  bool _isMyTurn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _myId = _sb.auth.currentUser?.id;
    _subscribeRoom();
    _pollFallback();
    _subscribeChat();
    _startHeartbeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roomSub?.cancel();
    for (final s in _handSubs.values) s.cancel();
    _chatChannel?.unsubscribe();
    _chatPollTimer?.cancel();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    _pollTimer?.cancel();
    _particleTimer?.cancel();
    _heartbeatTimer?.cancel();
    _botMoveTimer?.cancel();
    for (final t in _offlineTimers.values) t.cancel();
    _turnGlowCtrl.dispose();
    _cardPlayCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sendHeartbeat();
    }
  }

  void _subscribeRoom() {
    _roomSub = _sb.from('multi_game_rooms')
        .stream(primaryKey: ['id'])
        .eq('id', widget.roomId)
        .listen((rows) async {
      if (!mounted) return;
      if (rows.isEmpty) {
        // Room was deleted (last player left or host force-closed)
        if (!_gameOver) {
          _snack('Room ended — returning to lobby', color: Colors.orange);
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const UnoLobbyScreen()),
                  (_) => false);
            }
          });
        }
        return;
      }
      _applyRoom(rows[0]);
    });
  }

  void _pollFallback() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        final r = await _sb.from('multi_game_rooms')
            .select().eq('id', widget.roomId).single();
        if (mounted) _applyRoom(r);
      } catch (_) {}
      // Also refresh all hands + last_seen so UNO-caught and presence detection
      // stay accurate (stream subscriptions may not fire without Realtime enabled)
      try {
        final rows = await _sb.from('multi_player_hands')
            .select('player_id, cards, last_seen')
            .eq('room_id', widget.roomId);
        if (!mounted) return;
        setState(() {
          for (final row in rows) {
            final pid = row['player_id']?.toString();
            if (pid == null) continue;
            final cards = (row['cards'] as List? ?? [])
                .map((c) => UnoCard.fromJson(Map<String, dynamic>.from(c)))
                .toList();
            _allHands[pid] = cards;
            if (pid == _myId) _myHand = cards;
            // Populate heartbeat map so _checkPresence can work without Realtime
            final lsStr = row['last_seen']?.toString();
            final ls = lsStr != null ? DateTime.tryParse(lsStr) : null;
            if (ls != null) _playerLastSeen[pid] = ls;
          }
        });
      } catch (_) {}
    });
  }

  // Called when the last player finishes — fetches immediately, then polls every 200ms until 'finished'
  void _awaitVerification() {
    _pollTimer?.cancel();
    int attempts = 0;

    // Immediate fetch — no waiting
    _sb.from('multi_game_rooms').select().eq('id', widget.roomId).single().then((r) {
      if (!mounted || _gameOver) return;
      _applyRoom(r);
    }).catchError((_) {});

    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (t) async {
      if (!mounted || _gameOver) { t.cancel(); return; }
      attempts++;
      try {
        final r = await _sb.from('multi_game_rooms')
            .select().eq('id', widget.roomId).single();
        if (mounted) {
          _applyRoom(r);
          if (r['status'] == 'finished' || attempts >= 30) {
            t.cancel();
            _pollFallback(); // resume normal polling
          }
        }
      } catch (_) {}
    });
  }

  // ══════════════════════════════════════════════════════════
  // FIX 1: _applyRoom — removed _myHand.isNotEmpty from _isMyTurn
  // ══════════════════════════════════════════════════════════
  void _applyRoom(Map<String, dynamic> room) async {
    final order = List<String>.from(room['player_order'] ?? []);
    final topJson = room['top_card'] as Map<String, dynamic>?;
    final wildStr = room['active_wild_color'] as String?;
    final wildColor = wildStr != null
        ? CardColor.values.firstWhere(
            (c) => c.name == wildStr,
            orElse: () => CardColor.wild)
        : null;

    final isFinished  = room['status'] == 'finished';
    final isVerifying = room['status'] == 'verifying';
    final pendingDraw = (room['pending_draw_count'] as int?) ?? 0;

    final unoCalledRaw = room['uno_called_by'];
    final Map<String, bool> unoCalledMap = {};
    if (unoCalledRaw is Map) {
      unoCalledRaw.forEach((k, v) {
        if (v == true) unoCalledMap[k.toString()] = true;
      });
    }

    final finishedRaw = room['finished_players'] as List? ?? [];
    final finishedIds = finishedRaw
        .map((f) => f['player_id']?.toString())
        .whereType<String>()
        .toSet();

    // Spectating = I am in finished_players AND game not over yet
    final nowSpectating = finishedIds.contains(_myId) &&
        !isFinished &&
        !isVerifying;

    int myRank = 0;
    for (final f in finishedRaw) {
      if (f['player_id']?.toString() == _myId) {
        myRank = (f['rank'] as int?) ?? 0;
        break;
      }
    }

    final prevCurrentId = _currentPlayerId;
    final prevPending   = _pendingDraw;
    final incomingCurrentId = room['current_player_id']?.toString();

    // SAFETY NET: If only 1 player remains and the game is not finished, they win by default.
    if (order.length == 1 && !isFinished && !_gameOver) {
      if (order[0] == _myId) {
        try {
          _sb.rpc('update_user_coins', params: {
            'p_user_id': _myId,
            'p_amount': 50,
            'p_game_type': 'uno_win',
            'p_description': 'Won by opponent quit',
          }).then((_) {});
        } catch (_) {}
        _sb.from('multi_game_rooms').update({
          'status': 'finished',
          'winner_id': _myId,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.roomId);
      }
    }

    setState(() {
      _room            = room;
      _playerOrder     = order;
      _currentPlayerId = room['current_player_id']?.toString();
      if (topJson != null) _topCard = UnoCard.fromJson(topJson);
      _activeWildColor  = wildColor;
      _direction        = (room['direction'] as int?) ?? 1;
      _pendingDraw      = pendingDraw;
      _unoCalledBy      = unoCalledMap;
      _finishedPlayerIds = finishedIds;
      _amSpectating     = nowSpectating;
      if (myRank > 0) _myFinishRank = myRank;

      // FIXED: removed _myHand.isNotEmpty — hand emptiness is handled
      // by nowSpectating (once registered via player_finished_uno,
      // finishedIds contains _myId which blocks the turn)
      _isMyTurn = _currentPlayerId == _myId
          && !isFinished
          && !isVerifying
          && !nowSpectating;

      _isLoading = false;

      if (isFinished && !_gameOver) {
        _gameOver    = true;
        _winnerId    = room['winner_id']?.toString();
        _lastPlaceId = room['last_place_id']?.toString();
        _startParticles();
        if (_winnerId == _myId) {
          SoundService.playWinSound();
        } else if (!_amSpectating) {
          SoundService.playLoseSound();
        }
      }
    });

    if (_currentPlayerId == _myId &&
        pendingDraw > 0 &&
        prevCurrentId != _myId) {
      final sourceCard =
          _topCard?.value == CardValue.wildDrawFour ? '+4' : '+2';
      _snack(
        '⚠️ You must stack a $sourceCard or take $pendingDraw cards!',
        color: Colors.orange.shade600,
        duration: const Duration(seconds: 3),
      );
    }


    // Track local turn-start time whenever the current player changes
    if (incomingCurrentId != null && incomingCurrentId != _lastKnownCurrentPlayer) {
      _lastKnownCurrentPlayer = incomingCurrentId;
      _currentTurnStartedAt = DateTime.now();
      // If the new current player is already known offline (bot is playing for them),
      // immediately schedule the next bot move — do NOT cancel their offline timer.
      if (_offlineCountdowns.containsKey(incomingCurrentId) &&
          _playerOrder.length > 2) {
        _scheduleBotMove(incomingCurrentId);
      }
    }

    for (final pid in order) {
      if (!_handSubs.containsKey(pid)) _subscribeHand(pid);
    }
    for (final pid in finishedIds) {
      if (!_handSubs.containsKey(pid)) _subscribeHand(pid);
    }
    // Load names for ALL players: active + finished/spectating
    await _loadNames([...order, ...finishedIds]);
    _checkPresence(room);
  }

  void _subscribeHand(String pid) {
    final sub = _sb.from('multi_player_hands')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .listen((rows) {
      if (!mounted) return;
      for (final row in rows) {
        final rPid = row['player_id']?.toString();
        if (rPid == null) continue;
        final cards = (row['cards'] as List? ?? [])
            .map((c) => UnoCard.fromJson(Map<String, dynamic>.from(c)))
            .toList();
        // Track last_seen per player (used for offline detection)
        final lsStr = row['last_seen']?.toString();
        final ls = lsStr != null ? DateTime.tryParse(lsStr) : null;
        setState(() {
          _allHands[rPid] = cards;
          if (rPid == _myId) _myHand = cards;
          if (ls != null) _playerLastSeen[rPid] = ls;
        });
      }
    });
    _handSubs[pid] = sub;
  }

  // Opens the UNO catch window for [playerId] if their hand is exactly 1 card
  // and they haven't already called UNO.

  Future<void> _loadNames(List<String> ids) async {
    final missing = ids.where((id) => !_playerNames.containsKey(id)).toList();
    if (missing.isEmpty) return;
    try {
      final rows = await _sb.from('profiles')
          .select('id, username')
          .inFilter('id', missing);
      final map = <String, String>{};
      for (final r in rows) {
        map[r['id'].toString()] = r['username']?.toString().isNotEmpty == true
            ? r['username'].toString() : 'Player';
      }
      if (mounted) setState(() => _playerNames.addAll(map));
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════
  // DRAW STACK LOGIC — unchanged
  // ══════════════════════════════════════════════════════════

  bool get _inDrawStack => _pendingDraw > 0;

  bool _canStackOnPending(UnoCard card) {
    final top = _topCard;
    if (top == null) return false;
    if (top.value == CardValue.wildDrawFour) {
      return card.value == CardValue.wildDrawFour;
    }
    if (top.value == CardValue.drawTwo) {
      return card.value == CardValue.drawTwo || card.value == CardValue.wildDrawFour;
    }
    return false;
  }

  bool _canPlayCard(UnoCard card) {
    if (_topCard == null) return true;
    if (_inDrawStack) return _canStackOnPending(card);
    if (_activeWildColor != null) {
      return card.color == _activeWildColor || card.isWild;
    }
    if (card.isWild) return true;
    return _topCard!.color == card.color || _topCard!.value == card.value;
  }

  String _nextPlayer({int skip = 0}) {
    if (_playerOrder.isEmpty) return _myId ?? '';
    final idx = _playerOrder.indexOf(_currentPlayerId ?? '');
    if (idx == -1) return _playerOrder[0];
    int next = idx;
    for (int i = 0; i <= skip; i++) {
      next = (next + _direction) % _playerOrder.length;
      if (next < 0) next += _playerOrder.length;
    }
    return _playerOrder[next];
  }

  Future<void> _onCardTap(int index) async {
    if (!_isMyTurn || _isLoading || _gameOver || _myHand.isEmpty) return;
    final card = _myHand[index];

    if (_drawnThisTurn && index != _drawnCardIdx) {
      _snack('You can only play the card you just drew, or pass turn');
      return;
    }

    if (_selectedIndex == index) {
      if (!_canPlayCard(card)) {
        if (_inDrawStack) {
          final top = _topCard?.value == CardValue.wildDrawFour ? '+4' : '+2';
          _snack('Draw stack active! You can only stack a $top card or take $_pendingDraw cards');
        } else {
          _snack('Cannot play that card — top card: ${_topCard?.displayText ?? "?"}');
        }
        HapticFeedback.lightImpact();
        setState(() { _selectedIndex = -1; _selectedCard = null; });
        return;
      }
      if (card.isWild) {
        _showColorPicker(card, index);
      } else {
        await _executePlay(card, index, null);
      }
    } else {
      setState(() { _selectedIndex = index; _selectedCard = card; });
    }
  }

  // ══════════════════════════════════════════════════════════
  // FIX 2: _executePlay — hand empty → call _playerFinishedUno
  // immediately after hand update, then return early.
  // No 300ms delay, no room update when finishing.
  // ══════════════════════════════════════════════════════════
  Future<void> _executePlay(UnoCard card, int index, CardColor? wildColor) async {
    HapticFeedback.mediumImpact();
    SoundService.playCardSound();
    _cardPlayCtrl.forward(from: 0);

    final newHand = List<UnoCard>.from(_myHand)..removeAt(index);
    setState(() {
      _myHand        = newHand;
      _selectedIndex = -1;
      _selectedCard  = null;
    });

    try {
      // Step 1: update hand in DB first — so DB hand is [] before RPC reads it
      await _sb.from('multi_player_hands')
          .update({'cards': UnoService.deckToJson(newHand)})
          .eq('room_id', widget.roomId)
          .eq('player_id', _myId!);

      // Step 2: if hand is now empty, register finish immediately and return.
      // player_finished_uno handles turn advance atomically in SQL.
      // Do NOT update multi_game_rooms turn here — that would race with the RPC.
      if (newHand.isEmpty) {
        setState(() { _drawnThisTurn = false; _drawnCardIdx = -1; });
        await _playerFinishedUno();
        // Clear uno flags after finishing
        try {
          final unoMap = Map<String, dynamic>.from(
              (_room?['uno_called_by'] as Map<dynamic, dynamic>?)?.map(
                  (k, v) => MapEntry(k.toString(), v)) ?? {});
          unoMap.remove(_myId);
          await _sb.from('multi_game_rooms').update({
            'uno_called_by': unoMap,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', widget.roomId);
        } catch (_) {}
        return; // ← early return: RPC handled everything
      }

      // Step 3: normal play — compute next room state
      String nextId  = _nextPlayer();
      int newDir     = _direction;
      int newPending = _pendingDraw;

      switch (card.value) {
        case CardValue.skip:
          if (!_inDrawStack) nextId = _nextPlayer(skip: 1);
          break;

        case CardValue.reverse:
          if (!_inDrawStack) {
            if (_playerOrder.length == 2) {
              nextId = _currentPlayerId!;
            } else {
              newDir = _direction * -1;
              final myIdx = _playerOrder.indexOf(_currentPlayerId ?? '');
              var nx = (myIdx + newDir) % _playerOrder.length;
              if (nx < 0) nx += _playerOrder.length;
              nextId = _playerOrder[nx];
            }
          }
          break;

        case CardValue.drawTwo:
          newPending = _pendingDraw + 2;
          nextId     = _nextPlayer();
          break;

        case CardValue.wildDrawFour:
          newPending = _pendingDraw + 4;
          nextId     = _nextPlayer();
          break;

        default:
          newPending = 0;
          break;
      }

      final List<dynamic> pile =
          List.from(_room?['draw_pile'] as List? ?? []);

      // Clear MY uno flag atomically with the turn advance — avoids the race
      // where observers see a stale uno_called_by before the separate clear fires.
      final unoMap = Map<String, dynamic>.from(
          (_room?['uno_called_by'] as Map<dynamic, dynamic>?)?.map(
              (k, v) => MapEntry(k.toString(), v)) ?? {});
      unoMap.remove(_myId);

      final Map<String, dynamic> roomUpdate = {
        'current_player_id':  nextId,
        'top_card':           card.toJson(),
        'active_wild_color':  wildColor?.name,
        'direction':          newDir,
        'draw_pile':          pile,
        'pending_draw_count': newPending,
        'uno_called_by':      unoMap,
        'updated_at':         DateTime.now().toIso8601String(),
      };

      await _sb.from('multi_game_rooms')
          .update(roomUpdate)
          .eq('id', widget.roomId);

      setState(() { _drawnThisTurn = false; _drawnCardIdx = -1; });

    } catch (e) {
      _snack('Play failed: $e');
      setState(() => _myHand = [..._myHand, card]);
    }
  }

  // _playerFinishedUno — unchanged
  Future<void> _playerFinishedUno() async {
    try {
      final result = await _sb.rpc('player_finished_uno', params: {
        'p_room_id':   widget.roomId.toString(),
        'p_player_id': (_myId ?? '').toString(),
      });

      if (result is Map && result['ok'] == true) {
        final isGameEnding = result['game_ending'] == true;
        final rank = result['rank'] as int? ?? 1;

        if (isGameEnding) {
          if (mounted) {
            _awaitVerification();
          }
        } else {
          final suffix = rank == 1
              ? '1st 🥇'
              : rank == 2
                  ? '2nd 🥈'
                  : rank == 3
                      ? '3rd 🥉'
                      : '${rank}th';
          final remaining = result['remaining_players'] as int? ?? 0;
          if (mounted) _snack(
            '🎉 You finished $suffix! $remaining player${remaining == 1 ? "" : "s"} still going…',
            color: const Color(0xFF34D399),
            duration: const Duration(seconds: 4),
          );
        }
      } else {
        final err = result?['error'] ?? 'unknown';
        if (mounted) _snack('Finish failed: $err', color: Colors.red);
      }
    } catch (e) {
      if (mounted) _snack('Could not register finish: $e', color: Colors.red);
    }
  }

  Future<void> _drawCard() async {
    if (!_isMyTurn || _isLoading || _drawnThisTurn || _gameOver || _myHand.isEmpty) return;

    if (_inDrawStack) {
      final canStack = _myHand.any((c) => _canStackOnPending(c));
      if (canStack) {
        final topLabel = _topCard?.value == CardValue.wildDrawFour ? '+4' : '+2';
        _snack(
          'You have a $topLabel to stack! Play it or tap DRAW to take $_pendingDraw cards',
          color: Colors.orange.shade400,
        );
        HapticFeedback.lightImpact();
        return;
      }
      await _takePendingCards();
      return;
    }

    final hasPlayable = _myHand.any((c) => _canPlayCard(c));
    if (hasPlayable) {
      _snack('You have a playable card — you must play it!');
      HapticFeedback.lightImpact();
      return;
    }

    HapticFeedback.lightImpact();
    SoundService.playDrawSound();
    setState(() { _selectedIndex = -1; _selectedCard = null; });

    try {
      List<dynamic> pile = List.from(_room?['draw_pile'] as List? ?? []);
      if (pile.isEmpty) {
        _snack('Draw pile empty — skipping turn');
        await _sb.from('multi_game_rooms').update({
          'current_player_id': _nextPlayer(),
          'pending_draw_count': 0,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.roomId);
        return;
      }

      final drawn = UnoCard.fromJson(Map<String, dynamic>.from(pile.removeLast()));
      final newHand = [..._myHand, drawn];

      await _sb.from('multi_player_hands')
          .update({'cards': UnoService.deckToJson(newHand)})
          .eq('room_id', widget.roomId)
          .eq('player_id', _myId!);

      final unoMap = Map<String, dynamic>.from(
          (_room?['uno_called_by'] as Map<dynamic, dynamic>?)?.map(
              (k, v) => MapEntry(k.toString(), v)) ?? {});
      unoMap.remove(_myId);

      await _sb.from('multi_game_rooms').update({
        'draw_pile':    pile,
        'uno_called_by': unoMap,
        'updated_at':   DateTime.now().toIso8601String(),
      }).eq('id', widget.roomId);

      setState(() { _myHand = newHand; _drawnThisTurn = true; _drawnCardIdx = newHand.length - 1; });

      if (_canPlayCard(drawn)) {
        _snack('Drew ${drawn.displayText} — tap it to play or pass turn',
            color: const Color(0xFF818CF8));
      } else {
        _snack('Drew ${drawn.displayText} — not playable, passing turn');
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        setState(() { _drawnThisTurn = false; _drawnCardIdx = -1; });
        await _sb.from('multi_game_rooms').update({
          'current_player_id': _nextPlayer(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.roomId);
      }
    } catch (e) {
      _snack('Draw failed: $e');
    }
  }

  Future<void> _takePendingCards() async {
    if (!_inDrawStack) return;
    final count = _pendingDraw;

    HapticFeedback.lightImpact();
    SoundService.playDrawSound();
    setState(() { _selectedIndex = -1; _selectedCard = null; });

    try {
      List<dynamic> pile = List.from(_room?['draw_pile'] as List? ?? []);
      final drawnCards = <UnoCard>[];
      for (int i = 0; i < count && pile.isNotEmpty; i++) {
        drawnCards.add(UnoCard.fromJson(Map<String, dynamic>.from(pile.removeLast())));
      }

      final newHand = [..._myHand, ...drawnCards];

      await _sb.from('multi_player_hands')
          .update({'cards': UnoService.deckToJson(newHand)})
          .eq('room_id', widget.roomId)
          .eq('player_id', _myId!);

      final unoMap = Map<String, dynamic>.from(
          (_room?['uno_called_by'] as Map<dynamic, dynamic>?)?.map(
              (k, v) => MapEntry(k.toString(), v)) ?? {});
      unoMap.remove(_myId);

      await _sb.from('multi_game_rooms').update({
        'draw_pile':          pile,
        'pending_draw_count': 0,
        'current_player_id':  _nextPlayer(),
        'uno_called_by':      unoMap,
        'updated_at':         DateTime.now().toIso8601String(),
      }).eq('id', widget.roomId);

      setState(() {
        _myHand        = newHand;
        _drawnThisTurn = false;
        _drawnCardIdx  = -1;
      });

      _snack(
        'You took $count cards — turn skipped! 😬',
        color: Colors.red.shade400,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      _snack('Draw failed: $e');
    }
  }

  Future<void> _passTurn() async {
    if (!_isMyTurn || !_drawnThisTurn) return;
    setState(() { _drawnThisTurn = false; _drawnCardIdx = -1; });
    await _sb.from('multi_game_rooms').update({
      'current_player_id': _nextPlayer(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', widget.roomId);
  }

  Future<void> _callUno() async {
    if (_myHand.length != 1) {
      _snack('Call UNO only when you have exactly 1 card!');
      return;
    }
    if (_unoCalledBy[_myId] == true) return;
    HapticFeedback.heavyImpact();
    SoundService.playUnoSound();
    final updated = Map<String, dynamic>.from(
        (_room?['uno_called_by'] as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v)) ?? {});
    updated[_myId!] = true;
    try {
      await _sb.from('multi_game_rooms').update({
        'uno_called_by': updated,
        'updated_at':    DateTime.now().toIso8601String(),
      }).eq('id', widget.roomId);
    } catch (_) {}
    setState(() {
      _unoCalled = true;
      _unoCalledBy[_myId!] = true;
    });
    _snack('🃏 UNO! Safe ✅', color: const Color(0xFFF59E0B));
  }

  Future<void> _callUnoCaught(String targetId) async {
    if (targetId == _myId) return;

    // Verify from DB — local state may be up to 3s stale
    final liveRow = await _sb.from('multi_player_hands')
        .select('cards')
        .eq('room_id', widget.roomId)
        .eq('player_id', targetId)
        .maybeSingle();
    final liveCount = (liveRow?['cards'] as List?)?.length ?? 0;
    final unoCalledLive = _unoCalledBy[targetId] == true;

    if (liveCount != 1 || unoCalledLive) {
      final attempts = (_wrongCaughtAttempts[_myId!] ?? 0) + 1;
      setState(() => _wrongCaughtAttempts[_myId!] = attempts);
      if (attempts >= 3) {
        _snack('❌ 3 wrong catches! You draw 2 penalty cards', color: Colors.red);
        setState(() => _wrongCaughtAttempts[_myId!] = 0);
        await _applyDrawPenalty(_myId!, 2);
      } else {
        final name = _playerNames[targetId] ?? 'that player';
        if (unoCalledLive) {
          _snack('Too late — $name already called UNO! ($attempts/3 wrong)');
        } else {
          _snack('Wrong catch — $name has $liveCount cards ($attempts/3 before penalty)');
        }
      }
      return;
    }

    HapticFeedback.heavyImpact();
    final name = _playerNames[targetId] ?? 'Player';
    _snack('🎯 Caught $name! They draw 2 penalty cards!', color: const Color(0xFF34D399));
    setState(() => _wrongCaughtAttempts[_myId!] = 0);

    // Mark as caught so the window closes for everyone
    final unoMap = Map<String, dynamic>.from(
        (_room?['uno_called_by'] as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v)) ?? {});
    unoMap[targetId] = true;
    try {
      await _sb.from('multi_game_rooms').update({
        'uno_called_by': unoMap,
        'updated_at':    DateTime.now().toIso8601String(),
      }).eq('id', widget.roomId);
    } catch (_) {}
    await _applyDrawPenalty(targetId, 2);
  }

  Future<void> _applyDrawPenalty(String playerId, int count) async {
    try {
      // Fetch fresh hand + pile from DB to avoid stale local state overwriting cards
      final handRow = await _sb.from('multi_player_hands')
          .select('cards')
          .eq('room_id', widget.roomId)
          .eq('player_id', playerId)
          .single();
      final roomRow = await _sb.from('multi_game_rooms')
          .select('draw_pile')
          .eq('id', widget.roomId)
          .single();

      final hand = (handRow['cards'] as List? ?? [])
          .map((c) => UnoCard.fromJson(Map<String, dynamic>.from(c)))
          .toList();
      final pile = List<dynamic>.from(roomRow['draw_pile'] as List? ?? []);

      for (int i = 0; i < count && pile.isNotEmpty; i++) {
        hand.add(UnoCard.fromJson(Map<String, dynamic>.from(pile.removeLast())));
      }

      await _sb.from('multi_player_hands')
          .update({'cards': UnoService.deckToJson(hand)})
          .eq('room_id', widget.roomId)
          .eq('player_id', playerId);
      await _sb.from('multi_game_rooms').update({
        'draw_pile':  pile,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.roomId);

      // Update local state immediately so the card count shows right away
      if (mounted) {
        setState(() {
          _allHands[playerId] = hand;
          if (playerId == _myId) _myHand = hand;
        });
      }
    } catch (e) {
      _snack('Penalty failed: $e');
    }
  }

  void _showColorPicker(UnoCard card, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColorPickerSheet(onPick: (color) {
        Navigator.pop(context);
        _executePlay(card, index, color);
      }),
    );
  }

  Future<void> _quitGame() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    // 1. Deduct 30 coins only if there are other active players still in the game
    final otherPlayers = _playerOrder.where((id) => id != uid).toList();
    if (!_gameOver && !_amSpectating && otherPlayers.isNotEmpty) {
      bool deducted = false;
      // Try RPC first (atomic, preferred)
      try {
        await _sb.rpc('deduct_coins', params: {
          'p_user_id': uid,
          'p_amount':  30,
          'p_reason':  'uno_left_mid_game',
          'p_room_id': widget.roomId,
        });
        deducted = true;
      } catch (_) {}
      // Fallback: direct profile update if RPC unavailable
      if (!deducted) {
        try {
          final prof = await _sb.from('profiles').select('coins').eq('id', uid).single();
          final current = (prof['coins'] as num?)?.toInt() ?? 0;
          await _sb.from('profiles')
              .update({'coins': (current - 30).clamp(0, 999999)})
              .eq('id', uid);
        } catch (_) {}
      }
    }

    // 2. If only 1 player remains, mark them as winner + record in match_history
    // We do this BEFORE leaving the room to ensure we still have database access.
    if (!_gameOver) {
      try {
        final allIds = List<String>.from(_playerOrder);
        final remaining = List<String>.from(allIds)..remove(uid);
        if (remaining.length == 1) {
          final winnerId = remaining[0];
          try {
            await _sb.rpc('update_user_coins', params: {
              'p_user_id': winnerId,
              'p_amount': 50,
              'p_game_type': 'uno_win',
              'p_description': 'Won by opponent quit',
            });
          } catch (_) {}
          await _sb.from('multi_game_rooms').update({
            'status': 'finished',
            'winner_id': winnerId,
            'last_place_id': uid,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', widget.roomId);
          // Record in match_history so both players see it in recents
          try {
            await _sb.from('match_history').insert({
              'room_id':        widget.roomId,
              'winner_id':      winnerId,
              'loser_id':       uid,
              'game_type':      'uno_multiplayer',
              'was_quit':       true,
              'all_player_ids': allIds,
            });
          } catch (_) {} // ignore duplicate if DB trigger already inserted
        }
      } catch (_) {}
    }

    // 3. Leave the room
    try {
      await _sb.rpc('leave_multi_room', params: {
        'p_room_id': widget.roomId, 'p_user_id': uid,
      });
    } catch (_) {}

    // 4. Navigate away
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const UnoLobbyScreen()),
          (_) => false);
    }
  }

  Future<void> _leaveAfterFinish() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _sb.rpc('leave_multi_room', params: {
        'p_room_id': widget.roomId, 'p_user_id': uid,
      });
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const UnoLobbyScreen()),
          (_) => false);
    }
  }

  void _startParticles() {
    final rng = math.Random();
    _particleTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        _particles.addAll(List.generate(4, (_) => _Particle(rng)));
        _particles.removeWhere((p) => p.isDead);
        for (final p in _particles) p.update();
      });
    });
    Future.delayed(const Duration(seconds: 4), _particleTimer?.cancel);
  }

  // ── Presence / Heartbeat ─────────────────────────────────────

  void _startHeartbeat() {
    _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) => _sendHeartbeat());
  }

  Future<void> _sendHeartbeat() async {
    if (!mounted || _myId == null || _gameOver) return;
    try {
      // Each player updates only their own row — no shared-map race condition
      await _sb.from('multi_player_hands')
          .update({'last_seen': DateTime.now().toIso8601String()})
          .eq('room_id', widget.roomId)
          .eq('player_id', _myId!);
    } catch (_) {}
  }

  void _checkPresence(Map<String, dynamic> room) {
    if (_gameOver) return;
    final now = DateTime.now();

    // Primary: heartbeat-based detection (requires last_seen column in multi_player_hands)
    for (final playerId in List<String>.from(_playerOrder)) {
      if (playerId == _myId) continue;
      final lastSeen = _playerLastSeen[playerId];
      if (lastSeen == null) continue; // no heartbeat data yet — fallback handles it

      final isOffline = now.difference(lastSeen).inSeconds > 20;
      if (isOffline && !_offlineCountdowns.containsKey(playerId)) {
        _startOfflineTimer(playerId);
      } else if (!isOffline && _offlineCountdowns.containsKey(playerId)) {
        _cancelOfflineTimer(playerId);
      }
    }

    // Fallback: if current player hasn't moved in 30s, treat as offline
    // Works even without the last_seen DB column
    _checkStuckTurn(room);
  }

  void _checkStuckTurn(Map<String, dynamic> room) {
    if (_gameOver || _isMyTurn) return;
    final currentId = room['current_player_id']?.toString();
    if (currentId == null || currentId == _myId) return;
    if (_offlineCountdowns.containsKey(currentId)) {
      // Already tracking — just keep scheduling bot if needed
      if (_playerOrder.length > 2 && _currentPlayerId == currentId) {
        _scheduleBotMove(currentId);
      }
      return;
    }

    // If we have a fresh heartbeat for this player, they are online — just thinking.
    // Never flag someone as offline when their last_seen is recent.
    final lastSeen = _playerLastSeen[currentId];
    if (lastSeen != null &&
        DateTime.now().difference(lastSeen).inSeconds < 20) {
      return; // heartbeat is healthy — player is online, just slow
    }

    // Use local turn-start clock as the last-resort fallback.
    // Only fires when:
    //   a) heartbeat data is missing (last_seen column not added yet), OR
    //   b) heartbeat is stale AND the turn has been stuck a long time.
    // 25s threshold — gives players time to think while keeping waits short.
    final turnStart = _currentTurnStartedAt;
    if (turnStart == null) return;
    final staleSecs = DateTime.now().difference(turnStart).inSeconds;
    if (staleSecs < 25) return;

    _startOfflineTimer(currentId);
    if (_playerOrder.length > 2) {
      _scheduleBotMove(currentId);
    }
  }

  void _startOfflineTimer(String playerId) {
    if (_offlineTimers.containsKey(playerId)) return;
    setState(() => _offlineCountdowns[playerId] = 30);

    // Immediately trigger bot if it's already this player's turn
    if (_playerOrder.length > 2 && _currentPlayerId == playerId) {
      _scheduleBotMove(playerId);
    }

    _offlineTimers[playerId] = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) { t.cancel(); return; }
      final remaining = (_offlineCountdowns[playerId] ?? 0) - 1;
      if (remaining <= 0) {
        t.cancel();
        _offlineTimers.remove(playerId);
        if (mounted) setState(() => _offlineCountdowns.remove(playerId));
        await _handleOfflineTimeout(playerId);
      } else {
        if (mounted) setState(() => _offlineCountdowns[playerId] = remaining);
        // Re-schedule bot on each tick in case previous attempt failed
        if (_playerOrder.length > 2 && _currentPlayerId == playerId) {
          _scheduleBotMove(playerId);
        }
      }
    });
  }

  void _cancelOfflineTimer(String playerId) {
    _offlineTimers[playerId]?.cancel();
    _offlineTimers.remove(playerId);
    if (mounted) setState(() => _offlineCountdowns.remove(playerId));
    // No snack — ScaffoldMessenger bleeds through to other screens
  }

  Future<void> _handleOfflineTimeout(String playerId) async {
    if (!mounted || _gameOver) return;
    if (_playerOrder.length == 2) {
      // 2-player: other player wins
      final allIds = List<String>.from(_playerOrder);
      try {
        try {
          await _sb.rpc('update_user_coins', params: {
            'p_user_id': _myId,
            'p_amount': 50,
            'p_game_type': 'uno_win',
            'p_description': 'Won by opponent offline',
          });
        } catch (_) {}
        await _sb.from('multi_game_rooms').update({
          'status': 'finished',
          'winner_id': _myId,
          'last_place_id': playerId,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.roomId);
        // Record in match_history so both players see it in recents
        try {
          await _sb.from('match_history').insert({
            'room_id':        widget.roomId,
            'winner_id':      _myId,
            'loser_id':       playerId,
            'game_type':      'uno_multiplayer',
            'was_quit':       true,
            'all_player_ids': allIds,
          });
        } catch (_) {}
      } catch (_) {}
    } else {
      // Multiplayer: remove offline player
      await _removeOfflinePlayer(playerId);
    }
  }

  Future<void> _removeOfflinePlayer(String playerId) async {
    if (!mounted) return;
    try {
      final newOrder = List<String>.from(_playerOrder)..remove(playerId);

      // If only 1 player remains, they win
      if (newOrder.length == 1) {
        try {
          await _sb.rpc('update_user_coins', params: {
            'p_user_id': newOrder[0],
            'p_amount': 50,
            'p_game_type': 'uno_win',
            'p_description': 'Won by opponent offline',
          });
        } catch (_) {}
        await _sb.from('multi_game_rooms').update({
          'status': 'finished',
          'winner_id': newOrder[0],
          'last_place_id': playerId,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', widget.roomId);
        return;
      }

      final Map<String, dynamic> update = {
        'player_order': newOrder,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (_currentPlayerId == playerId && newOrder.isNotEmpty) {
        final idx = _playerOrder.indexOf(playerId);
        update['current_player_id'] = newOrder[idx % newOrder.length];
      }
      await _sb.from('multi_game_rooms').update(update).eq('id', widget.roomId);
      await _sb.from('multi_player_hands')
          .delete()
          .eq('room_id', widget.roomId)
          .eq('player_id', playerId);
      if (mounted) {
        _snack('${_playerNames[playerId] ?? 'Player'} removed (offline)',
            color: Colors.orange);
      }
    } catch (_) {}
  }

  void _scheduleBotMove(String playerId) {
    if (_botMoveTimer != null) return;
    // Small jitter by seat index so only one client "wins" the race
    final myIdx = _playerOrder.indexOf(_myId ?? '').clamp(0, 10);
    final jitter = Duration(milliseconds: 800 + myIdx * 600);
    _botMoveTimer = Timer(jitter, () async {
      _botMoveTimer = null;
      if (!mounted || _currentPlayerId != playerId || _gameOver) return;
      await _executeBotPlay(playerId);
    });
  }

  Future<void> _executeBotPlay(String playerId) async {
    try {
      // ── 1. Fetch fresh room state from DB (never use stale local state) ──
      final roomRow = await _sb.from('multi_game_rooms')
          .select()
          .eq('id', widget.roomId)
          .single();

      // Abort if another client already moved this turn
      if (roomRow['current_player_id']?.toString() != playerId) return;

      final order       = List<String>.from(roomRow['player_order'] ?? []);
      final dir         = (roomRow['direction'] as int?) ?? 1;
      final pendingDraw = (roomRow['pending_draw_count'] as int?) ?? 0;
      final pile        = List<dynamic>.from(roomRow['draw_pile'] as List? ?? []);
      final inStack     = pendingDraw > 0;

      final topJson  = roomRow['top_card'] as Map<String, dynamic>?;
      final topCard  = topJson != null ? UnoCard.fromJson(topJson) : null;
      final wildStr  = roomRow['active_wild_color'] as String?;
      final wildColor = wildStr != null
          ? CardColor.values.firstWhere((c) => c.name == wildStr,
              orElse: () => CardColor.wild)
          : null;

      // ── 2. Fresh next-player helper (uses live dir & order) ──
      String nextAfter(String pid, {int extraSkip = 0}) {
        if (order.isEmpty) return pid;
        final idx = order.indexOf(pid);
        if (idx == -1) return order[0];
        var n = (idx + dir * (1 + extraSkip)) % order.length;
        if (n < 0) n += order.length;
        return order[n];
      }

      // ── 3. Fresh canPlay helper (uses live room state) ──
      bool canPlay(UnoCard card) {
        if (topCard == null) return true;
        if (inStack) {
          if (topCard.value == CardValue.wildDrawFour) {
            return card.value == CardValue.wildDrawFour;
          }
          if (topCard.value == CardValue.drawTwo) {
            return card.value == CardValue.drawTwo ||
                card.value == CardValue.wildDrawFour;
          }
          return false;
        }
        if (wildColor != null) return card.color == wildColor || card.isWild;
        if (card.isWild) return true;
        return topCard.color == card.color || topCard.value == card.value;
      }

      // ── 4. Fetch offline player's actual hand from DB ──
      final handRow = await _sb.from('multi_player_hands')
          .select('cards')
          .eq('room_id', widget.roomId)
          .eq('player_id', playerId)
          .maybeSingle();
      if (handRow == null) return;

      var hand = (handRow['cards'] as List? ?? [])
          .map((j) => UnoCard.fromJson(j as Map<String, dynamic>))
          .toList();
      if (hand.isEmpty) return;

      // ── 5. Find first playable card ──
      int cardIndex = -1;
      for (int i = 0; i < hand.length; i++) {
        if (canPlay(hand[i])) { cardIndex = i; break; }
      }

      // ── 6. No playable card ──
      if (cardIndex == -1) {
        if (inStack) {
          // Take ALL pending draw cards — same as _takePendingCards for live players
          final drawnCards = <UnoCard>[];
          for (int i = 0; i < pendingDraw && pile.isNotEmpty; i++) {
            drawnCards.add(UnoCard.fromJson(pile.removeLast() as Map<String, dynamic>));
          }
          await _sb.from('multi_player_hands')
              .update({'cards': UnoService.deckToJson([...hand, ...drawnCards])})
              .eq('room_id', widget.roomId).eq('player_id', playerId);
          await _sb.from('multi_game_rooms').update({
            'current_player_id': nextAfter(playerId),
            'draw_pile':         pile,
            'pending_draw_count': 0,
            'updated_at':        DateTime.now().toIso8601String(),
          }).eq('id', widget.roomId).eq('current_player_id', playerId);
          return;
        }

        // Normal: draw one card, play it if possible, otherwise pass
        if (pile.isEmpty) {
          await _sb.from('multi_game_rooms').update({
            'current_player_id': nextAfter(playerId),
            'updated_at':        DateTime.now().toIso8601String(),
          }).eq('id', widget.roomId).eq('current_player_id', playerId);
          return;
        }
        final drawn = UnoCard.fromJson(pile.removeLast() as Map<String, dynamic>);
        hand = [...hand, drawn];
        await _sb.from('multi_player_hands')
            .update({'cards': UnoService.deckToJson(hand)})
            .eq('room_id', widget.roomId).eq('player_id', playerId);
        if (canPlay(drawn)) {
          cardIndex = hand.length - 1;
        } else {
          // Drew but can't play — pass turn
          await _sb.from('multi_game_rooms').update({
            'current_player_id': nextAfter(playerId),
            'draw_pile':         pile,
            'updated_at':        DateTime.now().toIso8601String(),
          }).eq('id', widget.roomId).eq('current_player_id', playerId);
          return;
        }
      }

      // ── 7. Play the card — apply ALL UNO rules ──
      final cardToPlay = hand[cardIndex];
      final newHand    = List<UnoCard>.from(hand)..removeAt(cardIndex);
      await _sb.from('multi_player_hands')
          .update({'cards': UnoService.deckToJson(newHand)})
          .eq('room_id', widget.roomId).eq('player_id', playerId);

      String nextId    = nextAfter(playerId);
      int    newDir    = dir;
      int    newPending = pendingDraw;
      CardColor? newWild;
      final colors = [CardColor.red, CardColor.blue, CardColor.green, CardColor.yellow];

      switch (cardToPlay.value) {
        case CardValue.skip:
          // Skip is only effective when NOT resolving a draw stack
          if (!inStack) nextId = nextAfter(playerId, extraSkip: 1);
          break;

        case CardValue.reverse:
          if (!inStack) {
            newDir = dir * -1;
            if (order.length == 2) {
              // 2-player: reverse = skip (bot plays again → pass to next)
              // Actually reverse in 2-player means the same player goes again,
              // but since bot already played, pass to the other player = skip
              nextId = nextAfter(playerId); // equivalent to skip
            } else {
              // 3+ players: direction flips, next player is first in NEW direction
              final myIdx = order.indexOf(playerId);
              var nx = (myIdx + newDir) % order.length;
              if (nx < 0) nx += order.length;
              nextId = order[nx];
            }
          }
          break;

        case CardValue.drawTwo:
          newPending = pendingDraw + 2;
          break;

        case CardValue.wildDrawFour:
          newPending = pendingDraw + 4;
          newWild = colors[math.Random().nextInt(colors.length)];
          break;

        case CardValue.wild:
          newWild    = colors[math.Random().nextInt(colors.length)];
          newPending = 0;
          break;

        default:
          newPending = 0;
          break;
      }

      await _sb.from('multi_game_rooms').update({
        'current_player_id': nextId,
        'top_card':          cardToPlay.toJson(),
        'active_wild_color': newWild?.name,
        'direction':         newDir,
        'draw_pile':         pile,
        'pending_draw_count': newPending,
        'updated_at':        DateTime.now().toIso8601String(),
      }).eq('id', widget.roomId).eq('current_player_id', playerId);
    } catch (_) {}
  }


  // ── Chat ─────────────────────────────────────────────────────
  void _subscribeChat() {
    // Initial fetch + start polling every 2s (realtime may not be enabled)
    _fetchChatMessages();
    _chatPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchChatMessages());

    // Also wire up realtime for instant delivery when enabled
    _chatChannel = _sb
        .channel('chat:${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'game_chat',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (payload) {
            if (!mounted) return;
            _applyNewChatRow(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe();
  }

  Future<void> _fetchChatMessages() async {
    if (!mounted) return;
    try {
      final rows = await _sb
          .from('game_chat')
          .select()
          .eq('room_id', widget.roomId)
          .order('created_at');
      if (!mounted) return;
      bool changed = false;
      setState(() {
        for (final r in rows) {
          final row = Map<String, dynamic>.from(r);
          final id = row['id']?.toString() ?? '';
          final tempIdx = _chatMessages.indexWhere((m) =>
              m['id']?.toString().startsWith('temp_') == true &&
              m['player_id'] == row['player_id'] &&
              m['message'] == row['message']);
          if (tempIdx >= 0) {
            _chatMessages[tempIdx] = row;
            changed = true;
          } else if (!_chatMessages.any((m) => m['id']?.toString() == id)) {
            _chatMessages.add(row);
            if (!_showChat && row['player_id'] != _myId) _unreadCount++;
            changed = true;
          }
        }
      });
      if (changed) _scrollChatToBottom();
    } catch (_) {}
  }

  void _applyNewChatRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    setState(() {
      final tempIdx = _chatMessages.indexWhere((m) =>
          m['id']?.toString().startsWith('temp_') == true &&
          m['player_id'] == row['player_id'] &&
          m['message'] == row['message']);
      if (tempIdx >= 0) {
        _chatMessages[tempIdx] = row;
      } else if (!_chatMessages.any((m) => m['id']?.toString() == id)) {
        _chatMessages.add(row);
        if (!_showChat && row['player_id'] != _myId) _unreadCount++;
      }
    });
    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _chatCtrl.clear();
    final username = _playerNames[_myId] ?? 'Player';

    // Optimistic update — show immediately without waiting for stream
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _chatMessages.add({
      'id': tempId,
      'room_id': widget.roomId,
      'player_id': _myId,
      'username': username,
      'message': text,
      'created_at': DateTime.now().toIso8601String(),
    }));
    _scrollChatToBottom();

    try {
      await _sb.from('game_chat').insert({
        'room_id':   widget.roomId,
        'player_id': _myId,
        'username':  username,
        'message':   text,
      });
    } catch (_) {
      // Remove optimistic entry on failure
      if (mounted) setState(() => _chatMessages.removeWhere((m) => m['id'] == tempId));
    }
  }

  void _toggleChat() {
    setState(() {
      _showChat = !_showChat;
      if (_showChat) _unreadCount = 0;
    });
    if (_showChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScroll.hasClients) {
          _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _snack(String msg, {Color? color, Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color ?? const Color(0xFF1A0A2E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
      duration: duration ?? const Duration(seconds: 2),
    ));
  }

  // ══════════════════════════════════════════════════════════
  // BUILD — unchanged
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const _LoadingScreen();
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _showQuitSheet(),
      child: Scaffold(
        backgroundColor: const Color(0xFF07060F),
        body: Stack(children: [
          _GameBg(topCard: _topCard, wildColor: _activeWildColor),

          SafeArea(child: Column(children: [
            _TopBar(
              direction: _direction,
              playerCount: _playerOrder.length,
              onQuit: _showQuitSheet,
              onChat: _toggleChat,
              unreadCount: _unreadCount,
            ),

            const SizedBox(height: 8),

            _OpponentsRow(
              playerOrder: _playerOrder,
              myId: _myId ?? '',
              currentPlayerId: _currentPlayerId ?? '',
              playerNames: _playerNames,
              allHands: _allHands,
              finishedPlayerIds: _finishedPlayerIds,
              turnGlow: _turnGlow,
            ),

            const Spacer(),

            if (_inDrawStack && _isMyTurn)
              _DrawStackBanner(
                pendingCount: _pendingDraw,
                topCard: _topCard,
                onTakePenalty: _takePendingCards,
              ),

            _CenterArea(
              topCard: _topCard,
              wildColor: _activeWildColor,
              isMyTurn: _isMyTurn,
              amSpectating: _amSpectating,
              currentName: _playerNames[_currentPlayerId] ?? 'Someone',
              pendingDraw: _pendingDraw,
              onDraw: _inDrawStack && _isMyTurn ? _takePendingCards : _drawCard,
              turnGlow: _turnGlow,
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_allHands.entries.any((e) =>
                      e.key != _myId &&
                      e.value.length == 1 &&
                      _unoCalledBy[e.key] != true))
                    GestureDetector(
                      onTap: () {
                        final target = _allHands.entries.firstWhere((e) =>
                            e.key != _myId &&
                            e.value.length == 1 &&
                            _unoCalledBy[e.key] != true).key;
                        _callUnoCaught(target);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE11D48).withOpacity(0.6)),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('🚨', style: TextStyle(fontSize: 14)),
                          SizedBox(width: 6),
                          Text('UNO Caught!', style: TextStyle(
                              color: Color(0xFFE11D48), fontSize: 12,
                              fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    )
                  else
                    const SizedBox.shrink(),

                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_isMyTurn && _drawnThisTurn)
                      GestureDetector(
                        onTap: _passTurn,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF818CF8).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF818CF8).withOpacity(0.6)),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('Pass Turn', style: TextStyle(
                                color: Color(0xFF818CF8), fontSize: 12,
                                fontWeight: FontWeight.w700)),
                            SizedBox(width: 6),
                            Text('→', style: TextStyle(color: Color(0xFF818CF8), fontSize: 14)),
                          ]),
                        ),
                      ),

                    if (_myHand.length == 1 && _unoCalledBy[_myId] != true)
                      _UnoButton(called: false, onTap: _callUno),
                    if (_myHand.length == 1 && _unoCalledBy[_myId] == true)
                      _UnoButton(called: true, onTap: () {}),
                  ]),
                ],
              ),
            ),

            if (_amSpectating && !_gameOver)
              _SpectatorBanner(rank: _myFinishRank, onLeave: _leaveAfterFinish),

            _MyHand(
              cards: _myHand,
              selectedIndex: _selectedIndex,
              isMyTurn: _isMyTurn,
              topCard: _topCard,
              wildColor: _activeWildColor,
              pendingDraw: _pendingDraw,
              onTap: _onCardTap,
            ),

            const SizedBox(height: 10),
          ])),

          for (final p in _particles)
            Positioned(
              left: p.x * size.width,
              top: p.y * size.height,
              child: Container(
                width: p.sz, height: p.sz,
                decoration: BoxDecoration(
                  color: p.color.withOpacity(p.opacity.clamp(0.0, 1.0)),
                  shape: BoxShape.circle,
                ),
              ),
            ),

          // Offline banners (one per offline opponent)
          if (_offlineCountdowns.isNotEmpty)
            Positioned(
              top: 56, left: 0, right: 0,
              child: Column(
                children: _offlineCountdowns.entries.map((e) {
                  final name = _playerNames[e.key] ?? 'Opponent';
                  final secs = e.value;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7F1D1D).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade600.withValues(alpha: 0.6)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('$name is offline',
                            style: const TextStyle(color: Colors.white,
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text('${secs}s',
                          style: const TextStyle(color: Colors.redAccent,
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ]),
                  );
                }).toList(),
              ),
            ),

          if (_showChat)
            _ChatPanel(
              messages: _chatMessages,
              myId: _myId ?? '',
              scrollController: _chatScroll,
              controller: _chatCtrl,
              onSend: _sendMessage,
              onClose: _toggleChat,
            ),

          if (_gameOver)
            _GameOverOverlay(
              myId: _myId ?? '',
              winnerId: _winnerId ?? '',
              lastPlaceId: _lastPlaceId ?? '',
              playerNames: _playerNames,
              onHome: _leaveAfterFinish,
            ),
        ]),
      ),
    );
  }

  void _showQuitSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuitSheet(onQuit: _quitGame),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SPECTATOR BANNER — unchanged
// ══════════════════════════════════════════════════════════════

class _SpectatorBanner extends StatelessWidget {
  final int rank;
  final VoidCallback onLeave;
  const _SpectatorBanner({required this.rank, required this.onLeave});

  String get _rankText {
    switch (rank) {
      case 1: return '1st 🥇';
      case 2: return '2nd 🥈';
      case 3: return '3rd 🥉';
      default: return '${rank}th';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF818CF8).withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF818CF8).withOpacity(0.4)),
      ),
      child: Row(children: [
        const Text('👀', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You finished $_rankText — Spectating',
              style: const TextStyle(
                color: Color(0xFF818CF8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'Watch the others battle it out!',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onLeave,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.6)),
            ),
            child: const Text('Leave',
              style: TextStyle(
                color: Color(0xFF7C3AED),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DRAW STACK BANNER — unchanged
// ══════════════════════════════════════════════════════════════

class _DrawStackBanner extends StatelessWidget {
  final int pendingCount;
  final UnoCard? topCard;
  final VoidCallback onTakePenalty;
  const _DrawStackBanner({
    required this.pendingCount,
    required this.topCard,
    required this.onTakePenalty,
  });

  @override
  Widget build(BuildContext context) {
    final isPlus4Stack = topCard?.value == CardValue.wildDrawFour;
    final stackType    = isPlus4Stack ? '+4' : '+2';
    final canStackWith = isPlus4Stack ? '+4 only' : '+2 or +4';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade400.withOpacity(0.7)),
      ),
      child: Row(children: [
        const Text('⚠️', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Draw stack: $pendingCount cards!',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
          ),
          Text(
            'Stack $canStackWith or take $pendingCount cards',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ])),
        GestureDetector(
          onTap: onTakePenalty,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Take $pendingCount',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DYNAMIC BACKGROUND — unchanged
// ══════════════════════════════════════════════════════════════

class _GameBg extends StatelessWidget {
  final UnoCard? topCard;
  final CardColor? wildColor;
  const _GameBg({required this.topCard, required this.wildColor});

  Color get _base {
    final c = wildColor ?? topCard?.color;
    switch (c) {
      case CardColor.red:    return const Color(0xFF2A0010);
      case CardColor.blue:   return const Color(0xFF001828);
      case CardColor.green:  return const Color(0xFF001A0A);
      case CardColor.yellow: return const Color(0xFF231800);
      default:               return const Color(0xFF1A0A3A);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 700),
    width: double.infinity, height: double.infinity,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [_base, const Color(0xFF07060F)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// TOP BAR — unchanged
// ══════════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  final int direction, playerCount;
  final VoidCallback onQuit;
  final VoidCallback onChat;
  final int unreadCount;
  const _TopBar({
    required this.direction,
    required this.playerCount,
    required this.onQuit,
    required this.onChat,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Row(children: [
      GestureDetector(
        onTap: onQuit,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
        ),
      ),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(children: [
          Icon(
            direction == 1 ? Icons.rotate_right_rounded : Icons.rotate_left_rounded,
            color: Colors.white54, size: 15),
          const SizedBox(width: 6),
          Text('$playerCount players',
              style: const TextStyle(color: Colors.white54,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onChat,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white54, size: 18),
            ),
            if (unreadCount > 0)
              Positioned(
                top: -4, right: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE11D48), shape: BoxShape.circle),
                  child: Text('$unreadCount',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════
// OPPONENTS ROW — unchanged
// ══════════════════════════════════════════════════════════════

class _OpponentsRow extends StatelessWidget {
  final List<String> playerOrder;
  final String myId, currentPlayerId;
  final Map<String, String> playerNames;
  final Map<String, List<UnoCard>> allHands;
  final Set<String> finishedPlayerIds;
  final Animation<double> turnGlow;
  const _OpponentsRow({
    required this.playerOrder, required this.myId,
    required this.currentPlayerId, required this.playerNames,
    required this.allHands, required this.finishedPlayerIds,
    required this.turnGlow,
  });

  static const _colors = [
    Color(0xFF818CF8), Color(0xFFE11D48), Color(0xFFF59E0B),
    Color(0xFF34D399), Color(0xFFE879F9), Color(0xFF60A5FA),
  ];

  @override
  Widget build(BuildContext context) {
    final allOpponents = {
      ...playerOrder.where((id) => id != myId),
      ...finishedPlayerIds.where((id) => id != myId),
    }.toList();

    if (allOpponents.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 82,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: allOpponents.length,
        itemBuilder: (_, i) {
          final pid      = allOpponents[i];
          final active   = pid == currentPlayerId;
          final finished = finishedPlayerIds.contains(pid);
          final handSize = allHands[pid]?.length ?? 0;
          final name     = playerNames[pid] ?? 'P${i+1}';
          final col      = _colors[i % _colors.length];

          return AnimatedBuilder(
            animation: turnGlow,
            builder: (_, __) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: finished
                    ? const Color(0xFF34D399).withOpacity(0.08)
                    : active
                        ? col.withOpacity(0.14)
                        : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: finished
                      ? const Color(0xFF34D399).withOpacity(0.4)
                      : active
                          ? col.withOpacity(turnGlow.value * 0.9)
                          : Colors.white.withOpacity(0.07),
                  width: active ? 2 : 1,
                ),
                boxShadow: active && !finished
                    ? [BoxShadow(color: col.withOpacity(turnGlow.value * 0.3),
                        blurRadius: 14)]
                    : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: col.withOpacity(0.22), shape: BoxShape.circle),
                    child: Center(child: Text(
                      finished ? '✓' : (name.isNotEmpty ? name[0].toUpperCase() : '?'),
                      style: TextStyle(
                        color: finished ? const Color(0xFF34D399) : col,
                        fontSize: 12, fontWeight: FontWeight.w900,
                      ),
                    )),
                  ),
                  const SizedBox(width: 7),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      name.length > 8 ? '${name.substring(0, 7)}…' : name,
                      style: TextStyle(
                        color: finished
                            ? const Color(0xFF34D399)
                            : active ? Colors.white : Colors.white54,
                        fontSize: 11,
                        fontWeight: active || finished ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    if (finished)
                      const Text('DONE ✓',
                          style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 8,
                              fontWeight: FontWeight.w900))
                    else
                      Row(children: [
                        ...List.generate(math.min(handSize, 5), (_) => Container(
                          width: 6, height: 9,
                          margin: const EdgeInsets.only(right: 1.5),
                          decoration: BoxDecoration(
                            color: active ? col : Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        )),
                        if (handSize > 5)
                          Text('+${handSize - 5}',
                              style: TextStyle(
                                  color: active ? col : Colors.white24,
                                  fontSize: 8, fontWeight: FontWeight.w800)),
                      ]),
                  ]),
                ]),
                if (handSize == 1 && !finished)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('UNO! 🃏',
                        style: TextStyle(color: col, fontSize: 8,
                            fontWeight: FontWeight.w900)),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CENTER PLAY AREA — unchanged
// ══════════════════════════════════════════════════════════════

class _CenterArea extends StatelessWidget {
  final UnoCard? topCard;
  final CardColor? wildColor;
  final bool isMyTurn;
  final bool amSpectating;
  final String currentName;
  final int pendingDraw;
  final VoidCallback onDraw;
  final Animation<double> turnGlow;
  const _CenterArea({
    required this.topCard, required this.wildColor, required this.isMyTurn,
    required this.amSpectating,
    required this.currentName, required this.pendingDraw,
    required this.onDraw, required this.turnGlow,
  });

  @override
  Widget build(BuildContext context) {
    final inStack = pendingDraw > 0;
    return Column(children: [
      AnimatedBuilder(
        animation: turnGlow,
        builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: isMyTurn
                ? (inStack
                    ? Colors.red.withOpacity(0.13 * turnGlow.value)
                    : const Color(0xFF34D399).withOpacity(0.13 * turnGlow.value))
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isMyTurn
                  ? (inStack
                      ? Colors.red.withOpacity(turnGlow.value * 0.7)
                      : const Color(0xFF34D399).withOpacity(turnGlow.value * 0.7))
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Text(
            amSpectating
                ? (inStack ? '🔥 $currentName must draw $pendingDraw!' : '👁 $currentName\'s turn')
                : isMyTurn
                    ? (inStack ? '🔥 Draw Stack! Take $pendingDraw cards' : '✨  Your Turn!')
                    : '$currentName\'s turn…',
            style: TextStyle(
              color: amSpectating
                  ? (inStack ? Colors.orange.shade300 : Colors.white)
                  : isMyTurn
                      ? (inStack ? Colors.red.shade300 : const Color(0xFF34D399))
                      : Colors.white38,
              fontSize: amSpectating ? 14 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),

      const SizedBox(height: 20),

      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(
          onTap: isMyTurn ? onDraw : null,
          child: AnimatedBuilder(
            animation: turnGlow,
            builder: (_, __) {
              final glowing    = isMyTurn;
              final stackGlow  = glowing && inStack;
              return Container(
                width: 76, height: 108,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: stackGlow
                        ? [
                            Colors.red.withOpacity((0.5 + 0.4 * turnGlow.value).clamp(0.0, 1.0)),
                            Colors.deepOrange.withOpacity((0.4 + 0.3 * turnGlow.value).clamp(0.0, 1.0)),
                          ]
                        : glowing
                        ? [
                            const Color(0xFF7C3AED).withOpacity((0.5 + 0.4 * turnGlow.value).clamp(0.0, 1.0)),
                            const Color(0xFF3B82F6).withOpacity((0.4 + 0.3 * turnGlow.value).clamp(0.0, 1.0)),
                          ]
                        : [Colors.white.withOpacity(0.09), Colors.white.withOpacity(0.05)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: stackGlow
                        ? Colors.red.withOpacity(turnGlow.value * 0.9)
                        : glowing
                        ? const Color(0xFF818CF8).withOpacity(turnGlow.value * 0.8)
                        : Colors.white.withOpacity(0.18),
                    width: 2,
                  ),
                  boxShadow: glowing
                      ? [BoxShadow(
                          color: (stackGlow ? Colors.red : const Color(0xFF7C3AED))
                              .withOpacity(turnGlow.value * 0.4),
                          blurRadius: 20)]
                      : null,
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(inStack ? '😬' : '🃏', style: const TextStyle(fontSize: 30)),
                  const SizedBox(height: 5),
                  Text(
                    inStack ? '+$pendingDraw' : 'DRAW',
                    style: TextStyle(
                      color: glowing ? Colors.white : Colors.white38,
                      fontSize: inStack ? 16 : 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: inStack ? 0 : 1.5,
                    ),
                  ),
                ]),
              );
            },
          ),
        ),

        const SizedBox(width: 22),

        topCard != null
            ? UnoCardWidget(card: topCard!, wildColor: wildColor, large: true)
            : Container(width: 84, height: 118,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                )),
      ]),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// MY HAND — unchanged
// ══════════════════════════════════════════════════════════════

class _MyHand extends StatelessWidget {
  final List<UnoCard> cards;
  final int selectedIndex;
  final bool isMyTurn;
  final UnoCard? topCard;
  final CardColor? wildColor;
  final int pendingDraw;
  final void Function(int) onTap;
  const _MyHand({
    required this.cards, required this.selectedIndex, required this.isMyTurn,
    required this.topCard, required this.wildColor, required this.pendingDraw,
    required this.onTap,
  });

  bool _canStack(UnoCard card) {
    if (topCard == null) return false;
    if (topCard!.value == CardValue.wildDrawFour) {
      return card.value == CardValue.wildDrawFour;
    }
    if (topCard!.value == CardValue.drawTwo) {
      return card.value == CardValue.drawTwo || card.value == CardValue.wildDrawFour;
    }
    return false;
  }

  bool _playable(UnoCard c) {
    if (topCard == null || c.isWild) return true;
    if (pendingDraw > 0) return _canStack(c);
    if (wildColor != null) return c.color == wildColor;
    return c.color == topCard!.color || c.value == topCard!.value;
  }

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('🎉 No cards left!',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
      );
    }

    final overlap = cards.length > 9 ? 46.0 : cards.length > 6 ? 54.0 : 62.0;

    return SizedBox(
      height: 130,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          left: 20,
          right: math.max(20, MediaQuery.of(context).size.width -
              (overlap * (cards.length - 1) + 80) - 20),
        ),
        child: SizedBox(
          width: overlap * (cards.length - 1) + 84,
          child: Stack(
            clipBehavior: Clip.none,
            children: List.generate(cards.length, (i) {
              final card     = cards[i];
              final selected = i == selectedIndex;
              final canPlay  = isMyTurn && _playable(card);
              return Positioned(
                left: i * overlap,
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    transform: Matrix4.translationValues(0, selected ? -24 : 0, 0),
                    child: UnoCardWidget(
                      card: card,
                      dimmed: isMyTurn && !canPlay,
                      selected: selected,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// UNO CARD WIDGET — unchanged
// ══════════════════════════════════════════════════════════════

class UnoCardWidget extends StatelessWidget {
  final UnoCard card;
  final bool dimmed;
  final bool selected;
  final CardColor? wildColor;
  final bool large;

  const UnoCardWidget({
    Key? key,
    required this.card,
    this.dimmed = false,
    this.selected = false,
    this.wildColor,
    this.large = false,
  }) : super(key: key);

  Color get _bg {
    final effective = card.isWild ? (wildColor ?? card.color) : card.color;
    switch (effective) {
      case CardColor.red:    return const Color(0xFFDC2626);
      case CardColor.blue:   return const Color(0xFF2563EB);
      case CardColor.green:  return const Color(0xFF16A34A);
      case CardColor.yellow: return const Color(0xFFEAB308);
      case CardColor.wild:   return const Color(0xFF1E1B4B);
    }
  }

  bool get _isDark => card.color != CardColor.yellow || card.isWild;
  String get _label => card.displayText;

  @override
  Widget build(BuildContext context) {
    final w          = large ? 84.0 : 76.0;
    final h          = large ? 118.0 : 108.0;
    final labelColor = _isDark ? Colors.white : Colors.black87;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: dimmed ? 0.38 : 1.0,
      child: Container(
        width: w, height: h,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(large ? 16 : 14),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withOpacity(0.28),
            width: selected ? 3 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _bg.withOpacity(selected ? 0.75 : 0.3),
              blurRadius: selected ? 22 : 8,
              spreadRadius: selected ? 3 : 0,
            ),
          ],
        ),
        child: Stack(children: [
          Center(child: Container(
            width: w * 0.62, height: h * 0.62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.3),
              color: Colors.white.withOpacity(0.12),
            ),
          )),
          Positioned(top: 5, left: 6,
              child: Text(_label, style: TextStyle(
                  color: labelColor, fontSize: 11, fontWeight: FontWeight.w900))),
          Center(child: Text(_label, style: TextStyle(
              color: labelColor,
              fontSize: _label.length > 2 ? 24 : 32,
              fontWeight: FontWeight.w900))),
          Positioned(bottom: 5, right: 6,
            child: Transform.rotate(angle: math.pi,
              child: Text(_label, style: TextStyle(
                  color: labelColor, fontSize: 11, fontWeight: FontWeight.w900)))),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// UNO BUTTON — unchanged
// ══════════════════════════════════════════════════════════════

class _UnoButton extends StatelessWidget {
  final bool called;
  final VoidCallback onTap;
  const _UnoButton({required this.called, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
      decoration: BoxDecoration(
        color: called
            ? const Color(0xFF34D399).withOpacity(0.15)
            : const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(26),
        border: called ? Border.all(color: const Color(0xFF34D399)) : null,
        boxShadow: called ? [] : [
          BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.55), blurRadius: 18),
        ],
      ),
      child: Text(
        called ? '✅  UNO Called!' : '🃏  UNO!',
        style: TextStyle(
          color: called ? const Color(0xFF34D399) : Colors.black87,
          fontWeight: FontWeight.w900, fontSize: 15,
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// COLOR PICKER SHEET — unchanged
// ══════════════════════════════════════════════════════════════

class _ColorPickerSheet extends StatelessWidget {
  final void Function(CardColor) onPick;
  const _ColorPickerSheet({required this.onPick});

  @override
  Widget build(BuildContext context) {
    const options = [
      (CardColor.red,    Color(0xFFDC2626), '🔴', 'Red'),
      (CardColor.blue,   Color(0xFF2563EB), '🔵', 'Blue'),
      (CardColor.green,  Color(0xFF16A34A), '🟢', 'Green'),
      (CardColor.yellow, Color(0xFFEAB308), '🟡', 'Yellow'),
    ];

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0F1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Text('Choose a Color ✨',
            style: TextStyle(color: Colors.white, fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: options.map((o) => GestureDetector(
            onTap: () => onPick(o.$1),
            child: Column(children: [
              Container(
                width: 68, height: 68,
                decoration: BoxDecoration(
                  color: o.$2,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: o.$2.withOpacity(0.5), blurRadius: 16)],
                ),
                child: Center(child: Text(o.$3, style: const TextStyle(fontSize: 28))),
              ),
              const SizedBox(height: 8),
              Text(o.$4, style: const TextStyle(color: Colors.white54,
                  fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          )).toList(),
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// GAME OVER OVERLAY — unchanged
// ══════════════════════════════════════════════════════════════

class _GameOverOverlay extends StatelessWidget {
  final String myId, winnerId, lastPlaceId;
  final Map<String, String> playerNames;
  final VoidCallback onHome;
  const _GameOverOverlay({
    required this.myId, required this.winnerId,
    required this.lastPlaceId, required this.playerNames,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final isWin  = myId == winnerId;
    final isLast = myId == lastPlaceId;
    final emoji  = isWin ? '🏆' : isLast ? '💀' : '😐';
    final title  = isWin ? 'You Won!' : isLast ? 'Last Place' : 'Game Over';
    final coins  = isWin ? '+50 🪙' : isLast ? '-20 🪙' : '±0 🪙';
    final coinCol = isWin ? const Color(0xFFFFD700)
        : isLast ? const Color(0xFFE11D48) : Colors.white38;
    final borderCol = isWin ? const Color(0xFFFFD700).withOpacity(0.4)
        : isLast ? const Color(0xFFE11D48).withOpacity(0.3)
        : Colors.white.withOpacity(0.1);
    final winnerName = playerNames[winnerId] ?? 'Someone';

    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Center(child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0F1C),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: borderCol, width: 1.5),
          boxShadow: [BoxShadow(
              color: isWin
                  ? const Color(0xFFFFD700).withOpacity(0.15)
                  : Colors.black54,
              blurRadius: 40)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 68)),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 28,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (!isWin)
            Text('$winnerName wins! 🏆',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            decoration: BoxDecoration(
              color: coinCol.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: coinCol.withOpacity(0.4)),
            ),
            child: Text(coins,
                style: TextStyle(color: coinCol, fontSize: 24,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: onHome,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('Back to Home',
                  style: TextStyle(color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// QUIT SHEET — unchanged
// ══════════════════════════════════════════════════════════════

class _QuitSheet extends StatelessWidget {
  final VoidCallback onQuit;
  const _QuitSheet({required this.onQuit});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
    decoration: const BoxDecoration(
      color: Color(0xFF0C0F1C),
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 20),
      const Text('🚪  Quit Game?',
          style: TextStyle(color: Colors.white, fontSize: 22,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('⚠️ Quitting mid-game will cost you 30 coins.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFE11D48), fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      const Text('Your opponent stays in the game.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 12)),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.07),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Keep Playing',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
        )),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          onPressed: () { Navigator.pop(context); onQuit(); },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE11D48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Quit',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        )),
      ]),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════
// LOADING SCREEN — unchanged
// ══════════════════════════════════════════════════════════════

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF07060F),
    body: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('🃏', style: TextStyle(fontSize: 64)),
        SizedBox(height: 20),
        CircularProgressIndicator(color: Color(0xFF818CF8), strokeWidth: 2.5),
        SizedBox(height: 16),
        Text('Dealing cards…',
            style: TextStyle(color: Colors.white38, fontSize: 14)),
      ],
    )),
  );
}

// ══════════════════════════════════════════════════════════════
// PARTICLE SYSTEM — unchanged
// ══════════════════════════════════════════════════════════════

class _Particle {
  double x, y, vx, vy, sz, opacity;
  Color color;

  static const _palette = [
    Color(0xFFF59E0B), Color(0xFFE11D48), Color(0xFF818CF8),
    Color(0xFF34D399), Color(0xFFE879F9),
  ];

  _Particle(math.Random rng)
      : x       = rng.nextDouble(),
        y       = 0.25 + rng.nextDouble() * 0.5,
        vx      = (rng.nextDouble() - 0.5) * 0.014,
        vy      = -rng.nextDouble() * 0.016,
        sz      = 4 + rng.nextDouble() * 9,
        opacity = 0.9,
        color   = _palette[rng.nextInt(_palette.length)];

  void update() {
    x += vx; y += vy; vy += 0.0006; opacity -= 0.017;
  }

  bool get isDead => opacity <= 0.017; // remove before next frame renders negative
}

// ══════════════════════════════════════════════════════════════
// CHAT PANEL
// ══════════════════════════════════════════════════════════════

class _ChatPanel extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final String myId;
  final ScrollController scrollController;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onClose;

  const _ChatPanel({
    required this.messages,
    required this.myId,
    required this.scrollController,
    required this.controller,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: GestureDetector(
            onTap: () {}, // absorb taps inside panel
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.55,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0B1A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                        blurRadius: 24),
                  ],
                ),
                child: Column(children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 0),
                    child: Row(children: [
                      const Text('💬',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      const Text('Game Chat',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      const Spacer(),
                      GestureDetector(
                        onTap: onClose,
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 20),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),

                  // Messages
                  Expanded(
                    child: messages.isEmpty
                        ? const Center(
                            child: Text('No messages yet.\nSay something! 👋',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 13)),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            itemCount: messages.length,
                            itemBuilder: (_, i) {
                              final m = messages[i];
                              final isMe = m['player_id'] == myId;
                              final name = m['username']?.toString() ?? 'Player';
                              final text = m['message']?.toString() ?? '';
                              return _ChatBubble(
                                  name: name, text: text, isMe: isMe);
                            },
                          ),
                  ),

                  // Input
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12,
                        MediaQuery.of(context).viewInsets.bottom + 12),
                    child: Row(children: [
                      Expanded(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1530),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFF7C3AED)
                                    .withValues(alpha: 0.3)),
                          ),
                          child: TextField(
                            controller: controller,
                            maxLength: 120,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => onSend(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            cursorColor: Colors.white,
                            decoration: const InputDecoration(
                              hintText: 'Say something…',
                              hintStyle: TextStyle(
                                  color: Colors.white24, fontSize: 13),
                              border: InputBorder.none,
                              counterText: '',
                              filled: true,
                              fillColor: Colors.transparent,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onSend,
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.send_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String name, text;
  final bool isMe;
  const _ChatBubble(
      {required this.name, required this.text, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Color(0xFF818CF8),
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text('@$name',
                        style: const TextStyle(
                            color: Color(0xFF818CF8),
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFF7C3AED).withValues(alpha: 0.35)
                        : const Color(0xFF1E1A33),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isMe ? 14 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 14),
                    ),
                    border: Border.all(
                      color: isMe
                          ? const Color(0xFF7C3AED).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Text(text,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.4)),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 7),
        ],
      ),
    );
  }
}