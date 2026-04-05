import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/fitness_models.dart';
import 'data/food_database.dart';
import 'services/fitness_service.dart';
import 'services/fitness_ai_service.dart';
import 'food_selection_screen.dart';
import 'fitness_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main widget
// ─────────────────────────────────────────────────────────────────────────────
class FitnessOnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const FitnessOnboardingScreen({super.key, required this.onComplete});

  @override
  State<FitnessOnboardingScreen> createState() => _FitnessOnboardingScreenState();
}

class _FitnessOnboardingScreenState extends State<FitnessOnboardingScreen>
    with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;

  // Step 1 — body stats (spinner-based, no TextFields)
  int _age = 20;
  double _heightVal = 170.0;
  double _weightKg = 65.0;
  String _gender = 'male';
  String _heightUnit = 'cm'; // 'cm' or 'in'

  // Step 2 — lifestyle
  double _sleepHours = 7;
  int _stressLevel = 3;
  String _activityLevel = 'light';

  // Step 3 — gym
  bool? _hasGym;

  // Step 4 — food
  String? _foodType;

  // Step 5 — goal
  String? _goal;

  // Step 6 — generating
  bool _generating = false;
  String _genStatus = 'Analysing your profile...';
  List<FoodItem> _selectedFoods = [];
  Map<String, int> _selectedQuantities = {};

  /// Pre-fetched plan future — started the moment food selection completes
  /// so the API call runs in parallel with the page-turn animation.
  Future<Map<String, dynamic>>? _pendingPlanFuture;

  FitnessProfile _buildBaseProfile() => FitnessProfile(
        userId: '',
        age: _age,
        heightCm: _heightCm,
        weightKg: _weightKg,
        gender: _gender,
        sleepHours: _sleepHours,
        stressLevel: _stressLevel,
        activityLevel: _activityLevel,
        hasGymAccess: _hasGym!,
        foodType: _foodType!,
        goal: _goal!,
        buddyName: '',
        buddyAvatarType: math.Random().nextInt(5) + 1,
        buddyPersonality: 'chill',
        createdAt: DateTime.now(),
      );

  void _prefetchPlan([String? goalOverride]) {
    if (_buildsLeft <= 0) return;
    if (_hasGym == null || _foodType == null) return;
    // Build a profile using the actual goal if known, or the override if not set yet
    final goal = _goal ?? goalOverride;
    if (goal == null) return;
    final profile = FitnessProfile(
      userId: '',
      age: _age, heightCm: _heightCm, weightKg: _weightKg, gender: _gender,
      sleepHours: _sleepHours, stressLevel: _stressLevel,
      activityLevel: _activityLevel, hasGymAccess: _hasGym!,
      foodType: _foodType!, goal: goal,
      buddyName: '', buddyAvatarType: math.Random().nextInt(5) + 1,
      buddyPersonality: 'chill', createdAt: DateTime.now(),
    );
    _pendingPlanFuture = FitnessAiService.generatePlan(profile);
  }

  // Rate limit — max 3 AI builds per day per device
  static const _maxBuildsPerDay = 3;
  static String get _buildCountKey {
    final d = DateTime.now();
    return 'fitness_ai_builds_${d.year}_${d.month}_${d.day}';
  }

  int _buildsToday = 0;
  int get _buildsLeft => (_maxBuildsPerDay - _buildsToday).clamp(0, _maxBuildsPerDay);

  Future<void> _loadBuildCount() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _buildsToday = prefs.getInt(_buildCountKey) ?? 0);
  }

  Future<void> _incrementBuildCount() async {
    final prefs = await SharedPreferences.getInstance();
    _buildsToday = (_buildsToday + 1);
    await prefs.setInt(_buildCountKey, _buildsToday);
  }

  late AnimationController _bgCtrl;
  late Animation<double> _bgAnim;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);
    _loadBuildCount();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  // ── height in cm (always) ─────────────────────────────────────────────────
  double get _heightCm => _heightUnit == 'in' ? _heightVal * 2.54 : _heightVal;

  // ── navigation ────────────────────────────────────────────────────────────
  void _next() {
    if (_page == 0 && !_validateStep1()) return;
    if (_page == 1) {/* lifestyle has defaults, always valid */}
    if (_page == 2 && _hasGym == null) { _snack('Please select gym access option'); return; }
    if (_page == 3 && _foodType == null) { _snack('Please select your food type'); return; }
    if (_page == 4 && _goal == null) { _snack('Please select your goal'); return; }

    // After goal step → go to food selection before generating
    if (_page == 4) {
      _openFoodSelection();
      return;
    }

    if (_page < 5) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
      setState(() => _page++);
    }
    if (_page == 5) _generate();
  }

  void _openFoodSelection() {
    final tempProfile = FitnessProfile(
      userId: '',
      age: _age,
      heightCm: _heightCm,
      weightKg: _weightKg,
      gender: _gender,
      sleepHours: _sleepHours,
      stressLevel: _stressLevel,
      activityLevel: _activityLevel,
      hasGymAccess: _hasGym!,
      foodType: _foodType!,
      goal: _goal!,
      buddyName: '',
      buddyAvatarType: 1,
      buddyPersonality: 'chill',
      createdAt: DateTime.now(),
    );
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FoodSelectionScreen(
        profile: tempProfile,
        onComplete: (selectedFoods, quantities, gaps) {
          _selectedFoods = selectedFoods;
          _selectedQuantities = quantities;
          _pageCtrl.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
          setState(() => _page = 5);
          _generate();
        },
      ),
    ));
  }

  bool _validateStep1() {
    if (_age < 14 || _age > 60) {
      _snack('Age must be between 14 and 60');
      return false;
    }
    if (_heightUnit == 'cm') {
      if (_heightVal < 100 || _heightVal > 230) {
        _snack('Enter height in cm (100–230)');
        return false;
      }
    } else {
      if (_heightVal < 39 || _heightVal > 91) {
        _snack('Enter height in inches (39–91)');
        return false;
      }
    }
    if (_weightKg < 30 || _weightKg > 200) {
      _snack('Weight must be between 30 and 200 kg');
      return false;
    }
    return true;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF1A1060),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _generate() async {
    if (_hasGym == null || _foodType == null || _goal == null) {
      _snack('Please complete all steps');
      return;
    }
    if (_buildsLeft <= 0) {
      _snack('Daily limit reached ($_maxBuildsPerDay/day). Use Quick Plan or try again tomorrow.');
      return;
    }
    setState(() { _generating = true; _genStatus = 'Creating your buddy...'; });

    final baseProfile = _buildBaseProfile();

    try {
      // Use pre-fetched future (started at food-type or goal selection),
      // otherwise fall back to a fresh call with the final profile.
      final planFuture = _pendingPlanFuture ?? FitnessAiService.generatePlan(baseProfile);
      _pendingPlanFuture = null;
      final planJson = await planFuture;

      // Always inject diet guide built from the user's actual food selections —
      // this guarantees accuracy regardless of what the AI returned.
      planJson['diet_guide'] = FitnessAiService.buildDietGuide(
        _selectedFoods, _selectedQuantities, baseProfile);

      setState(() => _genStatus = 'Building your plan...');
      final finalProfile = FitnessProfile(
        userId: '',
        age: baseProfile.age, heightCm: baseProfile.heightCm,
        weightKg: baseProfile.weightKg, gender: baseProfile.gender,
        sleepHours: baseProfile.sleepHours, stressLevel: baseProfile.stressLevel,
        activityLevel: baseProfile.activityLevel, hasGymAccess: baseProfile.hasGymAccess,
        foodType: baseProfile.foodType, goal: baseProfile.goal,
        buddyName: planJson['buddy_name'] as String? ?? 'Ryuu',
        buddyAvatarType: (planJson['buddy_avatar_type'] as num?)?.toInt() ?? baseProfile.buddyAvatarType,
        buddyPersonality: planJson['buddy_personality'] as String? ?? 'chill',
        buddyIntro: planJson['buddy_intro'] as String?,
        createdAt: DateTime.now(),
      );

      setState(() => _genStatus = 'Saving to your profile...');
      await Future.wait([
        FitnessService.saveProfile(finalProfile),
        FitnessService.savePlan(planJson),
        FitnessService.createInitialBuddyState(),
        _incrementBuildCount(),
      ]).timeout(const Duration(seconds: 20));

      if (mounted) { widget.onComplete(); Navigator.pop(context); }
    } catch (e) {
      if (!mounted) return;
      setState(() { _generating = false; _genStatus = 'Analysing your profile...'; });
      _pageCtrl.jumpToPage(4);
      setState(() => _page = 4);
      _snack('Something went wrong: ${e.toString().split('\n').first}. Try again.');
    }
  }

  Future<void> _generateQuick() async {
    if (_hasGym == null || _foodType == null || _goal == null) {
      _snack('Please complete all steps');
      return;
    }
    setState(() { _generating = true; _genStatus = 'Building quick plan...'; });

    try {
      final baseProfile = FitnessProfile(
        userId: '',
        age: _age,
        heightCm: _heightCm,
        weightKg: _weightKg,
        gender: _gender,
        sleepHours: _sleepHours,
        stressLevel: _stressLevel,
        activityLevel: _activityLevel,
        hasGymAccess: _hasGym!,
        foodType: _foodType!,
        goal: _goal!,
        buddyName: '',
        buddyAvatarType: math.Random().nextInt(5) + 1,
        buddyPersonality: 'chill',
        createdAt: DateTime.now(),
      );

      final planJson = FitnessAiService.fallbackPlan(baseProfile);
      planJson['diet_guide'] = FitnessAiService.buildDietGuide(
          _selectedFoods, _selectedQuantities, baseProfile);
      final finalProfile = FitnessProfile(
        userId: '',
        age: baseProfile.age, heightCm: baseProfile.heightCm,
        weightKg: baseProfile.weightKg, gender: baseProfile.gender,
        sleepHours: baseProfile.sleepHours, stressLevel: baseProfile.stressLevel,
        activityLevel: baseProfile.activityLevel, hasGymAccess: baseProfile.hasGymAccess,
        foodType: baseProfile.foodType, goal: baseProfile.goal,
        buddyName: planJson['buddy_name'] as String? ?? 'Ryuu',
        buddyAvatarType: (planJson['buddy_avatar_type'] as num?)?.toInt() ?? baseProfile.buddyAvatarType,
        buddyPersonality: planJson['buddy_personality'] as String? ?? 'chill',
        buddyIntro: planJson['buddy_intro'] as String?,
        createdAt: DateTime.now(),
      );

      setState(() => _genStatus = 'Saving...');
      await Future.wait([
        FitnessService.saveProfile(finalProfile),
        FitnessService.savePlan(planJson),
        FitnessService.createInitialBuddyState(),
      ]).timeout(const Duration(seconds: 20));

      if (mounted) { widget.onComplete(); Navigator.pop(context); }
    } catch (e) {
      if (!mounted) return;
      setState(() { _generating = false; _genStatus = 'Analysing your profile...'; });
      _pageCtrl.jumpToPage(4);
      setState(() => _page = 4);
      _snack('Save failed. Check internet and try again.');
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final kFitAccents = [kFitBlue, kFitGreen, kFitRed, kFitOrange, kFitPurple, kFitGreen];
    final accent = kFitAccents[_page.clamp(0, kFitAccents.length - 1)];
    return Scaffold(
      backgroundColor: fc.bg,
      body: Stack(children: [
        // Animated radial gradient background that pulses with step accent
        AnimatedBuilder(
          animation: _bgAnim,
          builder: (ctx, child) => Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(_bgAnim.value * 0.4 - 0.2, -0.5),
                radius: 1.2,
                colors: [
                  accent.withValues(alpha: 0.18),
                  fc.bg,
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            _buildHeader(accent, fc),
            _buildProgressBar(accent, fc),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StepBodyStats(
                    age: _age,
                    heightVal: _heightVal,
                    weightKg: _weightKg,
                    gender: _gender,
                    heightUnit: _heightUnit,
                    onAge: (v) => setState(() => _age = v),
                    onHeight: (v) => setState(() => _heightVal = v),
                    onWeight: (v) => setState(() => _weightKg = v),
                    onGender: (v) => setState(() => _gender = v),
                    onHeightUnit: (v) => setState(() {
                      _heightUnit = v;
                      // Convert value when switching units
                      if (v == 'in') {
                        _heightVal = double.parse((_heightVal / 2.54).toStringAsFixed(1));
                        if (_heightVal < 39) _heightVal = 67.0;
                        if (_heightVal > 91) _heightVal = 91.0;
                      } else {
                        _heightVal = double.parse((_heightVal * 2.54).toStringAsFixed(1));
                        if (_heightVal < 100) _heightVal = 170.0;
                        if (_heightVal > 230) _heightVal = 230.0;
                      }
                    }),
                  ),
                  _StepLifestyle(
                    sleepHours: _sleepHours,
                    stressLevel: _stressLevel,
                    activityLevel: _activityLevel,
                    onSleep: (v) => setState(() => _sleepHours = v),
                    onStress: (v) => setState(() => _stressLevel = v),
                    onActivity: (v) => setState(() => _activityLevel = v),
                  ),
                  _StepGym(
                    selected: _hasGym,
                    onSelect: (v) { setState(() => _hasGym = v); _next(); },
                  ),
                  _StepFood(
                    selected: _foodType,
                    onSelect: (v) {
                      setState(() => _foodType = v);
                      // Start AI call immediately with a default goal so it
                      // runs while the user is still on the goal selection page.
                      _prefetchPlan('maintain_fitness');
                      _next();
                    },
                  ),
                  _StepGoal(
                    selected: _goal,
                    onSelect: (v) {
                      setState(() => _goal = v);
                      // Restart with the real goal (replaces the speculative future).
                      _prefetchPlan();
                      _next();
                    },
                  ),
                  _StepGenerating(
                    status: _genStatus,
                    onQuickPlan: _generateQuick,
                    isGenerating: _generating,
                    buildsLeft: _buildsLeft,
                  ),
                ],
              ),
            ),
            // Continue button only for steps 0 and 1
            if (_page == 0 || _page == 1) ...[
              _buildContinueButton(accent),
              const SizedBox(height: 16),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── header bar ────────────────────────────────────────────────────────────
  Widget _buildHeader(Color accent, FitnessColors fc) {
    final stepLabels = ['Body Stats', 'Lifestyle', 'Workout', 'Nutrition', 'Goal', 'Building'];
    final label = stepLabels[_page.clamp(0, stepLabels.length - 1)];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(children: [
        // Step label (left)
        Text(
          'Step ${_page + 1} of 6',
          style: TextStyle(color: accent.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600),
        ),
        // Centered icon + title
        Expanded(
          child: Column(children: [
            Text(label, style: TextStyle(color: fc.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        ),
        // Back arrow (right)
        if (_page > 0 && _page < 5)
          GestureDetector(
            onTap: () {
              _pageCtrl.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              setState(() => _page--);
            },
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: fc.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: fc.border),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: fc.textSecondary, size: 14),
            ),
          )
        else
          const SizedBox(width: 32),
      ]),
    );
  }

  // ── thin linear progress bar ──────────────────────────────────────────────
  Widget _buildProgressBar(Color accent, FitnessColors fc) {
    final progress = (_page + 1) / 6.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 4, color: fc.border),
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              height: 4,
              width: (MediaQuery.of(context).size.width - 40) * progress,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [accent.withValues(alpha: 0.7), accent]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 6)],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── continue button ───────────────────────────────────────────────────────
  Widget _buildContinueButton(Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _next,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent, accent.withValues(alpha: 0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6)),
            ],
          ),
          child: const Center(
            child: Text('Continue',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — Body Stats (spinner-based, no keyboard)
// ─────────────────────────────────────────────────────────────────────────────
class _StepBodyStats extends StatelessWidget {
  final int age;
  final double heightVal;
  final double weightKg;
  final String gender;
  final String heightUnit;
  final ValueChanged<int> onAge;
  final ValueChanged<double> onHeight;
  final ValueChanged<double> onWeight;
  final ValueChanged<String> onGender;
  final ValueChanged<String> onHeightUnit;

  const _StepBodyStats({
    required this.age,
    required this.heightVal,
    required this.weightKg,
    required this.gender,
    required this.heightUnit,
    required this.onAge,
    required this.onHeight,
    required this.onWeight,
    required this.onGender,
    required this.onHeightUnit,
  });

  double get _bmi {
    final hCm = heightUnit == 'in' ? heightVal * 2.54 : heightVal;
    if (hCm <= 0) return 0;
    final hM = hCm / 100.0;
    return weightKg / (hM * hM);
  }

  String get _bmiLabel {
    final b = _bmi;
    if (b < 18.5) return 'Underweight';
    if (b < 25.0) return 'Normal';
    if (b < 30.0) return 'Overweight';
    return 'Obese';
  }

  Color _bmiColor() {
    final b = _bmi;
    if (b < 18.5) return kFitBlue;
    if (b < 25.0) return kFitGreen;
    if (b < 30.0) return kFitOrange;
    return kFitRed;
  }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final bmiColor = _bmiColor();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [fc.accentFg(kFitBlue), fc.accentFg(kFitGreen)],
          ).createShader(bounds),
          child: const Text('Your Stats',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Text('No typing needed — just tap + or −',
          style: TextStyle(color: fc.textHint, fontSize: 12)),
        const SizedBox(height: 20),

        // Three stat cards
        Row(children: [
          Expanded(child: _StatSpinner(
            icon: '🎂',
            label: 'Age',
            unit: 'yrs',
            displayValue: '$age',
            onDecrement: () => onAge((age - 1).clamp(14, 60)),
            onIncrement: () => onAge((age + 1).clamp(14, 60)),
          )),
          const SizedBox(width: 10),
          Expanded(child: _StatSpinner(
            icon: '📏',
            label: 'Height',
            unit: heightUnit,
            displayValue: heightUnit == 'cm'
                ? heightVal.toStringAsFixed(0)
                : heightVal.toStringAsFixed(1),
            onDecrement: () {
              final step = heightUnit == 'cm' ? 1.0 : 0.5;
              final min = heightUnit == 'cm' ? 100.0 : 39.0;
              onHeight((heightVal - step).clamp(min, heightUnit == 'cm' ? 230.0 : 91.0));
            },
            onIncrement: () {
              final step = heightUnit == 'cm' ? 1.0 : 0.5;
              final max = heightUnit == 'cm' ? 230.0 : 91.0;
              onHeight((heightVal + step).clamp(heightUnit == 'cm' ? 100.0 : 39.0, max));
            },
          )),
          const SizedBox(width: 10),
          Expanded(child: _StatSpinner(
            icon: '⚖️',
            label: 'Weight',
            unit: 'kg',
            displayValue: weightKg.toStringAsFixed(1),
            onDecrement: () => onWeight((weightKg - 0.5).clamp(30.0, 200.0)),
            onIncrement: () => onWeight((weightKg + 0.5).clamp(30.0, 200.0)),
          )),
        ]),

        // Height unit toggle
        const SizedBox(height: 10),
        Center(
          child: _PillToggle(
            current: heightUnit,
            options: const ['cm', 'in'],
            accent: kFitBlue,
            onSelect: onHeightUnit,
          ),
        ),

        // Gender row
        const SizedBox(height: 18),
        Text('Gender', style: TextStyle(color: fc.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          _GenderCard(emoji: '♂', label: 'Male',   selected: gender == 'male',   onTap: () => onGender('male')),
          const SizedBox(width: 8),
          _GenderCard(emoji: '♀', label: 'Female', selected: gender == 'female', onTap: () => onGender('female')),
          const SizedBox(width: 8),
          _GenderCard(emoji: '⚧', label: 'Other',  selected: gender == 'other',  onTap: () => onGender('other')),
        ]),

        // BMI display
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: fc.accentBgStrong(bmiColor),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: fc.accentBorder(bmiColor)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('BMI  ', style: TextStyle(color: fc.textHint, fontSize: 13)),
              Text(_bmi.toStringAsFixed(1),
                style: TextStyle(color: fc.accentFg(bmiColor), fontSize: 18, fontWeight: FontWeight.w900)),
              Text('  · $_bmiLabel',
                style: TextStyle(color: fc.accentFg(bmiColor).withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// Spinner card widget
class _StatSpinner extends StatelessWidget {
  final String icon, label, unit, displayValue;
  final VoidCallback onDecrement, onIncrement;

  const _StatSpinner({
    required this.icon,
    required this.label,
    required this.unit,
    required this.displayValue,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fc.border),
      ),
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 6),
        Text(displayValue,
          style: TextStyle(color: fc.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
        Text(unit, style: TextStyle(color: fc.textHint, fontSize: 11)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _SpinBtn(icon: Icons.remove, onTap: onDecrement),
          const SizedBox(width: 8),
          _SpinBtn(icon: Icons.add, onTap: onIncrement),
        ]),
      ]),
    );
  }
}

class _SpinBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SpinBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: fc.accentBorderStrong(kFitBlue)),
          color: fc.accentBg(kFitBlue),
        ),
        child: Icon(icon, color: fc.accentFg(kFitBlue), size: 14),
      ),
    );
  }
}

