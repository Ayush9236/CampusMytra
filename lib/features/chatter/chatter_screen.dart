import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';
import '../buzz/notification_service.dart';
import '../profile/user_profile_screen.dart';
import 'group_chat_screen.dart';

final _sb = Supabase.instance.client;

const _indigo = Color(0xFF818CF8);
const _pink   = Color(0xFFE879F9);
const _green  = Color(0xFF4ADE80);
const _ghost  = Color(0xFF94A3B8);

const _kReactions = ['❤️', '😂', '😮', '😢', '😡', '👍'];

// ═══════════════════════════════════════════════════════════
// BACKGROUND ANIMATION SYSTEM
// ═══════════════════════════════════════════════════════════

class _AuroraWave {
  double phase, amplitude, frequency, speed, yBase, opacity;
  Color color;
  _AuroraWave({required this.phase, required this.amplitude,
    required this.frequency, required this.speed, required this.yBase,
    required this.color, required this.opacity});
}

class _Star {
  double x, y, radius, twinklePhase, twinkleSpeed, opacity;
  _Star({required this.x, required this.y, required this.radius,
    required this.twinklePhase, required this.twinkleSpeed, required this.opacity});
}

class _ConstellationLine {
  int a, b;
  double opacity;
  _ConstellationLine(this.a, this.b, this.opacity);
}

class _Ripple {
  double x, y, radius, maxRadius, opacity;
  Color color;
  _Ripple({required this.x, required this.y, required this.maxRadius,
    required this.color}) : radius = 0, opacity = 0.6;
}

class _Orb {
  double x, y, vx, vy, radius, opacity, phase;
  Color color;
  _Orb({required this.x, required this.y, required this.vx, required this.vy,
    required this.radius, required this.opacity, required this.color, required this.phase});
}

// ═══════════════════════════════════════════════════════════
// COSMIC BACKGROUND WIDGET
// ═══════════════════════════════════════════════════════════
class _CosmicBackground extends StatefulWidget {
  final Widget child;
  const _CosmicBackground({required this.child});
  @override
  State<_CosmicBackground> createState() => _CosmicBackgroundState();
}

class _CosmicBackgroundState extends State<_CosmicBackground>
    with TickerProviderStateMixin {
  late AnimationController _mainCtrl;
  final _rng = Random();
  Size _size = Size.zero;
  final List<_AuroraWave> _waves = [];
  final List<_Star> _stars = [];
  final List<_ConstellationLine> _lines = [];
  final List<_Ripple> _ripples = [];
  final List<_Orb> _orbs = [];
  double _time = 0;
  bool _initialized = false;

  static const _starCount = 55;
  static const _orbCount  = 5;
  static const _waveCount = 4;
  static const _palette = [
    Color(0xFF818CF8), Color(0xFFE879F9),
    Color(0xFF38BDF8), Color(0xFFA78BFA), Color(0xFF34D399),
  ];

  @override
  void initState() {
    super.initState();
    _mainCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 16),
    )..addListener(_tick)..repeat();
  }

  void _init() {
    if (_initialized || _size == Size.zero) return;
    _initialized = true;

    final waveColors = [
      const Color(0xFF6366F1), const Color(0xFFEC4899),
      const Color(0xFF8B5CF6), const Color(0xFF06B6D4),
    ];
    for (int i = 0; i < _waveCount; i++) {
      _waves.add(_AuroraWave(
        phase:     _rng.nextDouble() * pi * 2,
        amplitude: 30 + _rng.nextDouble() * 50,
        frequency: 0.003 + _rng.nextDouble() * 0.004,
        speed:     0.008 + _rng.nextDouble() * 0.012,
        yBase:     _size.height * (0.45 + i * 0.14),
        color:     waveColors[i % waveColors.length],
        opacity:   0.06 + _rng.nextDouble() * 0.07,
      ));
    }

    for (int i = 0; i < _starCount; i++) {
      _stars.add(_Star(
        x:            _rng.nextDouble() * _size.width,
        y:            _rng.nextDouble() * _size.height * 0.75,
        radius:       0.8 + _rng.nextDouble() * 2.2,
        twinklePhase: _rng.nextDouble() * pi * 2,
        twinkleSpeed: 0.02 + _rng.nextDouble() * 0.04,
        opacity:      0.3 + _rng.nextDouble() * 0.7,
      ));
    }

    for (int i = 0; i < _stars.length; i++) {
      for (int j = i + 1; j < _stars.length; j++) {
        final dx = _stars[i].x - _stars[j].x;
        final dy = _stars[i].y - _stars[j].y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < 90 && _rng.nextDouble() < 0.3) {
          _lines.add(_ConstellationLine(i, j, 0.06 + _rng.nextDouble() * 0.08));
        }
      }
    }

    for (int i = 0; i < _orbCount; i++) {
      _orbs.add(_Orb(
        x:       _rng.nextDouble() * _size.width,
        y:       _rng.nextDouble() * _size.height,
        vx:      (_rng.nextDouble() - 0.5) * 0.4,
        vy:      (_rng.nextDouble() - 0.5) * 0.3,
        radius:  80 + _rng.nextDouble() * 120,
        opacity: 0.04 + _rng.nextDouble() * 0.06,
        color:   _palette[i % _palette.length],
        phase:   _rng.nextDouble() * pi * 2,
      ));
    }
  }

  void _tick() {
    if (!mounted) return;
    _init();
    _time += 0.016;

    for (final w in _waves) { w.phase += w.speed; }
    for (final s in _stars)  { s.twinklePhase += s.twinkleSpeed; }

    for (final o in _orbs) {
      o.phase += 0.008;
      o.x += o.vx + sin(o.phase) * 0.3;
      o.y += o.vy + cos(o.phase * 0.7) * 0.2;
      if (o.x < -o.radius) o.x = _size.width + o.radius;
      if (o.x > _size.width + o.radius) o.x = -o.radius;
      if (o.y < -o.radius) o.y = _size.height + o.radius;
      if (o.y > _size.height + o.radius) o.y = -o.radius;
    }

    for (final r in _ripples) {
      r.radius += 6;
      r.opacity = (1.0 - r.radius / r.maxRadius).clamp(0, 1) * 0.5;
    }
    _ripples.removeWhere((r) => r.radius >= r.maxRadius);

    setState(() {});
  }

  void triggerBurst(double x, double y) {
    HapticFeedback.mediumImpact();
    for (int i = 0; i < 3; i++) {
      final color = _palette[_rng.nextInt(_palette.length)];
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (mounted) {
          _ripples.add(_Ripple(x: x, y: y,
            maxRadius: 120.0 + i * 60, color: color));
        }
      });
    }
    for (int i = 0; i < 3; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 0.8 + _rng.nextDouble() * 1.2;
      _orbs.add(_Orb(
        x: x, y: y,
        vx: cos(angle) * speed, vy: sin(angle) * speed,
        radius: 40 + _rng.nextDouble() * 60,
        opacity: 0.18 + _rng.nextDouble() * 0.15,
        color: _palette[_rng.nextInt(_palette.length)],
        phase: _rng.nextDouble() * pi * 2,
      ));
    }
    while (_orbs.length > _orbCount + 6) { _orbs.removeAt(0); }
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return LayoutBuilder(builder: (ctx, constraints) {
      _size = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        onLongPressStart: (d) => triggerBurst(d.localPosition.dx, d.localPosition.dy),
        behavior: HitTestBehavior.translucent,
        child: Stack(children: [
          Positioned.fill(child: Container(
            decoration: BoxDecoration(
              gradient: isDark
                ? const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF050714), Color(0xFF0A0D1F), Color(0xFF080B18)],
                    stops: [0.0, 0.5, 1.0])
                : const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFF0F0FF), Color(0xFFEEF2FF), Color(0xFFF5F0FF)]),
            ))),
          Positioned.fill(child: CustomPaint(
            painter: _CosmicPainter(
              waves: _waves, stars: _stars, lines: _lines,
              ripples: _ripples, orbs: _orbs, time: _time, isDark: isDark))),
          widget.child,
        ]),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════
