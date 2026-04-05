import '../../settings/theme_provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/uno_services.dart';
import '../models/uno_card.dart';
import 'uno_waiting_screen.dart';
import 'uno_match_makingscreen.dart';
import 'uno_game_screen.dart';
import '../../home/home_screen.dart';

final _sb = Supabase.instance.client;

// ══════════════════════════════════════════════════════
//  UNO LOBBY SCREEN
// ══════════════════════════════════════════════════════
class UnoLobbyScreen extends StatefulWidget {
  const UnoLobbyScreen({Key? key}) : super(key: key);
  @override
  State<UnoLobbyScreen> createState() => _UnoLobbyScreenState();
}

class _UnoLobbyScreenState extends State<UnoLobbyScreen>
    with TickerProviderStateMixin {
  late final AnimationController _floatCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat(reverse: true);
  late final AnimationController _glowCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);
  late final Animation<double> _float =
      Tween<double>(begin: -12, end: 12).animate(
          CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));
  late final Animation<double> _glow =
      Tween<double>(begin: 0.3, end: 1.0).animate(
          CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _cleanStaleRooms();
    // Delay slightly so the screen renders before showing dialog
    Future.delayed(const Duration(milliseconds: 400), _checkRejoinGame);
  }

  /// Remove this user from any stale waiting rooms they didn't properly leave.
  /// Runs silently on lobby open so they never appear as a ghost player.
  Future<void> _cleanStaleRooms() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      // Get all hand rows for this user
      final hands = await _sb
          .from('multi_player_hands')
          .select('room_id')
          .eq('player_id', uid);

      for (final row in hands) {
        final roomId = row['room_id']?.toString();
        if (roomId == null) continue;
        final room = await _sb
            .from('multi_game_rooms')
            .select('status, host_id')
            .eq('id', roomId)
            .maybeSingle();

        // Only clean waiting rooms — keep playing rows for rejoin
        if (room == null || room['status'] == 'waiting') {
          // Remove hand row
          await _sb.from('multi_player_hands')
              .delete()
              .eq('room_id', roomId)
              .eq('player_id', uid);

          if (room != null) {
            // Check if room is now empty
            final remaining = await _sb
                .from('multi_player_hands')
                .select('player_id')
                .eq('room_id', roomId);

            if (remaining.isEmpty) {
              await _sb.from('multi_game_rooms').delete().eq('id', roomId);
            } else {
              // Use leave_multi_room RPC to handle player_order cleanup
              await _sb.rpc('leave_multi_room', params: {
                'p_room_id': roomId,
                'p_user_id': uid,
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _checkRejoinGame() async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null || !mounted) return;
    try {
      final rooms = await _sb
          .from('multi_game_rooms')
          .select()
          .eq('status', 'playing')
          .contains('player_order', [userId])
          .limit(1);
      if (!mounted || rooms.isEmpty) return;
      _showRejoinDialog(rooms.first as Map<String, dynamic>);
    } catch (_) {}
  }

  void _showRejoinDialog(Map<String, dynamic> room) {
    int countdown = 60;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
          if (!ctx.mounted) { t.cancel(); return; }
          setS(() => countdown--);
          if (countdown <= 0) {
            t.cancel();
            Navigator.of(ctx).pop();
            _abandonGame(room);
          }
        });
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1530),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Rejoin Game?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('You have an active UNO game in progress.',
                style: TextStyle(color: AppColors.textSecondary(context))),
            const SizedBox(height: 16),
            Text('$countdown s',
                style: TextStyle(color: Color(0xFF7C3AED),
                    fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('before you forfeit', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                timer?.cancel();
                Navigator.of(ctx).pop();
                _abandonGame(room);
              },
              child: Text('Forfeit', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                timer?.cancel();
                Navigator.of(ctx).pop();
                Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => UnoGameScreen(roomId: room['id'].toString())));
              },
              child: Text('Rejoin', style: TextStyle(color: AppColors.text(context))),
            ),
          ],
        );
      }),
    ).then((_) => timer?.cancel());
  }

  Future<void> _abandonGame(Map<String, dynamic> room) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final order = List<String>.from(room['player_order'] ?? []);
      if (order.length <= 2) {
        final winnerId = order.firstWhere((id) => id != userId, orElse: () => '');
        if (winnerId.isNotEmpty) {
          await _sb.from('multi_game_rooms').update({
            'status': 'finished',
            'winner_id': winnerId,
            'last_place_id': userId,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', room['id'].toString());
          // Record in match_history so both players see it in recents
          try {
            await _sb.from('match_history').insert({
              'room_id':        room['id'].toString(),
              'winner_id':      winnerId,
              'loser_id':       userId,
              'game_type':      'uno_multiplayer',
              'was_quit':       true,
              'all_player_ids': order,
            });
          } catch (_) {}
        }
      } else {
        // Multiplayer: remove this player
        final newOrder = List<String>.from(order)..remove(userId);
        final Map<String, dynamic> update = {
          'player_order': newOrder,
          'updated_at': DateTime.now().toIso8601String(),
        };
        final currentPlayer = room['current_player_id']?.toString();
        if (currentPlayer == userId && newOrder.isNotEmpty) {
          final idx = order.indexOf(userId);
          update['current_player_id'] = newOrder[idx % newOrder.length];
        }
        await _sb.from('multi_game_rooms').update(update).eq('id', room['id'].toString());
        await _sb.from('multi_player_hands')
            .delete()
            .eq('room_id', room['id'].toString())
            .eq('player_id', userId);
      }
      // Deduct 20 coins for forfeiting
      try {
        await _sb.rpc('deduct_coins', params: {
          'p_user_id': userId,
          'p_amount':  20,
          'p_reason':  'uno_forfeit',
          'p_room_id': room['id'].toString(),
        });
      } catch (_) {}
    } catch (_) {}
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  // ── FIXED: always navigate to a fresh HomeScreen ──
  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── FIXED: PopScope intercepts system back button ──
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _goHome(),
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        body: Stack(children: [
          // Grid
          _GridBg(color: AppColors.isDark(context) ? Colors.white.withOpacity(0.028) : Colors.black.withOpacity(0.05)),
          // Top glow blob
          Positioned(
            top: -120, left: -60,
            child: AnimatedBuilder(
              animation: _glow,
              builder: (_, __) => Container(
                width: 340, height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF7C3AED).withOpacity(0.18 * _glow.value),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80, right: -60,
            child: AnimatedBuilder(
              animation: _glow,
              builder: (_, __) => Container(
                width: 260, height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFE11D48).withOpacity(0.14 * _glow.value),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 18),

                  // ── Header ──
                  Row(children: [
                    // FIXED: back button calls _goHome() instead of Navigator.pop()
                    GestureDetector(
                      onTap: _goHome,
                      child: _GlassIcon(icon: Icons.arrow_back_ios_new_rounded, size: 18),
                    ),
                    const SizedBox(width: 14),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          colors: [Color(0xFF818CF8), Color(0xFFE879F9)],
                        ).createShader(b),
                        child: Text('UNO',
                            style: TextStyle(
                                fontSize: 32, fontWeight: FontWeight.w900,
                                color: Colors.white, letterSpacing: 5)),
                      ),
                      Text('MULTIPLAYER',
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w700,
                              color: Color(0xFF818CF8), letterSpacing: 4)),
                    ]),
                    const Spacer(),
                    _LiveBadge(),
                  ]),

                  const SizedBox(height: 28),

                  // ── Hero card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 24, 20, 24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E1040), Color(0xFF0E1A3A)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: const Color(0xFF7C3AED).withOpacity(0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.2),
                            blurRadius: 40, spreadRadius: 4),
                      ],
                    ),
                    child: Row(children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Battle up to\n7 players\nin real time',
                              style: TextStyle(color: Colors.white, fontSize: 24,
                                  fontWeight: FontWeight.w900, height: 1.2)),
                          const SizedBox(height: 18),
                          _StatPill(emoji: '🏆', label: 'Win', value: '+50', color: const Color(0xFFFFD700)),
                          const SizedBox(height: 8),
                          _StatPill(emoji: '💀', label: 'Last Place', value: '-20', color: const Color(0xFFE11D48)),
                        ],
                      )),
                      const SizedBox(width: 12),
                      // Floating card
                      AnimatedBuilder(
                        animation: _float,
                        builder: (_, __) => Transform.translate(
                          offset: Offset(0, _float.value),
                          child: AnimatedBuilder(
                            animation: _glow,
                            builder: (_, __) => Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 88, height: 88,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(
                                        color: const Color(0xFFE879F9)
                                            .withOpacity(0.45 * _glow.value),
                                        blurRadius: 32, spreadRadius: 8)],
                                  ),
                                ),
                                Text('🃏', style: TextStyle(fontSize: 72)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  // ── Reward strip ──
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border(context)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RewardCell('2–7', 'Players', const Color(0xFF818CF8)),
                        _vLine(),
                        _RewardCell('+50🪙', 'Winner', const Color(0xFFFFD700)),
                        _vLine(),
                        _RewardCell('-20🪙', 'Last', const Color(0xFFE11D48)),
                        _vLine(),
                        _RewardCell('0🪙', 'Others', AppColors.textSecondary(context)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  _sectionLabel('CHOOSE MODE'),
                  const SizedBox(height: 14),

                  // Quick Match
                  _ModeCard(
                    icon: '⚡',
                    title: 'Quick Match',
                    subtitle: 'Instantly matched.\nGame auto-starts 60 s after 2nd player joins.',
                    gradColors: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
                    glow: const Color(0xFFF59E0B),
                    tag: 'AUTO-START',
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.push(context,
                          _route(const UnoMatchmakingScreen()));
                    },
                  ),
                  const SizedBox(height: 12),

                  // Create Room
                  _ModeCard(
                    icon: '🏠',
                    title: 'Create Room',
                    subtitle: 'Private room, share the code.\nYou decide when to start.',
                    gradColors: const [Color(0xFFE11D48), Color(0xFF9333EA)],
                    glow: const Color(0xFFE11D48),
                    tag: 'PRIVATE',
                    loading: _creating,
                    onTap: _createRoom,
                  ),
                  const SizedBox(height: 12),

                  // Join Room
                  _ModeCard(
                    icon: '🔑',
                    title: 'Join Room',
                    subtitle: 'Enter a 6-char code to\njoin a friend\'s private game.',
                    gradColors: const [Color(0xFF7C3AED), Color(0xFF3B82F6)],
                    glow: const Color(0xFF7C3AED),
                    tag: 'BY CODE',
                    onTap: () => _showJoinSheet(),
                  ),

                  const SizedBox(height: 32),

                  // Rules
                  _RulesCard(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Helpers — unchanged ──

  Widget _sectionLabel(String t) => Text(t,
      style: TextStyle(
          color: AppColors.textHint(context), fontSize: 10,
          fontWeight: FontWeight.w800, letterSpacing: 3));

  Widget _vLine() => Container(width: 1, height: 30,
      color: AppColors.border(context));

  PageRoute _route(Widget w) =>
      MaterialPageRoute(builder: (_) => w);

  Future<void> _createRoom() async {
    if (_creating) return;
    setState(() => _creating = true);
    HapticFeedback.mediumImpact();
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) { setState(() => _creating = false); return; }
    try {
      final code = UnoService.generateRoomCode();
      final room = await _sb.from('multi_game_rooms').insert({
        'room_code': code,
        'host_id': uid,
        'player_order': [uid],
        'max_players': 7,
        'min_players': 2,
        'room_type': 'private',
        'status': 'waiting',
      }).select().single();

      await _sb.from('multi_player_hands').insert({
        'room_id': room['id'],
        'player_id': uid,
        'cards': [],
        'seat_index': 0,
      });

      if (!mounted) return;
      Navigator.push(context, _route(UnoWaitingScreen(
        roomId: room['id'].toString(),
        roomCode: code,
        isHost: true,
        isQuickMatch: false,
      )));
    } catch (e) {
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _showJoinSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JoinSheet(
        onJoin: (code) => _joinRoom(code),
      ),
    );
  }

  Future<void> _joinRoom(String code) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await _sb.from('multi_game_rooms')
          .select()
          .eq('room_code', code.toUpperCase())
          .eq('status', 'waiting');

      if (rows.isEmpty) { _snack('Room not found or already started.'); return; }
      final room = rows[0] as Map<String, dynamic>;
      final roomId = room['id'].toString();
      final players = List<String>.from(room['player_order'] ?? []);

      if (players.length >= 7) { _snack('Room is full (7/7)!'); return; }
      if (players.contains(uid)) {
        if (!mounted) return;
        Navigator.push(context, _route(UnoWaitingScreen(
          roomId: roomId,
          roomCode: code.toUpperCase(),
          isHost: room['host_id'].toString() == uid,
          isQuickMatch: room['room_type'] == 'quick',
        )));
        return;
      }

      players.add(uid);

      // Best-effort update of player_order (may be blocked by RLS for non-hosts).
      // The waiting screen uses multi_player_hands as source of truth instead.
      _sb.from('multi_game_rooms').update({
        'player_order': players,
      }).eq('id', roomId).catchError((_) {});

      // Upsert hand row (safe to call even if one exists)
      await _sb.from('multi_player_hands').upsert({
        'room_id': roomId,
        'player_id': uid,
        'cards': [],
        'seat_index': players.length - 1,
      }, onConflict: 'room_id,player_id');

      if (!mounted) return;
      Navigator.push(context, _route(UnoWaitingScreen(
        roomId: roomId,
        roomCode: code.toUpperCase(),
        isHost: false,
        isQuickMatch: room['room_type'] == 'quick',
      )));
    } catch (e) {
      _snack('Error joining: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF1C1F2E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }
}

// ──────────────────────────────────────────────────────
//  REUSABLE WIDGETS — all unchanged
// ──────────────────────────────────────────────────────

class _GridBg extends StatelessWidget {
  final Color color;
  const _GridBg({required this.color});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _GridPainter(color: color));
}

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 0.6;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  const _GlassIcon({required this.icon, this.size = 20});
  @override
  Widget build(BuildContext context) => Container(
    width: 42, height: 42,
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border(context)),
    ),
    child: Icon(icon, color: AppColors.icon(context), size: size),
  );
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFE11D48).withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE11D48).withOpacity(0.5)),
    ),
    child: Row(children: [
      Container(width: 6, height: 6,
          decoration: BoxDecoration(
              color: Color(0xFFE11D48), shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text('LIVE',
          style: TextStyle(color: Color(0xFFE11D48), fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 1.5)),
    ]),
  );
}

