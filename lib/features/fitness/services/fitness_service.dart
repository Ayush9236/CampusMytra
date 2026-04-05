// ─────────────────────────────────────────────────────────────────────────────
// Supabase SQL — run this once in your Supabase SQL editor:
// ─────────────────────────────────────────────────────────────────────────────
// create table fitness_profiles (
//   user_id uuid primary key references auth.users(id) on delete cascade,
//   age integer not null,
//   height_cm numeric not null,
//   weight_kg numeric not null,
//   gender text not null,
//   sleep_hours numeric not null,
//   stress_level integer not null,
//   activity_level text not null,
//   has_gym_access boolean not null default false,
//   food_type text not null,
//   goal text not null,
//   buddy_name text not null,
//   buddy_avatar_type integer not null,
//   buddy_personality text not null,
//   buddy_intro text,
//   custom_workout jsonb not null default '{}',
//   created_at timestamptz default now()
// );
// -- Migration (run if table already exists):
// alter table fitness_profiles add column if not exists custom_workout jsonb not null default '{}';
// create table fitness_plans (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   daily_calories integer not null,
//   protein_g integer not null,
//   carbs_g integer not null,
//   fat_g integer not null,
//   duration_weeks integer not null default 12,
//   workout_plan jsonb not null default '{}',
//   diet_guide jsonb not null default '{}',
//   projected_gains jsonb not null default '{}',
//   key_tips jsonb not null default '[]',
//   created_at timestamptz default now()
// );
// create table fitness_logs (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   log_date date not null default current_date,
//   weight_kg numeric,
//   diet_followed text not null,
//   workout_done boolean not null default false,
//   mood integer not null,
//   notes text,
//   created_at timestamptz default now(),
//   unique(user_id, log_date)
// );
// create table buddy_state (
//   user_id uuid primary key references auth.users(id) on delete cascade,
//   level integer not null default 1,
//   streak_days integer not null default 0,
//   total_days_followed integer not null default 0,
//   body_stage integer not null default 1,
//   last_message text,
//   updated_at timestamptz default now()
// );
// alter table fitness_profiles enable row level security;
// alter table fitness_plans enable row level security;
// alter table fitness_logs enable row level security;
// alter table buddy_state enable row level security;
// create policy "own" on fitness_profiles for all using (auth.uid() = user_id);
// create policy "own" on fitness_plans for all using (auth.uid() = user_id);
// create policy "own" on fitness_logs for all using (auth.uid() = user_id);
// create policy "own" on buddy_state for all using (auth.uid() = user_id);
// ─────────────────────────────────────────────────────────────────────────────

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fitness_models.dart';

final _db = Supabase.instance.client;

class FitnessService {
  static String get _uid => _db.auth.currentUser!.id;

  // ── Profile ────────────────────────────────────────────────────────────────

  static Future<FitnessProfile?> getProfile() async {
    final res = await _db
        .from('fitness_profiles')
        .select()
        .eq('user_id', _uid)
        .maybeSingle();
    if (res == null) return null;
    return FitnessProfile.fromMap(res);
  }

  static Future<void> saveProfile(FitnessProfile p) async {
    await _db.from('fitness_profiles').upsert({
      'user_id': _uid,
      ...p.toMap(),
    });
  }

  // ── Plan ───────────────────────────────────────────────────────────────────

  static Future<FitnessPlan?> getPlan() async {
    final res = await _db
        .from('fitness_plans')
        .select()
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (res == null) return null;
    return FitnessPlan.fromMap(res);
  }

  static Future<void> savePlan(Map<String, dynamic> planJson) async {
    await _db.from('fitness_plans').insert({
      'user_id': _uid,
      'daily_calories': planJson['daily_calories'],
      'protein_g': planJson['protein_g'],
      'carbs_g': planJson['carbs_g'],
      'fat_g': planJson['fat_g'],
      'duration_weeks': planJson['duration_weeks'] ?? 12,
      'workout_plan': planJson['workout_plan'],
      'diet_guide': planJson['diet_guide'],
      'projected_gains': planJson['projected_gains'] ?? {},
      'key_tips': planJson['key_tips'] ?? [],
    });
  }

  // ── Logs ───────────────────────────────────────────────────────────────────

  static Future<bool> hasCheckedInToday() async {
    final today = _todayStr();
    final res = await _db
        .from('fitness_logs')
        .select('id')
        .eq('user_id', _uid)
        .eq('log_date', today)
        .maybeSingle();
    return res != null;
  }

