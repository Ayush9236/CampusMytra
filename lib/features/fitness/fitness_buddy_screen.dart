import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/fitness_models.dart';
import 'services/fitness_service.dart';
import 'services/fitness_notification_service.dart';
import 'fitness_onboarding_screen.dart';
import 'fitness_plan_screen.dart';
import 'daily_checkin_screen.dart';
import 'fitness_progress_screen.dart';
import 'widgets/buddy_character.dart';
import 'buddy_chat_screen.dart';
import 'fitness_theme.dart';

// ─── Personality-to-color mapping ────────────────────────────────────────────
Color buddyColor(String personality) {
  switch (personality) {
    case 'hype':   return kFitRed;
    case 'zen':    return kFitPurple;
    case 'grind':  return kFitOrange;
    case 'soft':   return const Color(0xFFFF69B4);
    default:       return kFitGreen; // chill
  }
}

String buddyEmoji(int displayStage) {
  switch (displayStage) {
    case 1: return '🌱';
    case 2: return '🔥';
    case 3: return '💪';
    case 4: return '⚡';
    default: return '🌟';
  }
}

String goalLabel(String goal) {
  switch (goal) {
    case 'lose_fat':        return 'Lose Fat';
    case 'gain_muscle':     return 'Gain Muscle';
    case 'stay_fit':        return 'Stay Fit';
    case 'improve_stamina': return 'Improve Stamina';
    default:                return goal;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
Future<void> _confirmReset(BuildContext context, VoidCallback onRefresh) async {
  final fc = FitnessColors.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: fc.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Start Fresh?',
          style: TextStyle(color: fc.textPrimary, fontWeight: FontWeight.w800)),
      content: Text(
        'This will permanently delete your buddy, fitness plan, all logs, and streak.\n\nThis cannot be undone.',
        style: TextStyle(color: fc.textHint, fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: fc.textHint)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Delete Everything',
              style: TextStyle(color: fc.accentFg(kFitRed), fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await FitnessService.deleteAllData();
    if (context.mounted) onRefresh();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reset: $e'), backgroundColor: kFitRed));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root widget
// ─────────────────────────────────────────────────────────────────────────────
class FitnessBuddyScreen extends StatefulWidget {
  const FitnessBuddyScreen({super.key});

  @override
  State<FitnessBuddyScreen> createState() => _FitnessBuddyScreenState();
}

class _FitnessBuddyScreenState extends State<FitnessBuddyScreen> {
  FitnessProfile? _profile;
  FitnessPlan? _plan;
  BuddyState? _buddy;
  bool _loading = true;
  bool _checkedInToday = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _profile = await FitnessService.getProfile();
      if (_profile != null) {
        final results = await Future.wait([
          FitnessService.getPlan(),
          FitnessService.getBuddyState(),
          FitnessService.hasCheckedInToday(),
        ]);
        _plan   = results[0] as FitnessPlan?;
        _buddy  = results[1] as BuddyState?;
        _checkedInToday = results[2] as bool;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: fc.bg,
        body: Center(child: CircularProgressIndicator(color: kFitGreen, strokeWidth: 2)),
      );
    }
    if (_profile == null) {
      return _WelcomeView(onStart: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FitnessOnboardingScreen(onComplete: _load)),
      ));
    }
    return _BuddyHub(
      profile: _profile!,
      plan: _plan,
      buddy: _buddy,
      checkedIn: _checkedInToday,
      onRefresh: _load,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Welcome screen
// ─────────────────────────────────────────────────────────────────────────────
class _WelcomeView extends StatefulWidget {
  final VoidCallback onStart;
  const _WelcomeView({required this.onStart});

  @override
  State<_WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends State<_WelcomeView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Scaffold(
      backgroundColor: fc.bg,
      body: Stack(children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (ctx, child) => Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2 + _ctrl.value * 0.3),
                radius: 1.1,
                colors: [fc.radialBg(kFitGreen), fc.bg],
              ),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const SizedBox(height: 48),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (ctx, child) => Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 160 + _ctrl.value * 10,
                    height: 160 + _ctrl.value * 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kFitGreen.withValues(alpha: 0.08 + _ctrl.value * 0.08),
                        width: 1,
                      ),
                    ),
                  ),
                  Container(
                    width: 130, height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        kFitGreen.withValues(alpha: 0.20 + _ctrl.value * 0.10),
                        kFitGreen.withValues(alpha: 0.04),
                      ]),
                      boxShadow: [BoxShadow(
                        color: fc.accentGlowStrong(kFitGreen),
                        blurRadius: 40, spreadRadius: 4,
                      )],
                    ),
                  ),
                  Text('🤖', style: TextStyle(fontSize: 54 + _ctrl.value * 6)),
                ]),
              ),
              const SizedBox(height: 36),
              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  colors: [fc.accentFg(kFitGreen), fc.accentFg(kFitBlue)],
                ).createShader(b),
                child: Text('Your Fitness Buddy',
                  style: TextStyle(
                    color: fc.textPrimary,
                    fontSize: 28, fontWeight: FontWeight.w900, height: 1.1)),
              ),
              const SizedBox(height: 12),
              Text(
                'An AI companion that evolves as you do.\nBuilt for hostel life, mess food, and busy college schedules.',
                textAlign: TextAlign.center,
                style: TextStyle(color: fc.textHint, fontSize: 14, height: 1.65),
              ),
              const SizedBox(height: 36),
              _FeatureRow(emoji: '🎯', text: 'Personalized plan — gym or bodyweight', fc: fc),
              const SizedBox(height: 10),
              _FeatureRow(emoji: '🍱', text: 'Mess-food friendly Indian diet guide', fc: fc),
              const SizedBox(height: 10),
              _FeatureRow(emoji: '📈', text: 'Buddy evolves as your streak grows', fc: fc),
              const SizedBox(height: 10),
              _FeatureRow(emoji: '⚡', text: '30-second daily check-in, no hassle', fc: fc),
              const SizedBox(height: 40),
              GestureDetector(
                onTap: widget.onStart,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [kFitGreen, Color(0xFF00B880)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                      color: fc.accentGlowStrong(kFitGreen),
                      blurRadius: 24, offset: const Offset(0, 8),
                    )],
                  ),
                  child: const Text('Meet My Buddy', textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ),
              ),
              const SizedBox(height: 10),
              Text('Free • No gym needed • ~2 min setup',
                textAlign: TextAlign.center,
                style: TextStyle(color: fc.textDisabled, fontSize: 11)),
              const SizedBox(height: 36),
            ]),
          ),
          ),
        ),
      ]),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String emoji, text;
  final FitnessColors fc;
  const _FeatureRow({required this.emoji, required this.text, required this.fc});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: fc.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: fc.border),
    ),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 12),
      Text(text, style: TextStyle(color: fc.textSecondary, fontSize: 13)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Buddy Hub
// ─────────────────────────────────────────────────────────────────────────────
class _BuddyHub extends StatefulWidget {
  final FitnessProfile profile;
  final FitnessPlan? plan;
  final BuddyState? buddy;
  final bool checkedIn;
  final VoidCallback onRefresh;

  const _BuddyHub({
    required this.profile, required this.plan, required this.buddy,
    required this.checkedIn, required this.onRefresh,
  });

  @override
  State<_BuddyHub> createState() => _BuddyHubState();
}

class _BuddyHubState extends State<_BuddyHub> with SingleTickerProviderStateMixin {
  late AnimationController _bgCtrl;
  bool _notifsEnabled = false;

  static const _notifPrefKey = 'fitness_notif_enabled';

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..repeat(reverse: true);
    _loadNotifPref();
  }

  Future<void> _loadNotifPref() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_notifPrefKey) ?? false;
    if (mounted) setState(() => _notifsEnabled = enabled);
    if (enabled) {
      await FitnessNotificationService.scheduleAll(widget.profile, widget.buddy);
    }
  }

  Future<void> _toggleNotifs() async {
    final prefs = await SharedPreferences.getInstance();
    final next = !_notifsEnabled;
    await prefs.setBool(_notifPrefKey, next);
    if (next) {
      await FitnessNotificationService.scheduleAll(widget.profile, widget.buddy);
    } else {
      await FitnessNotificationService.cancelAll();
    }
    if (mounted) setState(() => _notifsEnabled = next);
  }

  @override
  void dispose() { _bgCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final fc     = FitnessColors.of(context);
    final color  = buddyColor(widget.profile.buddyPersonality);
    final stage  = widget.buddy?.displayStage ?? 1;
    final streak = widget.buddy?.streakDays ?? 0;

    return Scaffold(
      backgroundColor: fc.bg,
      body: Stack(children: [
        AnimatedBuilder(
          animation: _bgCtrl,
          builder: (ctx, child) => Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(_bgCtrl.value * 0.3 - 0.15, -0.6),
                radius: 1.0,
                colors: [fc.radialBg(color), fc.bg],
              ),
            ),
          ),
        ),
        SafeArea(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Column(children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  Text('Fitness Buddy',
                    style: TextStyle(
                      color: fc.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (streak > 0) _StreakBadge(streak: streak, fc: fc),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _toggleNotifs,
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: _notifsEnabled ? fc.accentBg(kFitGreen) : fc.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _notifsEnabled ? fc.accentBorder(kFitGreen) : fc.border,
                        ),
                      ),
                      child: Icon(
                        _notifsEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_outlined,
                        color: _notifsEnabled ? fc.accentFg(kFitGreen) : fc.textDisabled,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _confirmReset(context, widget.onRefresh),
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: fc.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: fc.border),
                      ),
                      child: Icon(Icons.delete_outline_rounded,
                          color: fc.textDisabled, size: 18),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),

              _BuddyAvatarWidget(
                personality: widget.profile.buddyPersonality,
                stage: stage, size: 160,
                gender: widget.profile.gender,
              ),
              const SizedBox(height: 14),

              // Name + badges
              Text(widget.profile.buddyName,
                style: TextStyle(
                  color: fc.accentFg(color),
                  fontSize: 24, fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: fc.accentGlow(color), blurRadius: 16)],
                )),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _Badge(
                  text: widget.profile.buddyPersonality.toUpperCase(),
                  fgColor: fc.accentFg(color),
                  bgColor: fc.accentBg(color),
                  borderColor: fc.accentBorder(color),
                  letterSpacing: 1.2,
                ),
                const SizedBox(width: 8),
                _Badge(
                  text: 'Stage $stage · ${goalLabel(widget.profile.goal)}',
                  fgColor: fc.textHint,
                  bgColor: fc.surface,
                ),
              ]),

              const SizedBox(height: 18),

              // Last message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: fc.accentBg(color),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: fc.accentBorder(color)),
                    boxShadow: [BoxShadow(
                        color: fc.accentGlow(color),
                        blurRadius: 20, offset: const Offset(0, 4))],
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(buddyEmoji(stage), style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      widget.buddy?.lastMessage ??
                          widget.profile.buddyIntro ??
                          'Hey! Ready to crush today? Tap check-in below! 💪',
                      style: TextStyle(color: fc.textSecondary, fontSize: 13, height: 1.55))),
                  ]),
                ),
              ),

              const SizedBox(height: 20),

              // Macros strip
              if (widget.plan != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    _MacroChip(label: 'Calories', value: '${widget.plan!.dailyCalories}',
                        unit: 'kcal', accent: kFitOrange, fc: fc),
                    const SizedBox(width: 8),
                    _MacroChip(label: 'Protein', value: '${widget.plan!.proteinG}g',
                        unit: 'daily', accent: kFitPurple, fc: fc),
                    const SizedBox(width: 8),
                    _MacroChip(label: 'Carbs', value: '${widget.plan!.carbsG}g',
                        unit: 'daily', accent: kFitBlue, fc: fc),
                  ]),
                ),

              if (widget.plan != null) const SizedBox(height: 20),

              // Today's snapshot
              if (widget.plan != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _TodaySnapshotCard(plan: widget.plan!, accent: color),
                ),

              if (widget.plan != null) const SizedBox(height: 20),

              // Action grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  _CheckInButton(
                    checkedIn: widget.checkedIn,
                    color: color,
                    fc: fc,
                    onTap: widget.checkedIn ? null : () async {
                      await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DailyCheckinScreen(
                            profile: widget.profile, buddy: widget.buddy),
                      ));
                      widget.onRefresh();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    _ActionCard(icon: Icons.chat_bubble_rounded,
                        label: 'Chat', accent: color, fc: fc,
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => BuddyChatScreen(
                              profile: widget.profile,
                              plan: widget.plan,
                              buddy: widget.buddy),
                        ))),
                    const SizedBox(width: 10),
                    _ActionCard(icon: Icons.assignment_rounded,
                        label: 'My Plan', accent: kFitBlue, fc: fc,
                        onTap: widget.plan == null ? null : () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FitnessPlanScreen(
                              profile: widget.profile, plan: widget.plan!)),
                        )),
                    const SizedBox(width: 10),
                    _ActionCard(icon: Icons.show_chart_rounded,
                        label: 'Progress', accent: kFitOrange, fc: fc,
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => FitnessProgressScreen(
                              profile: widget.profile,
                              buddy: widget.buddy,
                              plan: widget.plan),
                        ))),
                  ]),
                ]),
              ),

              const SizedBox(height: 24),

              if (widget.buddy != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _EvolutionBar(buddy: widget.buddy!, color: color, fc: fc),
                ),

              const SizedBox(height: 200),
            ])),
          ]),
        ),
      ]),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Today's snapshot card
