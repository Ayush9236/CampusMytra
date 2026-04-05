import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Personality color map
// ─────────────────────────────────────────────────────────────────────────────
Color buddyPersonalityColor(String p) {
  switch (p) {
    case 'hype':  return const Color(0xFFFF375F);
    case 'zen':   return const Color(0xFF9C27B0);
    case 'grind': return const Color(0xFFFFB800);
    case 'soft':  return const Color(0xFFFF69B4);
    default:      return const Color(0xFF00C97B); // chill
  }
}

Color _hairColor(String p) {
  switch (p) {
    case 'hype':  return const Color(0xFFFF6B35);
    case 'zen':   return const Color(0xFF7B5EFF);
    case 'grind': return const Color(0xFF1A1A2E);
    case 'soft':  return const Color(0xFFFF8FAB);
    default:      return const Color(0xFF3D2B1F); // chill — dark brown
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BuddyCharacter — animated custom-painted anime character
// ─────────────────────────────────────────────────────────────────────────────
class BuddyCharacter extends StatefulWidget {
  final String personality;
  final int stage; // 1–5
  final double size;
  final VoidCallback? onTap;
  final String gender; // 'male' / 'female' / 'other'

  const BuddyCharacter({
    super.key,
    required this.personality,
    required this.stage,
    required this.size,
    this.onTap,
    this.gender = 'male',
  });

  @override
  State<BuddyCharacter> createState() => _BuddyCharacterState();
}

class _BuddyCharacterState extends State<BuddyCharacter>
    with TickerProviderStateMixin {
  late AnimationController _breatheCtrl;
  late AnimationController _blinkCtrl;
  late AnimationController _auraCtrl;
  late AnimationController _revealCtrl;
  late AnimationController _highFiveCtrl;
  late AnimationController _sparkleCtrl;

  @override
  void initState() {
    super.initState();

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scheduleBlink();

    _auraCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.stage >= 4 ? 1800 : 3000),
    )..repeat();

    _revealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _highFiveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _sparkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  void _scheduleBlink() async {
    final delay = 2500 + math.Random().nextInt(2500);
    await Future.delayed(Duration(milliseconds: delay));
    if (!mounted) return;
    await _blinkCtrl.forward();
    await _blinkCtrl.reverse();
    _scheduleBlink();
  }

  @override
  void didUpdateWidget(BuddyCharacter old) {
    super.didUpdateWidget(old);
    if (old.stage != widget.stage) {
      _auraCtrl.duration =
          Duration(milliseconds: widget.stage >= 4 ? 1800 : 3000);
    }
  }

  void _onTap() {
    widget.onTap?.call(); // tap → open chat
  }

  void _onLongPress() {
    _highFiveCtrl.forward().then((_) async {
      await Future.delayed(const Duration(milliseconds: 380));
      if (mounted) _highFiveCtrl.reverse();
    });
    _sparkleCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _blinkCtrl.dispose();
    _auraCtrl.dispose();
    _revealCtrl.dispose();
    _highFiveCtrl.dispose();
    _sparkleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onLongPress: _onLongPress,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _revealCtrl, curve: Curves.elasticOut),
        child: AnimatedBuilder(
          animation: Listenable.merge(
              [_breatheCtrl, _blinkCtrl, _auraCtrl, _highFiveCtrl, _sparkleCtrl]),
          builder: (context, child) => CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _BuddyPainter(
              personality: widget.personality,
              stage: widget.stage,
              gender: widget.gender,
              color: buddyPersonalityColor(widget.personality),
              breathe: _breatheCtrl.value,
              blink: _blinkCtrl.value,
              auraAngle: _auraCtrl.value * 2 * math.pi,
              highFive: _highFiveCtrl.value,
              sparkle: _sparkleCtrl.value,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────
class _BuddyPainter extends CustomPainter {
  final String personality;
  final int stage;
  final String gender;
  final Color color;
  final double breathe;  // 0–1
  final double blink;    // 0–1 (1 = fully closed)
  final double auraAngle;
  final double highFive; // 0–1 (1 = arm fully raised)
  final double sparkle;  // 0–1 (burst animation)

  static const _skin     = Color(0xFFFFD7A8);
  static const _skinShad = Color(0xFFE8B88A);
  static const _outline  = Color(0xFF2A1A0E);

  bool get _isFemale => gender == 'female';

  _BuddyPainter({
    required this.personality,
    required this.stage,
    required this.gender,
    required this.color,
    required this.breathe,
    required this.blink,
    required this.auraAngle,
    required this.highFive,
    required this.sparkle,
  });

  // Shoulder width grows with stage
  double _shoulderW(double s) => s * (0.18 + stage * 0.028);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s * 0.50;
    // Breathing: entire character bobs slightly
    final bob = breathe * s * 0.012;

    // Layer order (back → front):
    if (stage >= 3) _drawAura(canvas, s, cx, bob);
    _drawShadow(canvas, s, cx);
    _drawLegs(canvas, s, cx, bob);
    _drawBody(canvas, s, cx, bob);
    _drawArms(canvas, s, cx, bob);
    _drawNeck(canvas, s, cx, bob);
    _drawHairBack(canvas, s, cx, bob);
    _drawHead(canvas, s, cx, bob);
    _drawFace(canvas, s, cx, bob);
    _drawHairFront(canvas, s, cx, bob);
    if (stage >= 4) _drawAccessory(canvas, s, cx, bob);
    if (stage >= 5) _drawParticles(canvas, s, cx, bob);
    if (sparkle > 0) _drawSparkles(canvas, s, cx, bob);
  }

  // ── AURA ──────────────────────────────────────────────────────────────────
  void _drawAura(Canvas canvas, double s, double cx, double bob) {
    final center = Offset(cx, s * 0.55 - bob);
    final numRays = 8 + (stage - 3) * 4;
    final rayLen  = s * (0.28 + (stage - 3) * 0.06);
    final opacity = 0.08 + (stage - 3) * 0.04;

    final auraPaint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < numRays; i++) {
      final angle = auraAngle + i * (2 * math.pi / numRays);
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + math.cos(angle - 0.12) * rayLen,
                 center.dy + math.sin(angle - 0.12) * rayLen)
        ..lineTo(center.dx + math.cos(angle + 0.12) * rayLen,
                 center.dy + math.sin(angle + 0.12) * rayLen)
        ..close();
      canvas.drawPath(path, auraPaint);
    }

    // Central glow
    canvas.drawCircle(center, s * 0.22,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
  }

  // ── SHADOW ─────────────────────────────────────────────────────────────────
  void _drawShadow(Canvas canvas, double s, double cx) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, s * 0.94), width: s * 0.30, height: s * 0.04),
      Paint()..color = Colors.black.withValues(alpha: 0.18)
             ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  // ── LEGS ───────────────────────────────────────────────────────────────────
  void _drawLegs(Canvas canvas, double s, double cx, double bob) {
    final legW  = s * 0.075;
    final legH  = s * 0.18;
    final topY  = s * 0.72 - bob;
    final paint = Paint()..style = PaintingStyle.fill;

    if (_isFemale) {
      // Skirt
      final skirtTop  = topY - s * 0.03;
      final skirtPath = Path()
        ..moveTo(cx - legW * 1.5, skirtTop)
        ..lineTo(cx + legW * 1.5, skirtTop)
        ..lineTo(cx + legW * 2.1, skirtTop + s * 0.09)
        ..lineTo(cx - legW * 2.1, skirtTop + s * 0.09)
        ..close();
      canvas.drawPath(skirtPath, Paint()..color = color);
      // Skirt hem detail
      canvas.drawPath(skirtPath, Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.006);

      // Legs (slimmer for female)
      paint.color = _skin;
      for (final xOff in [cx - legW * 1.3, cx + legW * 0.3]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(xOff, skirtTop + s * 0.08, legW * 0.85, legH * 0.9),
            Radius.circular(legW * 0.4),
          ), paint);
      }

      // Shoes (small rounded flats)
      final shoeY = topY + legH - s * 0.01;
      paint.color = stage >= 3 ? const Color(0xFF1A1A2E) : const Color(0xFF555555);
      for (final xOff in [-legW * 1.35, legW * 0.25]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx + xOff, shoeY, legW * 1.1, s * 0.035),
            Radius.circular(s * 0.015),
          ), paint);
      }
    } else {
      // Left leg
      paint.color = color.withValues(alpha: 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - legW * 1.4, topY, legW, legH),
          Radius.circular(legW * 0.4),
        ), paint);

      // Right leg
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx + legW * 0.4, topY, legW, legH),
          Radius.circular(legW * 0.4),
        ), paint);

      // Shoes
      final shoeY  = topY + legH - s * 0.01;
      final shoeColor = stage >= 3 ? const Color(0xFF1A1A2E) : const Color(0xFF555555);
      paint.color = shoeColor;
      for (final xOff in [-legW * 1.5, legW * 0.3]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx + xOff, shoeY, legW * 1.3, s * 0.04),
            Radius.circular(s * 0.015),
          ), paint);
      }
    }
  }

  // ── BODY ───────────────────────────────────────────────────────────────────
  void _drawBody(Canvas canvas, double s, double cx, double bob) {
    final bw   = _shoulderW(s);
    final bh   = s * 0.22;
    final topY = s * 0.50 - bob;

    // Slouch angle for lower stages
    if (stage == 1) canvas.save();
    if (stage == 1) {
      canvas.translate(cx, topY + bh * 0.5);
      canvas.rotate(0.04);
      canvas.translate(-cx, -(topY + bh * 0.5));
    }

    // Main torso
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, topY + bh * 0.5), width: bw, height: bh),
        Radius.circular(bw * 0.25),
      ),
      Paint()..color = color,
    );

    // Outline
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, topY + bh * 0.5), width: bw, height: bh),
        Radius.circular(bw * 0.25),
      ),
      Paint()..color = _outline.withValues(alpha: 0.25)
             ..style = PaintingStyle.stroke
             ..strokeWidth = s * 0.007,
    );

    // Collar / V-neck (stage 2+)
    if (stage >= 2) {
      final collarPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008
        ..strokeCap = StrokeCap.round;
      final vPath = Path()
        ..moveTo(cx - bw * 0.15, topY + s * 0.02)
        ..lineTo(cx, topY + s * 0.055)
        ..lineTo(cx + bw * 0.15, topY + s * 0.02);
      canvas.drawPath(vPath, collarPaint);
    }

    // Muscle / shirt line (stage 3+)
    if (stage >= 3) {
      canvas.drawLine(
        Offset(cx, topY + s * 0.06),
        Offset(cx, topY + bh * 0.85),
        Paint()..color = Colors.white.withValues(alpha: 0.12)
               ..strokeWidth = s * 0.006,
      );
    }

    // Badge (stage 4+)
    if (stage >= 4) {
      canvas.drawCircle(
        Offset(cx - bw * 0.18, topY + s * 0.04),
        s * 0.018,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
      canvas.drawCircle(
        Offset(cx - bw * 0.18, topY + s * 0.04),
        s * 0.010,
        Paint()..color = color.withValues(alpha: 0.9),
      );
    }

    if (stage == 1) canvas.restore();
  }

  // ── ARMS ──────────────────────────────────────────────────────────────────
  void _drawArms(Canvas canvas, double s, double cx, double bob) {
    final shoulderY = s * 0.51 - bob;
    final armW = s * (0.055 + stage * 0.007);

    // Arm poses per personality
    final poses = _armPose();
    final armLen  = s * 0.15;
    final foreLen = s * 0.13;

    // Smooth step interpolation for high-five arm raise
    final t = highFive * highFive * (3 - 2 * highFive);
    const hfUpper = -math.pi * 0.55; // arm pointing up-left (high five!)
    const hfFore  = -math.pi * 0.48; // forearm also raised

    for (final side in [-1.0, 1.0]) {
      final shoulderX = cx + side * _shoulderW(s) * 0.48;
      final shoulder  = Offset(shoulderX, shoulderY);

      final double armAngle, foreAngle;
      if (side > 0) {
        // Right arm: lerp toward high-five pose
        armAngle  = poses[2] + (hfUpper - poses[2]) * t;
        foreAngle = poses[3] + (hfFore  - poses[3]) * t;
      } else {
        armAngle  = poses[0];
        foreAngle = poses[1];
      }

      final elbow = Offset(
        shoulder.dx + math.cos(armAngle) * armLen,
        shoulder.dy + math.sin(armAngle) * armLen,
      );
      final hand = Offset(
        elbow.dx + math.cos(foreAngle) * foreLen,
        elbow.dy + math.sin(foreAngle) * foreLen,
      );

      // Upper arm (outfit color)
      canvas.drawLine(shoulder, elbow,
        Paint()..color = color
               ..strokeWidth = armW
               ..strokeCap = StrokeCap.round
               ..style = PaintingStyle.stroke);

      // Forearm (skin)
      canvas.drawLine(elbow, hand,
        Paint()..color = _skin
               ..strokeWidth = armW * 0.88
               ..strokeCap = StrokeCap.round
               ..style = PaintingStyle.stroke);

      // Hand
      _drawHand(canvas, hand, armW, s, side, raised: side > 0 && highFive > 0.5);
    }
  }

  // ── HAND ──────────────────────────────────────────────────────────────────
  void _drawHand(Canvas canvas, Offset center, double armW, double s,
      double side, {bool raised = false}) {
    final palmW = armW * 1.3;
    final palmH = armW * 1.6;

    if (raised) {
      // Open high-five palm — fingers pointing upward
      // Palm
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: palmW * 1.05, height: palmH),
          Radius.circular(palmW * 0.32),
        ),
        Paint()..color = _skin,
      );
      // 4 fingers at top
      for (int i = 0; i < 4; i++) {
        final fx = center.dx - palmW * 0.36 + i * palmW * 0.245;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(fx, center.dy - palmH * 0.56),
                width: armW * 0.36, height: armW * 0.62),
            Radius.circular(armW * 0.18),
          ),
          Paint()..color = _skin,
        );
      }
      // Thumb to outer side
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(center.dx - side * palmW * 0.60, center.dy - palmH * 0.18),
              width: armW * 0.34, height: armW * 0.54),
          Radius.circular(armW * 0.16),
        ),
        Paint()..color = _skin,
      );
    } else {
      // Relaxed hanging hand — fingers pointing downward
      // Palm
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: palmW, height: palmH),
          Radius.circular(palmW * 0.36),
        ),
        Paint()..color = _skin,
      );
      // 4 finger bumps at bottom
      for (int i = 0; i < 4; i++) {
        final fx = center.dx - palmW * 0.34 + i * palmW * 0.225;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(fx, center.dy + palmH * 0.53),
            width: armW * 0.34, height: armW * 0.48,
          ),
          Paint()..color = _skin,
        );
      }
      // Thumb to inner side
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx - side * palmW * 0.56, center.dy + palmH * 0.06),
          width: armW * 0.32, height: armW * 0.46,
        ),
        Paint()..color = _skin,
      );
      // Palm crease
      canvas.drawLine(
        Offset(center.dx - palmW * 0.28, center.dy + palmH * 0.06),
        Offset(center.dx + palmW * 0.28, center.dy + palmH * 0.06),
        Paint()
          ..color = _skinShad.withValues(alpha: 0.28)
          ..strokeWidth = s * 0.004
          ..strokeCap = StrokeCap.round,
      );
    }

    // Palm outline
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: palmW, height: palmH),
        Radius.circular(palmW * 0.36),
      ),
      Paint()
        ..color = _skinShad.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.005,
    );
  }

  // Returns [leftUpperAngle, leftForeAngle, rightUpperAngle, rightForeAngle]
  // All personalities: arms relaxed at sides, hands resting down
  List<double> _armPose() {
    return [
      math.pi * 0.60,  // left upper: slightly outward-down
      math.pi * 0.64,  // left fore:  continuing down
      math.pi * 0.40,  // right upper: slightly outward-down
      math.pi * 0.36,  // right fore:  continuing down
    ];
  }

  // ── NECK ──────────────────────────────────────────────────────────────────
  void _drawNeck(Canvas canvas, double s, double cx, double bob) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, s * 0.475 - bob),
          width: s * 0.07, height: s * 0.05,
        ),
        Radius.circular(s * 0.02),
      ),
      Paint()..color = _skin,
    );
  }

  // ── HAIR BACK ─────────────────────────────────────────────────────────────
  void _drawHairBack(Canvas canvas, double s, double cx, double bob) {
    final headCy = s * 0.285 - bob;
    final hw = s * 0.145;
    final hh = s * 0.155;
    final hairCol = _hairColor(personality);
    final p = Paint()..color = hairCol..style = PaintingStyle.fill;
    final pDark = Paint()..color = hairCol.withValues(alpha: 0.65)..style = PaintingStyle.fill;

    switch (personality) {
      case 'zen': // Long straight hair flowing well below shoulders
        // Main back curtain — wide panel
        final back = Path()
          ..moveTo(cx - hw * 1.0, headCy - hh * 0.7)
          ..cubicTo(cx - hw * 1.45, headCy + hh * 0.3,
              cx - hw * 1.35, headCy + s * 0.22,
              cx - hw * 0.7, headCy + s * 0.32)
          ..lineTo(cx + hw * 0.7, headCy + s * 0.32)
          ..cubicTo(cx + hw * 1.35, headCy + s * 0.22,
              cx + hw * 1.45, headCy + hh * 0.3,
              cx + hw * 1.0, headCy - hh * 0.7)
          ..close();
        canvas.drawPath(back, p);
        // Inner shadow stripe for depth
        final shadow = Path()
          ..moveTo(cx - hw * 0.5, headCy - hh * 0.5)
          ..cubicTo(cx - hw * 0.7, headCy + hh * 0.4,
              cx - hw * 0.65, headCy + s * 0.18,
              cx - hw * 0.35, headCy + s * 0.30)
          ..lineTo(cx - hw * 0.15, headCy + s * 0.30)
          ..cubicTo(cx - hw * 0.35, headCy + s * 0.15,
              cx - hw * 0.30, headCy + hh * 0.35, cx - hw * 0.18, headCy - hh * 0.45)
          ..close();
        canvas.drawPath(shadow, pDark);
        break;

      case 'soft': // Voluminous twin tails with ribbon ties
        for (final sign in [-1.0, 1.0]) {
          // Poofy tail base — wide then tapers
          final tail = Path()
            ..moveTo(cx + sign * hw * 0.45, headCy - hh * 0.1)
            ..cubicTo(
                cx + sign * hw * 1.5, headCy + hh * 0.3,
                cx + sign * hw * 1.6, headCy + hh * 0.9,
                cx + sign * hw * 1.1, headCy + s * 0.28)
            ..lineTo(cx + sign * hw * 0.65, headCy + s * 0.24)
            ..cubicTo(
                cx + sign * hw * 0.9, headCy + hh * 0.8,
                cx + sign * hw * 0.85, headCy + hh * 0.25,
                cx + sign * hw * 0.4, headCy - hh * 0.05)
            ..close();
          canvas.drawPath(tail, p);
          // Inner highlight on tail
          final highlight = Path()
            ..moveTo(cx + sign * hw * 0.65, headCy + hh * 0.15)
            ..cubicTo(
                cx + sign * hw * 1.2, headCy + hh * 0.5,
                cx + sign * hw * 1.25, headCy + hh * 0.95,
                cx + sign * hw * 0.95, headCy + s * 0.22)
            ..lineTo(cx + sign * hw * 0.75, headCy + s * 0.21)
            ..cubicTo(
                cx + sign * hw * 0.9, headCy + hh * 0.88,
                cx + sign * hw * 0.85, headCy + hh * 0.45,
                cx + sign * hw * 0.5, headCy + hh * 0.1)
            ..close();
          canvas.drawPath(highlight, Paint()..color = Colors.white.withValues(alpha: 0.18)..style = PaintingStyle.fill);
        }
        break;

      case 'hype': // Wild spiky back — chaotic jutting spikes
        // Base back blob
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, headCy + hh * 0.05), width: hw * 2.0, height: hh * 2.1),
          p,
        );
        // Extra wild back spikes
        for (int i = 0; i < 4; i++) {
          final bx = cx - hw * 0.75 + i * hw * 0.5;
          final spike = Path()
            ..moveTo(bx - hw * 0.18, headCy + hh * 0.6)
            ..lineTo(bx + (i.isEven ? -hw * 0.35 : hw * 0.35), headCy + s * 0.26)
            ..lineTo(bx + hw * 0.18, headCy + hh * 0.6)
            ..close();
          canvas.drawPath(spike, p);
        }
        break;

      case 'grind': // Undercut — close-cropped at back
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, headCy + hh * 0.05), width: hw * 1.85, height: hh * 1.75),
          p,
        );
        // Fade line (lighter band at bottom of back)
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, headCy + hh * 0.65), width: hw * 1.75, height: hh * 0.35),
          Paint()..color = hairCol.withValues(alpha: 0.35)..style = PaintingStyle.fill,
        );
        break;

      default: // chill — medium wavy back, slightly tousled
        final back = Path()
          ..moveTo(cx - hw * 0.9, headCy - hh * 0.5)
          ..cubicTo(cx - hw * 1.3, headCy + hh * 0.2,
              cx - hw * 1.2, headCy + s * 0.14,
              cx - hw * 0.55, headCy + s * 0.20)
          ..lineTo(cx + hw * 0.55, headCy + s * 0.20)
          ..cubicTo(cx + hw * 1.2, headCy + s * 0.14,
              cx + hw * 1.3, headCy + hh * 0.2,
              cx + hw * 0.9, headCy - hh * 0.5)
          ..close();
        canvas.drawPath(back, p);
        // Wavy texture line
        final wave = Path()
          ..moveTo(cx - hw * 0.4, headCy + s * 0.12)
          ..cubicTo(cx - hw * 0.1, headCy + s * 0.09,
              cx + hw * 0.1, headCy + s * 0.15,
              cx + hw * 0.4, headCy + s * 0.12);
        canvas.drawPath(wave, Paint()..color = hairCol.withValues(alpha: 0.55)..style = PaintingStyle.stroke..strokeWidth = s * 0.012..strokeCap = StrokeCap.round);
    }
  }

  // ── HEAD ──────────────────────────────────────────────────────────────────
  void _drawHead(Canvas canvas, double s, double cx, double bob) {
    final headCy = s * 0.285 - bob;
    final hw = s * 0.145;
    final hh = s * 0.155;

    // Jaw / head shape (slightly pointy chin for anime)
    final headPath = Path();
    headPath.addOval(Rect.fromCenter(
        center: Offset(cx, headCy - hh * 0.05),
        width: hw * 2, height: hh * 1.85));
    canvas.drawPath(headPath, Paint()..color = _skin);

    // Chin point
    final chinPath = Path()
      ..moveTo(cx - hw * 0.35, headCy + hh * 0.65)
      ..quadraticBezierTo(cx, headCy + hh * 1.0, cx + hw * 0.35, headCy + hh * 0.65);
    canvas.drawPath(chinPath,
        Paint()..color = _skin..style = PaintingStyle.fill);

    // Head outline
    canvas.drawPath(headPath,
        Paint()..color = _outline.withValues(alpha: 0.18)
               ..style = PaintingStyle.stroke
               ..strokeWidth = s * 0.006);

    // Jaw shading
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, headCy + hh * 0.25), width: hw * 1.6, height: hh * 0.5),
      Paint()..color = _skinShad.withValues(alpha: 0.18),
    );
  }

  // ── FACE ──────────────────────────────────────────────────────────────────
  void _drawFace(Canvas canvas, double s, double cx, double bob) {
    final headCy = s * 0.285 - bob;
    final hw = s * 0.145;
    final hh = s * 0.155;
    final eyeY = headCy - hh * 0.10;

    _drawEyebrows(canvas, s, cx, eyeY, hw);
    _drawEyes(canvas, s, cx, eyeY, hw, hh);
    _drawNose(canvas, s, cx, headCy, hh);
    _drawMouth(canvas, s, cx, headCy, hw, hh);
    _drawBlush(canvas, s, cx, headCy, hw, hh);
  }

  void _drawEyebrows(Canvas canvas, double s, double cx, double eyeY, double hw) {
    final browY = eyeY - s * 0.038; // moved up to match bigger eyes
    final browW = hw * 0.46;        // wider to match wider eyes
    // Female: thinner, more arched brows
    final strokeW = _isFemale ? s * 0.009 : s * 0.014;
    final browPaint = Paint()
      ..color = _hairColor(personality)
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final sign in [-1.0, 1.0]) {
      final bx = cx + sign * hw * 0.42;
      if (_isFemale) {
        // High, elegant arch for all female personalities
        final archLift = personality == 'hype' ? s * 0.016 : s * 0.012;
        final path = Path()
          ..moveTo(bx - sign * browW * 0.52, browY + s * 0.005)
          ..quadraticBezierTo(bx + sign * browW * 0.05, browY - archLift,
              bx + sign * browW * 0.52, browY + s * 0.007);
        canvas.drawPath(path, browPaint);
      } else {
        switch (personality) {
          case 'hype': // raised/excited
            canvas.drawLine(
              Offset(bx - sign * browW * 0.5, browY + s * 0.005),
              Offset(bx + sign * browW * 0.5, browY - s * 0.008),
              browPaint,
            );
            break;
          case 'grind': // sharp/furrowed
            canvas.drawLine(
              Offset(bx - sign * browW * 0.5, browY - s * 0.004),
              Offset(bx + sign * browW * 0.5, browY + s * 0.006),
              browPaint,
            );
            break;
          default: // neutral/soft arch
            final path = Path()
              ..moveTo(bx - sign * browW * 0.5, browY + s * 0.003)
              ..quadraticBezierTo(bx, browY - s * 0.006, bx + sign * browW * 0.5, browY + s * 0.003);
            canvas.drawPath(path, browPaint);
        }
      }
    }
  }

  void _drawEyes(Canvas canvas, double s, double cx, double eyeY, double hw, double hh) {
    // Anime-style: wide rounded-rectangle eyes with thick lids + catchlights
    final eyeW   = hw * 0.56;
    final eyeH   = hh * 0.32;
    final eyeXOff = hw * 0.44;
    final blinkF  = 1.0 - blink * 0.97;

    for (final sign in [-1.0, 1.0]) {
      final ex = cx + sign * eyeXOff;

      // ── Sclera (white) ────────────────────────────────────────────────────
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(ex, eyeY),
              width: eyeW, height: eyeH * blinkF),
          Radius.circular(eyeW * 0.36),
        ),
        Paint()..color = Colors.white,
      );

      final irisH = eyeH * 0.90 * blinkF;
      if (irisH > 1.0) {
        // ── Iris ──────────────────────────────────────────────────────────
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(ex, eyeY + eyeH * 0.03),
                width: eyeW * 0.74, height: irisH),
            Radius.circular(eyeW * 0.28),
          ),
          Paint()..color = color,
        );

        // Iris top gloss (lighter band)
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(ex, eyeY + eyeH * 0.03 - irisH * 0.26),
                width: eyeW * 0.58, height: irisH * 0.40),
            Radius.circular(eyeW * 0.18),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.20),
        );

        // ── Pupil ─────────────────────────────────────────────────────────
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(ex + eyeW * 0.02, eyeY + eyeH * 0.05),
                width: eyeW * 0.36, height: irisH * 0.52),
            Radius.circular(eyeW * 0.12),
          ),
          Paint()..color = const Color(0xFF0D0818),
        );

        // ── Catchlight 1 — large top-left oval (essential anime detail) ───
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(ex - eyeW * 0.15, eyeY - irisH * 0.20),
            width: eyeW * 0.26, height: irisH * 0.28,
          ),
          Paint()..color = Colors.white,
        );

        // ── Catchlight 2 — small bottom-right dot ─────────────────────────
        canvas.drawCircle(
          Offset(ex + eyeW * 0.15, eyeY + irisH * 0.08),
          eyeW * 0.09,
          Paint()..color = Colors.white.withValues(alpha: 0.78),
        );

        // Stage 4-5 iris glow
        if (stage >= 4) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(ex, eyeY),
                  width: eyeW * 1.3, height: eyeH * 1.3),
              Radius.circular(eyeW * 0.4),
            ),
            Paint()
              ..color = color.withValues(alpha: 0.22)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }
      }

      // ── Thick top eyelid — #1 feature for anime look ──────────────────
      final lidH = eyeH * 0.24 + blink * eyeH * 0.76;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(ex,
                eyeY - eyeH * 0.50 * (1 - blink) + lidH * 0.5 - eyeH * 0.02),
            width: eyeW * 1.12, height: lidH,
          ),
          Radius.circular(eyeW * 0.20),
        ),
        Paint()..color = const Color(0xFF130D1E),
      );

      // ── Outer corner lash flick ────────────────────────────────────────
      if (blink < 0.6) {
        canvas.drawLine(
          Offset(ex + sign * eyeW * 0.50, eyeY - eyeH * 0.26 * (1 - blink)),
          Offset(ex + sign * eyeW * 0.74, eyeY - eyeH * 0.44 * (1 - blink)),
          Paint()
            ..color = const Color(0xFF130D1E)
            ..strokeWidth = s * 0.011
            ..strokeCap = StrokeCap.round,
        );
      }

      // ── Female extra upper lashes ──────────────────────────────────────
      if (_isFemale && blink < 0.5) {
        final lashPaint = Paint()
          ..color = const Color(0xFF130D1E)
          ..strokeWidth = s * 0.009
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        // 4 curved lashes fanning upward from lid
        final lashPositions = [-0.30, -0.08, 0.15, 0.38];
        final lashAngles    = [-0.45, -0.30, -0.15, 0.02];
        for (int li = 0; li < 4; li++) {
          final lx = ex + eyeW * lashPositions[li] * sign;
          final baseY = eyeY - eyeH * 0.44 * (1 - blink);
          final cp = Offset(
            lx + math.cos(lashAngles[li] * sign - math.pi / 2) * eyeH * 0.18,
            baseY - eyeH * 0.22,
          );
          final tip = Offset(
            lx + math.cos(lashAngles[li] * sign - math.pi / 2) * eyeH * 0.32,
            baseY - eyeH * 0.38,
          );
          final path = Path()
            ..moveTo(lx, baseY)
            ..quadraticBezierTo(cp.dx, cp.dy, tip.dx, tip.dy);
          canvas.drawPath(path, lashPaint);
        }
      }

      // ── Bottom lash line — thin ────────────────────────────────────────
      canvas.drawLine(
        Offset(ex - eyeW * 0.40, eyeY + eyeH * 0.40 * (1 - blink * 0.9)),
        Offset(ex + eyeW * 0.40, eyeY + eyeH * 0.40 * (1 - blink * 0.9)),
        Paint()
          ..color = const Color(0xFF130D1E).withValues(alpha: 0.55)
          ..strokeWidth = s * 0.007
          ..strokeCap = StrokeCap.round,
      );

      // ── Sparkle dots — soft/hype ───────────────────────────────────────
      if ((personality == 'soft' || personality == 'hype') && blink < 0.3) {
        canvas.drawCircle(
          Offset(ex + sign * eyeW * 0.68, eyeY - eyeH * 0.60),
          s * 0.011,
          Paint()..color = color.withValues(alpha: 0.90),
        );
        canvas.drawCircle(
          Offset(ex + sign * eyeW * 0.82, eyeY - eyeH * 0.30),
          s * 0.007,
          Paint()..color = color.withValues(alpha: 0.55),
        );
      }
    }
  }

  void _drawNose(Canvas canvas, double s, double cx, double headCy, double hh) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, headCy + hh * 0.22),
        width: s * 0.024, height: s * 0.012),
      Paint()..color = _skinShad.withValues(alpha: 0.45),
    );
  }

  void _drawMouth(Canvas canvas, double s, double cx, double headCy, double hw, double hh) {
    final mouthY = headCy + hh * 0.46;

    // Female: draw filled lips before stroke
    if (_isFemale) {
      final lipW = personality == 'hype' ? hw * 0.30 : (personality == 'soft' ? hw * 0.22 : hw * 0.18);
      final lipH = hh * 0.07;
      // Lower lip fill
      final lipPath = Path()
        ..moveTo(cx - lipW, mouthY)
        ..quadraticBezierTo(cx, mouthY + lipH * 1.4, cx + lipW, mouthY)
        ..close();
      canvas.drawPath(lipPath, Paint()
        ..color = const Color(0xFFE8607A).withValues(alpha: 0.75)
        ..style = PaintingStyle.fill);
      // Upper lip thin line
      canvas.drawLine(
        Offset(cx - lipW * 0.85, mouthY),
        Offset(cx + lipW * 0.85, mouthY),
        Paint()
          ..color = const Color(0xFFD04060).withValues(alpha: 0.55)
          ..strokeWidth = s * 0.007
          ..strokeCap = StrokeCap.round,
      );
    }

    final mouthPaint = Paint()
      ..color = _isFemale ? const Color(0xFFD04060) : const Color(0xFFD07070)
      ..strokeWidth = s * 0.010
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final mouthPath = Path();
    switch (personality) {
      case 'hype': // big grin
        mouthPath
          ..moveTo(cx - hw * 0.30, mouthY)
          ..quadraticBezierTo(cx, mouthY + hh * 0.18, cx + hw * 0.30, mouthY);
        canvas.drawPath(mouthPath, mouthPaint..strokeWidth = s * 0.012);
        // Teeth
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, mouthY + hh * 0.07), width: hw * 0.42, height: hh * 0.10),
            Radius.circular(s * 0.01),
          ),
          Paint()..color = Colors.white,
        );
        break;
      case 'grind': // determined straight line
        canvas.drawLine(
          Offset(cx - hw * 0.22, mouthY),
          Offset(cx + hw * 0.22, mouthY),
          mouthPaint,
        );
        break;
      case 'zen': // small peaceful smile
        mouthPath
          ..moveTo(cx - hw * 0.14, mouthY)
          ..quadraticBezierTo(cx, mouthY + hh * 0.08, cx + hw * 0.14, mouthY);
        canvas.drawPath(mouthPath, mouthPaint);
        break;
      case 'soft': // big cute smile
        mouthPath
          ..moveTo(cx - hw * 0.22, mouthY)
          ..quadraticBezierTo(cx, mouthY + hh * 0.15, cx + hw * 0.22, mouthY);
        canvas.drawPath(mouthPath, mouthPaint..strokeWidth = s * 0.011);
        break;
      default: // chill — slight relaxed smile
        mouthPath
          ..moveTo(cx - hw * 0.18, mouthY)
          ..quadraticBezierTo(cx, mouthY + hh * 0.10, cx + hw * 0.18, mouthY);
        canvas.drawPath(mouthPath, mouthPaint);
    }
  }

  void _drawBlush(Canvas canvas, double s, double cx, double headCy, double hw, double hh) {
    final blushY = headCy + hh * 0.16;
    final blushPaint = Paint()
      ..color = const Color(0xFFFFB5B5).withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    for (final sign in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + sign * hw * 0.62, blushY),
          width: hw * 0.42, height: hh * 0.13,
        ),
        blushPaint,
      );
    }
  }

  // ── HAIR FRONT ────────────────────────────────────────────────────────────
  void _drawHairFront(Canvas canvas, double s, double cx, double bob) {
    final headCy = s * 0.285 - bob;
    final hw = s * 0.145;
    final hh = s * 0.155;
    final hairCol = _hairColor(personality);
    final p = Paint()..color = hairCol..style = PaintingStyle.fill;
    final pLight = Paint()..color = Colors.white.withValues(alpha: 0.22)..style = PaintingStyle.fill;

    switch (personality) {
      case 'hype': // Explosive upward spikes — anime battle style
        // Base cap covering top of head
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, headCy - hh * 0.48), width: hw * 2.05, height: hh * 0.62),
          p,
        );
        // 7 alternating-height spikes fanning upward
        final spikeAngles = [-0.55, -0.30, -0.10, 0.0, 0.10, 0.30, 0.55];
        final spikeHeights = [hh * 0.65, hh * 0.95, hh * 1.15, hh * 1.30, hh * 1.15, hh * 0.95, hh * 0.65];
        for (int i = 0; i < 7; i++) {
          final baseX = cx + spikeAngles[i] * hw * 2.0;
          final tipX = cx + spikeAngles[i] * hw * 1.5;
          final tipY = headCy - hh * 0.62 - spikeHeights[i];
          final spike = Path()
            ..moveTo(baseX - hw * 0.14, headCy - hh * 0.38)
            ..lineTo(tipX, tipY)
            ..lineTo(baseX + hw * 0.14, headCy - hh * 0.38)
            ..close();
          canvas.drawPath(spike, p);
          // Highlight line on each spike
          canvas.drawLine(
            Offset(tipX - hw * 0.03, headCy - hh * 0.42),
            Offset(tipX - hw * 0.02, tipY + hh * 0.12),
            Paint()..color = Colors.white.withValues(alpha: 0.30)..strokeWidth = s * 0.007..strokeCap = StrokeCap.round..style = PaintingStyle.stroke,
          );
        }
        break;

      case 'grind': // Undercut fade + bold headband with logo zone
        // Short cropped top — geometric flat top
        final topPath = Path()
          ..moveTo(cx - hw * 1.02, headCy - hh * 0.30)
          ..lineTo(cx - hw * 0.92, headCy - hh * 0.95)
          ..lineTo(cx + hw * 0.92, headCy - hh * 0.95)
          ..lineTo(cx + hw * 1.02, headCy - hh * 0.30)
          ..close();
        canvas.drawPath(topPath, p);
        // Slight rounded corners on flat top
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(cx - hw * 0.92, headCy - hh * 1.0, cx + hw * 0.92, headCy - hh * 0.88),
            Radius.circular(hw * 0.12),
          ),
          p,
        );
        // Bold headband — wide, with 2-tone stripe
        final bandY = headCy - hh * 0.36;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, bandY), width: hw * 2.25, height: hh * 0.20),
            Radius.circular(hh * 0.06),
          ),
          Paint()..color = color,
        );
        // White stripe inside headband
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, bandY), width: hw * 2.25, height: hh * 0.07),
            Radius.circular(hh * 0.03),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.35),
        );
        break;

      case 'zen': // Sleek center-parted curtain bangs with ear-length side strands
        // Main bang curtain
        final bangPath = Path()
          ..moveTo(cx - hw * 0.95, headCy - hh * 0.80)
          ..cubicTo(cx - hw * 1.0, headCy - hh * 0.30,
              cx - hw * 0.5, headCy + hh * 0.05,
              cx - hw * 0.05, headCy - hh * 0.15)
          ..lineTo(cx + hw * 0.05, headCy - hh * 0.15)
          ..cubicTo(cx + hw * 0.5, headCy + hh * 0.05,
              cx + hw * 1.0, headCy - hh * 0.30,
              cx + hw * 0.95, headCy - hh * 0.80)
          ..close();
        canvas.drawPath(bangPath, p);
        // Center-part gap (slight lighter line)
        canvas.drawLine(
          Offset(cx, headCy - hh * 0.82),
          Offset(cx, headCy - hh * 0.18),
          Paint()..color = Colors.white.withValues(alpha: 0.18)..strokeWidth = s * 0.010..strokeCap = StrokeCap.round..style = PaintingStyle.stroke,
        );
        // Long side curtain strands hanging past jaw
        for (final sign in [-1.0, 1.0]) {
          final strand = Path()
            ..moveTo(cx + sign * hw * 0.82, headCy - hh * 0.78)
            ..cubicTo(
                cx + sign * hw * 1.10, headCy - hh * 0.10,
                cx + sign * hw * 1.08, headCy + hh * 0.45,
                cx + sign * hw * 0.88, headCy + hh * 0.70)
            ..lineTo(cx + sign * hw * 0.68, headCy + hh * 0.65)
            ..cubicTo(
                cx + sign * hw * 0.85, headCy + hh * 0.38,
                cx + sign * hw * 0.82, headCy - hh * 0.08,
                cx + sign * hw * 0.62, headCy - hh * 0.72)
            ..close();
          canvas.drawPath(strand, p);
          // Highlight shimmer
          canvas.drawLine(
            Offset(cx + sign * hw * 0.78, headCy - hh * 0.65),
            Offset(cx + sign * hw * 0.74, headCy + hh * 0.52),
            Paint()..color = Colors.white.withValues(alpha: 0.22)..strokeWidth = s * 0.009..strokeCap = StrokeCap.round..style = PaintingStyle.stroke,
          );
        }
        break;

      case 'soft': // Puffy cloud bangs with high twin-tail ties
        // Fluffy cloud bang — three overlapping ovals
        final puffCenters = [-hw * 0.55, -hw * 0.18, hw * 0.18, hw * 0.55];
        final puffWidths = [hw * 0.72, hw * 0.80, hw * 0.80, hw * 0.72];
        for (int i = 0; i < 4; i++) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx + puffCenters[i], headCy - hh * 0.52),
              width: puffWidths[i], height: hh * 0.72,
            ),
            p,
          );
        }
        // Shine dabs on puffs
        for (int i = 0; i < 4; i++) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx + puffCenters[i] - hw * 0.05, headCy - hh * 0.65),
              width: puffWidths[i] * 0.35, height: hh * 0.22,
            ),
            pLight,
          );
        }
        // Cute side puffs at ear level
        for (final sign in [-1.0, 1.0]) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(cx + sign * hw * 0.92, headCy - hh * 0.10), width: hw * 0.60, height: hh * 0.78),
            p,
          );
        }
        // Ribbon hair ties (small bow shapes)
        for (final sign in [-1.0, 1.0]) {
          final tieX = cx + sign * hw * 0.88;
          final tieY = headCy - hh * 0.50;
          // Bow left/right petals
          for (final bs in [-1.0, 1.0]) {
            canvas.drawOval(
              Rect.fromCenter(center: Offset(tieX + bs * s * 0.025, tieY), width: s * 0.038, height: s * 0.022),
              Paint()..color = color.withValues(alpha: 0.9),
            );
          }
          // Bow knot
          canvas.drawCircle(Offset(tieX, tieY), s * 0.012, Paint()..color = color);
        }
        break;

      default: // chill — relaxed side-swept with natural flow
        // Main bang block offset slightly to one side
        final bangRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + hw * 0.10, headCy - hh * 0.50), width: hw * 2.10, height: hh * 0.75),
          Radius.circular(hw * 0.35),
        );
        canvas.drawRRect(bangRect, p);
        // Big sweeping forelock from left
        final forelock = Path()
          ..moveTo(cx - hw * 0.95, headCy - hh * 0.75)
          ..cubicTo(cx - hw * 0.60, headCy - hh * 0.90,
              cx - hw * 0.10, headCy - hh * 0.60,
              cx + hw * 0.20, headCy - hh * 0.20)
          ..lineTo(cx + hw * 0.05, headCy - hh * 0.14)
          ..cubicTo(cx - hw * 0.12, headCy - hh * 0.55,
              cx - hw * 0.58, headCy - hh * 0.82,
              cx - hw * 0.78, headCy - hh * 0.68)
          ..close();
        canvas.drawPath(forelock, Paint()..color = hairCol.withValues(alpha: 0.88));
        // Small wispy strand at temple
        final wisp = Path()
          ..moveTo(cx + hw * 0.80, headCy - hh * 0.62)
          ..cubicTo(cx + hw * 0.95, headCy - hh * 0.28,
              cx + hw * 0.90, headCy + hh * 0.08,
              cx + hw * 0.72, headCy + hh * 0.22)
          ..lineTo(cx + hw * 0.60, headCy + hh * 0.18)
          ..cubicTo(cx + hw * 0.74, headCy + hh * 0.02,
              cx + hw * 0.76, headCy - hh * 0.25,
              cx + hw * 0.65, headCy - hh * 0.58)
          ..close();
        canvas.drawPath(wisp, Paint()..color = hairCol.withValues(alpha: 0.75));
    }

    // Shared shine highlight on top of all hairstyles
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - hw * 0.12, headCy - hh * 0.72), width: hw * 0.55, height: hh * 0.18),
      Paint()..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  // ── ACCESSORY (stage 4+) ──────────────────────────────────────────────────
  void _drawAccessory(Canvas canvas, double s, double cx, double bob) {
    // Cape / aura collar behind head
    final collarY = s * 0.46 - bob;
    final capeW = _shoulderW(s) * 1.6;

    final capePaint = Paint()
      ..color = color.withValues(alpha: stage >= 5 ? 0.55 : 0.35)
      ..style = PaintingStyle.fill;

    final capePath = Path()
      ..moveTo(cx - capeW * 0.5, collarY)
      ..quadraticBezierTo(cx, collarY - s * 0.06, cx + capeW * 0.5, collarY)
      ..quadraticBezierTo(cx + capeW * 0.62, collarY + s * 0.12, cx + capeW * 0.4, collarY + s * 0.25)
      ..lineTo(cx - capeW * 0.4, collarY + s * 0.25)
      ..quadraticBezierTo(cx - capeW * 0.62, collarY + s * 0.12, cx - capeW * 0.5, collarY)
      ..close();
    canvas.drawPath(capePath, capePaint);

    // Cape shimmer line
    canvas.drawPath(capePath,
      Paint()..color = Colors.white.withValues(alpha: 0.15)
             ..style = PaintingStyle.stroke
             ..strokeWidth = s * 0.006);
  }

  // ── PARTICLES (stage 5 only) ───────────────────────────────────────────────
  void _drawParticles(Canvas canvas, double s, double cx, double bob) {
    final rng = math.Random(42);
    for (int i = 0; i < 12; i++) {
      final angle = auraAngle * (i % 2 == 0 ? 1 : -1) + i * 0.52;
      final dist  = s * (0.30 + rng.nextDouble() * 0.12);
      final px    = cx + math.cos(angle) * dist;
      final py    = s * 0.50 - bob + math.sin(angle) * dist * 0.8;
      final sz    = s * (0.008 + rng.nextDouble() * 0.014);

      canvas.drawCircle(Offset(px, py), sz,
        Paint()..color = color.withValues(alpha: 0.5 + rng.nextDouble() * 0.4));

      // Star shape
      if (i % 3 == 0) {
        _drawStar(canvas, Offset(px, py), sz * 1.6, color.withValues(alpha: 0.7));
      }
    }
  }

  // ── HIGH-FIVE SPARKLES ────────────────────────────────────────────────────
  void _drawSparkles(Canvas canvas, double s, double cx, double bob) {
    // Compute hand position at high-five pose
    final shoulderY = s * 0.51 - bob;
    final shoulderX = cx + _shoulderW(s) * 0.48;
    final armLen    = s * 0.15;
    final foreLen   = s * 0.13;
    const hfUpperAngle = -math.pi * 0.55;
    const hfForeAngle  = -math.pi * 0.48;

    final elbow = Offset(
      shoulderX + math.cos(hfUpperAngle) * armLen,
      shoulderY + math.sin(hfUpperAngle) * armLen,
    );
    final hand = Offset(
      elbow.dx + math.cos(hfForeAngle) * foreLen,
      elbow.dy + math.sin(hfForeAngle) * foreLen,
    );

    final fade  = (1.0 - sparkle).clamp(0.0, 1.0);
    final burst = s * 0.24 * sparkle;

    // 8 radial burst particles
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8.0) * 2 * math.pi - math.pi / 2;
      final px = hand.dx + math.cos(angle) * burst;
      final py = hand.dy + math.sin(angle) * burst;
      final sz = s * 0.017 * fade;

      if (i.isEven) {
        _drawStar(canvas, Offset(px, py), sz * 1.6,
            color.withValues(alpha: fade * 0.95));
      } else {
        canvas.drawCircle(
          Offset(px, py), sz * 0.9,
          Paint()..color = Colors.white.withValues(alpha: fade * 0.85),
        );
      }
    }

    // Flash ring at hand
    final flashFade = (1.0 - sparkle * 2.4).clamp(0.0, 1.0);
    if (flashFade > 0) {
      canvas.drawCircle(
        hand, s * 0.058 * flashFade,
        Paint()
          ..color = Colors.white.withValues(alpha: flashFade * 0.88)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.025),
      );
      canvas.drawCircle(
        hand, s * 0.030 * flashFade,
        Paint()..color = color.withValues(alpha: flashFade * 0.9),
      );
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color c) {
    final path = Path();
    for (int i = 0; i < 4; i++) {
      final a = auraAngle + i * math.pi / 2;
      if (i == 0) {
        path.moveTo(center.dx + math.cos(a) * radius, center.dy + math.sin(a) * radius);
      } else {
        path.lineTo(center.dx + math.cos(a) * radius, center.dy + math.sin(a) * radius);
      }
      final mid = a + math.pi / 4;
      path.lineTo(center.dx + math.cos(mid) * radius * 0.4, center.dy + math.sin(mid) * radius * 0.4);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = c..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_BuddyPainter old) =>
      old.breathe != breathe || old.blink != blink || old.auraAngle != auraAngle ||
      old.stage != stage || old.personality != personality || old.gender != gender ||
      old.highFive != highFive || old.sparkle != sparkle;
}
