import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/fitness_models.dart';
import 'services/fitness_service.dart';
import 'fitness_buddy_screen.dart' show buddyColor, buddyEmoji;
import 'fitness_theme.dart';
import 'exercise_customizer_screen.dart';

class FitnessProgressScreen extends StatefulWidget {
  final FitnessProfile profile;
  final BuddyState? buddy;
  final FitnessPlan? plan;
  const FitnessProgressScreen({super.key, required this.profile, required this.buddy, this.plan});

  @override
  State<FitnessProgressScreen> createState() => _FitnessProgressScreenState();
}

class _FitnessProgressScreenState extends State<FitnessProgressScreen> {
  List<FitnessLog> _logs = [];
  bool _loading = true;
  BuddyState? _buddy;

  @override
  void initState() {
    super.initState();
    _buddy = widget.buddy;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        FitnessService.getRecentLogs(days: 30),
        FitnessService.getBuddyState(),
      ]);
      _logs = results[0] as List<FitnessLog>;
      _buddy = results[1] as BuddyState?;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _handleAllDone() async {
    try {
      final currentBuddy = _buddy;
      if (currentBuddy == null) {
        await _load();
        return;
      }
      // Log is already submitted in _DailyTodoCard._toggle
      // Just update buddy state
      final log = FitnessLog(
        userId: '',
        logDate: DateTime.now(),
        workoutDone: true,
        dietFollowed: 'yes',
        mood: 4,
      );
      final updated = await FitnessService.updateBuddyAfterCheckin(
        current: currentBuddy,
        log: log,
        newMessage: _congratsMessage(),
      );
      if (mounted) setState(() => _buddy = updated);
    } catch (_) {}
    await _load();
  }

  String _congratsMessage() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning grind done! Every check ✓ builds the streak 🔥';
    if (h < 17) return 'Afternoon hustle locked in! Keep the momentum going 💪';
    return 'Day complete! Rest up and come back stronger tomorrow 🌙';
  }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final color = buddyColor(widget.profile.buddyPersonality);
    final buddy = _buddy ?? widget.buddy;

    return Scaffold(
      backgroundColor: fc.bg,
      body: Stack(children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.8),
              radius: 0.9,
              colors: [fc.radialBg(color), fc.bg],
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.arrow_back_ios_new_rounded, color: fc.textSecondary, size: 20),
                ),
                const SizedBox(width: 12),
                Text('My Progress', style: TextStyle(color: fc.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),

            if (_loading)
              Expanded(child: Center(child: CircularProgressIndicator(color: kFitGreen)))
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // Daily todo
                    if (widget.plan != null) ...[
                      _SectionTitle(title: "✅ Today's Tasks", color: color),
                      const SizedBox(height: 12),
                      _DailyTodoCard(plan: widget.plan!, color: color, onAllDone: _handleAllDone),
                      const SizedBox(height: 24),
                    ],

                    // Buddy evolution card
                    if (buddy != null) ...[
                      _EvolutionCard(buddy: buddy, color: color),
                      const SizedBox(height: 20),
                    ],

                    // Stats summary
                    _SectionTitle(title: '📊 Last 30 Days', color: color),
                    const SizedBox(height: 12),
                    _StatsGrid(logs: _logs, color: color),

                    const SizedBox(height: 24),

                    // Streak calendar
                    _SectionTitle(title: '📅 Consistency Calendar', color: color),
                    const SizedBox(height: 12),
                    _ConsistencyCalendar(logs: _logs, color: color),

                    // Weight chart
                    if (_logs.any((l) => l.weightKg != null)) ...[
                      const SizedBox(height: 24),
                      _SectionTitle(title: '⚖️ Weight Trend', color: color),
                      const SizedBox(height: 12),
                      _WeightChart(logs: _logs.where((l) => l.weightKg != null).toList(), color: color),
                    ],

                    const SizedBox(height: 24),
                    _SectionTitle(title: '📝 Recent Logs', color: color),
                    const SizedBox(height: 12),
                    if (_logs.isEmpty)
                      Center(child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(children: [
                          const Text('📋', style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 12),
                          Text('No logs yet', style: TextStyle(color: fc.textHint, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('Start your first check-in!', style: TextStyle(color: fc.textDisabled, fontSize: 12)),
                        ]),
                      ))
                    else
                      ..._logs.take(14).map((log) => _LogRow(log: log, color: color)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Text(title, style: TextStyle(color: fc.accentFg(color), fontSize: 14, fontWeight: FontWeight.w700));
  }
}

class _EvolutionCard extends StatelessWidget {
  final BuddyState buddy;
  final Color color;
  const _EvolutionCard({required this.buddy, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final stage = buddy.displayStage;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [fc.accentBgStrong(color), fc.accentBg(color)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fc.accentBorder(color)),
      ),
      child: Column(children: [
        Row(children: [
          Text(buddyEmoji(stage), style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Stage $stage / 5', style: TextStyle(color: fc.accentFg(color), fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${buddy.totalDaysFollowed} consistent days total', style: TextStyle(color: fc.textTertiary, fontSize: 12)),
            const SizedBox(height: 2),
            Text('🔥 ${buddy.streakDays} day current streak', style: TextStyle(color: fc.accentFg(kFitRed), fontSize: 11, fontWeight: FontWeight.w600)),
          ])),
          Column(
            children: List.generate(5, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Icon(
                i < stage ? Icons.star_rounded : Icons.star_border_rounded,
                color: i < stage ? color : fc.border, size: 16,
              ),
            )).reversed.toList(),
          ),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: buddy.bodyStage >= 10 ? 1.0 : (buddy.totalDaysFollowed % 14) / 14.0,
            backgroundColor: fc.border,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          buddy.bodyStage >= 10 ? 'MAX LEVEL REACHED 🌟' : '${buddy.totalDaysFollowed % 14}/14 days to stage ${(buddy.displayStage + 1).clamp(1, 5)}',
          style: TextStyle(color: fc.textHint, fontSize: 10),
        ),
      ]),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final List<FitnessLog> logs;
  final Color color;
  const _StatsGrid({required this.logs, required this.color});

  @override
  Widget build(BuildContext context) {
    final total = logs.length;
    final workouts = logs.where((l) => l.workoutDone).length;
    final fullDiet = logs.where((l) => l.dietFollowed == 'yes').length;
    final consistency = total > 0 ? (workouts / total * 100).round() : 0;

    return Row(children: [
      _StatBox(label: 'Days Logged', value: '$total', emoji: '📋', color: color),
      const SizedBox(width: 8),
      _StatBox(label: 'Workouts Done', value: '$workouts', emoji: '💪', color: kFitPurple),
      const SizedBox(width: 8),
      _StatBox(label: 'Full Diet Days', value: '$fullDiet', emoji: '🍱', color: kFitOrange),
      const SizedBox(width: 8),
      _StatBox(label: 'Consistency', value: '$consistency%', emoji: '📈', color: kFitGreen),
    ]);
  }
}

