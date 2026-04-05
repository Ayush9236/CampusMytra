import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/fitness_models.dart';

/// Schedules 4 daily local notifications from the fitness buddy.
/// Notification IDs 100–103 are reserved for this service.
class FitnessNotificationService {
  static const _channelId   = 'fitness_buddy';
  static const _channelName = 'Fitness Buddy';
  static const _channelDesc = 'Daily motivational messages from your fitness buddy';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    // Request POST_NOTIFICATIONS permission on Android 13+
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
    _initialized = true;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Cancel all previous fitness notifications, then schedule 4 new ones.
  static Future<void> scheduleAll(FitnessProfile profile, BuddyState? buddy) async {
    await init();
    await cancelAll();

    final name = profile.buddyName;
    final p    = profile.buddyPersonality;

    final slots = [
      _Slot(id: 100, hour: 8,  minute: 0,  title: '$name says...',         body: _morning(name, p)),
      _Slot(id: 101, hour: 13, minute: 0,  title: 'Lunch check from $name', body: _lunch(name, p)),
      _Slot(id: 102, hour: 18, minute: 0,  title: '$name: workout time!',   body: _workout(name, p)),
      _Slot(id: 103, hour: 21, minute: 0,  title: '$name is checking in',   body: _evening(name, p)),
    ];

    for (final slot in slots) {
      await _schedule(slot);
    }
  }

  static Future<void> cancelAll() async {
    await init();
    for (final id in [100, 101, 102, 103]) {
      await _plugin.cancel(id);
    }
  }

  // ── Scheduling internals ──────────────────────────────────────────────────

  static Future<void> _schedule(_Slot slot) async {
    final now  = tz.TZDateTime.now(tz.local);
    var   next = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, slot.hour, slot.minute,
    );
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      await _plugin.zonedSchedule(
        slot.id,
        slot.title,
        slot.body,
        next,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('[FitnessNotif] schedule error: $e');
    }
  }

  // ── Message bank ─────────────────────────────────────────────────────────

  static String _morning(String name, String p) {
    switch (p) {
      case 'hype':  return 'RISE AND GRIND! 🔥 Today we crush it — your body is ready. Let\'s GO! 💪';
      case 'zen':   return 'Morning. 🌅 Take a breath, set your intention. Today is a fresh start. You\'ve got this.';
      case 'grind': return 'No excuses today. You said you wanted it — so get up and earn it. Clock\'s ticking.';
      case 'soft':  return 'Good morning! 🌸 You woke up, that already counts. Let\'s make today a good one, okay?';
      default:      return 'Hey! Morning sunshine. ☀️ Small steps today still count. Let\'s have a chill good day!';
    }
  }

  static String _lunch(String name, String p) {
    switch (p) {
      case 'hype':  return 'FUEL UP! ⚡ Your muscles need food to grow. Don\'t skip lunch — eat big, lift bigger!';
      case 'zen':   return 'Lunchtime 🍱. Eat mindfully, chew slowly. What you put in shows up in your workouts.';
      case 'grind': return 'Meal time. Hit your protein. No junk. You know what\'s on your plan — stick to it.';
      case 'soft':  return 'Hey, have you eaten yet? 🥗 Please take care of yourself at lunch. You deserve nourishment!';
      default:      return 'Lunchtime! 🍜 Remember your diet plan. You\'re doing great — keep it balanced and yummy!';
    }
  }

  static String _workout(String name, String p) {
    switch (p) {
      case 'hype':  return 'IT\'S GO TIME! 🏋️ Every rep, every drop of sweat — that\'s your future self being built. MOVE!';
      case 'zen':   return 'Time to move 🧘. Your workout is self-care. Be present. Breathe. Each rep is a gift to yourself.';
      case 'grind': return 'Workout window is open. No motivation needed — just discipline. Get it done, no skipping.';
      case 'soft':  return 'Hey friend 💕 even a short workout counts! Walk, stretch, do what you can. I\'m proud of you!';
      default:      return 'Workout time! 🎵 Put on your fav music and just start. You always feel better after. Let\'s go!';
    }
  }

  static String _evening(String name, String p) {
    switch (p) {
      case 'hype':  return 'Evening check-in! 🌙 Did you CRUSH it today?! Log your check-in — let\'s see that STREAK! 🔥';
      case 'zen':   return 'End of day reflection 🌙. Take a moment to log your check-in. Every day you show up matters.';
      case 'grind': return 'Day\'s not done till you log it. Check in, protect your streak, and rest well. Same time tomorrow.';
      case 'soft':  return 'Hey, how was your day? 🌙 Don\'t forget your check-in! Then rest up — you deserve it 💤';
      default:      return 'Evening! 🌙 Check-in time! Even if today wasn\'t perfect, logging it keeps your streak alive. You got this!';
    }
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

class _Slot {
  final int    id, hour, minute;
  final String title, body;
  const _Slot({
    required this.id, required this.hour, required this.minute,
    required this.title, required this.body,
  });
}