// COSMIC PAINTER
// ═══════════════════════════════════════════════════════════
class _CosmicPainter extends CustomPainter {
  final List<_AuroraWave> waves;
  final List<_Star> stars;
  final List<_ConstellationLine> lines;
  final List<_Ripple> ripples;
  final List<_Orb> orbs;
  final double time;
  final bool isDark;

  _CosmicPainter({required this.waves, required this.stars, required this.lines,
    required this.ripples, required this.orbs, required this.time, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    _drawOrbs(canvas);
    _drawAurora(canvas, size);
    _drawConstellations(canvas);
    _drawStars(canvas);
    _drawRipples(canvas);
  }

  void _drawOrbs(Canvas canvas) {
    for (final o in orbs) {
      canvas.drawCircle(
        Offset(o.x, o.y), o.radius,
        Paint()
          ..color = o.color.withOpacity(o.opacity.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, o.radius * 0.7));
    }
  }

  void _drawAurora(Canvas canvas, Size size) {
    for (final w in waves) {
      final path = Path();
      path.moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 3) {
        final y = w.yBase
          + sin(x * w.frequency + w.phase) * w.amplitude
          + sin(x * w.frequency * 2.3 + w.phase * 1.7) * (w.amplitude * 0.4);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [w.color.withOpacity(w.opacity), w.color.withOpacity(0)],
        ).createShader(Rect.fromLTWH(0, w.yBase - w.amplitude, size.width, w.amplitude * 3))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    }
  }

  void _drawConstellations(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (final l in lines) {
      final a = stars[l.a]; final b = stars[l.b];
      final twinkle = (sin(a.twinklePhase) + 1) / 2;
      paint.color = const Color(0xFF818CF8)
          .withOpacity((l.opacity * (0.5 + twinkle * 0.5)).clamp(0, 1));
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
    }
  }