class _StatBox extends StatelessWidget {
  final String label, value, emoji;
  final Color color;
  const _StatBox({required this.label, required this.value, required this.emoji, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: fc.accentBg(color),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fc.accentBorder(color)),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: fc.accentFg(color), fontSize: 14, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: fc.textHint, fontSize: 8), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _ConsistencyCalendar extends StatelessWidget {
  final List<FitnessLog> logs;
  final Color color;
  const _ConsistencyCalendar({required this.logs, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final logMap = <String, FitnessLog>{};
    for (final l in logs) {
      final key = '${l.logDate.year}-${l.logDate.month.toString().padLeft(2, '0')}-${l.logDate.day.toString().padLeft(2, '0')}';
      logMap[key] = l;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fc.border),
      ),
      child: Wrap(
        spacing: 4, runSpacing: 4,
        children: List.generate(30, (i) {
          final day = DateTime.now().subtract(Duration(days: 29 - i));
          final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
          final log = logMap[key];
          Color cellColor;
          if (log == null) {
            cellColor = fc.surface;
          } else if (log.workoutDone && log.dietFollowed == 'yes') {
            cellColor = color;
          } else if (log.workoutDone || log.dietFollowed != 'no') {
            cellColor = color.withValues(alpha: 0.4);
          } else {
            cellColor = kFitRed.withValues(alpha: 0.3);
          }

          return Tooltip(
            message: '${day.day}/${day.month}',
            child: Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: cellColor, borderRadius: BorderRadius.circular(4)),
              child: log != null ? Center(child: Text(
                log.workoutDone ? '✓' : '·',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              )) : null,
            ),
          );
        }),
      ),
    );
  }
}

