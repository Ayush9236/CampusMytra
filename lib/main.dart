import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'features/auth/login_screen.dart';
import 'services/app_icon_service.dart';
import 'features/home/home_screen.dart';
import 'features/settings/theme_provider.dart';
import 'features/buzz/notification_service.dart';
import 'features/fitness/services/fitness_notification_service.dart';
import 'features/playground/services/sound_services.dart';
import 'features/notifications/notifications_screen.dart';
import 'firebase_options.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Init sound service (loads saved preference)
  await SoundService.init();

  try {
    await Supabase.initialize(
      url: 'https://iukxnbifojobmerspvxn.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1a3huYmlmb2pvYm1lcnNwdnhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyMzAxOTgsImV4cCI6MjA4NjgwNjE5OH0.-go5he8W7NmSaJJYbkj8rHoYST0SBTuk4yZdIC7EIJg',
    );
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }

  // Init fitness local notifications (Android only — not supported on web)
  if (!kIsWeb) await FitnessNotificationService.init();

  // Set navigator key for notification tap routing
  NotificationService.navigatorKey = navigatorKey;

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    // Init notifications when auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        // User logged in — init FCM and save token
        NotificationService.instance.init();
        NotificationService.instance.onNotificationTap = (data) {
          final type = data['type']?.toString() ?? '';
          final nav = navigatorKey.currentState;
          if (nav == null) return;
          // Route by type — for tab-based deep links use initialTab
          int? tab;
          switch (type) {
            case 'like':
            case 'comment':
            case 'college_buzz':
              tab = 2; break;
            case 'chatter_message':
              tab = 3; break;
            case 'game_result':
            case 'coins_received':
              tab = 5; break;
          }
          if (tab != null) {
            nav.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => HomeScreen(initialTab: tab!)),
              (r) => false);
          } else {
            nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          }
        };
      } else {
        // User logged out — clear FCM token
        NotificationService.instance.clearToken();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'CampusMytra',
      debugShowCheckedModeBanner: false,
      theme: ThemeProvider.lightTheme,
      darkTheme: ThemeProvider.darkTheme,
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      navigatorKey: navigatorKey,
      home: const SplashScreen(),
    );
  }
}

// ============================================================
// SPLASH SCREEN — checks connectivity + auth
// ============================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Starting...';

  @override
  void initState() {
    super.initState();
    _checkAndNavigate();
  }

  Future<void> _checkAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 500));

    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      bool connected = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          setState(() => _status = attempt == 1 ? 'Connecting...' : 'Retrying ($attempt/3)...');
          await Supabase.instance.client
              .from('profiles')
              .select('id')
              .limit(1)
              .timeout(const Duration(seconds: 12));
          connected = true;
          break;
        } catch (_) {
          if (attempt < 3) await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (!mounted) return;
      if (connected) {
        // Sync app icon from Supabase (owner may have changed it)
        try {
          final row = await Supabase.instance.client
              .from('app_settings')
              .select('value')
              .eq('key', 'active_icon')
              .maybeSingle();
          if (row != null) {
            final iconName = row['value'] as String?;
            if (iconName != null) {
              final variant = AppIconVariant.values.firstWhere(
                (v) => v.aliasName == iconName,
                orElse: () => AppIconVariant.defaultIcon,
              );
              await AppIconService.changeIcon(variant);
            }
          }
        } catch (e) {
          debugPrint('[AppIcon] Sync failed: $e');
        }
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDownScreen(onRetry: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SplashScreen()),
              );
            }),
          ),
        );
      }
    } else {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Center content — fills entire stack so mainAxisAlignment.center works ──
            Positioned.fill(
              child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'CampusMytra',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 48),
                CircularProgressIndicator(color: primary),
                const SizedBox(height: 16),
                Text(
                  _status,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            ),

            // ── Bottom branding — Instagram style ──
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/kaarma_techis_logo.png',
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Powered by KA-arma Techis',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SERVICE DOWN SCREEN
// ============================================================
class ServiceDownScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const ServiceDownScreen({Key? key, required this.onRetry}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;
    final textSecondary = Theme.of(context).textTheme.bodySmall?.color;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('😵', style: TextStyle(fontSize: 52)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Server Unreachable',
                style: TextStyle(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'CampusMytra servers are currently unavailable. This could be due to maintenance or a network issue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'status.supabase.com',
                style: TextStyle(
                  color: primary.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'We\'ll be back shortly! 🚀',
                style: TextStyle(color: textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}