class _StatPill extends StatelessWidget {
  final String emoji, label, value;
  final Color color;
  const _StatPill({required this.emoji, required this.label,
      required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(emoji, style: TextStyle(fontSize: 13)),
    const SizedBox(width: 6),
    Text(value, style: TextStyle(
        color: color, fontSize: 14, fontWeight: FontWeight.w800)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(
        color: Colors.white38, fontSize: 12)),
  ]);
}

class _RewardCell extends StatelessWidget {
  final String value, label;
  final Color color;
  const _RewardCell(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(
        color: color, fontSize: 13, fontWeight: FontWeight.w800)),
    const SizedBox(height: 3),
    Text(label, style: TextStyle(color: AppColors.textHint(context), fontSize: 10)),
  ]);
}

// ── Mode Card ──────────────────────────────────────

class _ModeCard extends StatefulWidget {
  final String icon, title, subtitle, tag;
  final List<Color> gradColors;
  final Color glow;
  final bool loading;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon, required this.title, required this.subtitle,
    required this.gradColors, required this.glow, required this.tag,
    this.loading = false, required this.onTap,
  });

  @override State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) { setState(() => _down = false); if (!widget.loading) widget.onTap(); },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.965 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: _down
                    ? widget.glow.withOpacity(0.55)
                    : widget.glow.withOpacity(0.22),
                width: 1.5),
            boxShadow: [BoxShadow(
                color: widget.glow.withOpacity(_down ? 0.18 : 0.07),
                blurRadius: 24, spreadRadius: 2)],
          ),
          child: Row(children: [
            // Icon blob
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: widget.gradColors,
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                    color: widget.glow.withOpacity(0.45), blurRadius: 14)],
              ),
              child: widget.loading
                  ? Center(child: SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5)))
                  : Center(child: Text(widget.icon,
                      style: TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 16),
            // Text
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(widget.title,
                      style: TextStyle(color: AppColors.text(context),
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.glow.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: widget.glow.withOpacity(0.35)),
                    ),
                    child: Text(widget.tag,
                        style: TextStyle(color: widget.glow, fontSize: 8,
                            fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ]),
                const SizedBox(height: 5),
                Text(widget.subtitle,
                    style: TextStyle(
                        color: AppColors.textSecondary(context), fontSize: 12, height: 1.45)),
              ],
            )),
            Icon(Icons.chevron_right_rounded,
                color: widget.glow.withOpacity(0.5), size: 22),
          ]),
        ),
      ),
    );
  }
}

