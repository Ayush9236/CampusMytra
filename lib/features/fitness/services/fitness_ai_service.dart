import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fitness_models.dart';
import '../data/food_database.dart';

// Gemini calls go through a Supabase Edge Function proxy so the API key
// never lives in the APK binary.
const String _kGeminiProxyUrl =
    'https://iukxnbifojobmerspvxn.supabase.co/functions/v1/gemini-proxy';

// Supabase anon key — public by design; real auth is enforced by Supabase RLS.
const String _kAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1a3huYmlmb2pvYm1lcnNwdnhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyMzAxOTgsImV4cCI6MjA4NjgwNjE5OH0.-go5he8W7NmSaJJYbkj8rHoYST0SBTuk4yZdIC7EIJg';

/// Sends [prompt] to the AI proxy (Groq backend).
/// Returns the response text, or null on failure.
Future<String?> _callGemini({
  required String prompt,
  double temperature = 0.7,
  int maxTokens = 500,
  bool jsonMode = false,
}) async {
  for (int attempt = 1; attempt <= 2; attempt++) {
    try {
      final token =
          Supabase.instance.client.auth.currentSession?.accessToken ?? _kAnonKey;
      final res = await http
          .post(
            Uri.parse(_kGeminiProxyUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'apikey': _kAnonKey,
            },
            body: jsonEncode({
              'prompt': prompt,
              'temperature': temperature,
              'maxTokens': maxTokens,
              'jsonMode': jsonMode,
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('[AIProxy] attempt $attempt status=${res.statusCode} body=${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');

      if (res.statusCode != 200) {
        debugPrint('[AIProxy] non-200: ${res.statusCode} ${res.body}');
        if (attempt < 2) continue;
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final text = data['text'] as String?;
      return (text?.isNotEmpty == true) ? text : null;
    } catch (e) {
      debugPrint('[AIProxy] attempt $attempt error: $e');
      if (attempt < 2) await Future.delayed(const Duration(seconds: 2));
    }
  }
  return null;
}

class FitnessAiService {
  // ──────────────────────────────────────────────────────────────
  // Generate full fitness plan + buddy persona from user profile
  // ──────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> generatePlan(FitnessProfile p) async {
    final bmi = p.bmi;
    final bmiLabel = bmi < 18.5
        ? 'Underweight'
        : bmi < 25
            ? 'Normal'
            : bmi < 30
                ? 'Overweight'
                : 'Obese';

    final prompt = '''
Indian college fitness coach. Return ONLY valid JSON, no markdown, no extra text.

PROFILE: Age ${p.age}, ${p.gender}, ${p.heightCm.toStringAsFixed(0)}cm, ${p.weightKg}kg, BMI ${bmi.toStringAsFixed(1)} ($bmiLabel), sleep ${p.sleepHours}h, stress ${p.stressLevel}/5, activity=${p.activityLevel}, gym=${p.hasGymAccess ? 'Y' : 'N'}, food=${p.foodType}, goal=${p.goal}

RULES: gym=N→bodyweight; calories=Mifflin-St Jeor(lose_fat-400,gain_muscle+400); protein=gym?2g/kg:1.6g/kg; personality: stress≥4→chill, goal=gain_muscle→hype, goal=lose_fat→grind, else→zen; max 2 supplements; each workout day max 3 exercises.

{"buddy_name":"","buddy_personality":"chill|hype|zen|grind|soft","buddy_intro":"1 sentence","daily_calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"workout_plan":{"monday":{"focus":"","is_rest":false,"exercises":[{"name":"","sets":3,"reps":"10","rest":"60s"}]},"tuesday":{"focus":"","is_rest":false,"exercises":[]},"wednesday":{"focus":"Rest","is_rest":true,"exercises":[]},"thursday":{"focus":"","is_rest":false,"exercises":[]},"friday":{"focus":"","is_rest":false,"exercises":[]},"saturday":{"focus":"Cardio","is_rest":false,"exercises":[]},"sunday":{"focus":"Rest","is_rest":true,"exercises":[]}},"projected_gains":{"week4":"","week8":"","week12":""},"key_tips":["","",""],"supplements":[{"name":"","dose":"","timing":"","why":"","priority":"high|medium|optional"}]}
''';

    try {
      final text = await _callGemini(
        prompt: prompt,
        temperature: 0.4,
        maxTokens: 800,
        jsonMode: true,
      );
      if (text == null || text.isEmpty) return fallbackPlan(p);
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return fallbackPlan(p);
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Build diet guide locally from user-selected foods.
  // Goal-aware: calculates totals, compares with target, adds
  // personalised notes so every user sees a relevant plan.
  // ──────────────────────────────────────────────────────────────
  static Map<String, dynamic> buildDietGuide(
    List<FoodItem> foods,
    Map<String, int> quantities, [
    FitnessProfile? profile,
  ]) {
    final breakfast = <String>[];
    final lunch     = <String>[];
    final dinner    = <String>[];
    final snacks    = <String>[];

    // ── Sort by goal to surface best options first ────────────────
    final sorted = List<FoodItem>.from(foods);
    if (profile != null) {
      if (profile.goal == 'gain_muscle') {
        sorted.sort((a, b) => b.proteinG.compareTo(a.proteinG)); // high protein first
      } else if (profile.goal == 'lose_fat') {
        sorted.sort((a, b) => a.calories.compareTo(b.calories)); // lower cal first
      }
    }

    for (final food in sorted) {
      final qty   = quantities[food.id] ?? 1;
      final label = _foodLabel(food, qty);
      bool tagged = false;
      for (final meal in food.meals) {
        switch (meal) {
          case 'breakfast': breakfast.add(label); tagged = true; break;
          case 'lunch':     lunch.add(label);     tagged = true; break;
          case 'dinner':    dinner.add(label);    tagged = true; break;
          case 'snacks':    snacks.add(label);    tagged = true; break;
        }
      }
      if (!tagged) {
        if (food.category == 'fruit' || food.category == 'snack' || food.category == 'beverage') {
          snacks.add(label);
        } else if (food.category == 'dairy') {
          breakfast.add(label);
        } else {
          lunch.add(label);
        }
      }
    }

    // Defaults for meals with no selections
    if (breakfast.isEmpty) breakfast.add('Milk 250ml + banana — ~200 kcal');
    if (lunch.isEmpty)     lunch.add('Dal + roti + sabzi — ~450 kcal');
    if (dinner.isEmpty)    dinner.add('Dal + roti + vegetable curry — ~400 kcal');
    if (snacks.isEmpty)    snacks.add('Peanuts 30g + banana — ~200 kcal');

    // ── Calorie & protein totals from selections ──────────────────
    double totalCal = 0, totalProtein = 0;
    for (final food in foods) {
      final qty = (quantities[food.id] ?? 1).toDouble();
      totalCal     += food.calories * qty;
      totalProtein += food.proteinG * qty;
    }

    // ── Goal-aware fields ─────────────────────────────────────────
    String goalNote      = '';
    String calSummary    = '';
    String hydration     = 'Drink 3–4 litres of water daily. Have a glass before each meal and after every workout.';

    if (profile != null) {
      final double bmr = profile.gender == 'female'
          ? 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * profile.age - 161
          : 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * profile.age + 5;
      final actMult = const {'sedentary': 1.2, 'light': 1.375, 'moderate': 1.55, 'active': 1.725}[profile.activityLevel] ?? 1.375;
      double targetCal = bmr * actMult;
      if (profile.goal == 'lose_fat')    targetCal -= 400;
      if (profile.goal == 'gain_muscle') targetCal += 400;
      final targetInt    = targetCal.round();
      final totalCalInt  = totalCal.round();
      final diff         = totalCalInt - targetInt;
      final proteinTarget = (profile.weightKg * (profile.hasGymAccess ? 2.0 : 1.6)).round();

      calSummary = '~$totalCalInt kcal selected  |  Target: $targetInt kcal';

      switch (profile.goal) {
        case 'lose_fat':
          if (diff > 200) {
            goalNote = '⚠️ Your selection is ~${diff} kcal above target. Consider halving snack portions or skipping one dinner item to stay in deficit.';
          } else if (diff < -200) {
            goalNote = '✅ Great — you\'re ${(-diff)} kcal under target. Make sure you\'re still hitting ${proteinTarget}g protein to preserve muscle.';
          } else {
            goalNote = '✅ Your selections are on track for fat loss. Keep dinner light and avoid late-night snacks.';
          }
          hydration = 'Drink 3–4 litres of water daily. A glass of water before meals helps reduce appetite and supports fat loss.';
          break;

        case 'gain_muscle':
          if (diff < -200) {
            goalNote = '⚡ You\'re ~${(-diff)} kcal below your muscle-gain target. Add an extra serving of rice/roti or a protein snack (eggs, paneer, whey) to close the gap.';
          } else if (totalProtein < proteinTarget * 0.8) {
            goalNote = '💪 Calorie target met! But protein (~${totalProtein.round()}g) is below your ${proteinTarget}g goal. Add eggs, paneer, dal, or whey to each meal.';
          } else {
            goalNote = '🏆 Your selections support muscle gain — ${totalProtein.round()}g protein from real food. Eat all meals consistently, especially post-workout.';
          }
          hydration = 'Drink 3–4 litres of water daily. Stay well-hydrated during and after workouts for optimal muscle recovery.';
          break;

        case 'maintain_fitness':
        default:
          goalNote = '⚖️ Your balanced selection (~$totalCalInt kcal) supports maintenance. Stick to consistent meal times and avoid skipping meals.';
          break;
      }
    }

    return {
      'breakfast':    breakfast,
      'lunch':        lunch,
      'dinner':       dinner,
      'snacks':       snacks,
      'hydration':    hydration,
      'goal_note':    goalNote,
      'cal_summary':  calSummary,
    };
  }

  static String _foodLabel(FoodItem food, int qty) {
    final cal = (food.calories * qty).round();
    if (qty == 1) {
      return '${food.emoji} ${food.name} (${food.servingLabel}) — $cal kcal';
    }
    return '${food.emoji} ${food.name} ×$qty — $cal kcal';
  }

  // ──────────────────────────────────────────────────────────────
  // Generate daily buddy message after check-in
  // ──────────────────────────────────────────────────────────────
  static Future<String> generateDailyMessage({
    required String buddyName,
    required String personality,
    required int streakDays,
    required String dietFollowed,
    required bool workoutDone,
    required String goal,
    required int bodyStage,
  }) async {
    final prompt = '''
You are "$buddyName", an anime fitness buddy with a "$personality" personality.
Send a SHORT motivational message (1-2 sentences max, very conversational) to the user.

Context:
- Streak: $streakDays days
- Today's diet: $dietFollowed
- Workout done: $workoutDone
- Goal: ${goal.replaceAll('_', ' ')}
- Buddy stage: $bodyStage/10

Personality guide:
- chill: relaxed, uses "bro", "ngl", casual slang
- hype: ALL CAPS sometimes, intense, uses "LET'S GO", "NO EXCUSES"
- zen: calm, poetic, "trust the process", mindful
- grind: direct, data-driven, "discipline beats motivation"
- soft: warm, encouraging, "proud of you", gentle

Return ONLY the message text, no JSON, no quotes.
''';

    final text = await _callGemini(prompt: prompt, temperature: 0.9, maxTokens: 100);
    return text?.trim().isNotEmpty == true
        ? text!.trim()
        : _fallbackMessage(personality, streakDays, dietFollowed, workoutDone);
  }

  // ──────────────────────────────────────────────────────────────
  // Chat — buddy replies to any user message
  // ──────────────────────────────────────────────────────────────
  static Future<String> chat(
    String userMessage,
    FitnessProfile profile,
    FitnessPlan? plan,
  ) async {
    final prompt = '''
You are "${profile.buddyName}", an anime fitness buddy with a "${profile.buddyPersonality}" personality.
The user's goal is: ${profile.goal.replaceAll('_', ' ')}.
Stats: ${profile.age}yr, ${profile.weightKg}kg, ${profile.heightCm}cm, gym access: ${profile.hasGymAccess}.
${plan != null ? 'Their daily target: ${plan.dailyCalories} kcal, ${plan.proteinG}g protein.' : ''}

Personality voice:
- chill: relaxed, "bro", "ngl", casual, short sentences
- hype: energetic, CAPS sometimes, "LET'S GO!", "NO EXCUSES"
- zen: calm, mindful, "trust the process", peaceful wisdom
- grind: direct, no-nonsense, data-driven, "discipline beats motivation"
- soft: warm, encouraging, "proud of you", gentle emojis

User says: "$userMessage"

Reply as ${profile.buddyName} in 1–3 short sentences.
Keep it conversational and relevant to their fitness journey.
If they ask something non-fitness, gently relate it back to health.
Return ONLY the reply text, no quotes, no JSON.
''';

    final text = await _callGemini(prompt: prompt, temperature: 0.9, maxTokens: 120);
    return text?.trim().isNotEmpty == true
        ? text!.trim()
        : _fallbackChatMessage(profile.buddyPersonality);
  }

  static String _fallbackChatMessage(String personality) {
    return "Seems like I'm having trouble connecting right now. Try again in a moment!";
  }

  // ──────────────────────────────────────────────────────────────
  // Fallbacks (no API key needed — demo mode)
  // ──────────────────────────────────────────────────────────────
  // Public so onboarding can call it directly as a safety fallback
  static Map<String, dynamic> fallbackPlan(FitnessProfile p) {
    // Mifflin-St Jeor BMR
    double bmr = p.gender == 'female'
        ? 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age - 161
        : 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age + 5;
    final actMult = {'sedentary': 1.2, 'light': 1.375, 'moderate': 1.55, 'active': 1.725}[p.activityLevel] ?? 1.375;
    double tdee = bmr * actMult;
    if (p.goal == 'lose_fat') tdee -= 400;
    if (p.goal == 'gain_muscle') tdee += 400;
    final cal = tdee.round();
    final proteinFactor = p.hasGymAccess ? 2.0 : 1.6;
    final protein = (p.weightKg * proteinFactor).round();
    final fat = (cal * 0.25 / 9).round();
    final carbs = ((cal - protein * 4 - fat * 9) / 4).round();

    final personality = p.stressLevel >= 4 ? 'chill' : p.activityLevel == 'active' ? 'grind' : p.goal == 'gain_muscle' ? 'hype' : 'zen';

    final gymWorkout = {
      'monday': {'focus': 'Chest & Triceps', 'is_rest': false, 'exercises': [{'name': 'Bench Press', 'sets': 4, 'reps': '8-10', 'rest': '90s'}, {'name': 'Incline Dumbbell Press', 'sets': 3, 'reps': '10-12', 'rest': '60s'}, {'name': 'Tricep Pushdown', 'sets': 3, 'reps': '12-15', 'rest': '60s'}]},
      'tuesday': {'focus': 'Back & Biceps', 'is_rest': false, 'exercises': [{'name': 'Barbell Row', 'sets': 4, 'reps': '8-10', 'rest': '90s'}, {'name': 'Lat Pulldown', 'sets': 3, 'reps': '10-12', 'rest': '60s'}, {'name': 'Bicep Curl', 'sets': 3, 'reps': '12-15', 'rest': '60s'}]},
      'wednesday': {'focus': 'Rest & Recovery', 'is_rest': true, 'exercises': []},
      'thursday': {'focus': 'Legs & Glutes', 'is_rest': false, 'exercises': [{'name': 'Squat', 'sets': 4, 'reps': '8-10', 'rest': '120s'}, {'name': 'Leg Press', 'sets': 3, 'reps': '10-12', 'rest': '90s'}, {'name': 'Leg Curl', 'sets': 3, 'reps': '12-15', 'rest': '60s'}]},
      'friday': {'focus': 'Shoulders & Arms', 'is_rest': false, 'exercises': [{'name': 'Overhead Press', 'sets': 4, 'reps': '8-10', 'rest': '90s'}, {'name': 'Lateral Raise', 'sets': 3, 'reps': '12-15', 'rest': '60s'}, {'name': 'Skull Crushers', 'sets': 3, 'reps': '10-12', 'rest': '60s'}]},
      'saturday': {'focus': 'Cardio & Core', 'is_rest': false, 'exercises': [{'name': 'Treadmill Run', 'sets': 1, 'reps': '20 min', 'rest': '-'}, {'name': 'Plank', 'sets': 3, 'reps': '45s', 'rest': '30s'}, {'name': 'Crunches', 'sets': 3, 'reps': '20', 'rest': '30s'}]},
      'sunday': {'focus': 'Full Rest', 'is_rest': true, 'exercises': []},
    };

    final homeWorkout = {
      'monday': {'focus': 'Full Body A', 'is_rest': false, 'exercises': [{'name': 'Push-ups', 'sets': 3, 'reps': '10-15', 'rest': '60s'}, {'name': 'Bodyweight Squats', 'sets': 3, 'reps': '15-20', 'rest': '60s'}, {'name': 'Plank', 'sets': 3, 'reps': '30-45s', 'rest': '45s'}]},
      'tuesday': {'focus': 'Cardio & Core', 'is_rest': false, 'exercises': [{'name': 'Jumping Jacks', 'sets': 3, 'reps': '30', 'rest': '30s'}, {'name': 'High Knees', 'sets': 3, 'reps': '30s', 'rest': '30s'}, {'name': 'Crunches', 'sets': 3, 'reps': '20', 'rest': '30s'}]},
      'wednesday': {'focus': 'Rest & Recovery', 'is_rest': true, 'exercises': []},
      'thursday': {'focus': 'Full Body B', 'is_rest': false, 'exercises': [{'name': 'Diamond Push-ups', 'sets': 3, 'reps': '8-12', 'rest': '60s'}, {'name': 'Reverse Lunges', 'sets': 3, 'reps': '12 each leg', 'rest': '60s'}, {'name': 'Superman Hold', 'sets': 3, 'reps': '30s', 'rest': '45s'}]},
      'friday': {'focus': 'Cardio & Stretch', 'is_rest': false, 'exercises': [{'name': 'Jogging / Stairs', 'sets': 1, 'reps': '20 min', 'rest': '-'}, {'name': 'Hip Flexor Stretch', 'sets': 2, 'reps': '30s each', 'rest': '-'}]},
      'saturday': {'focus': 'Full Body C', 'is_rest': false, 'exercises': [{'name': 'Wide Push-ups', 'sets': 3, 'reps': '10-15', 'rest': '60s'}, {'name': 'Jump Squats', 'sets': 3, 'reps': '12', 'rest': '60s'}, {'name': 'Mountain Climbers', 'sets': 3, 'reps': '30s', 'rest': '30s'}]},
      'sunday': {'focus': 'Full Rest', 'is_rest': true, 'exercises': []},
    };

    final gains = p.goal == 'lose_fat'
        ? {'week4': 'Expect 1-2 kg fat loss, clothes feeling looser', 'week8': 'Noticeable body composition change, 3-4 kg total loss possible', 'week12': 'Significant transformation — 5-6 kg fat loss with consistent effort'}
        : p.goal == 'gain_muscle'
            ? {'week4': 'Strength gains noticeable, scale may go up 0.5-1 kg', 'week8': 'Visible muscle fullness, 1-2 kg lean mass gained', 'week12': 'Clear physique change — 2-3 kg muscle with proper protein intake'}
            : {'week4': 'Improved energy levels and sleep quality', 'week8': 'Better stamina, visible toning', 'week12': 'Consistently fit — body composition improved'};

    return {
      'buddy_name': ['Ryuu', 'Kaito', 'Hana', 'Zen', 'Mika'][p.buddyAvatarType - 1],
      'buddy_personality': personality,
      'buddy_avatar_type': p.buddyAvatarType,
      'buddy_intro': _fallbackIntro(personality, p.goal),
      'daily_calories': cal,
      'protein_g': protein,
      'carbs_g': carbs,
      'fat_g': fat,
      'duration_weeks': 12,
      'workout_plan': p.hasGymAccess ? gymWorkout : homeWorkout,
      'diet_guide': <String, dynamic>{},
      'projected_gains': gains,
      'key_tips': [
        'Sleep 7-8 hours — it\'s when your body actually builds muscle',
        'Consistency > perfection. A partial day beats skipping.',
        'Protein at every meal — eggs, dal, milk, paneer are your friends',
        'Track your weight weekly, same time every morning',
      ],
      'supplements': _fallbackSupplements(p.goal, p.hasGymAccess),
    };
  }

  static List<Map<String, String>> _fallbackSupplements(String goal, bool hasGym) {
    final base = <Map<String, String>>[
      {'name': 'Whey Protein', 'dose': '25–30g', 'timing': 'Post-workout or between meals', 'why': 'Easiest way to hit daily protein target', 'priority': 'high'},
      {'name': 'Multivitamin', 'dose': '1 tablet', 'timing': 'With breakfast', 'why': 'Covers micronutrient gaps in hostel/mess diet', 'priority': 'medium'},
    ];
    if (goal == 'gain_muscle' && hasGym) {
      base.add({'name': 'Creatine Monohydrate', 'dose': '5g', 'timing': 'Daily (any time)', 'why': 'Proven to boost strength and muscle volume', 'priority': 'high'});
      base.add({'name': 'Omega-3 Fish Oil', 'dose': '1000mg', 'timing': 'With dinner', 'why': 'Reduces joint inflammation from heavy training', 'priority': 'medium'});
    } else if (goal == 'lose_fat') {
      base.add({'name': 'Green Tea Extract', 'dose': '400mg', 'timing': 'Before workout or morning', 'why': 'Mild thermogenic effect, helps fat oxidation', 'priority': 'optional'});
      base.add({'name': 'Omega-3 Fish Oil', 'dose': '1000mg', 'timing': 'With dinner', 'why': 'Supports fat metabolism and reduces inflammation', 'priority': 'medium'});
    } else {
      base.add({'name': 'Electrolyte Powder', 'dose': '1 sachet', 'timing': 'During/after workout', 'why': 'Prevents cramps and fatigue during cardio', 'priority': 'optional'});
      base.add({'name': 'Omega-3 Fish Oil', 'dose': '1000mg', 'timing': 'With dinner', 'why': 'Heart health, stamina, and recovery', 'priority': 'medium'});
    }
    return base;
  }

  static String _fallbackIntro(String personality, String goal) {
    switch (personality) {
      case 'hype':
        return 'YO! I\'ve been waiting for you! We\'re about to go FULL SEND on this ${goal.replaceAll('_', ' ')} journey. No half measures. Let\'s build something incredible together!';
      case 'zen':
        return 'Hey. I\'m here with you on this journey. Every great transformation begins with a single mindful step. Trust the process, and I\'ll guide you there.';
      case 'grind':
        return 'Alright. You\'ve made the right call. Discipline beats motivation every single time — and I\'m going to make sure you don\'t miss a day. Let\'s get to work.';
      case 'soft':
        return 'Hi there! I\'m so happy you\'re here. Don\'t worry about being perfect — we\'ll take this one day at a time, together. You\'ve got this!';
      default: // chill
        return 'Hey, no stress. We\'re gonna take this step by step, nice and easy. I\'ll keep things simple and you just show up. That\'s literally all you need to do.';
    }
  }

  static String _fallbackMessage(String personality, int streak, String diet, bool workout) {
    final great = diet == 'yes' && workout;
    final ok = diet != 'no' || workout;

    switch (personality) {
      case 'hype':
        return great
            ? 'THAT\'S WHAT I\'M TALKING ABOUT! $streak day streak. You\'re on FIRE! 🔥'
            : ok
                ? 'Not your best day but you still showed up. That counts. TOMORROW WE GO HARDER.'
                : 'Hey. I know. Get some rest and come back stronger. This isn\'t over.';
      case 'zen':
        return great
            ? 'Beautiful consistency. $streak days of showing up. Your body is quietly transforming.'
            : ok
                ? 'Progress is rarely linear. You showed up today — that\'s enough. Rest and return.'
                : 'Every dip is part of the journey. Tomorrow is a fresh start. Be kind to yourself.';
      case 'grind':
        return great
            ? 'Day $streak. Logged. Every rep, every meal — it compounds. Keep the data clean.'
            : ok
                ? 'Partial is not zero. Recalibrate, stay on track. Don\'t let this become a pattern.'
                : 'Missed day. Analyze why. Adjust. Don\'t let it slide to two.';
      case 'soft':
        return great
            ? 'You did SO well today! I\'m genuinely proud of you. Keep it going! 💚'
            : ok
                ? 'Hey, you still made an effort and that matters so much. Tomorrow fresh start!'
                : 'It\'s okay, really. Bad days happen. I believe in you. Let\'s try again tomorrow.';
      default: // chill
        return great
            ? 'Ngl that was a solid day bro. $streak streak going. Keep it rolling 🤙'
            : ok
                ? 'Not perfect but hey, you\'re still here. That\'s the move.'
                : 'All good. Rest up. We go again tomorrow, no pressure.';
    }
  }
}
