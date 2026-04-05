// ─────────────────────────────────────────────────────────────────────────────
// Exercise library — gym exercises grouped by muscle
// ─────────────────────────────────────────────────────────────────────────────

class ExerciseItem {
  final String name;
  final String muscle;
  final String equipment;
  final String defaultReps;

  const ExerciseItem({
    required this.name,
    required this.muscle,
    required this.equipment,
    this.defaultReps = '10',
  });
}

const kExerciseMuscles = [
  'All', 'Chest', 'Back', 'Legs', 'Shoulders', 'Biceps', 'Triceps', 'Core', 'Cardio',
];

const kGymExercises = <ExerciseItem>[
  // ── Chest ────────────────────────────────────────────────────────────────
  ExerciseItem(name: 'Flat Bench Press',    muscle: 'Chest', equipment: 'Barbell'),
  ExerciseItem(name: 'Incline Bench Press', muscle: 'Chest', equipment: 'Barbell'),
  ExerciseItem(name: 'Decline Bench Press', muscle: 'Chest', equipment: 'Barbell'),
  ExerciseItem(name: 'Dumbbell Fly',        muscle: 'Chest', equipment: 'Dumbbell'),
  ExerciseItem(name: 'Incline Dumbbell Press', muscle: 'Chest', equipment: 'Dumbbell'),
  ExerciseItem(name: 'Cable Fly',           muscle: 'Chest', equipment: 'Cable'),
  ExerciseItem(name: 'Pec Deck Machine',    muscle: 'Chest', equipment: 'Machine'),
  ExerciseItem(name: 'Chest Dips',          muscle: 'Chest', equipment: 'Bodyweight', defaultReps: '12'),
  ExerciseItem(name: 'Push-ups',            muscle: 'Chest', equipment: 'Bodyweight', defaultReps: '15'),

  // ── Back ─────────────────────────────────────────────────────────────────
  ExerciseItem(name: 'Deadlift',            muscle: 'Back', equipment: 'Barbell', defaultReps: '5'),
  ExerciseItem(name: 'Barbell Row',         muscle: 'Back', equipment: 'Barbell'),
  ExerciseItem(name: 'Lat Pulldown',        muscle: 'Back', equipment: 'Cable'),
  ExerciseItem(name: 'Seated Cable Row',    muscle: 'Back', equipment: 'Cable'),
  ExerciseItem(name: 'Single-Arm DB Row',   muscle: 'Back', equipment: 'Dumbbell'),
  ExerciseItem(name: 'Pull-ups',            muscle: 'Back', equipment: 'Bodyweight', defaultReps: '8'),
  ExerciseItem(name: 'Chest-Supported Row', muscle: 'Back', equipment: 'Machine'),
  ExerciseItem(name: 'Face Pulls',          muscle: 'Back', equipment: 'Cable', defaultReps: '15'),
  ExerciseItem(name: 'T-Bar Row',           muscle: 'Back', equipment: 'Barbell'),

  // ── Legs ─────────────────────────────────────────────────────────────────
  ExerciseItem(name: 'Barbell Squat',       muscle: 'Legs', equipment: 'Barbell', defaultReps: '8'),
  ExerciseItem(name: 'Romanian Deadlift',   muscle: 'Legs', equipment: 'Barbell'),
  ExerciseItem(name: 'Leg Press',           muscle: 'Legs', equipment: 'Machine', defaultReps: '12'),
  ExerciseItem(name: 'Hack Squat',          muscle: 'Legs', equipment: 'Machine'),
  ExerciseItem(name: 'Leg Extension',       muscle: 'Legs', equipment: 'Machine', defaultReps: '15'),
  ExerciseItem(name: 'Leg Curl',            muscle: 'Legs', equipment: 'Machine', defaultReps: '12'),
  ExerciseItem(name: 'Walking Lunges',      muscle: 'Legs', equipment: 'Dumbbell', defaultReps: '12'),
  ExerciseItem(name: 'Bulgarian Split Squat', muscle: 'Legs', equipment: 'Dumbbell'),
  ExerciseItem(name: 'Calf Raises',         muscle: 'Legs', equipment: 'Machine', defaultReps: '20'),
  ExerciseItem(name: 'Hip Thrust',          muscle: 'Legs', equipment: 'Barbell', defaultReps: '12'),

  // ── Shoulders ─────────────────────────────────────────────────────────────
  ExerciseItem(name: 'Overhead Press',      muscle: 'Shoulders', equipment: 'Barbell', defaultReps: '8'),
  ExerciseItem(name: 'Dumbbell OHP',        muscle: 'Shoulders', equipment: 'Dumbbell'),
  ExerciseItem(name: 'Lateral Raise',       muscle: 'Shoulders', equipment: 'Dumbbell', defaultReps: '15'),
  ExerciseItem(name: 'Front Raise',         muscle: 'Shoulders', equipment: 'Dumbbell', defaultReps: '12'),
  ExerciseItem(name: 'Arnold Press',        muscle: 'Shoulders', equipment: 'Dumbbell'),
  ExerciseItem(name: 'Cable Lateral Raise', muscle: 'Shoulders', equipment: 'Cable', defaultReps: '15'),
  ExerciseItem(name: 'Rear Delt Fly',       muscle: 'Shoulders', equipment: 'Dumbbell', defaultReps: '15'),
  ExerciseItem(name: 'Upright Row',         muscle: 'Shoulders', equipment: 'Barbell', defaultReps: '12'),

  // ── Biceps ────────────────────────────────────────────────────────────────
  ExerciseItem(name: 'Barbell Curl',        muscle: 'Biceps', equipment: 'Barbell', defaultReps: '12'),
  ExerciseItem(name: 'Dumbbell Curl',       muscle: 'Biceps', equipment: 'Dumbbell', defaultReps: '12'),
  ExerciseItem(name: 'Hammer Curl',         muscle: 'Biceps', equipment: 'Dumbbell', defaultReps: '12'),
  ExerciseItem(name: 'Concentration Curl',  muscle: 'Biceps', equipment: 'Dumbbell', defaultReps: '12'),
  ExerciseItem(name: 'Preacher Curl',       muscle: 'Biceps', equipment: 'Machine', defaultReps: '10'),
  ExerciseItem(name: 'Cable Curl',          muscle: 'Biceps', equipment: 'Cable', defaultReps: '12'),
  ExerciseItem(name: 'Incline Dumbbell Curl', muscle: 'Biceps', equipment: 'Dumbbell', defaultReps: '10'),

  // ── Triceps ───────────────────────────────────────────────────────────────
  ExerciseItem(name: 'Skull Crushers',      muscle: 'Triceps', equipment: 'Barbell', defaultReps: '10'),
  ExerciseItem(name: 'Tricep Pushdown',     muscle: 'Triceps', equipment: 'Cable', defaultReps: '12'),
  ExerciseItem(name: 'Overhead Tricep Ext', muscle: 'Triceps', equipment: 'Dumbbell', defaultReps: '12'),
  ExerciseItem(name: 'Close-Grip Bench',    muscle: 'Triceps', equipment: 'Barbell', defaultReps: '10'),
  ExerciseItem(name: 'Tricep Dips',         muscle: 'Triceps', equipment: 'Bodyweight', defaultReps: '12'),
  ExerciseItem(name: 'Kickbacks',           muscle: 'Triceps', equipment: 'Dumbbell', defaultReps: '12'),

  // ── Core ──────────────────────────────────────────────────────────────────
  ExerciseItem(name: 'Plank',              muscle: 'Core', equipment: 'Bodyweight', defaultReps: '30s'),
  ExerciseItem(name: 'Crunches',           muscle: 'Core', equipment: 'Bodyweight', defaultReps: '20'),
  ExerciseItem(name: 'Leg Raises',         muscle: 'Core', equipment: 'Bodyweight', defaultReps: '15'),
  ExerciseItem(name: 'Russian Twist',      muscle: 'Core', equipment: 'Bodyweight', defaultReps: '20'),
  ExerciseItem(name: 'Cable Crunch',       muscle: 'Core', equipment: 'Cable', defaultReps: '15'),
  ExerciseItem(name: 'Ab Wheel Rollout',   muscle: 'Core', equipment: 'Machine', defaultReps: '10'),
  ExerciseItem(name: 'Hanging Knee Raise', muscle: 'Core', equipment: 'Bodyweight', defaultReps: '15'),
  ExerciseItem(name: 'Side Plank',         muscle: 'Core', equipment: 'Bodyweight', defaultReps: '30s'),

  // ── Cardio ────────────────────────────────────────────────────────────────
  ExerciseItem(name: 'Treadmill Run',      muscle: 'Cardio', equipment: 'Machine', defaultReps: '20 min'),
  ExerciseItem(name: 'Cycling',            muscle: 'Cardio', equipment: 'Machine', defaultReps: '20 min'),
  ExerciseItem(name: 'Stair Climber',      muscle: 'Cardio', equipment: 'Machine', defaultReps: '15 min'),
  ExerciseItem(name: 'Jump Rope',          muscle: 'Cardio', equipment: 'Bodyweight', defaultReps: '5 min'),
  ExerciseItem(name: 'Battle Ropes',       muscle: 'Cardio', equipment: 'Machine', defaultReps: '30s'),
  ExerciseItem(name: 'Rowing Machine',     muscle: 'Cardio', equipment: 'Machine', defaultReps: '10 min'),
];