// ─────────────────────────────────────────────────────────────────────────────
class _TodaySnapshotCard extends StatefulWidget {
  final FitnessPlan plan;
  final Color accent;
  const _TodaySnapshotCard({required this.plan, required this.accent});

  @override
  State<_TodaySnapshotCard> createState() => _TodaySnapshotCardState();
}

class _TodaySnapshotCardState extends State<_TodaySnapshotCard> {
  int _total = 0, _done = 0;
  bool _loaded = false;

  static String get _todayKey {
    final d = DateTime.now();
    return 'fitness_todo_${d.year}_${d.month}_${d.day}';
  }

  static String get _todayWeekday {
    const days = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    return days[DateTime.now().weekday - 1];
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final plan = widget.plan;
    var total = 1;
    for (final m in ['breakfast','lunch','dinner','snacks']) {
      final opts = plan.dietGuide[m] as List?;
      if (opts != null && opts.isNotEmpty) total++;
    }
    final todayData = plan.workoutPlan[_todayWeekday] as Map<String, dynamic>?;
    final isRest = todayData?['is_rest'] as bool? ?? true;
    if (!isRest && todayData != null) {
      final exs = todayData['exercises'] as List? ?? [];
      total += exs.isEmpty ? 1 : exs.length;
    } else {
      total++;
    }
    total += plan.supplements.length + 1;

    final prefs = await SharedPreferences.getInstance();
    final done = (prefs.getStringList(_todayKey) ?? []).length;
    if (mounted) setState(() { _total = total; _done = done.clamp(0, total); _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final fc = FitnessColors.of(context);
    final progress = _total > 0 ? _done / _total : 0.0;
    final pct = (progress * 100).round();
    final color = widget.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fc.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text("Today's Tasks",
              style: TextStyle(color: fc.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('$_done / $_total',
              style: TextStyle(color: fc.accentFg(color), fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Text('($pct%)', style: TextStyle(color: fc.textHint, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 5, color: fc.border),
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              height: 5,
              width: (MediaQuery.of(context).size.width - 72) * progress,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.6)]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: fc.accentGlow(color), blurRadius: 6)],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          _done == _total && _total > 0
              ? '🎉 All tasks completed! Check in now.'
              : _done == 0
                  ? 'Open Progress tab to tick off your tasks'
                  : '${_total - _done} tasks remaining — keep going!',
          style: TextStyle(
              color: _done == _total ? fc.accentFg(kFitGreen) : fc.textDisabled,
              fontSize: 11),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────
class _CheckInButton extends StatelessWidget {
  final bool checkedIn;
  final Color color;
  final FitnessColors fc;
  final VoidCallback? onTap;
  const _CheckInButton({required this.checkedIn, required this.color,
      required this.fc, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: BoxDecoration(
        gradient: checkedIn
            ? null
            : LinearGradient(
                colors: [color, color.withValues(alpha: 0.75)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
        color: checkedIn ? fc.surface : null,
        borderRadius: BorderRadius.circular(16),
        border: checkedIn ? Border.all(color: fc.border) : null,
        boxShadow: checkedIn
            ? []
            : [BoxShadow(color: fc.accentGlowStrong(color),
                blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          checkedIn ? Icons.check_circle_rounded : Icons.flash_on_rounded,
          color: checkedIn ? fc.textDisabled : Colors.white,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          checkedIn ? 'Checked in today ✓' : "Today's Check-In",
          style: TextStyle(
            color: checkedIn ? fc.textHint : Colors.white,
            fontSize: 15, fontWeight: FontWeight.w800)),
      ]),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final FitnessColors fc;
  final VoidCallback? onTap;
  const _ActionCard({required this.icon, required this.label, required this.accent,
      required this.fc, this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: onTap == null ? fc.surface : fc.accentBg(accent),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: onTap == null ? fc.border : fc.accentBorder(accent)),
        ),
        child: Column(children: [
          Icon(icon, color: onTap == null ? fc.textDisabled : fc.accentFg(accent), size: 22),
          const SizedBox(height: 6),
          Text(label,
            style: TextStyle(
              color: onTap == null ? fc.textDisabled : fc.accentFg(accent),
              fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    ),
  );
}

class _MacroChip extends StatelessWidget {
  final String label, value, unit;
  final Color accent;
  final FitnessColors fc;
  const _MacroChip({required this.label, required this.value, required this.unit,
      required this.accent, required this.fc});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: fc.accentBg(accent),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fc.accentBorder(accent)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(color: fc.accentFg(accent), fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 1),
        Text(unit, style: TextStyle(color: fc.textDisabled, fontSize: 9)),
        Text(label, style: TextStyle(color: fc.textTertiary, fontSize: 9, fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

class _StreakBadge extends StatelessWidget {
  final int streak;
  final FitnessColors fc;
  const _StreakBadge({required this.streak, required this.fc});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: fc.accentBg(kFitRed),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: fc.accentBorder(kFitRed)),
      boxShadow: [BoxShadow(color: fc.accentGlow(kFitRed), blurRadius: 10)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('🔥', style: TextStyle(fontSize: 12)),
      const SizedBox(width: 4),
      Text('$streak day${streak != 1 ? 's' : ''}',
        style: TextStyle(color: fc.accentFg(kFitRed), fontSize: 11, fontWeight: FontWeight.w800)),
    ]),
  );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color fgColor, bgColor;
  final Color? borderColor;
  final double letterSpacing;
  const _Badge({required this.text, required this.fgColor, required this.bgColor,
      this.borderColor, this.letterSpacing = 0});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      border: borderColor != null ? Border.all(color: borderColor!) : null,
    ),
    child: Text(text,
      style: TextStyle(color: fgColor, fontSize: 9,
          fontWeight: FontWeight.w800, letterSpacing: letterSpacing)),
  );
}

class _EvolutionBar extends StatelessWidget {
  final BuddyState buddy;
  final Color color;
  final FitnessColors fc;
  const _EvolutionBar({required this.buddy, required this.color, required this.fc});

  @override
  Widget build(BuildContext context) {
    final progress = buddy.bodyStage >= 10
        ? 1.0
        : (buddy.totalDaysFollowed % 14) / 14.0;
    final stage = buddy.displayStage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fc.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(buddyEmoji(stage), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Buddy Evolution  —  Stage $stage / 5',
              style: TextStyle(color: fc.accentFg(color), fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              buddy.bodyStage >= 10
                  ? 'MAX EVOLUTION REACHED 🌟'
                  : '${buddy.totalDaysFollowed % 14}/14 days to stage ${(stage + 1).clamp(1, 5)}',
              style: TextStyle(color: fc.textHint, fontSize: 10),
            ),
          ])),
          Row(children: List.generate(5, (i) => Icon(
            i < stage ? Icons.star_rounded : Icons.star_outline_rounded,
            color: i < stage ? kFitGold : fc.textDisabled, size: 12,
          ))),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 6, color: fc.border),
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              height: 6,
              width: (MediaQuery.of(context).size.width - 72) * progress,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.8), color]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: fc.accentGlow(color), blurRadius: 8)],
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Buddy avatar with pulsing glow rings
// ─────────────────────────────────────────────────────────────────────────────
class _BuddyAvatarWidget extends StatefulWidget {
  final String personality;
  final int stage;
  final double size;
  final String gender;
  const _BuddyAvatarWidget({required this.personality, required this.stage, required this.size, this.gender = 'male'});

  @override
  State<_BuddyAvatarWidget> createState() => _BuddyAvatarWidgetState();
}

class _BuddyAvatarWidgetState extends State<_BuddyAvatarWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl, _revealCtrl;
  late Animation<double> _pulse, _revealAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _revealCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _revealAnim = CurvedAnimation(parent: _revealCtrl, curve: Curves.elasticOut);
    _revealCtrl.forward();
  }

  @override
  void dispose() { _pulseCtrl.dispose(); _revealCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final fc    = FitnessColors.of(context);
    final color = buddyColor(widget.personality);
    return ScaleTransition(
      scale: _revealAnim,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (ctx, child) {
          final glowOpacity = 0.15 + _pulse.value * 0.10 * widget.stage;
          return Transform.scale(
            scale: 1.0 + _pulse.value * 0.015,
            child: SizedBox(
              width: widget.size, height: widget.size,
              child: Stack(alignment: Alignment.center, children: [
                ...List.generate(widget.stage, (i) {
                  final ringSize = widget.size * (0.92 - i * 0.10);
                  final opacity = (glowOpacity * (1 - i * 0.18)).clamp(0.0, 1.0);
                  return Container(
                    width: ringSize, height: ringSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withValues(alpha: opacity), width: 1.5),
                    ),
                  );
                }),
                Container(
                  width: widget.size * 0.58, height: widget.size * 0.58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      color.withValues(alpha: 0.20 + _pulse.value * 0.10),
                      color.withValues(alpha: 0.04),
                    ]),
                    boxShadow: [BoxShadow(
                      color: fc.accentGlowStrong(color),
                      blurRadius: 30, spreadRadius: 6,
                    )],
                  ),
                ),
                BuddyCharacter(
                    personality: widget.personality,
                    stage: widget.stage,
                    gender: widget.gender,
                    size: widget.size * 0.85),
                Positioned(
                  bottom: 2,
                  child: Row(mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) => Icon(
                      i < widget.stage ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i < widget.stage ? kFitGold : fc.textDisabled, size: 10,
                    ))),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