  void _drawStars(Canvas canvas) {
    for (final s in stars) {
      final twinkle = (sin(s.twinklePhase) + 1) / 2;
      final op = (s.opacity * (0.4 + twinkle * 0.6)).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(s.x, s.y), s.radius * 1.5,
        Paint()
          ..color = const Color(0xFFE0E7FF).withOpacity(op * 0.3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.radius * 2.5));
      canvas.drawCircle(Offset(s.x, s.y), s.radius,
        Paint()..color = Color.lerp(
          const Color(0xFFE0E7FF), const Color(0xFFE879F9), twinkle * 0.3)!.withOpacity(op));
      if (s.radius > 1.8 && twinkle > 0.7) {
        final sp = Paint()
          ..color = Colors.white.withOpacity(op * 0.6)
          ..strokeWidth = 0.8..style = PaintingStyle.stroke;
        final len = s.radius * 3;
        canvas.drawLine(Offset(s.x - len, s.y), Offset(s.x + len, s.y), sp);
        canvas.drawLine(Offset(s.x, s.y - len), Offset(s.x, s.y + len), sp);
      }
    }
  }

  void _drawRipples(Canvas canvas) {
    for (final r in ripples) {
      canvas.drawCircle(Offset(r.x, r.y), r.radius,
        Paint()
          ..color = r.color.withOpacity(r.opacity.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(Offset(r.x, r.y), r.radius * 0.6,
        Paint()
          ..color = r.color.withOpacity((r.opacity * 0.15).clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    }
  }

  @override
  bool shouldRepaint(_CosmicPainter old) => true;
}

// ─────────────────────────────────────────────────────────
// CHATTER SCREEN — Inbox (UNCHANGED)
// ─────────────────────────────────────────────────────────
class ChatterScreen extends StatefulWidget {
  const ChatterScreen({Key? key}) : super(key: key);
  @override
  State<ChatterScreen> createState() => _ChatterScreenState();
}

class _ChatterScreenState extends State<ChatterScreen>
    with SingleTickerProviderStateMixin {
  final _myId = _sb.auth.currentUser?.id;
  List<Map<String, dynamic>> _inbox  = [];
  List<Map<String, dynamic>> _groups = [];
  bool _loading       = true;
  bool _loadingGroups = true;
  late TabController _tabCtrl;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadInbox();
    _loadGroups();
    _updateLastSeen();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) _loadInbox(silent: true);
        if (mounted) _loadGroups(silent: true);
      });
  }

  @override
  void dispose() { _tabCtrl.dispose(); _pollTimer?.cancel(); super.dispose(); }

  Future<void> _updateLastSeen() async {
    if (_myId == null) return;
    try {
      await _sb.from('profiles')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', _myId!);
    } catch (_) {}
  }

  Future<void> _loadInbox({bool silent = false}) async {
    if (_myId == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final data = await _sb.rpc('get_my_inbox', params: {'p_user_id': _myId});
      if (mounted) setState(() {
        _inbox = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadGroups({bool silent = false}) async {
    if (_myId == null) return;
    if (!silent) setState(() => _loadingGroups = true);
    try {
      final data = await _sb.rpc('get_my_groups', params: {'p_user_id': _myId});
      if (mounted) setState(() {
        _groups = List<Map<String, dynamic>>.from(data as List);
        _loadingGroups = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingGroups = false);
    }
  }

  bool _isOnline(dynamic raw) {
    if (raw == null) return false;
    final t = DateTime.tryParse(raw.toString())?.toLocal();
    return t != null && DateTime.now().difference(t).inMinutes < 5;
  }

  String _onlineLabel(dynamic raw) {
    if (raw == null) return 'offline';
    final t = DateTime.tryParse(raw.toString())?.toLocal();
    if (t == null) return 'offline';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 5)  return 'online';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _timeAgo(String? raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1)  return 'now';
    if (diff.inHours < 1)    return '${diff.inMinutes}m';
    if (diff.inDays < 1)     return '${diff.inHours}h';
    if (diff.inDays == 1)    return 'Yesterday';
    return '${d.day}/${d.month}';
  }

  void _openChat(Map<String, dynamic> conv) {
    setState(() {
      final idx = _inbox.indexWhere(
        (c) => c['conversation_id'] == conv['conversation_id']);
      if (idx != -1) _inbox[idx] = {..._inbox[idx], 'unread_count': 0};
    });
    final myId = _sb.auth.currentUser?.id;
    if (myId != null) {
      _sb.rpc('mark_messages_read', params: {
        'p_conversation_id': conv['conversation_id'].toString(),
        'p_reader_id': myId,
      }).then((_) {}).catchError((_) {
        _sb.from('messages')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('conversation_id', conv['conversation_id'].toString())
            .neq('sender_id', myId).isFilter('read_at', null).then((_) {});
      });
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(
        conversationId: conv['conversation_id'].toString(),
        otherUserId:    conv['other_user_id'].toString(),
        otherName:      conv['other_name']?.toString() ?? 'Unknown',
        otherEmoji:     conv['other_emoji']?.toString() ?? '🎓',
        otherLastSeen:  conv['other_last_seen'],
      ),
    )).then((_) => _loadInbox(silent: true));
  }

  String _timeAgoGroup(String? raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1)  return 'now';
    if (diff.inHours < 1)    return '${diff.inMinutes}m';
    if (diff.inDays < 1)     return '${diff.inHours}h';
    if (diff.inDays == 1)    return 'Yesterday';
    return '${d.day}/${d.month}';
  }

  void _openGroup(Map<String, dynamic> g) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => GroupChatScreen(
        conversationId: g['conversation_id'].toString(),
        groupName:      g['group_name']?.toString() ?? 'Group',
        groupEmoji:     g['group_emoji']?.toString() ?? '👥',
        memberCount:    (g['member_count'] as num?)?.toInt() ?? 0,
      ))).then((_) => _loadGroups(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);
    final surface   = AppColors.surface(context);
    final border    = AppColors.border(context);
    final bg        = AppColors.background(context);

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: AnimatedBuilder(
        animation: _tabCtrl,
        builder: (_, __) => _tabCtrl.index == 1
          ? FloatingActionButton(
              onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()))
                  .then((_) => _loadGroups(silent: true)),
              backgroundColor: _indigo,
              child: const Icon(Icons.group_add_rounded, color: Colors.white))
          : const SizedBox.shrink()),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [_indigo, _pink]).createShader(b),
                child: const Text('Chatter', style: TextStyle(fontSize: 30,
                  fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.2))),
              const SizedBox(height: 2),
              Row(children: [
                const Text('👻', style: TextStyle(fontSize: 10)),
                const SizedBox(width: 4),
                Text('ghost mode · messages vanish after reading',
                  style: TextStyle(fontSize: 10, color: subColor,
                    letterSpacing: 0.5, fontWeight: FontWeight.w500)),
              ]),
            ])),
            GestureDetector(
              onTap: () { _loadInbox(); _loadGroups(); },
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [_indigo.withOpacity(0.15), _pink.withOpacity(0.15)]),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border)),
                child: Icon(Icons.refresh_rounded, color: subColor, size: 18))),
          ])),
        // Tab bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border)),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                gradient: const LinearGradient(colors: [_indigo, _pink]),
                borderRadius: BorderRadius.circular(10)),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              labelColor: Colors.white,
              unselectedLabelColor: subColor,
              tabs: const [
                Tab(text: '💬  Messages'),
                Tab(text: '👥  Groups'),
              ]))),
        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [
            // ── DMs Tab ──────────────────────────────────────────
            Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _ghost.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _ghost.withOpacity(0.2))),
                  child: Row(children: [
                    const Text('👻', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Messages auto-delete after reading. Long-press to save.',
                      style: TextStyle(color: subColor, fontSize: 11, fontWeight: FontWeight.w500))),
                  ]))),
              Expanded(child: _loading
                ? Center(child: CircularProgressIndicator(color: _indigo, strokeWidth: 2))
                : _inbox.isEmpty
                  ? _EmptyInbox()
                  : RefreshIndicator(
                      onRefresh: _loadInbox, color: _indigo,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        itemCount: _inbox.length,
                        itemBuilder: (_, i) {
                          final c       = _inbox[i];
                          final unread  = (c['unread_count'] as num?)?.toInt() ?? 0;
                          final online  = _isOnline(c['other_last_seen']);
                          final label   = _onlineLabel(c['other_last_seen']);
                          final preview = c['last_message']?.toString() ?? '';
                          final timeAgo = _timeAgo(c['last_message_at']?.toString());
                          return GestureDetector(
                            onTap: () => _openChat(c),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: surface, borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: unread > 0 ? _indigo.withOpacity(0.4) : border,
                                  width: unread > 0 ? 1.5 : 1),
                                boxShadow: [BoxShadow(
                                  color: unread > 0 ? _indigo.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                                  blurRadius: 12, offset: const Offset(0, 3))]),
                              child: Row(children: [
                                Stack(children: [
                                  Container(
                                    width: 52, height: 52,
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(colors: [_indigo.withOpacity(0.3), _indigo.withOpacity(0.08)]),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: _indigo.withOpacity(0.3), width: 1.5)),
                                    child: Center(child: Text(c['other_emoji']?.toString() ?? '🎓',
                                      style: const TextStyle(fontSize: 26)))),
                                  if (online) Positioned(right: 1, bottom: 1,
                                    child: Container(width: 13, height: 13,
                                      decoration: BoxDecoration(color: _green, shape: BoxShape.circle,
                                        border: Border.all(color: surface, width: 2)))),
                                ]),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(c['other_name']?.toString() ?? 'Unknown',
                                      style: TextStyle(color: textColor,
                                        fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.w700,
                                        fontSize: 15), overflow: TextOverflow.ellipsis)),
                                    Text(timeAgo, style: TextStyle(
                                      color: unread > 0 ? _indigo : subColor, fontSize: 11,
                                      fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400)),
                                  ]),
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 5),
                                      decoration: BoxDecoration(
                                        color: online ? _green : subColor.withOpacity(0.3),
                                        shape: BoxShape.circle)),
                                    Text(online ? 'online' : label,
                                      style: TextStyle(color: online ? _green : subColor,
                                        fontSize: 10, fontWeight: FontWeight.w600)),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text(preview.isEmpty ? 'Start chatting 👻' : preview,
                                    style: TextStyle(
                                      color: unread > 0 ? textColor : subColor, fontSize: 12,
                                      fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                ])),
                                if (unread > 0) Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [_indigo, _pink]),
                                    borderRadius: BorderRadius.circular(12)),
                                  child: Text('$unread', style: const TextStyle(
                                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
                              ])));
                        }))),
            ]),

            // ── Groups Tab ────────────────────────────────────────
            _loadingGroups
              ? Center(child: CircularProgressIndicator(color: _indigo, strokeWidth: 2))
              : _groups.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_indigo, _pink],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(24)),
                      child: const Center(child: Text('👥', style: TextStyle(fontSize: 36)))),
                    const SizedBox(height: 16),
                    Text('No groups yet', style: TextStyle(
                      color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('Tap + to create your first group', style: TextStyle(
                      color: subColor, fontSize: 13)),
                  ]))
                : RefreshIndicator(
                    onRefresh: _loadGroups, color: _indigo,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      itemCount: _groups.length,
                      itemBuilder: (_, i) {
                        final g       = _groups[i];
                        final unread  = (g['unread_count'] as num?)?.toInt() ?? 0;
                        final members = (g['member_count'] as num?)?.toInt() ?? 0;
                        final preview = g['last_message']?.toString() ?? '';
                        final timeAgo = _timeAgoGroup(g['last_message_at']?.toString());
                        return GestureDetector(
                          onTap: () => _openGroup(g),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: surface, borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: unread > 0 ? _indigo.withOpacity(0.4) : border,
                                width: unread > 0 ? 1.5 : 1),
                              boxShadow: [BoxShadow(
                                color: unread > 0 ? _indigo.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                                blurRadius: 12, offset: const Offset(0, 3))]),
                            child: Row(children: [
                              Container(
                                width: 52, height: 52,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [_indigo, _pink],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(16)),
                                child: Center(child: Text(g['group_emoji']?.toString() ?? '👥',
                                  style: const TextStyle(fontSize: 26)))),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(g['group_name']?.toString() ?? 'Group',
                                    style: TextStyle(color: textColor,
                                      fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.w700,
                                      fontSize: 15), overflow: TextOverflow.ellipsis)),
                                  Text(timeAgo, style: TextStyle(
                                    color: unread > 0 ? _indigo : subColor, fontSize: 11,
                                    fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400)),
                                ]),
                                const SizedBox(height: 2),
                                Text('$members members', style: TextStyle(
                                  color: subColor, fontSize: 10, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(preview.isEmpty ? 'No messages yet' : preview,
                                  style: TextStyle(
                                    color: unread > 0 ? textColor : subColor, fontSize: 12,
                                    fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              ])),
                              if (unread > 0) Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [_indigo, _pink]),
                                  borderRadius: BorderRadius.circular(12)),
                                child: Text('$unread', style: const TextStyle(
                                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
                            ])));
                      })),
          ])),
      ])),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_indigo, _pink],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: _indigo.withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 8))]),
        child: const Center(child: Text('👻', style: TextStyle(fontSize: 44)))),
      const SizedBox(height: 20),
      Text('no chats yet', style: TextStyle(color: AppColors.text(context),
        fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      const SizedBox(height: 6),
      Text("go to a friend's profile\nand tap Message",
        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
        textAlign: TextAlign.center),
    ]));
}

