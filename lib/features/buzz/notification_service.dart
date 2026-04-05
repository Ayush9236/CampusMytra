import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════
// 🔔 PUSH NOTIFICATION SERVICE
// Handles FCM init, token registration,
// foreground display, tap routing, and in-app inbox
// ══════════════════════════════════════════════

// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotif = FlutterLocalNotificationsPlugin();
  final _supabase = Supabase.instance.client;

  // Set from main.dart
  static GlobalKey<NavigatorState>? navigatorKey;

  // Called when notification is tapped; receives data map
  Function(Map<String, dynamic>)? onNotificationTap;

  // ── Android notification channel ──
  static const _channel = AndroidNotificationChannel(
    'campus_mytra',
    'CampusMytra',
    description: 'All CampusMytra notifications',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  // ── Initialize ──
  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    final settings = await _fcm.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    await _localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotif.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (details) => _handleTap(details.payload),
    );

    FirebaseMessaging.onMessage.listen(_handleForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((msg) => _handleTap(jsonEncode(msg.data)));

    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      Future.delayed(const Duration(milliseconds: 500), () => _handleTap(jsonEncode(initial.data)));
    }

    await _saveToken();
    _fcm.onTokenRefresh.listen(_updateToken);
  }

  // ── Show foreground notification ──
  void _handleForeground(RemoteMessage message) {
    final notif = message.notification;
    if (notif == null) return;
    _localNotif.show(
      message.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id, _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF818CF8),
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  // ── Handle notification tap ──
  void _handleTap(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      onNotificationTap?.call(data);
    } catch (_) {}
  }

  // ── Token management ──
  Future<void> _saveToken() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final token = await _fcm.getToken();
    if (token == null) return;
    await _supabase.from('profiles').update({'fcm_token': token}).eq('id', userId);
  }

  Future<void> _updateToken(String token) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.from('profiles').update({'fcm_token': token}).eq('id', userId);
  }

  Future<void> clearToken() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.from('profiles').update({'fcm_token': null}).eq('id', userId);
    await _fcm.deleteToken();
  }

  // ── Save notification to in-app inbox ──
  static Future<void> saveToInbox({
    required String userId,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': userId,
        'type':    type,
        'title':   title,
        'body':    body,
        'data':    data,
      });
    } catch (_) {}
  }

  // ── Internal sender — uses raw HTTP to bypass any SDK edge cases ──
  static Future<void> _send(Map<String, dynamic> body) async {
    try {
      const url = 'https://iukxnbifojobmerspvxn.supabase.co/functions/v1/send-notification';
      const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1a3huYmlmb2pvYm1lcnNwdnhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyMzAxOTgsImV4cCI6MjA4NjgwNjE5OH0.-go5he8W7NmSaJJYbkj8rHoYST0SBTuk4yZdIC7EIJg';
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $anonKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      debugPrint('[Notif] sent type=${body['type']} → ${res.statusCode} ${res.body}');
    } catch (e) {
      debugPrint('[Notif] ERROR type=${body['type']} → $e');
    }
  }

  // ════════════════════════════════════════════
  // BUZZ
  // ════════════════════════════════════════════

  static Future<void> sendLikeNotification({
    required String postId,
    required String postOwnerId,
    required String actorName,
    required String postPreview,
  }) => _send({
    'type': 'like',
    'postId': postId,
    'actorId': Supabase.instance.client.auth.currentUser?.id ?? '',
    'actorName': actorName,
    'postOwnerId': postOwnerId,
    'postPreview': postPreview,
  });

  static Future<void> sendCommentNotification({
    required String postId,
    required String postOwnerId,
    required String actorName,
    required String postPreview,
  }) => _send({
    'type': 'comment',
    'postId': postId,
    'actorId': Supabase.instance.client.auth.currentUser?.id ?? '',
    'actorName': actorName,
    'postOwnerId': postOwnerId,
    'postPreview': postPreview,
  });

  static Future<void> sendCollegeBuzzNotification({
    required String postId,
    required String collegeId,
    required String actorName,
    required String postPreview,
  }) => _send({
    'type': 'college_buzz',
    'postId': postId,
    'actorId': Supabase.instance.client.auth.currentUser?.id ?? '',
    'actorName': actorName,
    'collegeId': collegeId,
    'postPreview': postPreview,
  });

  // ════════════════════════════════════════════
  // SOCIAL
  // ════════════════════════════════════════════

  static Future<void> sendFriendRequestNotification({
    required String toUserId,
    required String fromName,
  }) => _send({
    'type': 'friend_request',
    'toUserId': toUserId,
    'actorId': Supabase.instance.client.auth.currentUser?.id ?? '',
    'actorName': fromName,
  });

  static Future<void> sendFriendAcceptNotification({
    required String toUserId,
    required String fromName,
  }) => _send({
    'type': 'friend_accept',
    'toUserId': toUserId,
    'actorId': Supabase.instance.client.auth.currentUser?.id ?? '',
    'actorName': fromName,
  });

  // ════════════════════════════════════════════
  // GAMES
  // ════════════════════════════════════════════

  static Future<void> sendGameInviteNotification({
    required String toUserId,
    required String fromName,
    required String roomId,
    required String gameType,
  }) => _send({
    'type': 'game_invite',
    'toUserId': toUserId,
    'actorId': Supabase.instance.client.auth.currentUser?.id ?? '',
    'actorName': fromName,
    'roomId': roomId,
    'gameType': gameType,
  });

  static Future<void> sendGameResultNotification({
    required String toUserId,
    required bool won,
    required String gameType,
    int coinsChange = 0,
  }) => _send({
    'type': 'game_result',
    'toUserId': toUserId,
    'won': won,
    'gameType': gameType,
    'coinsChange': coinsChange,
  });

  // ════════════════════════════════════════════
  // COINS & ADMIN
  // ════════════════════════════════════════════

  static Future<void> sendCoinsNotification({
    required String toUserId,
    required int amount,
    required String reason,
  }) => _send({
    'type': 'coins_received',
    'toUserId': toUserId,
    'amount': amount,
    'reason': reason,
  });

  static Future<void> sendAdminNotification({
    required String collegeId,
    required String title,
    required String message,
  }) => _send({
    'type': 'admin',
    'collegeId': collegeId,
    'title': title,
    'message': message,
  });

  static Future<void> sendChatNotification({
    required String toUserId,
    required String fromName,
    required String messagePreview,
  }) => _send({
    'type': 'chatter_message',
    'toUserId': toUserId,
    'actorId': Supabase.instance.client.auth.currentUser?.id ?? '',
    'actorName': fromName,
    'messagePreview': messagePreview,
  });
}