class _PillToggle extends StatelessWidget {
  final String current;
  final List<String> options;
  final Color accent;
  final ValueChanged<String> onSelect;
  const _PillToggle({required this.current, required this.options, required this.accent, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fc.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: options.map((opt) {
        final sel = current == opt;
        return GestureDetector(
          onTap: () => onSelect(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: sel ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: sel ? [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 8)] : [],
            ),
            child: Text(opt, style: TextStyle(
              color: sel ? Colors.white : fc.textHint,
              fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        );
      }).toList()),
    );
  }
}

class _GenderCard extends StatelessWidget {
  final String emoji, label;
  final bool selected;
  final VoidCallback onTap;
  const _GenderCard({required this.emoji, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? fc.accentBgStrong(kFitBlue) : fc.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? fc.accentBorderStrong(kFitBlue) : fc.border, width: selected ? 1.5 : 1),
            boxShadow: selected ? [BoxShadow(color: fc.accentGlow(kFitBlue), blurRadius: 10)] : [],
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              color: selected ? fc.accentFg(kFitBlue) : fc.textTertiary,
              fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — Lifestyle
// ─────────────────────────────────────────────────────────────────────────────
class _StepLifestyle extends StatelessWidget {
  final double sleepHours;
  final int stressLevel;
  final String activityLevel;
  final ValueChanged<double> onSleep;
  final ValueChanged<int> onStress;
  final ValueChanged<String> onActivity;

  const _StepLifestyle({
    required this.sleepHours, required this.stressLevel, required this.activityLevel,
    required this.onSleep, required this.onStress, required this.onActivity,
  });

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final activityOptions = [
      ('sedentary', '🪑', 'Mostly Sitting', 'Desk life, rarely move'),
      ('light',     '🚶', 'Light Active',   'Walk around campus'),
      ('moderate',  '🏃', 'Moderate',        'Sports, gym few times'),
      ('active',    '⚡', 'Very Active',     'Daily intense activity'),
    ];
    final stressEmojis = ['😌', '🙂', '😐', '😤', '😰'];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [fc.accentFg(kFitGreen), fc.accentFg(kFitBlue)],
          ).createShader(bounds),
          child: const Text('Your Lifestyle',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Text('Be honest — this shapes your calorie targets and recovery needs.',
          style: TextStyle(color: fc.textHint, fontSize: 12)),
        const SizedBox(height: 24),

        // Sleep
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: fc.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: fc.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🌙', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('Sleep Hours', style: TextStyle(color: fc.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${sleepHours.toStringAsFixed(1)} hrs',
                style: TextStyle(color: fc.accentFg(kFitGreen), fontSize: 14, fontWeight: FontWeight.w800)),
            ]),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbColor: kFitGreen,
                activeTrackColor: kFitGreen,
                inactiveTrackColor: fc.border,
                overlayColor: kFitGreen.withValues(alpha: 0.15),
                trackHeight: 3,
              ),
              child: Slider(value: sleepHours, min: 4, max: 10, divisions: 12, onChanged: onSleep),
            ),
          ]),
        ),

        const SizedBox(height: 14),

        // Stress
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: fc.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: fc.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🧠', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('Stress Level', style: TextStyle(color: fc.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$stressLevel / 5',
                style: TextStyle(color: fc.accentFg(kFitOrange), fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (i) {
                final val = i + 1;
                final sel = stressLevel == val;
                return GestureDetector(
                  onTap: () => onStress(val),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48, height: 52,
                    decoration: BoxDecoration(
                      color: sel ? fc.accentBgStrong(kFitOrange) : fc.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? fc.accentBorderStrong(kFitOrange) : fc.border, width: sel ? 1.5 : 1),
                      boxShadow: sel ? [BoxShadow(color: fc.accentGlow(kFitOrange), blurRadius: 8)] : [],
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(stressEmojis[i], style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text('$val', style: TextStyle(
                        color: sel ? fc.accentFg(kFitOrange) : fc.textHint,
                        fontSize: 10, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                );
              }),
            ),
          ]),
        ),

        const SizedBox(height: 18),
        Text('Activity Level', style: TextStyle(color: fc.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...activityOptions.map((opt) {
          final sel = activityLevel == opt.$1;
          return GestureDetector(
            onTap: () => onActivity(opt.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: sel ? fc.accentBg(kFitGreen) : fc.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? fc.accentBorderStrong(kFitGreen) : fc.border, width: sel ? 1.5 : 1),
                boxShadow: sel ? [BoxShadow(color: fc.accentGlow(kFitGreen), blurRadius: 10)] : [],
              ),
              child: Row(children: [
                Text(opt.$2, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(opt.$3, style: TextStyle(
                    color: sel ? fc.accentFg(kFitGreen) : fc.textPrimary,
                    fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(opt.$4, style: TextStyle(color: fc.textHint, fontSize: 11)),
                ])),
                if (sel) Icon(Icons.check_circle_rounded, color: fc.accentFg(kFitGreen), size: 18),
              ]),
            ),
          );
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3 — Gym Access
// ─────────────────────────────────────────────────────────────────────────────
class _StepGym extends StatelessWidget {
  final bool? selected;
  final ValueChanged<bool> onSelect;
  const _StepGym({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [fc.accentFg(kFitRed), fc.accentFg(kFitOrange)],
          ).createShader(bounds),
          child: const Text('Workout Access',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Text('This determines your entire workout plan — weights vs bodyweight.',
          style: TextStyle(color: fc.textHint, fontSize: 12)),
        const SizedBox(height: 32),
        Expanded(
          child: Column(children: [
            _BigChoice(
              emoji: '🏋️',
              title: 'Yes, I go to gym',
              subtitle: 'Barbells, dumbbells, machines',
              selected: selected == true,
              color: kFitRed,
              onTap: () => onSelect(true),
            ),
            const SizedBox(height: 16),
            _BigChoice(
              emoji: '🏠',
              title: 'No, home / hostel only',
              subtitle: 'Bodyweight exercises, no equipment needed',
              selected: selected == false,
              color: kFitGreen,
              onTap: () => onSelect(false),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 4 — Food Type
// ─────────────────────────────────────────────────────────────────────────────
class _StepFood extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _StepFood({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [fc.accentFg(kFitOrange), fc.accentFg(kFitRed)],
          ).createShader(bounds),
          child: const Text('Where do you eat?',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Text('Your diet plan will use food actually available to you.',
          style: TextStyle(color: fc.textHint, fontSize: 12)),
        const SizedBox(height: 32),
        _BigChoice(
          emoji: '🍱', title: 'Hostel Mess',
          subtitle: 'Dal, roti, sabzi, rice daily',
          selected: selected == 'mess', color: kFitOrange,
          onTap: () => onSelect('mess'),
        ),
        const SizedBox(height: 12),
        _BigChoice(
          emoji: '🥗', title: 'College Canteen',
          subtitle: 'Mix of options available',
          selected: selected == 'canteen', color: kFitPurple,
          onTap: () => onSelect('canteen'),
        ),
        const SizedBox(height: 12),
        _BigChoice(
          emoji: '🏡', title: 'Home Cooked',
          subtitle: 'Full control over food',
          selected: selected == 'home', color: kFitGreen,
          onTap: () => onSelect('home'),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 5 — Goal
// ─────────────────────────────────────────────────────────────────────────────
class _StepGoal extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _StepGoal({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final goals = [
      ('lose_fat',        '🔥', 'Lose Fat',          'Calorie deficit + cardio + toning',     kFitRed,    'Burn 4–6 kg in 3 months'),
      ('gain_muscle',     '💪', 'Gain Muscle',        'Calorie surplus + resistance training', kFitPurple, 'Gain 3–5 kg lean mass in 3 months'),
      ('stay_fit',        '⚡', 'Stay Fit',           'Maintenance + body composition',        kFitGreen,  'Maintain & recompose over 8 weeks'),
      ('improve_stamina', '🏃', 'Improve Stamina',    'Endurance + cardio + mobility',         kFitOrange, 'Double run distance in 6 weeks'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [fc.accentFg(kFitPurple), fc.accentFg(kFitBlue)],
          ).createShader(bounds),
          child: const Text('Your Goal',
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 4),
        Text("Pick your primary goal. You can change this later.",
          style: TextStyle(color: fc.textHint, fontSize: 12)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: goals.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _BigChoice(
                emoji: g.$2, title: g.$3, subtitle: g.$4,
                selected: selected == g.$1, color: g.$5,
                onTap: () => onSelect(g.$1),
                resultTag: g.$6,
              ),
            )).toList(),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 6 — Generating
// ─────────────────────────────────────────────────────────────────────────────
class _StepGenerating extends StatefulWidget {
  final String status;
  final VoidCallback onQuickPlan;
  final bool isGenerating;
  final int buildsLeft;
  const _StepGenerating({required this.status, required this.onQuickPlan, required this.isGenerating, required this.buildsLeft});

  @override
  State<_StepGenerating> createState() => _StepGeneratingState();
}

class _StepGeneratingState extends State<_StepGenerating> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulseAnim;

  static const _hints = [
    'Crunching your fitness numbers...',
    'Designing your workout split...',
    'Crafting your Indian diet plan...',
    'Picking your buddy\'s personality...',
    'Calculating calorie targets...',
    'Building your 12-week roadmap...',
    'Almost ready...',
  ];
  int _hintIndex = 0;
  late final _hintTimer = Stream.periodic(const Duration(seconds: 2))
      .listen((_) {
        if (mounted) setState(() => _hintIndex = (_hintIndex + 1) % _hints.length);
      });

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _hintTimer.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Pulsing ring + rotating dumbbell
        AnimatedBuilder(
          animation: _ctrl,
          builder: (ctx, child) => Stack(alignment: Alignment.center, children: [
            // Outer pulsing ring
            Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: fc.accentGlow(kFitGreen), width: 2),
                ),
              ),
            ),
            // Rotating sweep gradient ring
            Transform.rotate(
              angle: _ctrl.value * 2 * math.pi,
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [Colors.transparent, kFitGreen.withValues(alpha: 0.8), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Inner circle with dumbbell
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(shape: BoxShape.circle, color: fc.bg),
              child: Center(
                child: Transform.rotate(
                  angle: _ctrl.value * 2 * math.pi * 0.5,
                  child: const Text('🏋️', style: TextStyle(fontSize: 30)),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 32),
        Text('Building your buddy...',
          style: TextStyle(color: fc.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
                  .animate(anim),
              child: child,
            ),
          ),
          child: Text(
            _hints[_hintIndex],
            key: ValueKey(_hintIndex),
            style: TextStyle(color: fc.textHint, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.auto_awesome_rounded, size: 13,
              color: widget.buildsLeft > 1 ? fc.accentFg(kFitGreen) : kFitRed),
          const SizedBox(width: 4),
          Text(
            widget.buildsLeft > 0
                ? '${widget.buildsLeft} AI build${widget.buildsLeft == 1 ? '' : 's'} left today'
                : 'Daily limit reached — using Quick Plan',
            style: TextStyle(
              color: widget.buildsLeft > 1 ? fc.textHint : kFitRed,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ]),
        const SizedBox(height: 32),
        if (widget.isGenerating)
          GestureDetector(
            onTap: widget.onQuickPlan,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: fc.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: fc.accentBorder(kFitGreen)),
              ),
              child: Text('Taking too long? Use Quick Plan',
                style: TextStyle(color: fc.accentFg(kFitGreen), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED — _BigChoice card (enhanced with left border stripe + glow)
// ─────────────────────────────────────────────────────────────────────────────
class _BigChoice extends StatelessWidget {
  final String emoji, title, subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final String? resultTag;

  const _BigChoice({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
    this.resultTag,
  });

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(0, 18, 18, 18),
        decoration: BoxDecoration(
          color: selected ? fc.accentBg(color) : fc.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? fc.accentBorderStrong(color) : fc.border,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: fc.accentGlow(color), blurRadius: 16, spreadRadius: 1)]
              : [],
        ),
        child: Row(children: [
          // Left accent stripe
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 4,
            height: 48,
            margin: const EdgeInsets.only(left: 0, right: 14),
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
            ),
          ),
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
              color: selected ? fc.accentFg(color) : fc.textPrimary,
              fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(color: fc.textHint, fontSize: 12)),
            if (resultTag != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: fc.accentBgStrong(color),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(resultTag!, style: TextStyle(
                  color: fc.accentFg(color), fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ])),
          if (selected) Icon(Icons.check_circle_rounded, color: fc.accentFg(color), size: 22),
        ]),
      ),
    );
  }
}
