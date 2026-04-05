// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'models/fitness_models.dart';
import 'data/food_database.dart';
import 'fitness_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class FoodSelectionScreen extends StatefulWidget {
  final FitnessProfile profile;

  /// Called when the user finalises their food list.
  /// [selectedFoods] — every food the user has picked.
  /// [quantities] — serving counts per food id.
  /// [nutrientGaps] — summary map for gap analysis.
  final void Function(
    List<FoodItem> selectedFoods,
    Map<String, int> quantities,
    Map<String, dynamic> nutrientGaps,
  ) onComplete;

  const FoodSelectionScreen({
    super.key,
    required this.profile,
    required this.onComplete,
  });

  @override
  State<FoodSelectionScreen> createState() => _FoodSelectionScreenState();
}

class _FoodSelectionScreenState extends State<FoodSelectionScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  /// food id → serving count (1 = default, 2 = double, etc.)
  final Map<String, int> _quantities = {};
  String _query = '';


  static const _tabs = ['All', 'Breakfast', 'Lunch', 'Dinner', 'Snacks'];
  static const _mealKeys = ['', 'breakfast', 'lunch', 'dinner', 'snacks'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<FoodItem> _filtered(int tabIndex) {
    final mealKey = _mealKeys[tabIndex];
    Iterable<FoodItem> base = tabIndex == 0
        ? FoodDatabase.all
        : FoodDatabase.all
            .where((f) => f.meals.contains(mealKey) || f.meals.contains('any'));

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      base = base.where((f) => f.name.toLowerCase().contains(q));
    }
    return base.toList();
  }

  List<FoodItem> get _selected =>
      FoodDatabase.all.where((f) => _quantities.containsKey(f.id)).toList();

  void _toggle(String id) {
    setState(() {
      if (_quantities.containsKey(id)) {
        _quantities.remove(id);
      } else {
        _quantities[id] = 1;
      }
    });
  }

  void _setQuantity(String id, int qty) {
    setState(() {
      if (qty <= 0) {
        _quantities.remove(id);
      } else {
        _quantities[id] = qty;
      }
    });
  }

  void _addFromSuggestion(String id) {
    setState(() => _quantities[id] = 1);
  }

  // ── TDEE (Mifflin-St Jeor) ─────────────────────────────────────────────────
  double _tdee() {
    final p = widget.profile;
    final bmr = p.gender == 'female'
        ? 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age - 161
        : 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age + 5;
    final mult = const {
          'sedentary': 1.2,
          'light': 1.375,
          'moderate': 1.55,
          'active': 1.725,
        }[p.activityLevel] ??
        1.375;
    double tdee = bmr * mult;
    if (p.goal == 'lose_fat') tdee -= 400;
    if (p.goal == 'gain_muscle') tdee += 400;
    return tdee;
  }

  // ── Nutrient targets ───────────────────────────────────────────────────────
  Map<String, double> _targets() {
    final p = widget.profile;
    return {
      'calories': _tdee(),
      'protein': p.weightKg * (p.hasGymAccess ? 2.0 : 1.6),
      'fiber': 25,
      'calcium': 1000,
      'iron': p.gender == 'female' ? 18.0 : 8.0,
      'vitaminC': 65,
      'vitaminB12': 2.4,
      'zinc': p.gender == 'female' ? 8.0 : 11.0,
    };
  }

  // ── Totals from selected foods ─────────────────────────────────────────────
  Map<String, double> _totals() {
    double cal = 0, pro = 0, fib = 0, ca = 0, fe = 0, vc = 0, b12 = 0, zn = 0;
    for (final f in _selected) {
      final qty = (_quantities[f.id] ?? 1).toDouble();
      cal += f.calories * qty;
      pro += f.proteinG * qty;
      fib += f.fiberG * qty;
      ca += f.calciumMg * qty;
      fe += f.ironMg * qty;
      vc += f.vitaminCMg * qty;
      b12 += (f.vitaminB12Mcg ?? 0) * qty;
      zn += (f.zincMg ?? 0) * qty;
    }
    return {
      'calories': cal,
      'protein': pro,
      'fiber': fib,
      'calcium': ca,
      'iron': fe,
      'vitaminC': vc,
      'vitaminB12': b12,
      'zinc': zn,
    };
  }

  // ── Build gap summary for onComplete ──────────────────────────────────────
  Map<String, dynamic> _buildGapSummary(
    Map<String, double> targets,
    Map<String, double> totals,
  ) {
    final gaps = <String, dynamic>{};
    final suggestions = <String>{};

    void checkGap(String key, String label, double Function(FoodItem) sel) {
      final gap = (targets[key]! - totals[key]!);
      if (gap > 0) {
        gaps['${key}_gap'] = gap.round();
        final top = FoodDatabase.topBy(
          selector: sel,
          excludeIds: _quantities.keys.toSet(),
          limit: 3,
        );
        for (final f in top) {
          suggestions.add(f.name);
        }
      }
    }

    checkGap('protein', 'protein', (f) => f.proteinG);
    checkGap('calcium', 'calcium', (f) => f.calciumMg);
    checkGap('iron', 'iron', (f) => f.ironMg);
    checkGap('vitaminC', 'vitaminC', (f) => f.vitaminCMg);
    checkGap('vitaminB12', 'vitaminB12', (f) => f.vitaminB12Mcg ?? 0);
    checkGap('zinc', 'zinc', (f) => f.zincMg ?? 0);
    checkGap('fiber', 'fiber', (f) => f.fiberG);
    checkGap('calories', 'calories', (f) => f.calories);

    gaps['suggestions'] = suggestions.toList();
    return gaps;
  }

  // ── Open analysis bottom sheet ─────────────────────────────────────────────
  void _openAnalysis() {
    if (_quantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Select at least one food to analyse.'),
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnalysisSheet(
        profile: widget.profile,
        targets: _targets(),
        totals: _totals(),
        selectedIds: _quantities.keys.toSet(),
        onAddFood: (id) {
          _addFromSuggestion(id);
          Navigator.of(context).pop();
        },
        onBuildPlan: () {
          final gaps = _buildGapSummary(_targets(), _totals());
          Navigator.of(context).pop();
          widget.onComplete(_selected, Map<String, int>.from(_quantities), gaps);
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Scaffold(
      backgroundColor: fc.bg,
      appBar: AppBar(
        backgroundColor: fc.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: fc.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Choose Your Foods',
          style: TextStyle(
            color: fc.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _SearchBar(controller: _searchCtrl),
              ),
              // Tab bar
              _DarkTabBar(controller: _tabCtrl, tabs: _tabs),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: List.generate(
                _tabs.length,
                (i) => _FoodList(
                  foods: _filtered(i),
                  quantities: _quantities,
                  onToggle: _toggle,
                  onQuantityChange: _setQuantity,
                ),
              ),
            ),
          ),
          _BottomBar(
            selectedCount: _quantities.length,
            onAnalyse: _openAnalysis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: fc.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fc.border),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(color: fc.textPrimary, fontSize: 14),
        cursorColor: kFitGreen,
        decoration: InputDecoration(
          hintText: 'Search foods...',
          hintStyle: TextStyle(
            color: fc.textHint,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: fc.textTertiary,
            size: 20,
          ),
          suffixIcon: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: fc.textTertiary,
                    ),
                    onPressed: controller.clear,
                  ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom dark tab bar
// ─────────────────────────────────────────────────────────────────────────────

class _DarkTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> tabs;
  const _DarkTabBar({required this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: Colors.transparent,
      indicatorColor: kFitGreen,
      indicatorWeight: 2,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: fc.accentFg(kFitGreen),
      unselectedLabelColor: fc.textSecondary,
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tabs: tabs.map((t) => Tab(text: t, height: 38)).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Food list (per tab)
// ─────────────────────────────────────────────────────────────────────────────

class _FoodList extends StatelessWidget {
  final List<FoodItem> foods;
  final Map<String, int> quantities;
  final void Function(String id) onToggle;
  final void Function(String id, int qty) onQuantityChange;

  const _FoodList({
    required this.foods,
    required this.quantities,
    required this.onToggle,
    required this.onQuantityChange,
  });

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    if (foods.isEmpty) {
      return Center(
        child: Text(
          'No foods found',
          style: TextStyle(color: fc.textHint, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: foods.length,
      itemBuilder: (_, i) {
        final food = foods[i];
        return _FoodTile(
          food: food,
          selected: quantities.containsKey(food.id),
          quantity: quantities[food.id] ?? 1,
          onTap: () => onToggle(food.id),
          onQuantityChange: (qty) => onQuantityChange(food.id, qty),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Food tile
// ─────────────────────────────────────────────────────────────────────────────

class _FoodTile extends StatelessWidget {
  final FoodItem food;
  final bool selected;
  final int quantity;
  final VoidCallback onTap;
  final void Function(int qty) onQuantityChange;

  // IDs where a +/- stepper is shown (roti = 2 pieces/serving, rice = 1 bowl/serving)
  static const _quantifiableIds = {'chapati_roti', 'roti_only', 'rice_cooked'};

  static String _qtyLabel(String id, int qty) {
    if (id == 'rice_cooked') return qty == 1 ? '1 bowl' : '$qty bowls';
    final pieces = qty * 2;
    return '$pieces rotis';
  }

  const _FoodTile({
    required this.food,
    required this.selected,
    required this.quantity,
    required this.onTap,
    required this.onQuantityChange,
  });

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final isQuantifiable = _quantifiableIds.contains(food.id);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? fc.accentBg(kFitGreen) : fc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? fc.accentBorder(kFitGreen) : fc.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _AnimatedCheckbox(checked: selected),
                const SizedBox(width: 12),
                Text(food.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food.name,
                        style: TextStyle(
                          color: fc.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${food.servingLabel}  •  ${food.calories.toInt()} kcal',
                        style: TextStyle(color: fc.textHint, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      _MacroRow(food: food, multiplier: selected ? quantity : 1),
                    ],
                  ),
                ),
              ],
            ),
            // Quantity stepper — only for roti/rice when selected
            if (selected && isQuantifiable) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 46), // align with text
                  Container(
                    decoration: BoxDecoration(
                      color: fc.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: fc.accentBorder(kFitGreen)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StepBtn(
                          icon: Icons.remove_rounded,
                          enabled: quantity > 1,
                          onTap: () => onQuantityChange(quantity - 1),
                          fc: fc,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _qtyLabel(food.id, quantity),
                            style: TextStyle(
                              color: fc.accentFg(kFitGreen),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _StepBtn(
                          icon: Icons.add_rounded,
                          enabled: quantity < 8,
                          onTap: () => onQuantityChange(quantity + 1),
                          fc: fc,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(food.calories * quantity).toInt()} kcal total',
                    style: TextStyle(color: fc.textHint, fontSize: 11),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final FitnessColors fc;

  const _StepBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.fc,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? fc.accentFg(kFitGreen) : fc.textDisabled,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated checkbox (22×22, rounded, border, check icon)
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedCheckbox extends StatelessWidget {
  final bool checked;
  const _AnimatedCheckbox({required this.checked});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked
            ? kFitGreen
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked
              ? kFitGreen
              : fc.textTertiary,
          width: 1.5,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: checked
            ? const Icon(
                Icons.check_rounded,
                key: ValueKey(true),
                size: 15,
                color: Colors.black,
              )
            : const SizedBox.shrink(key: ValueKey(false)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Macro row: protein / carbs / fat coloured dots
// ─────────────────────────────────────────────────────────────────────────────

class _MacroRow extends StatelessWidget {
  final FoodItem food;
  final int multiplier;
  const _MacroRow({required this.food, this.multiplier = 1});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final m = multiplier.toDouble();
    return Row(
      children: [
        _macroDot(fc, kFitGreen, 'P ${(food.proteinG * m).toStringAsFixed(1)}g'),
        const SizedBox(width: 8),
        _macroDot(fc, kFitBlue, 'C ${(food.carbsG * m).toStringAsFixed(1)}g'),
        const SizedBox(width: 8),
        _macroDot(fc, kFitOrange, 'F ${(food.fatG * m).toStringAsFixed(1)}g'),
      ],
    );
  }

  Widget _macroDot(FitnessColors fc, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: fc.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onAnalyse;

  const _BottomBar({required this.selectedCount, required this.onAnalyse});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: fc.bg,
        border: Border(
          top: BorderSide(color: fc.border),
        ),
      ),
      child: Row(
        children: [
          // Selection count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: fc.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: fc.border),
            ),
            child: Text(
              '$selectedCount selected',
              style: TextStyle(
                color: selectedCount > 0
                    ? fc.accentFg(kFitGreen)
                    : fc.textHint,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Analyse button
          Expanded(
            child: GestureDetector(
              onTap: onAnalyse,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: kFitGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Analyse & Build Plan',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Analysis modal bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AnalysisSheet extends StatefulWidget {
  final FitnessProfile profile;
  final Map<String, double> targets;
  final Map<String, double> totals;
  final Set<String> selectedIds;
  final void Function(String id) onAddFood;
  final VoidCallback onBuildPlan;

  const _AnalysisSheet({
    required this.profile,
    required this.targets,
    required this.totals,
    required this.selectedIds,
    required this.onAddFood,
    required this.onBuildPlan,
  });

  @override
  State<_AnalysisSheet> createState() => _AnalysisSheetState();
}

class _AnalysisSheetState extends State<_AnalysisSheet> {
  late Set<String> _currentSelected;

  @override
  void initState() {
    super.initState();
    _currentSelected = Set<String>.from(widget.selectedIds);
  }

  // ── Nutrient descriptor ───────────────────────────────────────────────────
  static const _nutrients = [
    _NutrientInfo(
      key: 'calories',
      label: 'Calories',
      emoji: '🔥',
      unit: 'kcal',
      selector: _selCalories,
    ),
    _NutrientInfo(
      key: 'protein',
      label: 'Protein',
      emoji: '💪',
      unit: 'g',
      selector: _selProtein,
    ),
    _NutrientInfo(
      key: 'fiber',
      label: 'Fiber',
      emoji: '🌾',
      unit: 'g',
      selector: _selFiber,
    ),
    _NutrientInfo(
      key: 'calcium',
      label: 'Calcium',
      emoji: '🦴',
      unit: 'mg',
      selector: _selCalcium,
    ),
    _NutrientInfo(
      key: 'iron',
      label: 'Iron',
      emoji: '🩸',
      unit: 'mg',
      selector: _selIron,
    ),
    _NutrientInfo(
      key: 'vitaminC',
      label: 'Vitamin C',
      emoji: '🍊',
      unit: 'mg',
      selector: _selVitC,
    ),
    _NutrientInfo(
      key: 'vitaminB12',
      label: 'Vitamin B12',
      emoji: '⚡',
      unit: 'mcg',
      selector: _selVitB12,
    ),
    _NutrientInfo(
      key: 'zinc',
      label: 'Zinc',
      emoji: '🔬',
      unit: 'mg',
      selector: _selZinc,
    ),
  ];

  // Static top-level selector functions required for const.
  static double _selCalories(FoodItem f) => f.calories;
  static double _selProtein(FoodItem f) => f.proteinG;
  static double _selFiber(FoodItem f) => f.fiberG;
  static double _selCalcium(FoodItem f) => f.calciumMg;
  static double _selIron(FoodItem f) => f.ironMg;
  static double _selVitC(FoodItem f) => f.vitaminCMg;
  static double _selVitB12(FoodItem f) => f.vitaminB12Mcg ?? 0;
  static double _selZinc(FoodItem f) => f.zincMg ?? 0;

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: fc.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fc.borderMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Text(
                    'Nutrient Gap Analysis',
                    style: TextStyle(
                      color: fc.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: fc.textTertiary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Nutrient rows
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: _nutrients
                    .map((n) => _NutrientRow(
                          info: n,
                          total: widget.totals[n.key] ?? 0,
                          target: widget.targets[n.key] ?? 0,
                          selectedIds: _currentSelected,
                          onAddFood: (id) {
                            setState(() => _currentSelected.add(id));
                            widget.onAddFood(id);
                          },
                        ))
                    .toList(),
              ),
            ),
            // Build plan button
            _SheetFooter(onBuildPlan: widget.onBuildPlan),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nutrient descriptor — const-safe
// ─────────────────────────────────────────────────────────────────────────────

class _NutrientInfo {
  final String key;
  final String label;
  final String emoji;
  final String unit;
  final double Function(FoodItem) selector;

  const _NutrientInfo({
    required this.key,
    required this.label,
    required this.emoji,
    required this.unit,
    required this.selector,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Single nutrient row inside the analysis sheet
// ─────────────────────────────────────────────────────────────────────────────

class _NutrientRow extends StatelessWidget {
  final _NutrientInfo info;
  final double total;
  final double target;
  final Set<String> selectedIds;
  final void Function(String id) onAddFood;

  static const _accent = kFitGreen;
  static const _deficiency = kFitRed;

  const _NutrientRow({
    required this.info,
    required this.total,
    required this.target,
    required this.selectedIds,
    required this.onAddFood,
  });

  bool get _met => total >= target;
  double get _ratio => target > 0 ? (total / target).clamp(0.0, 1.0) : 1.0;
  double get _gap => (target - total).clamp(0, double.infinity);
  bool get _shortBy20 => _gap / target > 0.20;

  String _fmt(double v) =>
      v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    final suggestions = _shortBy20
        ? FoodDatabase.topBy(
            selector: info.selector,
            excludeIds: selectedIds,
            limit: 3,
          )
        : <FoodItem>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _met
              ? fc.accentBorder(_accent)
              : fc.accentBorder(_deficiency),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: emoji + label + status
          Row(
            children: [
              Text(info.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                info.label,
                style: TextStyle(
                  color: fc.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_met)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: fc.accentBgStrong(_accent),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Met!',
                    style: TextStyle(
                      color: fc.accentFg(_accent),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _ratio,
              minHeight: 6,
              backgroundColor: fc.border,
              valueColor: AlwaysStoppedAnimation(_met ? _accent : _deficiency),
            ),
          ),
          const SizedBox(height: 6),
          // Status text
          Text(
            _met
                ? '${_fmt(total)} / ${_fmt(target)} ${info.unit}'
                : '${_fmt(total)} / ${_fmt(target)} ${info.unit}  —  ${_fmt(_gap)} ${info.unit} short',
            style: TextStyle(
              color: _met
                  ? fc.accentFg(_accent)
                  : fc.textTertiary,
              fontSize: 12,
            ),
          ),
          // Suggestion chips
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Add to boost ${info.label}:',
              style: TextStyle(
                color: fc.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: suggestions
                  .map((f) => _SuggestionChip(food: f, onTap: () => onAddFood(f.id)))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tappable suggestion chip
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionChip extends StatelessWidget {
  final FoodItem food;
  final VoidCallback onTap;

  const _SuggestionChip({required this.food, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: fc.accentBg(kFitGreen),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: fc.accentBorder(kFitGreen),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(food.emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              '+ ${food.name}',
              style: TextStyle(
                color: fc.accentFg(kFitGreen),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet footer with "Build My Plan" button
// ─────────────────────────────────────────────────────────────────────────────

class _SheetFooter extends StatelessWidget {
  final VoidCallback onBuildPlan;
  const _SheetFooter({required this.onBuildPlan});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: fc.card,
        border: Border(
          top: BorderSide(color: fc.border),
        ),
      ),
      child: GestureDetector(
        onTap: onBuildPlan,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: kFitGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: const Text(
            'Build My Plan',
            style: TextStyle(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
