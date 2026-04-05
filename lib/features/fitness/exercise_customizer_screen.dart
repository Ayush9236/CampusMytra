import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fitness_theme.dart';
import 'exercise_library.dart';
import 'services/fitness_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class CustomExercise {
  String name;
  int sets;
  String reps;
  String rest;

  CustomExercise({
    required this.name,
    this.sets = 3,
    this.reps = '10',
    this.rest = '60s',
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'sets': sets, 'reps': reps, 'rest': rest};

  factory CustomExercise.fromJson(Map<String, dynamic> j) => CustomExercise(
        name: j['name'] as String,
        sets: (j['sets'] as num).toInt(),
        reps: j['reps'] as String,
        rest: j['rest'] as String? ?? '60s',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Persistence helpers
// ─────────────────────────────────────────────────────────────────────────────

const _kCustomWorkoutKey = 'fitness_custom_workout';

Map<String, dynamic> _planToJson(
  Map<String, List<CustomExercise>> plan, [
  Map<String, String> labels = const {},
]) {
  final json = <String, dynamic>{
    for (final e in plan.entries) e.key: e.value.map((ex) => ex.toJson()).toList(),
  };
  if (labels.isNotEmpty) json['_labels'] = labels;
  return json;
}

// Only parse day keys (skip internal keys like _labels)
Map<String, List<CustomExercise>> _planFromJson(Map<String, dynamic> raw) {
  final result = <String, List<CustomExercise>>{};
  for (final entry in raw.entries) {
    if (entry.key.startsWith('_')) continue;
    result[entry.key] = (entry.value as List)
        .map((e) => CustomExercise.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  return result;
}

Map<String, String> _labelsFromJson(Map<String, dynamic> raw) {
  final labels = raw['_labels'];
  if (labels == null) return {};
  return Map<String, String>.from(labels as Map);
}

/// Loads exercises from Supabase (source of truth). Falls back to local cache if offline.
Future<Map<String, List<CustomExercise>>> loadCustomWorkout() async {
  final raw = await _loadRaw();
  return _planFromJson(raw);
}

/// Loads day labels from Supabase. Falls back to local cache if offline.
Future<Map<String, String>> loadCustomDayLabels() async {
  final raw = await _loadRaw();
  return _labelsFromJson(raw);
}

/// Loads both exercises and labels in a single network call.
Future<(Map<String, List<CustomExercise>>, Map<String, String>)> loadCustomWorkoutFull() async {
  final raw = await _loadRaw();
  return (_planFromJson(raw), _labelsFromJson(raw));
}

Future<Map<String, dynamic>> _loadRaw() async {
  try {
    final remote = await FitnessService.getCustomWorkout();
    if (remote.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCustomWorkoutKey, jsonEncode(remote));
      return remote;
    }
  } catch (_) {}
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCustomWorkoutKey);
    if (raw != null) return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {}
  return {};
}

/// Saves exercises + labels to both Supabase and local cache.
Future<void> saveCustomWorkout(
  Map<String, List<CustomExercise>> plan, [
  Map<String, String> labels = const {},
]) async {
  final json = _planToJson(plan, labels);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kCustomWorkoutKey, jsonEncode(json));
  await FitnessService.saveCustomWorkout(json);
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ExerciseCustomizerScreen extends StatefulWidget {
  final Map<String, List<CustomExercise>> initial;
  final Map<String, String> initialLabels;
  /// AI-generated day focuses shown as placeholder when no custom label is set.
  final Map<String, String> aiFocuses;

  const ExerciseCustomizerScreen({
    super.key,
    required this.initial,
    this.initialLabels = const {},
    this.aiFocuses = const {},
  });

  @override
  State<ExerciseCustomizerScreen> createState() => _ExerciseCustomizerScreenState();
}

class _ExerciseCustomizerScreenState extends State<ExerciseCustomizerScreen> {
  static const _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late Map<String, List<CustomExercise>> _plan;
  late Map<String, String> _focuses; // custom day labels
  int _dayIndex = 0;
  String _search = '';
  String _muscle = 'All';
  bool _showLibrary = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _plan = {for (final d in _days) d: List.from(widget.initial[d] ?? [])};
    _focuses = Map.from(widget.initialLabels);
  }

  String get _day => _days[_dayIndex];
  List<CustomExercise> get _dayExercises => _plan[_day]!;
  String get _currentFocus => _focuses[_day] ?? widget.aiFocuses[_day] ?? '';

  List<ExerciseItem> get _filtered {
    final q = _search.toLowerCase();
    return kGymExercises.where((e) {
      final muscleMatch = _muscle == 'All' || e.muscle == _muscle;
      final searchMatch = q.isEmpty || e.name.toLowerCase().contains(q);
      return muscleMatch && searchMatch;
    }).toList();
  }

  bool _isAdded(String name) => _dayExercises.any((e) => e.name == name);

  void _addExercise(ExerciseItem item) {
    if (_isAdded(item.name)) return;
    setState(() {
      _dayExercises.add(CustomExercise(name: item.name, reps: item.defaultReps));
    });
  }

  void _removeExercise(int index) {
    setState(() => _dayExercises.removeAt(index));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await saveCustomWorkout(_plan, _focuses);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context, (_plan, _focuses));
    }
  }

  void _renameDayFocus() {
    final fc = FitnessColors.of(context);
    final ctrl = TextEditingController(text: _currentFocus);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: fc.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename ${_dayLabels[_dayIndex]}',
            style: TextStyle(color: fc.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: fc.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'e.g. Chest & Triceps',
            hintStyle: TextStyle(color: fc.textDisabled),
            filled: true,
            fillColor: fc.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: fc.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: fc.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: kFitOrange),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: fc.textHint)),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              setState(() {
                if (v.isEmpty) {
                  _focuses.remove(_day);
                } else {
                  _focuses[_day] = v;
                }
              });
              Navigator.pop(ctx);
            },
            child: Text('Save', style: TextStyle(color: kFitOrange, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(int index) {
    final ex = _dayExercises[index];
    int sets = ex.sets;
    String reps = ex.reps;
    String rest = ex.rest;
    final fc = FitnessColors.of(context);
    final nameCtrl = TextEditingController(text: ex.name);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: fc.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Edit Exercise',
              style: TextStyle(color: fc.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // Name
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: fc.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'Exercise name',
                labelStyle: TextStyle(color: fc.textHint, fontSize: 12),
                filled: true,
                fillColor: fc.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: fc.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: fc.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kFitGreen),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),
            // Sets
            _DialogRow(
              label: 'Sets',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _StepBtn(icon: Icons.remove, onTap: sets > 1 ? () => setDialog(() => sets--) : null, fc: fc),
                SizedBox(
                  width: 36,
                  child: Text('$sets',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: fc.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                _StepBtn(icon: Icons.add, onTap: sets < 10 ? () => setDialog(() => sets++) : null, fc: fc),
              ]),
            ),
            const SizedBox(height: 16),
            // Reps
            _DialogRow(
              label: 'Reps',
              child: _RepsField(initial: reps, fc: fc, onChanged: (v) => reps = v),
            ),
            const SizedBox(height: 16),
            // Rest
            _DialogRow(
              label: 'Rest',
              child: _RestSelector(initial: rest, fc: fc, onChanged: (v) => setDialog(() => rest = v)),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: fc.textHint)),
            ),
            TextButton(
              onPressed: () {
                final trimmed = nameCtrl.text.trim();
                setState(() {
                  ex.name = trimmed.isNotEmpty ? trimmed : ex.name;
                  ex.sets = sets;
                  ex.reps = reps;
                  ex.rest = rest;
                });
                Navigator.pop(ctx);
              },
              child: Text('Done', style: TextStyle(color: kFitGreen, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    ).then((_) => nameCtrl.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Scaffold(
      backgroundColor: fc.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Top bar ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: fc.textSecondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Customize Workout',
                    style: TextStyle(color: fc.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: kFitGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kFitGreen.withValues(alpha: 0.4)),
                  ),
                  child: _saving
                      ? SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: kFitGreen, strokeWidth: 2))
                      : Text('Save', style: TextStyle(
                          color: kFitGreen, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),

          // ── Day tabs ────────────────────────────────────────────────────
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _days.length,
              itemBuilder: (_, i) {
                final active = i == _dayIndex;
                return GestureDetector(
                  onTap: () => setState(() { _dayIndex = i; _showLibrary = false; }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: active ? kFitGreen.withValues(alpha: 0.18) : fc.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active ? kFitGreen.withValues(alpha: 0.6) : fc.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_dayLabels[i],
                          style: TextStyle(
                            color: active ? kFitGreen : fc.textHint,
                            fontSize: 12, fontWeight: FontWeight.w700,
                          )),
                      if (_plan[_days[i]]!.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: active ? kFitGreen : fc.textDisabled,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ]),
                  ),
                );
              },
            ),
          ),

          // ── Day focus label + rename ────────────────────────────────────
          if (!_showLibrary) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: _renameDayFocus,
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _currentFocus.isEmpty ? 'Tap to set day focus…' : _currentFocus,
                      style: TextStyle(
                        color: _currentFocus.isEmpty ? fc.textDisabled : fc.textSecondary,
                        fontSize: 13, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_rounded, color: kFitOrange, size: 14),
                ]),
              ),
            ),
          ],

          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _showLibrary
                  ? _LibraryPane(
                      key: ValueKey('lib$_dayIndex'),
                      filtered: _filtered,
                      search: _search,
                      muscle: _muscle,
                      isAdded: _isAdded,
                      onAdd: _addExercise,
                      onSearch: (v) => setState(() => _search = v),
                      onMuscle: (v) => setState(() => _muscle = v),
                      onBack: () => setState(() => _showLibrary = false),
                      fc: fc,
                    )
                  : _DayPane(
                      key: ValueKey('day$_dayIndex'),
                      exercises: _dayExercises,
                      onEdit: _showEditDialog,
                      onRemove: _removeExercise,
                      onReorder: (oldI, newI) {
                        setState(() {
                          if (newI > oldI) newI--;
                          final item = _dayExercises.removeAt(oldI);
                          _dayExercises.insert(newI, item);
                        });
                      },
                      onAddTap: () => setState(() => _showLibrary = true),
                      fc: fc,
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Day pane — shows exercises for the selected day
// ─────────────────────────────────────────────────────────────────────────────

class _DayPane extends StatelessWidget {
  final List<CustomExercise> exercises;
  final void Function(int) onEdit;
  final void Function(int) onRemove;
  final void Function(int, int) onReorder;
  final VoidCallback onAddTap;
  final FitnessColors fc;

  const _DayPane({
    super.key,
    required this.exercises,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
    required this.onAddTap,
    required this.fc,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: exercises.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('💪', style: const TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text('No exercises yet',
                      style: TextStyle(color: fc.textSecondary, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Tap "Add Exercises" to build this day',
                      style: TextStyle(color: fc.textHint, fontSize: 13)),
                ]),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                itemCount: exercises.length,
                onReorder: onReorder,
                itemBuilder: (_, i) {
                  final ex = exercises[i];
                  return _ExerciseEditTile(
                    key: ValueKey('${ex.name}_$i'),
                    ex: ex,
                    onEdit: () => onEdit(i),
                    onRemove: () => onRemove(i),
                    fc: fc,
                  );
                },
              ),
      ),
      // Add button
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: GestureDetector(
          onTap: onAddTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: kFitGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kFitGreen.withValues(alpha: 0.35), style: BorderStyle.solid),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, color: kFitGreen, size: 20),
              const SizedBox(width: 8),
              Text('Add Exercises',
                  style: TextStyle(color: kFitGreen, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _ExerciseEditTile extends StatelessWidget {
  final CustomExercise ex;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final FitnessColors fc;

  const _ExerciseEditTile({
    super.key,
    required this.ex,
    required this.onEdit,
    required this.onRemove,
    required this.fc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: fc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fc.accentBorder(kFitGreen)),
      ),
      child: Row(children: [
        // Drag handle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.drag_handle_rounded, color: fc.textDisabled, size: 18),
        ),
        // Name
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(ex.name,
                style: TextStyle(color: fc.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
        // Sets × Reps (tappable)
        GestureDetector(
          onTap: onEdit,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: fc.accentBg(kFitGreen),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${ex.sets} × ${ex.reps}',
                style: TextStyle(color: fc.accentFg(kFitGreen), fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
        // Rest
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(ex.rest, style: TextStyle(color: fc.textDisabled, fontSize: 10)),
        ),
        // Remove
        GestureDetector(
          onTap: onRemove,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 12, 14),
            child: Icon(Icons.close_rounded, color: fc.textDisabled, size: 16),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Library pane — searchable exercise list
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryPane extends StatelessWidget {
  final List<ExerciseItem> filtered;
  final String search;
  final String muscle;
  final bool Function(String) isAdded;
  final void Function(ExerciseItem) onAdd;
  final void Function(String) onSearch;
  final void Function(String) onMuscle;
  final VoidCallback onBack;
  final FitnessColors fc;

  const _LibraryPane({
    super.key,
    required this.filtered,
    required this.search,
    required this.muscle,
    required this.isAdded,
    required this.onAdd,
    required this.onSearch,
    required this.onMuscle,
    required this.onBack,
    required this.fc,
  });

  @override
  Widget build(BuildContext context) {
    // Group by muscle for display
    final grouped = <String, List<ExerciseItem>>{};
    for (final e in filtered) {
      grouped.putIfAbsent(e.muscle, () => []).add(e);
    }

    return Column(children: [
      // Back + search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: fc.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: fc.border)),
              child: Icon(Icons.arrow_back_rounded, color: fc.textSecondary, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: fc.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fc.border),
              ),
              child: TextField(
                onChanged: onSearch,
                style: TextStyle(color: fc.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search exercises…',
                  hintStyle: TextStyle(color: fc.textDisabled, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: fc.textDisabled, size: 16),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),
        ]),
      ),
      // Muscle filter chips
      const SizedBox(height: 10),
      SizedBox(
        height: 30,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: kExerciseMuscles.length,
          itemBuilder: (_, i) {
            final m = kExerciseMuscles[i];
            final active = m == muscle;
            return GestureDetector(
              onTap: () => onMuscle(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active ? kFitOrange.withValues(alpha: 0.18) : fc.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? kFitOrange.withValues(alpha: 0.5) : fc.border),
                ),
                alignment: Alignment.center,
                child: Text(m,
                    style: TextStyle(
                      color: active ? kFitOrange : fc.textHint,
                      fontSize: 11, fontWeight: FontWeight.w600,
                    )),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      // Exercise list
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Text('No exercises found', style: TextStyle(color: fc.textHint, fontSize: 13)))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: grouped.entries.map((entry) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(entry.key,
                          style: TextStyle(color: fc.textHint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    ),
                    ...entry.value.map((item) => _ExerciseLibraryTile(
                          item: item,
                          added: isAdded(item.name),
                          onAdd: () => onAdd(item),
                          fc: fc,
                        )),
                  ]);
                }).toList(),
              ),
      ),
    ]);
  }
}

class _ExerciseLibraryTile extends StatelessWidget {
  final ExerciseItem item;
  final bool added;
  final VoidCallback onAdd;
  final FitnessColors fc;

  const _ExerciseLibraryTile({
    required this.item, required this.added, required this.onAdd, required this.fc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: added ? fc.accentBg(kFitGreen) : fc.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: added ? fc.accentBorder(kFitGreen) : fc.border),
      ),
      child: Row(children: [
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name,
                  style: TextStyle(
                    color: added ? fc.accentFg(kFitGreen) : fc.textSecondary,
                    fontSize: 13, fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 2),
              Text(item.equipment,
                  style: TextStyle(color: fc.textDisabled, fontSize: 10)),
            ]),
          ),
        ),
        GestureDetector(
          onTap: added ? null : onAdd,
          child: Container(
            margin: const EdgeInsets.only(right: 10),
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: added ? kFitGreen.withValues(alpha: 0.15) : kFitGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: kFitGreen.withValues(alpha: added ? 0.4 : 0.3)),
            ),
            child: Icon(
              added ? Icons.check_rounded : Icons.add_rounded,
              color: kFitGreen, size: 16,
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog helpers
// ─────────────────────────────────────────────────────────────────────────────

class _DialogRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _DialogRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final fc = FitnessColors.of(context);
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: fc.textHint, fontSize: 13)),
      child,
    ]);
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final FitnessColors fc;
  const _StepBtn({required this.icon, required this.onTap, required this.fc});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: onTap != null ? fc.surface : fc.border,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: fc.border),
        ),
        child: Icon(icon, size: 16,
            color: onTap != null ? fc.textSecondary : fc.textDisabled),
      ),
    );
  }
}

class _RepsField extends StatefulWidget {
  final String initial;
  final FitnessColors fc;
  final void Function(String) onChanged;
  const _RepsField({required this.initial, required this.fc, required this.onChanged});

  @override
  State<_RepsField> createState() => _RepsFieldState();
}

class _RepsFieldState extends State<_RepsField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        textAlign: TextAlign.center,
        style: TextStyle(color: widget.fc.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: '10',
          hintStyle: TextStyle(color: widget.fc.textDisabled),
          filled: true,
          fillColor: widget.fc.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: widget.fc.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: widget.fc.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: kFitGreen),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}

class _RestSelector extends StatelessWidget {
  final String initial;
  final FitnessColors fc;
  final void Function(String) onChanged;
  const _RestSelector({required this.initial, required this.fc, required this.onChanged});

  static const _options = ['30s', '45s', '60s', '90s', '2 min', '3 min'];

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: _options.contains(initial) ? initial : '60s',
      onChanged: (v) { if (v != null) onChanged(v); },
      underline: const SizedBox(),
      dropdownColor: fc.card,
      style: TextStyle(color: fc.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
      items: _options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
    );
  }
}
