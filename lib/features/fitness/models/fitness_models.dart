// ignore_for_file: public_member_api_docs

class FitnessProfile {
  final String userId;
  final int age;
  final double heightCm;
  final double weightKg;
  final String gender; // male / female / other
  final double sleepHours;
  final int stressLevel; // 1-5
  final String activityLevel; // sedentary / light / moderate / active
  final bool hasGymAccess;
  final String foodType; // mess / canteen / home
  final String goal; // lose_fat / gain_muscle / stay_fit / improve_stamina
  final String buddyName;
  final int buddyAvatarType; // 1-5
  final String buddyPersonality; // chill / hype / zen / grind / soft
  final String? buddyIntro;
  final DateTime createdAt;

  const FitnessProfile({
    required this.userId,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.gender,
    required this.sleepHours,
    required this.stressLevel,
    required this.activityLevel,
    required this.hasGymAccess,
    required this.foodType,
    required this.goal,
    required this.buddyName,
    required this.buddyAvatarType,
    required this.buddyPersonality,
    this.buddyIntro,
    required this.createdAt,
  });

  factory FitnessProfile.fromMap(Map<String, dynamic> m) => FitnessProfile(
        userId: m['user_id'] as String,
        age: (m['age'] as num).toInt(),
        heightCm: (m['height_cm'] as num).toDouble(),
        weightKg: (m['weight_kg'] as num).toDouble(),
        gender: m['gender'] as String,
        sleepHours: (m['sleep_hours'] as num).toDouble(),
        stressLevel: (m['stress_level'] as num).toInt(),
        activityLevel: m['activity_level'] as String,
        hasGymAccess: m['has_gym_access'] as bool,
        foodType: m['food_type'] as String,
        goal: m['goal'] as String,
        buddyName: m['buddy_name'] as String,
        buddyAvatarType: (m['buddy_avatar_type'] as num).toInt(),
        buddyPersonality: m['buddy_personality'] as String,
        buddyIntro: m['buddy_intro'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'age': age,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'gender': gender,
        'sleep_hours': sleepHours,
        'stress_level': stressLevel,
        'activity_level': activityLevel,
        'has_gym_access': hasGymAccess,
        'food_type': foodType,
        'goal': goal,
        'buddy_name': buddyName,
        'buddy_avatar_type': buddyAvatarType,
        'buddy_personality': buddyPersonality,
        if (buddyIntro != null) 'buddy_intro': buddyIntro,
      };

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));
}

class SupplementItem {
  final String name;
  final String dose;
  final String timing;
  final String why;
  final String priority; // high / medium / optional

  const SupplementItem({
    required this.name,
    required this.dose,
    required this.timing,
    required this.why,
    required this.priority,
  });

  factory SupplementItem.fromMap(Map<String, dynamic> m) => SupplementItem(
        name: m['name'] as String? ?? '',
        dose: m['dose'] as String? ?? '',
        timing: m['timing'] as String? ?? '',
        why: m['why'] as String? ?? '',
        priority: m['priority'] as String? ?? 'medium',
      );
}

class FitnessPlan {
  final String userId;
  final int dailyCalories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int durationWeeks;
  final Map<String, dynamic> workoutPlan;
  final Map<String, dynamic> dietGuide;
  final Map<String, dynamic> projectedGains;
  final List<String> keyTips;
  final List<SupplementItem> supplements;
  final DateTime createdAt;

  const FitnessPlan({
    required this.userId,
    required this.dailyCalories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.durationWeeks,
    required this.workoutPlan,
    required this.dietGuide,
    required this.projectedGains,
    required this.keyTips,
    this.supplements = const [],
    required this.createdAt,
  });

  factory FitnessPlan.fromMap(Map<String, dynamic> m) => FitnessPlan(
        userId: m['user_id'] as String,
        dailyCalories: (m['daily_calories'] as num).toInt(),
        proteinG: (m['protein_g'] as num).toInt(),
        carbsG: (m['carbs_g'] as num).toInt(),
        fatG: (m['fat_g'] as num).toInt(),
        durationWeeks: (m['duration_weeks'] as num).toInt(),
        workoutPlan: Map<String, dynamic>.from(m['workout_plan'] as Map? ?? {}),
        dietGuide: Map<String, dynamic>.from(m['diet_guide'] as Map? ?? {}),
        projectedGains: Map<String, dynamic>.from(m['projected_gains'] as Map? ?? {}),
        keyTips: List<String>.from(m['key_tips'] as List? ?? []),
        supplements: (m['supplements'] as List? ?? [])
            .map((s) => SupplementItem.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList(),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

class FitnessLog {
  final String userId;
  final DateTime logDate;
  final double? weightKg;
  final String dietFollowed; // yes / partial / no
  final bool workoutDone;
  final int mood; // 1-5
  final String? notes;

  const FitnessLog({
    required this.userId,
    required this.logDate,
    this.weightKg,
    required this.dietFollowed,
    required this.workoutDone,
    required this.mood,
    this.notes,
  });

  factory FitnessLog.fromMap(Map<String, dynamic> m) => FitnessLog(
        userId: m['user_id'] as String,
        logDate: DateTime.parse(m['log_date'] as String),
        weightKg: (m['weight_kg'] as num?)?.toDouble(),
        dietFollowed: m['diet_followed'] as String,
        workoutDone: m['workout_done'] as bool,
        mood: (m['mood'] as num).toInt(),
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'log_date': '${logDate.year}-${logDate.month.toString().padLeft(2, '0')}-${logDate.day.toString().padLeft(2, '0')}',
        if (weightKg != null) 'weight_kg': weightKg,
        'diet_followed': dietFollowed,
        'workout_done': workoutDone,
        'mood': mood,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

class BuddyState {
  final String userId;
  final int level; // 1-5
  final int streakDays;
  final int totalDaysFollowed;
  final int bodyStage; // 1-10
  final String? lastMessage;
  final DateTime updatedAt;

  const BuddyState({
    required this.userId,
    required this.level,
    required this.streakDays,
    required this.totalDaysFollowed,
    required this.bodyStage,
    this.lastMessage,
    required this.updatedAt,
  });

  // Maps body_stage 1-10 → display stage 1-5
  int get displayStage => ((bodyStage - 1) ~/ 2).clamp(0, 4) + 1;

  factory BuddyState.fromMap(Map<String, dynamic> m) => BuddyState(
        userId: m['user_id'] as String,
        level: (m['level'] as num).toInt(),
        streakDays: (m['streak_days'] as num).toInt(),
        totalDaysFollowed: (m['total_days_followed'] as num).toInt(),
        bodyStage: (m['body_stage'] as num).toInt(),
        lastMessage: m['last_message'] as String?,
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'level': level,
        'streak_days': streakDays,
        'total_days_followed': totalDaysFollowed,
        'body_stage': bodyStage,
        if (lastMessage != null) 'last_message': lastMessage,
        'updated_at': updatedAt.toIso8601String(),
      };
}