// ─────────────────────────────────────────────────────────
// CHAT SCREEN
// ─────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String conversationId, otherUserId, otherName, otherEmoji;
  final dynamic otherLastSeen;
  const ChatScreen({Key? key, required this.conversationId, required this.otherUserId,
    required this.otherName, required this.otherEmoji, required this.otherLastSeen}) : super(key: key);
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _myId       = _sb.auth.currentUser?.id;
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true, _sending = false;
  bool _otherTyping = false;
  RealtimeChannel? _channel;
  RealtimeChannel? _typingChannel;
  Timer? _pollTimer, _lastSeenTimer, _typingTimer, _typingClearTimer;
  dynamic _otherLastSeen;

  @override
  void initState() {
    super.initState();
    _otherLastSeen = widget.otherLastSeen;
    _loadMessages(); _subscribeRealtime(); _subscribeTyping();
    _updateLastSeen(); _refreshOtherLastSeen();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) { _silentRefresh(); _refreshOtherLastSeen(); }
    });
    _lastSeenTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _updateLastSeen();
    });
    _msgCtrl.addListener(_onTypingChanged);
  }

  void _subscribeTyping() {
    _typingChannel = _sb
        .channel('typing_${widget.conversationId}')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            if (!mounted) return;
            final sender = payload['user_id']?.toString();
            if (sender != null && sender != _myId) {
              setState(() => _otherTyping = true);
              _typingClearTimer?.cancel();
              _typingClearTimer = Timer(const Duration(seconds: 3), () {
                if (mounted) setState(() => _otherTyping = false);
              });
            }
          })
        .subscribe();
  }

  void _onTypingChanged() {
    if (_msgCtrl.text.isEmpty) return;
    // Broadcast at most once per second
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 800), () {
      _typingChannel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': _myId ?? ''},
      );
    });
  }

  Future<void> _updateLastSeen() async {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;
    try { await _sb.from('profiles')
        .update({'last_seen': DateTime.now().toUtc().toIso8601String()}).eq('id', myId);
    } catch (_) {}
  }

  Future<void> _refreshOtherLastSeen() async {
    try {
      final row = await _sb.from('profiles').select('last_seen')
          .eq('id', widget.otherUserId).maybeSingle();
      if (row != null && mounted) setState(() => _otherLastSeen = row['last_seen']);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel(); _lastSeenTimer?.cancel();
    _typingTimer?.cancel(); _typingClearTimer?.cancel();
    _channel?.unsubscribe(); _typingChannel?.unsubscribe();
    _msgCtrl.removeListener(_onTypingChanged);
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = _sb.channel('chat_${widget.conversationId}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert, schema: 'public', table: 'messages',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
          column: 'conversation_id', value: widget.conversationId),
        callback: (payload) async {
          if (!mounted) return;
          final m = payload.newRecord;
          final reactions = await _fetchReactions(m['id'].toString());
          setState(() => _messages.add({...m, 'reactions': reactions}));
          _scrollToBottom();
          if (m['sender_id'] != _myId) _markRead(m['id'].toString());
        })
      .onPostgresChanges(
        event: PostgresChangeEvent.update, schema: 'public', table: 'messages',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
          column: 'conversation_id', value: widget.conversationId),
        callback: (payload) {
          if (!mounted) return;
          final updated = payload.newRecord;
          if (updated['deleted_at'] != null) {
            setState(() => _messages.removeWhere((m) => m['id'] == updated['id']));
            return;
          }
          setState(() {
            final idx = _messages.indexWhere((m) => m['id'] == updated['id']);
            if (idx != -1) _messages[idx] = {..._messages[idx], ...updated};
          });
        })
      .subscribe();
  }

  Future<void> _silentRefresh() async {
    try {
      final data = await _sb.from('messages')
          .select('*, message_reactions(emoji, user_id)')
          .eq('conversation_id', widget.conversationId)
          .isFilter('deleted_at', null).order('created_at', ascending: true);
      if (!mounted) return;
      final incoming = List<Map<String, dynamic>>.from(data).map((m) => {
        ...m, 'reactions': List<Map<String, dynamic>>.from(m['message_reactions'] ?? []),
      }).toList();
      final prevIds = _messages.map((m) => m['id']).toSet();
      final newFromOther = incoming.where(
        (m) => !prevIds.contains(m['id']) && m['sender_id'] != _myId).toList();
      final hasChange = incoming.length != _messages.length ||
        (incoming.isNotEmpty && _messages.isNotEmpty && incoming.last['id'] != _messages.last['id']);
      if (hasChange) {
        final wasAtBottom = _scrollCtrl.hasClients &&
          _scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 80;
        setState(() => _messages = incoming);
        if (wasAtBottom) _scrollToBottom();
      }
      if (newFromOther.isNotEmpty) _markAllRead();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _fetchReactions(String msgId) async {
    try {
      final d = await _sb.from('message_reactions').select('emoji, user_id').eq('message_id', msgId);
      return List<Map<String, dynamic>>.from(d);
    } catch (_) { return []; }
  }

  Future<void> _loadMessages() async {
    try {
      final data = await _sb.from('messages')
          .select('*, message_reactions(emoji, user_id)')
          .eq('conversation_id', widget.conversationId)
          .isFilter('deleted_at', null).order('created_at', ascending: true);
      if (mounted) {
        final allMsgs = List<Map<String, dynamic>>.from(data).map((m) => {
          ...m, 'reactions': List<Map<String, dynamic>>.from(m['message_reactions'] ?? []),
        }).toList();
        setState(() { _messages = allMsgs; _loading = false; });
        _markAllRead(); _scrollToBottom();
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _markAllRead() async {
    if (_myId == null) return;
    try {
      await _sb.rpc('mark_messages_read', params: {
        'p_conversation_id': widget.conversationId, 'p_reader_id': _myId});
    } catch (_) {
      try { await _sb.from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', widget.conversationId)
          .neq('sender_id', _myId!).isFilter('read_at', null);
      } catch (_) {}
    }
  }

  Future<void> _markRead(String msgId) async {
    try { await _sb.from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', msgId);
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending || _myId == null) return;
    _msgCtrl.clear(); setState(() => _sending = true);
    try {
      await _sb.rpc('send_message', params: {
        'p_conversation_id': widget.conversationId,
        'p_sender_id': _myId, 'p_content': text});
      // Notify the other person (actorName resolved server-side from actorId)
      NotificationService.sendChatNotification(
        toUserId: widget.otherUserId,
        fromName: '', // resolved by edge function from actorId
        messagePreview: text.length > 60 ? '${text.substring(0, 57)}…' : text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
        _msgCtrl.text = text;
      }
    } finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _deleteMessage(String msgId) async {
    if (_myId == null) return;
    try {
      final result = await _sb.from('messages')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', msgId).eq('sender_id', _myId!).select();
      if ((result as List).isNotEmpty) {
        setState(() => _messages.removeWhere((m) => m['id'] == msgId));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not unsend this message'),
            backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _saveMessage(String msgId) async {
    try {
      await _sb.from('messages').update({'saved': true}).eq('id', msgId);
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == msgId);
        if (idx != -1) _messages[idx] = {..._messages[idx], 'saved': true};
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('💾 Saved — this message won\'t disappear'),
          backgroundColor: _green, behavior: SnackBarBehavior.floating));
    } catch (_) {}
  }

  Future<void> _toggleReaction(String msgId, String emoji) async {
    if (_myId == null) return;
    try {
      final existing = await _sb.from('message_reactions')
          .select().eq('message_id', msgId).eq('user_id', _myId!).maybeSingle();
      if (existing != null) {
        if (existing['emoji'] == emoji) {
          await _sb.from('message_reactions').delete().eq('message_id', msgId).eq('user_id', _myId!);
        } else {
          await _sb.from('message_reactions').update({'emoji': emoji})
              .eq('message_id', msgId).eq('user_id', _myId!);
        }
      } else {
        await _sb.from('message_reactions').insert({'message_id': msgId, 'user_id': _myId!, 'emoji': emoji});
      }
      final reactions = await _fetchReactions(msgId);
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == msgId);
        if (idx != -1) _messages[idx] = {..._messages[idx], 'reactions': reactions};
      });
    } catch (_) {}
  }

  void _showOptions(Map<String, dynamic> msg) {
    final isOwn   = msg['sender_id'] == _myId;
    final isSaved = msg['saved'] as bool? ?? false;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(color: AppColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _kReactions.map((e) => GestureDetector(
              onTap: () { Navigator.pop(context); _toggleReaction(msg['id'].toString(), e); },
              child: Container(width: 48, height: 48,
                decoration: BoxDecoration(color: AppColors.surfaceVariant(context),
                  borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 24))))
            )).toList()),
          const SizedBox(height: 16),
          Divider(color: AppColors.border(context)),
          const SizedBox(height: 8),
          if (!isSaved) _OptionTile(icon: Icons.bookmark_border_rounded,
            label: '💾 Save message (won\'t vanish)', color: _green,
            onTap: () { Navigator.pop(context); _saveMessage(msg['id'].toString()); }),
          if (isSaved) _OptionTile(icon: Icons.bookmark_rounded,
            label: '✅ Already saved', color: _green, onTap: () => Navigator.pop(context)),
          if (isOwn) _OptionTile(icon: Icons.delete_outline_rounded,
            label: 'Unsend message', color: Colors.red,
            onTap: () { Navigator.pop(context); _deleteMessage(msg['id'].toString()); }),
        ])));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  bool _isOnline(dynamic raw) {
    if (raw == null) return false;
    final t = DateTime.tryParse(raw.toString())?.toLocal();
    return t != null && DateTime.now().difference(t).inMinutes < 5;
  }

  String _statusLabel(dynamic raw) {
    if (raw == null) return 'offline';
    final t = DateTime.tryParse(raw.toString())?.toLocal();
    if (t == null) return 'offline';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 5)  return 'online now';
    if (diff.inMinutes < 60) return 'active ${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return 'active ${diff.inHours}h ago';
    return 'active ${diff.inDays}d ago';
  }

  bool _differentDay(String? a, String? b) {
    if (a == null || b == null) return false;
    final da = DateTime.tryParse(a)?.toLocal();
    final db = DateTime.tryParse(b)?.toLocal();
    if (da == null || db == null) return false;
    return da.day != db.day || da.month != db.month || da.year != db.year;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);
    final online    = _isOnline(_otherLastSeen);
    final status    = _statusLabel(_otherLastSeen);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context), elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 18),
          onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: Row(children: [
          Stack(children: [
            Container(width: 38, height: 38,
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [_indigo.withOpacity(0.3), _indigo.withOpacity(0.08)]),
                shape: BoxShape.circle,
                border: Border.all(color: _indigo.withOpacity(0.3), width: 1.5)),
              child: Center(child: Text(widget.otherEmoji, style: const TextStyle(fontSize: 20)))),
            if (online) Positioned(right: 0, bottom: 0,
              child: Container(width: 11, height: 11,
                decoration: BoxDecoration(color: _green, shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface(context), width: 2)))),
          ]),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.otherName, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w800)),
            Text(status, style: TextStyle(color: online ? _green : subColor, fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: _ghost.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _ghost.withOpacity(0.3))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('👻', style: TextStyle(fontSize: 11)),
              SizedBox(width: 4),
              Text('ghost', style: TextStyle(color: _ghost, fontSize: 10, fontWeight: FontWeight.w700)),
            ])),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: textColor, size: 22),
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: AppColors.surface(context),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border(context),
                    borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.person_outline_rounded, color: textColor),
                  title: Text('View Profile', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(context); openUserProfile(context, widget.otherUserId); }),
                ListTile(
                  leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
                  title: const Text('Block User', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(context); openUserProfile(context, widget.otherUserId); }),
                const SizedBox(height: 8),
              ])))),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border(context)))),

      body: Column(children: [
        // ── MESSAGES with cosmic background ──
        Expanded(
          child: _CosmicBackground(
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: _indigo, strokeWidth: 2))
              : _messages.isEmpty
                ? _EmptyChat(otherName: widget.otherName)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg   = _messages[i];
                      final isOwn = msg['sender_id'] == _myId;
                      final showDate = i == 0 || _differentDay(
                        _messages[i - 1]['created_at']?.toString(),
                        msg['created_at']?.toString());
                      return Column(children: [
                        if (showDate) _DateSeparator(dateStr: msg['created_at']?.toString()),
                        GestureDetector(
                          onLongPress: () => _showOptions(msg),
                          child: _MessageBubble(
                            content: msg['content']?.toString() ?? '',
                            isOwn: isOwn, isSaved: msg['saved'] as bool? ?? false,
                            createdAt: msg['created_at']?.toString(),
                            readAt: msg['read_at']?.toString(),
                            reactions: List<Map<String, dynamic>>.from(msg['reactions'] ?? []),
                            myId: _myId ?? '')),
                      ]);
                    }),
          ),
        ),

        // ── TYPING INDICATOR ──
        if (_otherTyping)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(children: [
              _TypingDots(),
              const SizedBox(width: 8),
              Text('${widget.otherName} is typing…',
                  style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12, fontStyle: FontStyle.italic)),
            ]),
          ),

        // ── INPUT BAR ──
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16,
            MediaQuery.of(context).padding.bottom > 0
              ? MediaQuery.of(context).viewInsets.bottom + 10 : 10),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            border: Border(top: BorderSide(color: AppColors.border(context)))),
          child: Row(children: [
            Expanded(child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border(context))),
              child: TextField(
                controller: _msgCtrl, maxLines: 4, minLines: 1,
                style: TextStyle(color: AppColors.text(context), fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'ghost message...',
                  hintStyle: TextStyle(color: AppColors.textSecondary(context),
                    fontSize: 14, fontStyle: FontStyle.italic),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                textCapitalization: TextCapitalization.sentences))),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _sending ? null : _sendMessage,
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_indigo, _pink],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: _indigo.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
                child: _sending
                  ? const Center(child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
          ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MESSAGE BUBBLE (UNCHANGED)
// ─────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final String content, myId;
  final bool isOwn, isSaved;
  final String? createdAt, readAt;
  final List<Map<String, dynamic>> reactions;

  const _MessageBubble({required this.content, required this.isOwn,
    required this.isSaved, required this.createdAt, this.readAt,
    required this.reactions, required this.myId});

  String _time(String? raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    String? myReaction;
    for (final r in reactions) {
      final e = r['emoji'].toString();
      groups[e] = (groups[e] ?? 0) + 1;
      if (r['user_id'] == myId) myReaction = e;
    }
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: reactions.isNotEmpty ? 4 : 8,
          left: isOwn ? 64 : 0, right: isOwn ? 0 : 64),
        child: Column(
          crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isOwn ? const LinearGradient(colors: [_indigo, _pink],
                  begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                color: isOwn ? null : AppColors.surfaceVariant(context),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isOwn ? 18 : 4),
                  bottomRight: Radius.circular(isOwn ? 4 : 18)),
                boxShadow: [BoxShadow(
                  color: isOwn ? _indigo.withOpacity(0.25) : Colors.black.withOpacity(0.04),
                  blurRadius: 8, offset: const Offset(0, 2))],
                border: isSaved ? Border.all(color: _green.withOpacity(0.5), width: 1.5) : null),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(content, style: TextStyle(
                  color: isOwn ? Colors.white : AppColors.text(context),
                  fontSize: 15, height: 1.4)),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isSaved) ...[const Text('💾', style: TextStyle(fontSize: 9)), const SizedBox(width: 3)],
                  Text(_time(createdAt), style: TextStyle(
                    color: isOwn ? Colors.white.withOpacity(0.6) : AppColors.textSecondary(context),
                    fontSize: 10)),
                  if (isOwn) ...[
                    const SizedBox(width: 4),
                    Icon(readAt != null ? Icons.done_all_rounded : Icons.done_rounded, size: 12,
                      color: readAt != null ? Colors.lightBlueAccent.withOpacity(0.9) : Colors.white.withOpacity(0.5)),
                  ],
                  if (!isOwn && readAt != null && !isSaved) ...[
                    const SizedBox(width: 4),
                    Text('👻', style: TextStyle(fontSize: 9,
                      color: AppColors.textSecondary(context).withOpacity(0.5))),
                  ],
                ]),
              ])),
            if (groups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 4, children: groups.entries.map((e) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: myReaction == e.key ? _indigo.withOpacity(0.15) : AppColors.surfaceVariant(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: myReaction == e.key ? _indigo.withOpacity(0.4) : AppColors.border(context))),
                  child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 11)))).toList())),
          ])));
  }
}

