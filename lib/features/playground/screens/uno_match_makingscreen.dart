import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/uno_services.dart';
import '../models/uno_card.dart';
import 'uno_waiting_screen.dart';

final _sb = Supabase.instance.client;

// ══════════════════════════════════════════════════════
//  UNO MATCHMAKING SCREEN  (Quick Match flow)
//
//  1. Calls find_public_multi_match RPC → joins or creates a room
//  2. AUTO-navigates to WaitingScreen immediately after RPC returns
//     (no manual "Go to Waiting Room" button needed)
//  3. isHost = true only if the RPC created a NEW room
// ══════════════════════════════════════════════════════

class UnoMatchmakingScreen extends StatefulWidget {
  const UnoMatchmakingScreen({Key? key}) : super(key: key);
  @override
  State<UnoMatchmakingScreen> createState() =>
      _UnoMatchmakingScreenState();
}

class _UnoMatchmakingScreenState extends State<UnoMatchmakingScreen>
    with TickerProviderStateMixin {

  bool _searching = true;
  bool _hasError = false;
  String _errorMsg = '';
  bool _navigated = false;

  // Animations
  late final AnimationController _radarCtrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();
  late final AnimationController _pulseCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
  late final Animation<double> _pulse =
      Tween<double>(begin: 0.88, end: 1.12).animate(
          CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _findMatch();
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _findMatch() async {
    setState(() { _searching = true; _hasError = false; });

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      setState(() { _searching = false; _hasError = true; _errorMsg = 'Not logged in.'; });
      return;
    }

    try {
      // Clean up any stale hand rows from previous sessions before finding a match
      try {
        final staleHands = await _sb
            .from('multi_player_hands')
            .select('room_id')
            .eq('player_id', uid);
        for (final row in staleHands) {
          final rId = row['room_id']?.toString();
          if (rId == null) continue;
          final room = await _sb
              .from('multi_game_rooms')
              .select('status')
              .eq('id', rId)
              .maybeSingle();
          // If room no longer exists or is not waiting, remove stale hand
          if (room == null || room['status'] != 'waiting') {
            await _sb.from('multi_player_hands')
                .delete()
                .eq('room_id', rId)
                .eq('player_id', uid);
          }
        }
      } catch (_) {}

      final result = await _sb.rpc('find_public_multi_match', params: {
        'p_user_id': uid,
      });

      if (!mounted || _navigated) return;

      if (result == null || (result is List && result.isEmpty)) {
        setState(() {
          _searching = false;
          _hasError = true;
          _errorMsg = 'No rooms available. Try again.';
        });
        return;
      }

      final data = result is List ? result[0] : result;
      final roomId = data['v_room_id']?.toString();
      final roomCode = data['v_room_code']?.toString();
      final isNew = data['v_is_new'] == true;

      if (roomId == null || roomCode == null) {
        setState(() {
          _searching = false;
          _hasError = true;
          _errorMsg = 'Invalid room data. Try again.';
        });
        return;
      }

      // Auto-navigate immediately — no manual button needed
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UnoWaitingScreen(
              roomId: roomId,
              roomCode: roomCode,
              isHost: isNew,        // only the creator is host
              isQuickMatch: true,
            ),
          ),
        );
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hasError = true;
        _errorMsg = e.toString();
      });
    }
  }

  Future<void> _cancel() async {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: Stack(children: [
          const _GridBg(),

          // Ambient glow
          Positioned(
            top: -100, left: 0, right: 0,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF59E0B).withOpacity(0.09),
                    Colors.transparent,
                  ],
                  radius: 0.7,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(children: [
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Row(children: [
                  GestureDetector(
                    onTap: _cancel,
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quick Match',
                          style: TextStyle(color: Colors.white,
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      Text('⚡ Searching for opponents',
                          style: TextStyle(color: Colors.white38,
                              fontSize: 12)),
                    ],
                  ),
                ]),
              ),

              // ── Content ──
              Expanded(
                child: Center(
                  child: _hasError
                      ? _buildError()
                      : _buildSearching(),
                ),
              ),

              // ── Cancel ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                child: SizedBox(
                  width: double.infinity, height: 52,
                  child: OutlinedButton(
                    onPressed: _cancel,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.white.withOpacity(0.14)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white38,
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildSearching() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Radar rings
      SizedBox(
        width: 220, height: 220,
        child: Stack(alignment: Alignment.center, children: [
          ...List.generate(3, (i) => AnimatedBuilder(
            animation: _radarCtrl,
            builder: (_, __) {
              final v = ((_radarCtrl.value + i / 3.0) % 1.0);
              return Container(
                width: 60 + v * 160,
                height: 60 + v * 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFF59E0B)
                        .withOpacity((1 - v) * 0.35),
                    width: 1.5,
                  ),
                ),
              );
            },
          )),
          // Core
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Transform.scale(
              scale: _pulse.value,
              child: Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                  border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.5),
                      width: 2),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFFF59E0B).withOpacity(0.25),
                      blurRadius: 24, spreadRadius: 6)],
                ),
                child: const Center(
                    child: Text('🃏', style: TextStyle(fontSize: 38))),
              ),
            ),
          ),
        ]),
      ),

      const SizedBox(height: 28),
      const Text('Finding a match…',
          style: TextStyle(color: Colors.white, fontSize: 24,
              fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Connecting you to a room',
          style: TextStyle(color: Colors.white38, fontSize: 14)),

      const SizedBox(height: 28),

      // Animated dots
      Row(mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) => AnimatedBuilder(
          animation: _radarCtrl,
          builder: (_, __) {
            final phase = ((_radarCtrl.value * 3 - i) % 1.0).abs();
            return Container(
              width: 10, height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B)
                    .withOpacity((1 - phase).clamp(0.2, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          },
        )),
      ),
    ]);
  }

  Widget _buildError() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('❌', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      const Text('Could not find a match',
          style: TextStyle(color: Colors.white, fontSize: 20,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(_errorMsg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 13)),
      ),
      const SizedBox(height: 28),
      ElevatedButton(
        onPressed: _findMatch,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF59E0B),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: const Text('Try Again',
            style: TextStyle(color: Color(0xFF1C1000),
                fontSize: 15, fontWeight: FontWeight.w800)),
      ),
    ]);
  }
}

// ── Shared background ──────────────────────────────

class _GridBg extends StatelessWidget {
  const _GridBg();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.028)
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