class _WeightChart extends StatelessWidget {
  final List<FitnessLog> logs;
  final Color color;
  const _WeightChart({required this.logs, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final sorted = logs.where((l) => l.weightKg != null).toList()
      ..sort((a, b) => a.logDate.compareTo(b.logDate));

    if (sorted.isEmpty) return const SizedBox();

    final weights = sorted.map((l) => l.weightKg!).toList();
    final minW = weights.reduce((a, b) => a < b ? a : b) - 2;
    final maxW = weights.reduce((a, b) => a > b ? a : b) + 2;
    final first = weights.first;
    final last = weights.last;
    final diff = last - first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fc.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${last.toStringAsFixed(1)} kg', style: TextStyle(color: fc.accentFg(color), fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: diff <= 0 ? fc.accentBgStrong(kFitGreen) : fc.accentBgStrong(kFitRed),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} kg',
              style: TextStyle(
                color: diff <= 0 ? fc.accentFg(kFitGreen) : fc.accentFg(kFitRed),
                fontSize: 11, fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Text('${sorted.length} readings', style: TextStyle(color: fc.textHint, fontSize: 10)),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 80,
          child: CustomPaint(
            painter: _WeightChartPainter(weights: weights, minW: minW, maxW: maxW, color: color),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text('${first.toStringAsFixed(1)} kg', style: TextStyle(color: fc.textHint, fontSize: 10)),
          const Spacer(),
          Text('${last.toStringAsFixed(1)} kg', style: TextStyle(color: fc.textHint, fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  final List<double> weights;
  final double minW, maxW;
  final Color color;
  const _WeightChartPainter({required this.weights, required this.minW, required this.maxW, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.3), Colors.transparent],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < weights.length; i++) {
      final x = i / (weights.length - 1) * size.width;
      final y = size.height - ((weights[i] - minW) / (maxW - minW)) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, paint);

    // Dots
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    for (int i = 0; i < weights.length; i++) {
      final x = i / (weights.length - 1) * size.width;
      final y = size.height - ((weights[i] - minW) / (maxW - minW)) * size.height;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WeightChartPainter old) => old.weights != weights;
}

class _LogRow extends StatelessWidget {
  final FitnessLog log;
  final Color color;
  const _LogRow({required this.log, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${log.logDate.day} ${months[log.logDate.month - 1]}';
    final moodEmojis = ['', '😩', '😔', '😐', '😊', '🔥'];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fc.border),
      ),
      child: Row(children: [
        SizedBox(width: 44, child: Text(dateStr, style: TextStyle(color: fc.textHint, fontSize: 11))),
        const SizedBox(width: 8),
        _LogDot(value: log.workoutDone, trueLabel: '💪', falseLabel: '—'),
        const SizedBox(width: 6),
        _LogDot(value: log.dietFollowed == 'yes', trueLabel: '🍱', falseLabel: log.dietFollowed == 'partial' ? '½' : '—'),
        const SizedBox(width: 8),
        Text(moodEmojis[log.mood.clamp(1, 5)], style: const TextStyle(fontSize: 14)),
        const Spacer(),
        if (log.weightKg != null)
          Text('${log.weightKg!.toStringAsFixed(1)} kg', style: TextStyle(color: fc.accentFg(color), fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _LogDot extends StatelessWidget {
  final bool value;
  final String trueLabel, falseLabel;
  const _LogDot({required this.value, required this.trueLabel, required this.falseLabel});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Container(
      width: 28, height: 24,
      decoration: BoxDecoration(
        color: value ? fc.accentBgStrong(kFitGreen) : fc.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(child: Text(
        value ? trueLabel : falseLabel,
        style: TextStyle(fontSize: value ? 12 : 10, color: value ? null : fc.textDisabled),
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DAILY TODO CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TodoItem {
  final String id;
  final String emoji;
  final String title;
  final String? subtitle;
  final String timeLabel; // e.g. "7–10 AM", "All day", "5–9 PM"
  bool done = false;
  _TodoItem({required this.id, required this.emoji, required this.title,
    this.subtitle, required this.timeLabel});
}

class _DailyTodoCard extends StatefulWidget {
  final FitnessPlan plan;
  final Color color;
  final VoidCallback? onAllDone;
  const _DailyTodoCard({required this.plan, required this.color, this.onAllDone});

  @override
  State<_DailyTodoCard> createState() => _DailyTodoCardState();
}

class _DailyTodoCardState extends State<_DailyTodoCard> {
  List<_TodoItem> _items = [];
  bool _loaded = false;
  Map<String, List<CustomExercise>> _customWorkout = {};

  static String get _todayKey {
    final d = DateTime.now();
    return 'fitness_todo_${d.year}_${d.month}_${d.day}';
  }

  static String get _todayWeekday {
    const days = ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
    return days[DateTime.now().weekday - 1];
  }

  @override
  void initState() {
    super.initState();
    _buildAndLoad();
  }

  Future<void> _buildAndLoad() async {
    _customWorkout = await loadCustomWorkout();
    final items = _buildItems();
    final prefs = await SharedPreferences.getInstance();
    final doneIds = prefs.getStringList(_todayKey) ?? [];
    for (final item in items) {
      item.done = doneIds.contains(item.id);
    }
    if (mounted) setState(() { _items = items; _loaded = true; });
  }

  List<_TodoItem> _buildItems() {
    final plan = widget.plan;
    final items = <_TodoItem>[];

    items.add(_TodoItem(
      id: 'water', emoji: '💧', title: 'Drink 3–4 litres of water',
      subtitle: plan.dietGuide['hydration'] as String?,
      timeLabel: 'All day',
    ));

    const mealMap = [
      ('breakfast', '🍳', 'Have breakfast'),
      ('lunch',     '🍱', 'Have lunch'),
      ('dinner',    '🌙', 'Have dinner'),
      ('snacks',    '🥜', 'Healthy snack'),
    ];
    for (final (key, emoji, label) in mealMap) {
      final opts = plan.dietGuide[key] as List?;
      if (opts != null && opts.isNotEmpty) {
        final String timeLabel;
        switch (key) {
          case 'breakfast': timeLabel = 'Morning';   break; // 4 AM – 12 PM
          case 'lunch':     timeLabel = 'Afternoon'; break; // 12 PM – 5 PM
          case 'snacks':    timeLabel = 'Afternoon'; break; // 12 PM – 5 PM
          case 'dinner':    timeLabel = 'Evening';   break; // 5 PM – 9 PM
          default:          timeLabel = 'Anytime';
        }
        items.add(_TodoItem(
          id: 'meal_$key', emoji: emoji, title: label,
          subtitle: opts.map((e) => e.toString()).join('\n'),
          timeLabel: timeLabel,
        ));
      }
    }

    final todayData = plan.workoutPlan[_todayWeekday] as Map<String, dynamic>?;
    final customExercises = _customWorkout[_todayWeekday];
    final hasCustom = customExercises != null && customExercises.isNotEmpty;
    final isRest = !hasCustom && (todayData?['is_rest'] as bool? ?? true);

    if (hasCustom) {
      // Use custom exercises
      for (var i = 0; i < customExercises.length; i++) {
        final ex = customExercises[i];
        items.add(_TodoItem(
          id: 'ex_$i', emoji: '🏋️', title: ex.name,
          subtitle: '${ex.sets} sets × ${ex.reps}  •  Rest ${ex.rest}',
          timeLabel: 'Anytime',
        ));
      }
    } else if (!isRest && todayData != null) {
      // Use AI exercises
      final exercises = todayData['exercises'] as List? ?? [];
      final focus = todayData['focus'] as String? ?? 'Workout';
      for (var i = 0; i < exercises.length; i++) {
        final ex = exercises[i] as Map<String, dynamic>;
        final name = ex['name'] as String? ?? '';
        final sets = ex['sets']?.toString() ?? '';
        final reps = ex['reps']?.toString() ?? '';
        items.add(_TodoItem(
          id: 'ex_$i', emoji: '🏋️', title: name,
          subtitle: '$sets sets × $reps  •  Rest ${ex['rest'] ?? '60s'}',
          timeLabel: 'Anytime',
        ));
      }
      if (exercises.isEmpty) {
        items.add(_TodoItem(id: 'workout', emoji: '🏋️', title: focus, timeLabel: 'Anytime'));
      }
    } else {
      items.add(_TodoItem(
        id: 'rest', emoji: '😴', title: 'Rest & Recovery day',
        subtitle: 'Light stretching or a walk is fine',
        timeLabel: 'All day',
      ));
    }

    for (var i = 0; i < plan.supplements.length; i++) {
      final s = plan.supplements[i];
      items.add(_TodoItem(
        id: 'supp_$i', emoji: '💊', title: s.name,
        subtitle: '${s.dose}  •  ${s.timing}',
        timeLabel: 'As scheduled',
      ));
    }

    items.add(_TodoItem(id: 'sleep', emoji: '🛌', title: 'Sleep 7–8 hours tonight', timeLabel: 'Night'));
    return items;
  }

  Future<void> _toggle(int index) async {
    setState(() => _items[index].done = !_items[index].done);
    final prefs = await SharedPreferences.getInstance();
    final doneIds = _items.where((i) => i.done).map((i) => i.id).toList();
    await prefs.setStringList(_todayKey, doneIds);

    // Auto-submit when all tasks done for the first time today
    final allDone = _items.every((i) => i.done);
    final now = DateTime.now();
    final submitKey = 'fitness_checkin_done_${now.year}_${now.month}_${now.day}';
    final alreadySubmitted = prefs.getBool(submitKey) ?? false;
    if (allDone && !alreadySubmitted) {
      await prefs.setBool(submitKey, true);
      try {
        final hasExercises = _items.any((i) => i.id.startsWith('ex_') || i.id == 'workout');
        final mealItems = _items.where((i) => i.id.startsWith('meal_')).toList();
        final mealsDone = mealItems.where((i) => i.done).length;
        final dietFollowed = mealItems.isEmpty || mealsDone == mealItems.length ? 'yes'
            : mealsDone > 0 ? 'partial' : 'no';
        final workoutDone = !hasExercises || _items.any((i) => (i.id.startsWith('ex_') || i.id == 'workout') && i.done);

        final log = FitnessLog(
          userId: '',
          logDate: DateTime.now(),
          workoutDone: workoutDone,
          dietFollowed: dietFollowed,
          mood: 4,
        );
        await FitnessService.submitLog(log);
      } catch (_) {}
      widget.onAllDone?.call();
    }
  }

  Color _timeBadgeColor(String timeLabel, FitnessColors fc) {
    switch (timeLabel) {
      case 'Morning':   return kFitOrange;                   // 4 AM – 12 PM
      case 'Afternoon': return kFitGreen;                    // 12 PM – 5 PM
      case 'Evening':   return kFitRed;                      // 5 PM – 9 PM
      case 'Night':     return const Color(0xFF7B5EFF);      // 9 PM – 4 AM
      default:          return fc.textHint;                  // All day, Anytime, As scheduled
    }
  }

  bool _isActive(String timeLabel, int hour) {
    switch (timeLabel) {
      case 'Morning':   return hour >= 4 && hour < 12;
      case 'Afternoon': return hour >= 12 && hour < 17;
      case 'Evening':   return hour >= 17 && hour < 21;
      case 'Night':     return hour >= 21 || hour < 4;
      default:          return false;
    }
  }

  Widget _buildTaskRow(BuildContext context, _TodoItem item, VoidCallback onTap) {
    final fc = FitnessColors.of(context);
    final hour = DateTime.now().hour;
    final active = !item.done && _isActive(item.timeLabel, hour);
    final badgeColor = _timeBadgeColor(item.timeLabel, fc);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? badgeColor.withValues(alpha: 0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? badgeColor.withValues(alpha: 0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Checkbox
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: item.done ? widget.color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: item.done ? widget.color : fc.textDisabled, width: 1.5),
            ),
            child: item.done ? Icon(Icons.check_rounded, size: 14, color: widget.color) : null,
          ),
          const SizedBox(width: 10),
          // Content
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(item.title,
                    style: TextStyle(
                      color: item.done ? fc.textHint : fc.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w500,
                      decoration: item.done ? TextDecoration.lineThrough : null,
                      decorationColor: fc.textHint,
                    )),
                ),
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('NOW', style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
              ]),
              if (item.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(item.subtitle!,
                  style: TextStyle(
                    color: item.done ? fc.textDisabled : fc.textHint,
                    fontSize: 11, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          // Right side: emoji + time badge
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(item.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(item.timeLabel,
                style: TextStyle(color: item.done ? fc.textDisabled : badgeColor, fontSize: 8, fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    if (!_loaded) {
      return SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: fc.textDisabled)),
      );
    }

    final done = _items.where((i) => i.done).length;
    final total = _items.length;
    final progress = total > 0 ? done / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fc.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$done/$total done',
              style: TextStyle(color: fc.accentFg(widget.color), fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (done == total && total > 0)
            Text('All done! 🎉',
                style: TextStyle(color: fc.accentFg(kFitGreen), fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: fc.border,
            valueColor: AlwaysStoppedAnimation(
              done == total ? kFitGreen : widget.color,
            ),
            minHeight: 5,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_items.length, (i) =>
          _buildTaskRow(context, _items[i], () => _toggle(i)),
        ),
      ]),
    );
  }
}