// ── Rules Card ─────────────────────────────────────

class _RulesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('📖', style: TextStyle(fontSize: 17)),
          SizedBox(width: 8),
          Text('How to Play', style: TextStyle(
              color: AppColors.text(context), fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        _rule(context, 'Match the top card by colour or number', const Color(0xFF818CF8)),
        _rule(context, 'Skip, Reverse, +2 are action cards', const Color(0xFFF59E0B)),
        _rule(context, 'Wild & Wild +4 — you pick the colour', const Color(0xFF34D399)),
        _rule(context, 'Shout UNO when down to 1 card!', const Color(0xFFE11D48)),
        _rule(context, 'Empty your hand first to win', const Color(0xFFFFD700)),
        _rule(context, 'Reverse = Skip in a 2-player game', AppColors.textHint(context)),
      ]),
    );
  }

  Widget _rule(BuildContext context, String t, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(children: [
      Container(width: 6, height: 6,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(child: Text(t,
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13))),
    ]),
  );
}

// ── Join Sheet ─────────────────────────────────────

class _JoinSheet extends StatefulWidget {
  final Function(String) onJoin;
  const _JoinSheet({required this.onJoin});
  @override State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      child: Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 32),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 38, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border(context), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 22),
          Text('🔑  Join a Room',
              style: TextStyle(color: AppColors.text(context), fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Enter the 6-character room code',
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141828),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4), width: 1.5),
            ),
            child: TextField(
              controller: _ctrl,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 28,
                  fontWeight: FontWeight.w900, letterSpacing: 8),
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: TextStyle(color: Color(0xFF252840),
                    fontSize: 28, letterSpacing: 8),
                border: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                backgroundColor: const Color(0xFF7C3AED),
                disabledBackgroundColor: Colors.white10,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Join Room  🚀',
                      style: TextStyle(color: AppColors.text(context),
                          fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }
}