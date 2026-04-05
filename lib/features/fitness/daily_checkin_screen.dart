import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/fitness_models.dart';
import 'services/fitness_service.dart';
import 'services/fitness_ai_service.dart';
import 'fitness_buddy_screen.dart' show buddyColor, buddyEmoji;
import 'fitness_theme.dart';

class DailyCheckinScreen extends StatefulWidget {
  final FitnessProfile profile;
  final BuddyState? buddy;
  const DailyCheckinScreen({super.key, required this.profile, required this.buddy});

  @override
  State<DailyCheckinScreen> createState() => _DailyCheckinScreenState();
}

class _DailyCheckinScreenState extends State<DailyCheckinScreen>
    with SingleTickerProviderStateMixin {
  String _diet = 'no';
  bool _workout = false;
  int _mood = 3;
  final _weightCtrl = TextEditingController();
  bool _submitting = false;
  bool _prefilled = false;

  late AnimationController _celebCtrl;

  static String get _todayKey {
    final d = DateTime.now();
    return 'fitness_todo_${d.year}_${d.month}_${d.day}';
  }

  @override
  void initState() {
    super.initState();
    _celebCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _prefillFromTodos();
  }

  Future<void> _prefillFromTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final doneIds = prefs.getStringList(_todayKey) ?? [];
    if (doneIds.isEmpty) return;

    final workoutDone = doneIds.any(
        (id) => id.startsWith('ex_') || id == 'workout' || id == 'rest');

    final meals = ['meal_breakfast', 'meal_lunch', 'meal_dinner'];
    final doneMeals = meals.where(doneIds.contains).length;
    final String diet;
    if (doneMeals == meals.length) {
      diet = 'yes';
    } else if (doneMeals > 0) {
      diet = 'partial';
    } else {
      diet = 'no';
    }

    if (mounted) {
      setState(() { _workout = workoutDone; _diet = diet; _prefilled = doneIds.isNotEmpty; });
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _celebCtrl.dispose();
    super.dispose();
  }

  static String get _checkinDoneKey {
    final d = DateTime.now();
    return 'fitness_checkin_done_${d.year}_${d.month}_${d.day}';
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final log = FitnessLog(
      userId: '',
      logDate: DateTime.now(),
      weightKg: double.tryParse(_weightCtrl.text),
      dietFollowed: _diet,
      workoutDone: _workout,
      mood: _mood,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyLogged = prefs.getBool(_checkinDoneKey) ?? false;

      // Only submit a new log row if the progress screen hasn't already
      // auto-submitted one today — prevents duplicate entries.
      if (!alreadyLogged) {
        await FitnessService.submitLog(log);
        await prefs.setBool(_checkinDoneKey, true);
      }

      // Always update profile weight if user entered one today
      if (log.weightKg != null) {
        await FitnessService.updateWeight(log.weightKg!);
      }

      final message = await FitnessAiService.generateDailyMessage(
        buddyName: widget.profile.buddyName,
        personality: widget.profile.buddyPersonality,
        streakDays: (widget.buddy?.streakDays ?? 0) + (_diet != 'no' && _workout ? 1 : 0),
        dietFollowed: _diet,
        workoutDone: _workout,
        goal: widget.profile.goal,
        bodyStage: widget.buddy?.bodyStage ?? 1,
      );

      if (widget.buddy != null) {
        await FitnessService.updateBuddyAfterCheckin(
            current: widget.buddy!, log: log, newMessage: message);
      }

      if (mounted) _showSuccess(message);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: kFitRed));
      }
    }
  }

  void _showSuccess(String message) {
    _celebCtrl.forward();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SuccessDialog(
        buddyName: widget.profile.buddyName,
        personality: widget.profile.buddyPersonality,
        stage: widget.buddy?.displayStage ?? 1,
        message: message,
        onDone: () { Navigator.pop(context); Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fc    = FitnessColors.of(context);
    final color = buddyColor(widget.profile.buddyPersonality);

    return Scaffold(
      backgroundColor: fc.bg,
      body: Stack(children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.5),
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
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: fc.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: fc.border),
                    ),
                    child: Icon(Icons.close_rounded, color: fc.textHint, size: 18),
                  ),
                ),
                const Spacer(),
                Column(children: [
                  Text("Today's Check-In",
                    style: TextStyle(
                      color: fc.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(_formatDate(DateTime.now()),
                    style: TextStyle(color: fc.textHint, fontSize: 11)),
                ]),
                const Spacer(),
                const SizedBox(width: 34),
              ]),
            ),

            if (_prefilled) ...[
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: fc.accentBg(kFitGreen),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: fc.accentBorder(kFitGreen)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome_rounded, size: 13,
                      color: fc.accentFg(kFitGreen)),
                  const SizedBox(width: 6),
                  Text('Pre-filled from your completed tasks',
                    style: TextStyle(
                      color: fc.accentFg(kFitGreen), fontSize: 11,
                      fontWeight: FontWeight.w600)),
                ]),
              ),
            ],

            const SizedBox(height: 4),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Diet
                  _SectionLabel(label: '🍱  Did you follow your diet?', fc: fc),
                  const SizedBox(height: 10),
                  Row(children: [
                    _DietBtn(label: 'Yes 😊', selected: _diet == 'yes',
                        accent: kFitGreen, fc: fc, onTap: () => setState(() => _diet = 'yes')),
                    const SizedBox(width: 8),
                    _DietBtn(label: 'Partial 😐', selected: _diet == 'partial',
                        accent: kFitOrange, fc: fc, onTap: () => setState(() => _diet = 'partial')),
                    const SizedBox(width: 8),
                    _DietBtn(label: 'No 😔', selected: _diet == 'no',
                        accent: kFitRed, fc: fc, onTap: () => setState(() => _diet = 'no')),
                  ]),

                  const SizedBox(height: 26),

                  // Workout
                  _SectionLabel(label: '💪  Did you complete your workout?', fc: fc),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => _workout = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: _workout ? fc.accentBgStrong(kFitGreen) : fc.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _workout ? fc.accentBorderStrong(kFitGreen) : fc.border,
                            width: _workout ? 1.5 : 1),
                          boxShadow: _workout
                              ? [BoxShadow(color: fc.accentGlow(kFitGreen), blurRadius: 12)]
                              : [],
                        ),
                        child: Column(children: [
                          const Text('💪', style: TextStyle(fontSize: 24)),
                          const SizedBox(height: 4),
                          Text('Yes, crushed it!',
                            style: TextStyle(
                              color: _workout ? fc.accentFg(kFitGreen) : fc.textHint,
                              fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => _workout = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: !_workout ? fc.accentBgStrong(kFitRed) : fc.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !_workout ? fc.accentBorderStrong(kFitRed) : fc.border,
                            width: !_workout ? 1.5 : 1),
                          boxShadow: !_workout
                              ? [BoxShadow(color: fc.accentGlow(kFitRed), blurRadius: 12)]
                              : [],
                        ),
                        child: Column(children: [
                          const Text('😴', style: TextStyle(fontSize: 24)),
                          const SizedBox(height: 4),
                          Text('Skipped today',
                            style: TextStyle(
                              color: !_workout ? fc.accentFg(kFitRed) : fc.textHint,
                              fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    )),
                  ]),

                  const SizedBox(height: 26),

                  // Mood
                  _SectionLabel(label: '😌  How\'s your energy today?', fc: fc),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (i) {
                      final val = i + 1;
                      final emojis = ['😩', '😔', '😐', '😊', '🔥'];
                      final labels = ['Low', 'Meh', 'Okay', 'Good', 'Fire'];
                      final sel = _mood == val;
                      return GestureDetector(
                        onTap: () => setState(() => _mood = val),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 58, height: 66,
                          decoration: BoxDecoration(
                            color: sel ? fc.accentBgStrong(color) : fc.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: sel ? fc.accentBorderStrong(color) : fc.border,
                              width: sel ? 1.5 : 1),
                            boxShadow: sel
                                ? [BoxShadow(color: fc.accentGlow(color), blurRadius: 12)]
                                : [],
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(emojis[i], style: const TextStyle(fontSize: 20)),
                            const SizedBox(height: 2),
                            Text(labels[i],
                              style: TextStyle(
                                color: sel ? fc.accentFg(color) : fc.textHint,
                                fontSize: 9, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 26),

                  // Weight (optional)
                  _SectionLabel(label: '⚖️  Current weight (optional)', fc: fc),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: fc.inputFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: fc.borderMid),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _weightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: fc.textPrimary, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'e.g. 68.5',
                            hintStyle: TextStyle(color: fc.textDisabled),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text('kg',
                          style: TextStyle(
                            color: fc.accentFg(kFitBlue), fontSize: 13,
                            fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text('Log weekly for best tracking',
                    style: TextStyle(color: fc.textDisabled, fontSize: 10)),
                ]),
              ),
            ),

            // Submit
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: GestureDetector(
                onTap: _submitting ? null : _submit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    gradient: _submitting
                        ? null
                        : LinearGradient(
                            colors: [color, color.withValues(alpha: 0.7)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                    color: _submitting ? fc.dimOverlay : null,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _submitting
                        ? []
                        : [BoxShadow(
                            color: fc.accentGlowStrong(color),
                            blurRadius: 20, offset: const Offset(0, 6))],
                  ),
                  child: _submitting
                      ? const Center(child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)))
                      : const Text('Submit Check-In', textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 15,
                              fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final FitnessColors fc;
  const _SectionLabel({required this.label, required this.fc});

  @override
  Widget build(BuildContext context) => Text(label,
    style: TextStyle(color: fc.textSecondary, fontSize: 13, fontWeight: FontWeight.w700));
}

class _DietBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final FitnessColors fc;
  final VoidCallback onTap;
  const _DietBtn({required this.label, required this.selected,
      required this.accent, required this.fc, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? fc.accentBgStrong(accent) : fc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? fc.accentBorderStrong(accent) : fc.border,
            width: selected ? 1.5 : 1),
          boxShadow: selected
              ? [BoxShadow(color: fc.accentGlow(accent), blurRadius: 10)]
              : [],
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? fc.accentFg(accent) : fc.textHint,
            fontSize: 11, fontWeight: FontWeight.w800)),
      ),
    ),
  );
}