class _DateSeparator extends StatelessWidget {
  final String? dateStr;
  const _DateSeparator({this.dateStr});
  String _label() {
    if (dateStr == null) return '';
    final d = DateTime.tryParse(dateStr!)?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month) return 'Today';
    final yest = now.subtract(const Duration(days: 1));
    if (d.day == yest.day && d.month == yest.month) return 'Yesterday';
    return '${d.day}/${d.month}/${d.year}';
  }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      Expanded(child: Divider(color: AppColors.border(context))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(_label(), style: TextStyle(color: AppColors.textSecondary(context),
          fontSize: 11, fontWeight: FontWeight.w600))),
      Expanded(child: Divider(color: AppColors.border(context))),
    ]));
}

class _EmptyChat extends StatelessWidget {
  final String otherName;
  const _EmptyChat({required this.otherName});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('👻', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 12),
      Text('say hi to $otherName', style: TextStyle(
        color: AppColors.textSecondary(context), fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('messages vanish after reading\nlong-press to save any message',
        style: TextStyle(color: AppColors.textSecondary(context).withOpacity(0.6), fontSize: 12),
        textAlign: TextAlign.center),
    ]));
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _OptionTile({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      ])));
}

Future<void> openChatWith(BuildContext context, {
  required String otherUserId, required String otherName,
  required String otherEmoji, dynamic otherLastSeen,
}) async {
  final myId = _sb.auth.currentUser?.id;
  if (myId == null) return;
  try {
    final convId = await _sb.rpc('get_or_create_conversation',
      params: {'p_user1': myId, 'p_user2': otherUserId});
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: convId.toString(),
          otherUserId: otherUserId, otherName: otherName,
          otherEmoji: otherEmoji, otherLastSeen: otherLastSeen)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open chat: $e'), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));
    }
  }
}

// ── Animated typing dots ──────────────────────────────────────
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
          final t = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
          final scale = 0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
          return Container(
            margin: const EdgeInsets.only(right: 3),
            width: 6 * scale,
            height: 6 * scale,
            decoration: BoxDecoration(
              color: const Color(0xFF818CF8).withValues(alpha: 0.5 + 0.5 * scale),
              shape: BoxShape.circle,
            ),
          );
        }));
      },
    );
  }
}