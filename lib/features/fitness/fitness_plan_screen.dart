import 'package:flutter/material.dart';
import 'models/fitness_models.dart';
import 'fitness_buddy_screen.dart' show buddyColor, goalLabel;
import 'fitness_theme.dart';
import 'exercise_customizer_screen.dart';

class FitnessPlanScreen extends StatefulWidget {
  final FitnessProfile profile;
  final FitnessPlan plan;
  const FitnessPlanScreen({super.key, required this.profile, required this.plan});

  @override
  State<FitnessPlanScreen> createState() => _FitnessPlanScreenState();
}

class _FitnessPlanScreenState extends State<FitnessPlanScreen> {
  Map<String, List<CustomExercise>> _custom = {};
  Map<String, String> _customLabels = {};

  @override
  void initState() {
    super.initState();
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    final (exercises, labels) = await loadCustomWorkoutFull();
    if (mounted) setState(() { _custom = exercises; _customLabels = labels; });
  }

  Map<String, String> get _aiFocuses => {
    for (final day in ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'])
      if (widget.plan.workoutPlan[day] != null)
        day: (widget.plan.workoutPlan[day] as Map<String, dynamic>)['focus'] as String? ?? '',
  };

  Future<void> _openCustomizer() async {
    final result = await Navigator.push<(Map<String, List<CustomExercise>>, Map<String, String>)>(
      context,
      MaterialPageRoute(builder: (_) => ExerciseCustomizerScreen(
        initial: _custom,
        initialLabels: _customLabels,
        aiFocuses: _aiFocuses,
      )),
    );
    if (result != null && mounted) {
      setState(() { _custom = result.$1; _customLabels = result.$2; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final color = buddyColor(widget.profile.buddyPersonality);
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
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.arrow_back_ios_new_rounded, color: fc.textSecondary, size: 20),
                ),
                const SizedBox(width: 12),
                Text('My Fitness Plan', style: TextStyle(color: fc.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 4),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Header card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [fc.accentBgStrong(color), fc.accentBg(color)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: fc.accentBorder(color)),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(goalLabel(widget.profile.goal),
                          style: TextStyle(color: fc.accentFg(color), fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('${widget.plan.durationWeeks}-week plan • ${widget.profile.hasGymAccess ? "Gym" : "Bodyweight"} • ${_foodLabel(widget.profile.foodType)}',
                          style: TextStyle(color: fc.textTertiary, fontSize: 11)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${widget.plan.dailyCalories}', style: TextStyle(color: fc.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                        Text('kcal/day', style: TextStyle(color: fc.textHint, fontSize: 10)),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 20),

                  // Macros
                  _SectionTitle(title: '📊 Daily Macros', color: color),
                  const SizedBox(height: 12),
                  Row(children: [
                    _MacroCard(label: 'Protein', value: '${widget.plan.proteinG}g', color: kFitPurple, emoji: '🥩'),
                    const SizedBox(width: 8),
                    _MacroCard(label: 'Carbs', value: '${widget.plan.carbsG}g', color: kFitOrange, emoji: '🍚'),
                    const SizedBox(width: 8),
                    _MacroCard(label: 'Fat', value: '${widget.plan.fatG}g', color: kFitRed, emoji: '🥑'),
                  ]),

                  const SizedBox(height: 8),
                  // Macro bars
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: fc.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: fc.border),
                    ),
                    child: Column(children: [
                      _MacroBar(label: 'Protein', grams: widget.plan.proteinG, total: widget.plan.dailyCalories, calsPerG: 4, color: kFitPurple),
                      const SizedBox(height: 10),
                      _MacroBar(label: 'Carbs', grams: widget.plan.carbsG, total: widget.plan.dailyCalories, calsPerG: 4, color: kFitOrange),
                      const SizedBox(height: 10),
                      _MacroBar(label: 'Fat', grams: widget.plan.fatG, total: widget.plan.dailyCalories, calsPerG: 9, color: kFitRed),
                    ]),
                  ),

                  const SizedBox(height: 24),

                  // Weekly workout
                  Row(children: [
                    Expanded(child: _SectionTitle(title: '🏋️ Weekly Workout', color: color)),
                    if (widget.profile.hasGymAccess)
                      GestureDetector(
                        onTap: _openCustomizer,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: kFitOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: kFitOrange.withValues(alpha: 0.4)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.tune_rounded, color: kFitOrange, size: 13),
                            const SizedBox(width: 5),
                            Text('Customize',
                                style: TextStyle(color: kFitOrange, fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  ...['monday','tuesday','wednesday','thursday','friday','saturday','sunday'].map((day) {
                    final dayData = widget.plan.workoutPlan[day] as Map<String, dynamic>?;
                    if (dayData == null) return const SizedBox();
                    return _DayCard(
                      day: day, dayData: dayData, color: color,
                      customExercises: _custom[day],
                      customLabel: _customLabels[day],
                    );
                  }),

                  const SizedBox(height: 24),

                  // Diet guide
                  _SectionTitle(title: '🍱 Diet Guide', color: color),
                  const SizedBox(height: 12),
                  _DietSection(dietGuide: widget.plan.dietGuide),

                  // Projected gains
                  if (widget.plan.projectedGains.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(title: '📈 Expected Progress', color: color),
                    const SizedBox(height: 12),
                    _GainsSection(gains: widget.plan.projectedGains, color: color),
                  ],

                  // Key tips
                  if (widget.plan.keyTips.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(title: '💡 Key Tips', color: color),
                    const SizedBox(height: 12),
                    ...widget.plan.keyTips.asMap().entries.map((e) => _TipRow(index: e.key + 1, tip: e.value)),
                  ],

                  // Supplements
                  if (widget.plan.supplements.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionTitle(title: '💊 Supplement Guide', color: color),
                    const SizedBox(height: 4),
                    Text(
                      'Whole foods first — supplements fill gaps, not replace meals.',
                      style: TextStyle(color: fc.textHint, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    ...widget.plan.supplements.map((s) => _SupplementCard(item: s, color: color)),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _foodLabel(String f) => f == 'mess' ? 'Mess Food' : f == 'canteen' ? 'Canteen' : 'Home Cooked';
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Text(title,
      style: TextStyle(color: fc.accentFg(color), fontSize: 14, fontWeight: FontWeight.w700));
  }
}

class _MacroCard extends StatelessWidget {
  final String label, value, emoji;
  final Color color;
  const _MacroCard({required this.label, required this.value, required this.emoji, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: fc.accentBg(color),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fc.accentBorder(color)),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: fc.accentFg(color), fontSize: 15, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: fc.textHint, fontSize: 10)),
        ]),
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  final String label;
  final int grams, total, calsPerG;
  final Color color;
  const _MacroBar({required this.label, required this.grams, required this.total, required this.calsPerG, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final cals = grams * calsPerG;
    final fraction = total > 0 ? cals / total : 0.0;
    return Row(children: [
      SizedBox(width: 50, child: Text(label, style: TextStyle(color: fc.textTertiary, fontSize: 11))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            backgroundColor: fc.border,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('${(fraction * 100).round()}%', style: TextStyle(color: fc.accentFg(color), fontSize: 10, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _DayCard extends StatefulWidget {
  final String day;
  final Map<String, dynamic> dayData;
  final Color color;
  final List<CustomExercise>? customExercises;
  final String? customLabel;
  const _DayCard({
    required this.day,
    required this.dayData,
    required this.color,
    this.customExercises,
    this.customLabel,
  });

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  bool _expanded = false;

  bool get _hasCustom => widget.customExercises != null && widget.customExercises!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final isRest = widget.dayData['is_rest'] as bool? ?? false;
    final focus = widget.dayData['focus'] as String? ?? '';
    final aiExercises = (widget.dayData['exercises'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Show custom exercises if available, otherwise show AI exercises
    final showCustom = _hasCustom;
    final displayCount = showCustom ? widget.customExercises!.length : aiExercises.length;
    final displayFocus = widget.customLabel?.isNotEmpty == true ? widget.customLabel! : focus;
    final hasExercises = displayCount > 0;

    return GestureDetector(
      onTap: (isRest && !_hasCustom) ? null : () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: fc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRest && !_hasCustom ? fc.border : fc.accentBorder(widget.color),
          ),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Text(_dayLabel(widget.day),
                style: TextStyle(
                  color: isRest && !_hasCustom ? fc.textHint : fc.textPrimary,
                  fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(child: Text(displayFocus,
                style: TextStyle(
                  color: isRest && !_hasCustom ? fc.textDisabled : fc.accentFg(widget.color),
                  fontSize: 12))),
              if (showCustom) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kFitOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('CUSTOM',
                      style: TextStyle(color: kFitOrange, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                ),
                const SizedBox(width: 6),
              ],
              if (hasExercises || _hasCustom) ...[
                Text('$displayCount exercise${displayCount == 1 ? '' : 's'}',
                    style: TextStyle(color: fc.textHint, fontSize: 10)),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: fc.textHint, size: 16),
              ] else if (isRest)
                Text('REST', style: TextStyle(color: fc.textDisabled, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ]),
          ),
          if (_expanded) ...[
            // Custom exercises
            if (showCustom)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: fc.accentBorder(widget.color))),
                ),
                child: Column(
                  children: widget.customExercises!.map((ex) => _ExerciseRow(
                    ex: {'name': ex.name, 'sets': ex.sets, 'reps': ex.reps, 'rest': ex.rest},
                    color: widget.color,
                  )).toList(),
                ),
              )
            // AI exercises
            else if (aiExercises.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: fc.accentBorder(widget.color))),
                ),
                child: Column(
                  children: aiExercises.map((ex) => _ExerciseRow(ex: ex, color: widget.color)).toList(),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  String _dayLabel(String d) => d[0].toUpperCase() + d.substring(1, 3);
}

class _ExerciseRow extends StatelessWidget {
  final Map<String, dynamic> ex;
  final Color color;
  const _ExerciseRow({required this.ex, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Container(width: 4, height: 4, decoration: BoxDecoration(color: fc.accentFg(color), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(ex['name'] as String? ?? '', style: TextStyle(color: fc.textSecondary, fontSize: 12))),
        Text('${ex['sets']} × ${ex['reps']}', style: TextStyle(color: fc.accentFg(color), fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(ex['rest'] as String? ?? '', style: TextStyle(color: fc.textHint, fontSize: 10)),
      ]),
    );
  }
}

class _DietSection extends StatelessWidget {
  final Map<String, dynamic> dietGuide;
  const _DietSection({required this.dietGuide});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final meals = [
      ('🌅', 'Breakfast', 'breakfast'),
      ('☀️', 'Lunch', 'lunch'),
      ('🌙', 'Dinner', 'dinner'),
      ('🍎', 'Snacks', 'snacks'),
    ];

    final goalNote   = dietGuide['goal_note']   as String?;
    final calSummary = dietGuide['cal_summary']  as String?;

    return Column(children: [
      // ── Goal note banner ────────────────────────────────────────
      if (goalNote != null && goalNote.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: fc.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: fc.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (calSummary != null && calSummary.isNotEmpty) ...[
              Text(calSummary,
                style: TextStyle(color: fc.textHint, fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
            ],
            Text(goalNote,
              style: TextStyle(color: fc.textSecondary, fontSize: 12, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      // ── Meal cards ──────────────────────────────────────────────
      ...meals.map((m) {
        final items = (dietGuide[m.$3] as List?)?.cast<String>() ?? [];
        if (items.isEmpty) return const SizedBox();
        return _MealCard(emoji: m.$1, meal: m.$2, options: items);
      }),
      // ── Hydration ───────────────────────────────────────────────
      if (dietGuide['hydration'] != null) ...[
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: fc.accentBg(kFitGreen),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: fc.accentBorder(kFitGreen)),
          ),
          child: Row(children: [
            const Text('💧', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(child: Text(dietGuide['hydration'] as String,
              style: TextStyle(color: fc.textTertiary, fontSize: 12))),
          ]),
        ),
      ],
    ]);
  }
}

class _MealCard extends StatelessWidget {
  final String emoji, meal;
  final List<String> options;
  const _MealCard({required this.emoji, required this.meal, required this.options});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fc.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(meal, style: TextStyle(color: fc.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        ...options.map((opt) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('• ', style: TextStyle(color: fc.textHint, fontSize: 12)),
            Expanded(child: Text(opt, style: TextStyle(color: fc.textTertiary, fontSize: 12))),
          ]),
        )),
      ]),
    );
  }
}

class _GainsSection extends StatelessWidget {
  final Map<String, dynamic> gains;
  final Color color;
  const _GainsSection({required this.gains, required this.color});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final timeline = [('Week 4', gains['week4']), ('Week 8', gains['week8']), ('Week 12', gains['week12'])];
    return Row(children: timeline.asMap().entries.map((e) {
      final i = e.key;
      final t = e.value;
      return Expanded(child: Padding(
        padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06 + i * 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.15 + i * 0.05)),
          ),
          child: Column(children: [
            Text(t.$1, style: TextStyle(color: fc.accentFg(color), fontSize: 10, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(t.$2?.toString() ?? '', style: TextStyle(color: fc.textTertiary, fontSize: 10, height: 1.4), textAlign: TextAlign.center),
          ]),
        ),
      ));
    }).toList());
  }
}

class _TipRow extends StatelessWidget {
  final int index;
  final String tip;
  const _TipRow({required this.index, required this.tip});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(color: fc.accentBgStrong(kFitOrange), shape: BoxShape.circle),
          child: Center(child: Text('$index', style: TextStyle(color: fc.accentFg(kFitOrange), fontSize: 10, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(tip, style: TextStyle(color: fc.textTertiary, fontSize: 13, height: 1.5))),
      ]),
    );
  }
}

class _SupplementCard extends StatelessWidget {
  final SupplementItem item;
  final Color color;
  const _SupplementCard({required this.item, required this.color});

  Color _priorityColor(FitnessColors fc) {
    switch (item.priority) {
      case 'high':     return kFitGreen;
      case 'medium':   return kFitOrange;
      default:         return fc.textHint;
    }
  }

  String get _priorityLabel {
    switch (item.priority) {
      case 'high':     return 'MUST HAVE';
      case 'medium':   return 'HELPFUL';
      default:         return 'OPTIONAL';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final pc = _priorityColor(fc);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fc.accentBorder(pc)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: fc.accentBgStrong(pc),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(child: Text('💊', style: TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(item.name,
                  style: TextStyle(color: fc.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: fc.accentBgStrong(pc),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_priorityLabel,
                  style: TextStyle(color: fc.accentFg(pc), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(item.why, style: TextStyle(color: fc.textTertiary, fontSize: 12, height: 1.4)),
            const SizedBox(height: 6),
            Row(children: [
              _Pill(icon: Icons.scale_outlined, text: item.dose),
              const SizedBox(width: 6),
              _Pill(icon: Icons.schedule_outlined, text: item.timing),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: fc.textHint),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: fc.textTertiary, fontSize: 11)),
      ]),
    );
  }
}