class _SuccessDialog extends StatelessWidget {
  final String buddyName, personality, message;
  final int stage;
  final VoidCallback onDone;
  const _SuccessDialog({required this.buddyName, required this.personality,
      required this.stage, required this.message, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final fc    = FitnessColors.of(context);
    final color = buddyColor(personality);
    return Dialog(
      backgroundColor: fc.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                fc.accentBgStrong(color),
                fc.accentBg(color),
              ]),
              boxShadow: [BoxShadow(
                  color: fc.accentGlowStrong(color),
                  blurRadius: 24, spreadRadius: 2)],
            ),
            child: Center(child: Text(buddyEmoji(stage),
                style: const TextStyle(fontSize: 36))),
          ),
          const SizedBox(height: 14),
          Text(buddyName,
            style: TextStyle(
              color: fc.accentFg(color), fontSize: 20, fontWeight: FontWeight.w900,
              shadows: [Shadow(color: fc.accentGlow(color), blurRadius: 12)],
            )),
          const SizedBox(height: 4),
          Text('Check-In Complete! ✓',
            style: TextStyle(color: fc.textHint, fontSize: 12)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: fc.accentBg(color),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: fc.accentBorder(color)),
            ),
            child: Text(message, textAlign: TextAlign.center,
              style: TextStyle(color: fc.textSecondary, fontSize: 13, height: 1.55)),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onDone,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                    color: fc.accentGlowStrong(color),
                    blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: const Text('Back to Hub', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ),
        ]),
      ),
    );
  }
}