  static Future<FitnessLog?> getTodayLog() async {
    final res = await _db
        .from('fitness_logs')
        .select()
        .eq('user_id', _uid)
        .eq('log_date', _todayStr())
        .maybeSingle();
    if (res == null) return null;
    return FitnessLog.fromMap(res);
  }

  static Future<void> submitLog(FitnessLog log) async {
    await _db.from('fitness_logs').upsert({
      'user_id': _uid,
      ...log.toMap(),
    });
  }

  static Future<List<FitnessLog>> getRecentLogs({int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final res = await _db
        .from('fitness_logs')
        .select()
        .eq('user_id', _uid)
        .gte('log_date', _dateStr(since))
        .order('log_date', ascending: false);
    return (res as List).map((m) => FitnessLog.fromMap(m)).toList();
  }

  // ── Buddy State ────────────────────────────────────────────────────────────

  static Future<BuddyState?> getBuddyState() async {
    final res = await _db
        .from('buddy_state')
        .select()
        .eq('user_id', _uid)
        .maybeSingle();
    if (res == null) return null;
    return BuddyState.fromMap(res);
  }

  static Future<BuddyState> createInitialBuddyState() async {
    final now = DateTime.now().toIso8601String();
    await _db.from('buddy_state').upsert({
      'user_id': _uid,
      'level': 1,
      'streak_days': 0,
      'total_days_followed': 0,
      'body_stage': 1,
      'last_message': null,
      'updated_at': now,
    });
    return BuddyState(
      userId: _uid,
      level: 1,
      streakDays: 0,
      totalDaysFollowed: 0,
      bodyStage: 1,
      updatedAt: DateTime.now(),
    );
  }

  static Future<BuddyState> updateBuddyAfterCheckin({
    required BuddyState current,
    required FitnessLog log,
    required String newMessage,
  }) async {
    final wasGood = log.dietFollowed != 'no' && log.workoutDone;
    final wasPartial = log.dietFollowed != 'no' || log.workoutDone;

    // Streak logic
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayStr = _dateStr(yesterday);
    final hadYesterday = await _db
        .from('fitness_logs')
        .select('id')
        .eq('user_id', _uid)
        .eq('log_date', yesterdayStr)
        .maybeSingle();

    final newStreak = wasGood
        ? (hadYesterday != null ? current.streakDays + 1 : 1)
        : 0;

    final newTotal = wasPartial ? current.totalDaysFollowed + 1 : current.totalDaysFollowed;

    // Body stage increases every 14 total good days
    final newBodyStage = ((newTotal / 14).floor() + 1).clamp(1, 10);

    // Level = display stage from body stage
    final newLevel = ((newBodyStage - 1) ~/ 2).clamp(0, 4) + 1;

    final now = DateTime.now();
    await _db.from('buddy_state').upsert({
      'user_id': _uid,
      'level': newLevel,
      'streak_days': newStreak,
      'total_days_followed': newTotal,
      'body_stage': newBodyStage,
      'last_message': newMessage,
      'updated_at': now.toIso8601String(),
    });

    return BuddyState(
      userId: _uid,
      level: newLevel,
      streakDays: newStreak,
      totalDaysFollowed: newTotal,
      bodyStage: newBodyStage,
      lastMessage: newMessage,
      updatedAt: now,
    );
  }

  // ── Weight update ─────────────────────────────────────────────────────────

  static Future<void> updateWeight(double weightKg) async {
    await _db.from('fitness_profiles').update({
      'weight_kg': weightKg,
    }).eq('user_id', _uid);
  }

  // ── Custom Workout ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getCustomWorkout() async {
    final res = await _db
        .from('fitness_profiles')
        .select('custom_workout')
        .eq('user_id', _uid)
        .maybeSingle();
    if (res == null) return {};
    return Map<String, dynamic>.from(res['custom_workout'] as Map? ?? {});
  }

  static Future<void> saveCustomWorkout(Map<String, dynamic> data) async {
    await _db.from('fitness_profiles').update({
      'custom_workout': data,
    }).eq('user_id', _uid);
  }

  // ── Delete all fitness data for the current user ──────────────────────────
  static Future<void> deleteAllData() async {
    await Future.wait([
      _db.from('fitness_logs').delete().eq('user_id', _uid),
      _db.from('fitness_plans').delete().eq('user_id', _uid),
      _db.from('buddy_state').delete().eq('user_id', _uid),
      _db.from('fitness_profiles').delete().eq('user_id', _uid),
    ]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _todayStr() => _dateStr(DateTime.now());

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
