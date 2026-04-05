import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../playground/playground_screen.dart';
import '../playground/screens/uno_lobby_screen.dart';
import '../playground/screens/dsa_lobby_screen.dart';
import '../buzz/buzz_screen.dart';
import '../chatter/chatter_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/theme_provider.dart';
import '../search/search_screen.dart';
import '../notifications/notifications_screen.dart';
import '../fitness/fitness_buddy_screen.dart';
import '../fitness/fitness_theme.dart';
import '../fitness/services/fitness_service.dart';
import '../fitness/models/fitness_models.dart';
import '../fitness/widgets/buddy_character.dart' show BuddyCharacter;

final supabase = Supabase.instance.client;

extension _Ctx on BuildContext {
  bool get isDark => AppColors.isDark(this);
  Color get bg => AppColors.background(this);
  Color get surface => AppColors.surface(this);
  Color get surfaceVar => AppColors.surfaceVariant(this);
  Color get textPrimary => AppColors.text(this);
  Color get textSec => AppColors.textSecondary(this);
  Color get border => AppColors.border(this);
}

// ══════════════════════════════════════════════════════════════════════════════
// TIME THEME
// ══════════════════════════════════════════════════════════════════════════════

class _TimeTheme {
  final Color canvas;
  final List<Color> orbs;
  final Color accent;
  final Color cardEdge;
  final List<Color> heroGrad;
  final String Function(String) greet;

  const _TimeTheme({
    required this.canvas, required this.orbs, required this.accent,
    required this.cardEdge, required this.heroGrad, required this.greet,
  });

  static _TimeTheme get now {
    final h = DateTime.now().hour;
    if (h >= 4  && h < 7)  return _dawn;
    if (h >= 7  && h < 12) return _morning;
    if (h >= 12 && h < 16) return _afternoon;
    if (h >= 16 && h < 20) return _evening;
    return _night;
  }

  static final _dawn = _TimeTheme(
    canvas: const Color(0xFF0A0012),
    orbs: [const Color(0xFF8B2FC9), const Color(0xFFD63AF9),
           const Color(0xFFFF4D8B), const Color(0xFF3D0066)],
    accent: const Color(0xFFD63AF9),
    cardEdge: const Color(0xFFD63AF9),
    heroGrad: [const Color(0xFF8B2FC9), const Color(0xFFFF4D8B)],
    greet: (n) => 'Rise & shine,\n$n ✨',
  );

  static final _morning = _TimeTheme(
    canvas: const Color(0xFF0D0800),
    orbs: [const Color(0xFFFF6B00), const Color(0xFFFFB800),
           const Color(0xFFFF375F), const Color(0xFF7B2400)],
    accent: const Color(0xFFFFB800),
    cardEdge: const Color(0xFFFFB800),
    heroGrad: [const Color(0xFFFF6B00), const Color(0xFFFFD166)],
    greet: (n) => 'Good morning,\n$n ☀️',
  );

  static final _afternoon = _TimeTheme(
    canvas: const Color(0xFF00050D),
    orbs: [const Color(0xFF0066FF), const Color(0xFF00C2FF),
           const Color(0xFF0033AA), const Color(0xFF00E5CC)],
    accent: const Color(0xFF00C2FF),
    cardEdge: const Color(0xFF00C2FF),
    heroGrad: [const Color(0xFF0033AA), const Color(0xFF00C2FF)],
    greet: (n) => 'Good afternoon,\n$n 🌊',
  );

  static final _evening = _TimeTheme(
    canvas: const Color(0xFF080010),
    orbs: [const Color(0xFFE63946), const Color(0xFF6C2BD9),
           const Color(0xFFFF8500), const Color(0xFF1A0040)],
    accent: const Color(0xFFE63946),
    cardEdge: const Color(0xFFE63946),
    heroGrad: [const Color(0xFF6C2BD9), const Color(0xFFE63946)],
    greet: (n) => 'Good evening,\n$n 🌆',
  );

  static final _night = _TimeTheme(
    canvas: const Color(0xFF00000A),
    orbs: [const Color(0xFF2D00F7), const Color(0xFF00B4D8),
           const Color(0xFF7B2FBE), const Color(0xFF000066)],
    accent: const Color(0xFF818CF8),
    cardEdge: const Color(0xFF818CF8),
    heroGrad: [const Color(0xFF2D00F7), const Color(0xFF7B2FBE)],
    greet: (n) => 'Good night,\n$n 🌙',
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN — logic 100% identical
// ══════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  final int initialTab;
  const HomeScreen({Key? key, this.initialTab = 0}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _pulseController;
  List<Widget> _screens = [];
  int _unreadCount = 0;
  RealtimeChannel? _unreadChannel;

  void _onTabTapped(int index) {
    HapticFeedback.lightImpact();
    if (index == 3) {
      setState(() { _currentIndex = index; _unreadCount = 0; });
    } else {
      setState(() => _currentIndex = index);
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await supabase.from('messages').select('id')
          .neq('sender_id', userId).isFilter('read_at', null).isFilter('deleted_at', null);
      if (mounted) setState(() => _unreadCount = (data as List).length);
    } catch (_) {}
  }

  void _subscribeToUnread() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    _unreadChannel?.unsubscribe();
    _unreadChannel = supabase.channel('unread_messages_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert, schema: 'public', table: 'messages',
          callback: (payload) {
            final record = payload.newRecord;
            if (record['sender_id'] != userId && record['read_at'] == null &&
                record['deleted_at'] == null && _currentIndex != 3 && mounted) {
              setState(() => _unreadCount++);
            }
          })
        .onPostgresChanges(
          event: PostgresChangeEvent.update, schema: 'public', table: 'messages',
          callback: (payload) {
            if (payload.newRecord['read_at'] != null) _loadUnreadCount();
          })
        .subscribe();
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, 5);
    _screens = [
      _HomeTab(onNavigate: _onTabTapped),
      const PlaygroundScreen(),
      const CampusBuzzScreen(),
      const ChatterScreen(),
      const FitnessBuddyScreen(),
      const ProfileScreen(),
    ];
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _loadUnreadCount();
    _subscribeToUnread();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _unreadChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _NeonBottomNav(
          currentIndex: _currentIndex, onTap: _onTabTapped, unreadCount: _unreadCount),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HOME TAB
// ══════════════════════════════════════════════════════════════════════════════
class _HomeTab extends StatefulWidget {
  final Function(int) onNavigate;
  const _HomeTab({required this.onNavigate});
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String _userName = '';
  int _coins = 0;
  int _unreadNotifs = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _loaded = false;
  RealtimeChannel? _coinChannel;
  RealtimeChannel? _notifChannel;

  final _theme = _TimeTheme.now;
  final _updater = ShorebirdUpdater();
  bool _updateAvailable = false;
  bool _isDownloading = false;
  static const _kDismissedPatchKey = 'update_dismissed_patch';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadUser();
    _loadUnreadNotifs();
    _subscribeNotifs();
    _checkForUpdate();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do NOT re-check for updates on resume — only check once on cold start.
    // Re-checking on every resume caused the banner to loop.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    _coinChannel?.unsubscribe();
    _notifChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadUnreadNotifs() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .eq('is_read', false);
      if (mounted) setState(() => _unreadNotifs = (rows as List).length);
    } catch (_) {}
  }

  void _subscribeNotifs() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _notifChannel = supabase.channel('notifs_bell_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            if (payload.newRecord['user_id'] == uid && mounted) {
              setState(() => _unreadNotifs++);
            }
          })
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _loadUnreadNotifs())
        .subscribe();
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    ).then((_) => _loadUnreadNotifs());
  }

  Future<void> _loadUser() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await supabase.from('profiles').select('name, coins').eq('id', userId).single();
      if (mounted) {
        setState(() {
          _userName = data['name']?.toString().split(' ')[0] ?? 'Homie';
          _coins = data['coins'] ?? 0;
          _loaded = true;
        });
        _animController.forward();
      }
      _coinChannel?.unsubscribe();
      _coinChannel = supabase.channel('home_coins_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update, schema: 'public', table: 'profiles',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: userId),
            callback: (payload) {
              final c = payload.newRecord['coins'];
              if (c != null && mounted) setState(() => _coins = c as int);
            })
          .subscribe();
    } catch (_) {
      if (mounted) { setState(() { _userName = 'Homie'; _loaded = true; }); _animController.forward(); }
    }
  }


  Future<void> _checkForUpdate() async {
    if (!_updater.isAvailable) return;
    try {
      final status = await _updater.checkForUpdate();
      debugPrint('[Shorebird] update status: $status');

      if (status != UpdateStatus.outdated) return;

      // Check if user already dismissed this exact patch number
      final nextPatch = await _updater.readNextPatch();
      if (nextPatch != null) {
        final prefs = await SharedPreferences.getInstance();
        final dismissed = prefs.getInt(_kDismissedPatchKey) ?? -1;
        if (dismissed == nextPatch.number) return;
      }

      if (mounted) setState(() => _updateAvailable = true);
    } catch (e) {
      debugPrint('[Shorebird] checkForUpdate error: $e');
    }
  }

  Future<void> _downloadUpdate() async {
    setState(() => _isDownloading = true);
    try {
      await _updater.update();
      debugPrint('[Shorebird] update downloaded');
    } catch (e) {
      debugPrint('[Shorebird] update() result: $e');
    }
    if (!mounted) return;

    // Save the patch number that was just downloaded — never show banner for it again
    try {
      final nextPatch = await _updater.readNextPatch();
      if (nextPatch != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kDismissedPatchKey, nextPatch.number);
      }
    } catch (_) {}

    setState(() { _isDownloading = false; _updateAvailable = false; });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Update Ready! 🎉', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Text('Restart the app to apply the latest update.',
          style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Restart Now')),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 4  && hour < 12) return 'Good morning ☀️';
    if (hour >= 12 && hour < 17) return 'Good afternoon 🌤️';
    if (hour >= 17 && hour < 21) return 'Good evening 🌆';
    return 'Good night 🌙';
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    // Direct subscription to ThemeProvider ensures rebuild on every theme toggle
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Stack(children: [
      Positioned.fill(child: _MeshBackground(theme: t, isDark: isDark)),
      SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // TOP BAR
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(
                      _userName.isEmpty ? '' : t.greet(_userName),
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontSize: 28,
                        fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.8),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      // Notification bell with unread badge
                      _ThinCard(theme: t, padding: EdgeInsets.zero,
                        child: SizedBox(width: 42, height: 42,
                          child: GestureDetector(
                            onTap: _openNotifications,
                            child: Stack(alignment: Alignment.center, children: [
                              Icon(Icons.notifications_outlined, color: isDark ? Colors.white : const Color(0xFF1A1A2E), size: 20),
                              if (_unreadNotifs > 0)
                                Positioned(
                                  top: 8, right: 8,
                                  child: Container(
                                    width: 8, height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF375F),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ]),
                          ))),
                      const SizedBox(width: 8),
                      // Search
                      _ThinCard(theme: t, padding: EdgeInsets.zero,
                        child: SizedBox(width: 42, height: 42,
                          child: GestureDetector(
                            onTap: () => openSearchScreen(context),
                            child: Icon(Icons.search_rounded, color: isDark ? Colors.white : const Color(0xFF1A1A2E), size: 19)))),
                    ]),
                    const SizedBox(height: 10),
                    _ThinCard(theme: t, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🪙', style: TextStyle(fontSize: 15)),
                        const SizedBox(width: 6),
                        Text('$_coins', style: TextStyle(color: t.accent, fontWeight: FontWeight.w800, fontSize: 14)),
                      ])),
                  ]),
                ]),
              ),

              if (_updateAvailable)
                GestureDetector(
                  onTap: _isDownloading ? null : _downloadUpdate,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))]),
                    child: Row(children: [
                      const Text('🚀', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Update Available!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        const Text('Tap to download the latest version', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ])),
                      _isDownloading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                    ]))),

              const SizedBox(height: 28),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _HeroBanner(theme: t)),
              const SizedBox(height: 32),

              _Label(text: '🎮 Games', sub: 'Play & win coins', theme: t),
              const SizedBox(height: 14),
              SizedBox(
                height: 178,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _GameCard(title: 'UNO', subtitle: 'Multiplayer • Up to 7', emoji: '🃏',
                      gradient: const [Color(0xFFFF375F), Color(0xFFFF6B35)],
                      glowColor: const Color(0xFFFF375F), badge: 'HOT',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UnoLobbyScreen()))),
                    const SizedBox(width: 12),
                    _GameCard(title: 'DSA Combat', subtitle: '1v1 Code Battle', emoji: '⚔️',
                      gradient: const [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
                      glowColor: const Color(0xFF6C63FF), badge: 'NEW',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DsaLobbyScreen()))),
                    const SizedBox(width: 12),
                    _GameCard(title: 'Chess', subtitle: 'Strategy Game', emoji: '♟️',
                      gradient: const [Color(0xFF2A2D4A), Color(0xFF1A1C35)],
                      glowColor: const Color(0xFF5C6BC0), badge: 'SOON',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: const Text('♟️ Chess coming soon!'),
                          backgroundColor: const Color(0xFF1A1C35),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.all(16)))),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              _Label(text: '🏫 Campus', sub: "What's happening", theme: t),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Expanded(child: _FeatureTile(theme: t, color: const Color(0xFF00B8A3),
                    title: 'Campus Buzz', subtitle: 'Anonymous posts', emoji: '📢',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CampusBuzzScreen())))),
                  const SizedBox(width: 12),
                  Expanded(child: _FeatureTile(theme: t, color: const Color(0xFF4D79FF),
                    title: 'Chatter', subtitle: 'Chat with batch', emoji: '💬',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatterScreen())))),
                ]),
              ),
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _RadarTeaser(theme: t)),
              const SizedBox(height: 32),
              _Label(text: '💪 Fitness Buddy', sub: 'Your daily journey', theme: t),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _FitnessBuddyCard(theme: t, onNavigate: widget.onNavigate),
              ),
              const SizedBox(height: 32),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _DailyChallenge(theme: t)),
              const SizedBox(height: 32),

              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ANIMATED MESH BACKGROUND
// 4 large soft orbs drift on independent Lissajous paths and blend via
// BlendMode.screen — producing a living, never-repeating fluid light mesh.
// ══════════════════════════════════════════════════════════════════════════════
class _MeshBackground extends StatefulWidget {
  final _TimeTheme theme;
  final bool isDark;
  const _MeshBackground({required this.theme, required this.isDark});
  @override
  State<_MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<_MeshBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _MeshPainter(widget.theme, _ctrl.value, widget.isDark),
        size: Size.infinite));
  }
}

class _MeshPainter extends CustomPainter {
  final _TimeTheme t;
  final double tick;
  final bool isDark;
  const _MeshPainter(this.t, this.tick, this.isDark);

  Offset _orbPos(Size s, int i) {
    final phase = i * math.pi * 0.618;
    final xFreqs = [1.0, 1.3, 0.7, 1.7];
    final yFreqs = [1.3, 0.9, 1.6, 1.1];
    final xAmps  = [0.38, 0.30, 0.42, 0.28];
    final yAmps  = [0.30, 0.38, 0.24, 0.36];
    final xBases = [0.35, 0.65, 0.50, 0.20];
    final yBases = [0.30, 0.55, 0.70, 0.50];
    final angle  = tick * math.pi * 2 + phase;
    return Offset(
      s.width  * (xBases[i] + xAmps[i] * math.sin(angle * xFreqs[i])),
      s.height * (yBases[i] + yAmps[i] * math.cos(angle * yFreqs[i])));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final baseRadius = size.width * 0.72;
    final radMults   = [1.0, 0.85, 0.9, 0.75];
    final freqs      = [1.1, 0.9, 1.3, 0.7];

    if (!isDark) {
      // Light mode: soft white canvas with subtle pastel orbs
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFFF5F6FF));

      for (int i = 0; i < t.orbs.length; i++) {
        final center  = _orbPos(size, i);
        final radius  = baseRadius * radMults[i];
        final breathe = 0.07 + 0.03 * math.sin(tick * math.pi * 2 * freqs[i] + i);
        canvas.drawCircle(center, radius,
          Paint()
            ..shader = RadialGradient(
              colors: [t.orbs[i].withOpacity(breathe), t.orbs[i].withOpacity(0.0)],
            ).createShader(Rect.fromCircle(center: center, radius: radius)));
      }
      return;
    }

    // Dark mode: solid dark canvas with glowing orbs
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = t.canvas);

    for (int i = 0; i < t.orbs.length; i++) {
      final center  = _orbPos(size, i);
      final radius  = baseRadius * radMults[i];
      final breathe = 0.55 + 0.12 * math.sin(tick * math.pi * 2 * freqs[i] + i);
      canvas.drawCircle(center, radius,
        Paint()
          ..shader = RadialGradient(
            colors: [t.orbs[i].withOpacity(breathe), t.orbs[i].withOpacity(0.0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..blendMode = BlendMode.screen);
    }

    // Vignette — keeps edges dark
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withOpacity(0.60)],
        radius: 0.82,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.tick != tick || old.isDark != isDark;
}

// ══════════════════════════════════════════════════════════════════════════════
// _ThinCard
// ══════════════════════════════════════════════════════════════════════════════
class _ThinCard extends StatelessWidget {
  final _TimeTheme theme;
  final Widget child;
  final EdgeInsets padding;
  final BorderRadius? radius;
  final Color? borderOverride;

  const _ThinCard({
    required this.theme, required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius, this.borderOverride});

  @override
  Widget build(BuildContext context) {
    final br = radius ?? BorderRadius.circular(16);
    final isDark = context.isDark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        borderRadius: br,
        border: Border.all(
          color: isDark
              ? (borderOverride ?? theme.cardEdge).withOpacity(0.28)
              : (borderOverride ?? theme.cardEdge).withOpacity(0.35),
          width: 1.0),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))
        ]),
      child: child);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HERO BANNER
// ══════════════════════════════════════════════════════════════════════════════
class _HeroBanner extends StatelessWidget {
  final _TimeTheme theme;
  const _HeroBanner({required this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: t.heroGrad, begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: t.heroGrad.last.withOpacity(0.5), width: 1.0),
        boxShadow: [BoxShadow(color: t.heroGrad.first.withOpacity(0.45), blurRadius: 28, offset: const Offset(0, 10))]),
      child: Stack(children: [
        Positioned(top: 0, left: 0, right: 0,
          child: Container(height: 1,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              gradient: LinearGradient(colors: [
                Colors.white.withOpacity(0.0),
                Colors.white.withOpacity(0.35),
                Colors.white.withOpacity(0.0)])))),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(6)),
                child: const Text('⚡ LIVE NOW', style: TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
              const SizedBox(height: 12),
              const Text('Challenge your\nbatchmates!', style: TextStyle(
                color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              Text('DSA Combat • Win 50 coins',
                style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 12)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DsaLobbyScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Text('Play Now →', style: TextStyle(
                    color: t.heroGrad.first, fontWeight: FontWeight.w800, fontSize: 13)))),
            ])),
            const Text('⚔️', style: TextStyle(fontSize: 68,
              shadows: [Shadow(color: Colors.black26, blurRadius: 12)])),
          ])),
      ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GAME CARD
// ══════════════════════════════════════════════════════════════════════════════
class _GameCard extends StatelessWidget {
  final String title, subtitle, emoji, badge;
  final List<Color> gradient;
  final Color glowColor;
  final VoidCallback onTap;

  const _GameCard({required this.title, required this.subtitle, required this.emoji,
    required this.gradient, required this.glowColor, required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.mediumImpact(); onTap(); },
      child: Container(
        width: 148,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
          boxShadow: [BoxShadow(color: glowColor.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8))]),
        child: Stack(children: [
          Positioned(top: 0, left: 12, right: 12,
            child: Container(height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.white.withOpacity(0), Colors.white.withOpacity(0.28), Colors.white.withOpacity(0)])))),
          Positioned(right: -14, bottom: -14,
            child: Text(emoji, style: TextStyle(fontSize: 82, color: Colors.white.withOpacity(0.1)))),
          Padding(padding: const EdgeInsets.all(15),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
                child: Text(badge, style: const TextStyle(
                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
              const Spacer(),
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 10)),
            ])),
        ])));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FEATURE TILE
// ══════════════════════════════════════════════════════════════════════════════
class _FeatureTile extends StatelessWidget {
  final _TimeTheme theme;
  final Color color;
  final String title, subtitle, emoji;
  final VoidCallback onTap;

  const _FeatureTile({required this.theme, required this.color, required this.title,
    required this.subtitle, required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: _ThinCard(theme: theme, borderOverride: color, padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.35), width: 1)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20)))),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ])));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RADAR TEASER
// ══════════════════════════════════════════════════════════════════════════════
class _RadarTeaser extends StatelessWidget {
  final _TimeTheme theme;
  const _RadarTeaser({required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _RadarScreen())),
      child: _ThinCard(
        theme: theme, borderOverride: const Color(0xFF00B8A3), padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF00B8A3).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00B8A3).withValues(alpha: 0.35), width: 1)),
            child: const Center(child: Text('📡', style: TextStyle(fontSize: 22)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Campus Radar', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1), width: 1)),
                child: Text('SOON', style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black45, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
            ]),
            const SizedBox(height: 3),
            Text('See where your friends are on campus',
              style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.white24 : Colors.black26, size: 14),
        ])),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RADAR SCREEN — coming soon placeholder
// ══════════════════════════════════════════════════════════════════════════════
class _RadarScreen extends StatefulWidget {
  const _RadarScreen();
  @override
  State<_RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<_RadarScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020D0D),
      body: Stack(children: [

        // ── Map grid background ──
        Positioned.fill(child: CustomPaint(painter: _MapGridPainter())),

        // ── Animated radar sweep ──
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, child) => CustomPaint(
              painter: _RadarSweepPainter(_pulseCtrl.value)),
          ),
        ),

        // ── Fake location dots ──
        const Positioned(top: 180, left: 80,  child: _LocationDot(color: Color(0xFF00B8A3))),
        const Positioned(top: 260, right: 100, child: _LocationDot(color: Color(0xFF818CF8))),
        const Positioned(top: 340, left: 140, child: _LocationDot(color: Color(0xFFFF375F))),
        const Positioned(top: 420, right: 60,  child: _LocationDot(color: Color(0xFF00B8A3))),
        const Positioned(top: 300, left: 200,  child: _LocationDot(color: Color(0xFFFFB800))),

        // ── Overlay gradient from bottom ──
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF020D0D).withValues(alpha: 0.6),
                  const Color(0xFF020D0D).withValues(alpha: 0.95),
                ],
                stops: const [0.3, 0.65, 1.0],
              ),
            ),
          ),
        ),

        // ── Lock + Coming Soon card ──
        Positioned.fill(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pulsing lock ring
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, child) => Container(
                  width: 100 + _pulseCtrl.value * 8,
                  height: 100 + _pulseCtrl.value * 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00B8A3).withValues(
                          alpha: 0.15 + _pulseCtrl.value * 0.25),
                      width: 1.5),
                  ),
                  child: child,
                ),
                child: Container(
                  width: 84, height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00B8A3).withValues(alpha: 0.12),
                    border: Border.all(
                        color: const Color(0xFF00B8A3).withValues(alpha: 0.5),
                        width: 2),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      color: Color(0xFF00B8A3), size: 36),
                ),
              ),
              const SizedBox(height: 28),
              const Text('Campus Radar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26, fontWeight: FontWeight.w900,
                  letterSpacing: -0.5)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B8A3).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF00B8A3).withValues(alpha: 0.4))),
                child: const Text('Coming Soon',
                  style: TextStyle(
                    color: Color(0xFF00B8A3),
                    fontSize: 13, fontWeight: FontWeight.w700,
                    letterSpacing: 1.0)),
              ),
              const SizedBox(height: 14),
              const Text('See where your friends are\non campus in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38, fontSize: 14, height: 1.6)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _LocationDot extends StatelessWidget {
  final Color color;
  const _LocationDot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 8)]),
  );
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00B8A3).withValues(alpha: 0.06)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Concentric circles from center
    final center = Offset(size.width / 2, size.height * 0.38);
    final ringPaint = Paint()
      ..color = const Color(0xFF00B8A3).withValues(alpha: 0.08)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double r = 60; r < size.width; r += 80) {
      canvas.drawCircle(center, r, ringPaint);
    }
  }

  @override
  bool shouldRepaint(_MapGridPainter _) => false;
}

class _RadarSweepPainter extends CustomPainter {
  final double t;
  const _RadarSweepPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.38);
    final angle = t * 2 * math.pi;
    const radius = 160.0;

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle - 1.2,
        endAngle: angle,
        colors: [
          Colors.transparent,
          const Color(0xFF00B8A3).withValues(alpha: 0.18),
        ],
        transform: GradientRotation(angle - 1.2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepPaint);

    // Sweep line
    final linePaint = Paint()
      ..color = const Color(0xFF00B8A3).withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(center,
      Offset(center.dx + radius * math.cos(angle),
             center.dy + radius * math.sin(angle)),
      linePaint);
  }

  @override
  bool shouldRepaint(_RadarSweepPainter old) => old.t != t;
}

// ══════════════════════════════════════════════════════════════════════════════
// LABEL
// ══════════════════════════════════════════════════════════════════════════════
class _Label extends StatelessWidget {
  final String text, sub;
  final _TimeTheme theme;
  const _Label({required this.text, required this.sub, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(text, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E), fontSize: 17, fontWeight: FontWeight.w800)),
        Text(sub, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12)),
      ]));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DAILY CHALLENGE — logic identical
// ══════════════════════════════════════════════════════════════════════════════
class _DailyChallenge extends StatefulWidget {
  final _TimeTheme theme;
  const _DailyChallenge({required this.theme});
  @override
  State<_DailyChallenge> createState() => _DailyChallengeState();
}

class _DailyChallengeState extends State<_DailyChallenge> {
  int _dsaWinsToday = 0, _unoWinsToday = 0;
  bool _loading = true;
  static const int _dsaTarget = 3, _unoTarget = 2;

  @override
  void initState() { super.initState(); _loadProgress(); }

  Future<void> _loadProgress() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();
      final dsaData = await supabase.from('match_history').select('id')
          .eq('winner_id', userId).eq('game_type', 'dsa_win').gte('created_at', startOfDay);
      final unoData = await supabase.from('match_history').select('id')
          .eq('winner_id', userId).or('game_type.eq.uno,game_type.eq.uno_win').gte('created_at', startOfDay);
      if (mounted) setState(() {
        _dsaWinsToday = (dsaData as List).length;
        _unoWinsToday = (unoData as List).length;
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final dsaDone = _dsaWinsToday.clamp(0, _dsaTarget);
    final unoDone = _unoWinsToday.clamp(0, _unoTarget);
    final totalDone = dsaDone + unoDone;
    final totalTarget = _dsaTarget + _unoTarget;
    final progress = _loading ? 0.0 : totalDone / totalTarget;
    final allDone = totalDone >= totalTarget;
    final accent = allDone ? const Color(0xFF4ADE80) : const Color(0xFFFFB800);

    final isDark = context.isDark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white38 : Colors.black38;
    return _ThinCard(theme: t, borderOverride: accent, padding: const EdgeInsets.all(20),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(allDone ? '✅' : '🔥', style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 7),
            Text(allDone ? 'Challenge Complete!' : 'Daily Challenge',
              style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
          const SizedBox(height: 7),
          Text('Win 3 DSA + 2 UNO today',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 5),
          Row(children: [
            _Mini(label: '⚔️ DSA', done: dsaDone, total: _dsaTarget, color: const Color(0xFF818CF8), isDark: isDark),
            const SizedBox(width: 14),
            _Mini(label: '🃏 UNO', done: unoDone, total: _unoTarget, color: const Color(0xFFFF375F), isDark: isDark),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
              minHeight: 6)),
          const SizedBox(height: 7),
          Text(_loading ? 'Loading...' : allDone ? 'Reward claimed! 🎉' : '$totalDone/$totalTarget completed',
            style: TextStyle(color: subColor, fontSize: 11)),
        ])),
        const SizedBox(width: 16),
        Column(children: [
          const Text('🪙', style: TextStyle(fontSize: 28)),
          const Text('+100', style: TextStyle(color: Color(0xFFFFB800), fontWeight: FontWeight.w800, fontSize: 15)),
          Text('reward', style: TextStyle(color: isDark ? Colors.white30 : Colors.black26, fontSize: 10)),
        ]),
      ]));
  }
}

class _Mini extends StatelessWidget {
  final String label;
  final int done, total;
  final Color color;
  final bool isDark;
  const _Mini({required this.label, required this.done, required this.total, required this.color, required this.isDark});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    const SizedBox(width: 4),
    Text('$done/$total', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11)),
  ]);
}

// ══════════════════════════════════════════════════════════════════════════════
// FITNESS BUDDY CARD
// ══════════════════════════════════════════════════════════════════════════════
class _FitnessBuddyCard extends StatefulWidget {
  final _TimeTheme theme;
  final Function(int) onNavigate;
  const _FitnessBuddyCard({required this.theme, required this.onNavigate});

  @override
  State<_FitnessBuddyCard> createState() => _FitnessBuddyCardState();
}

class _FitnessBuddyCardState extends State<_FitnessBuddyCard> {
  FitnessProfile? _profile;
  BuddyState? _buddy;
  bool _checkedIn = false;
  bool _loading = true;

  static const _kGreen = Color(0xFF00E5A0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _profile = await FitnessService.getProfile();
      if (_profile != null) {
        final results = await Future.wait([
          FitnessService.getBuddyState(),
          FitnessService.hasCheckedInToday(),
        ]);
        _buddy = results[0] as BuddyState?;
        _checkedIn = results[1] as bool;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final isDark = context.isDark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white38 : Colors.black38;

    if (_loading) {
      return _ThinCard(
        theme: t,
        borderOverride: _kGreen,
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 13, width: 90,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 8),
            Container(height: 10, width: 60,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(4))),
          ])),
        ]),
      );
    }

    // No profile — teaser
    if (_profile == null) {
      return GestureDetector(
        onTap: () => widget.onNavigate(4),
        child: _ThinCard(
          theme: t,
          borderOverride: _kGreen,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kGreen.withValues(alpha: 0.4), width: 1),
              ),
              child: const Center(child: Text('💪', style: TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fitness Buddy', style: TextStyle(
                color: textColor, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 3),
              Text('AI-powered fitness companion', style: TextStyle(color: subColor, fontSize: 12)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kGreen.withValues(alpha: 0.35), width: 1),
                ),
                child: Text('Set up now →', style: TextStyle(
                  color: isDark ? _kGreen : const Color(0xFF047857),
                  fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ])),
            const Text('🤖', style: TextStyle(fontSize: 36)),
          ]),
        ),
      );
    }

    // Has profile — show buddy state
    final profile = _profile!;
    final streak = _buddy?.streakDays ?? 0;
    final stage = _buddy?.displayStage ?? 1;
    final bColor = buddyColor(profile.buddyPersonality);
    final fc = FitnessColors.of(context);
    final chipAccent = _checkedIn ? const Color(0xFF4ADE80) : bColor;

    return GestureDetector(
      onTap: () => widget.onNavigate(4),
      child: _ThinCard(
        theme: t,
        borderOverride: bColor,
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(
            width: 56, height: 56,
            child: BuddyCharacter(
              personality: profile.buddyPersonality,
              stage: stage,
              size: 56,
              gender: profile.gender,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(profile.buddyName, style: TextStyle(
                color: textColor, fontWeight: FontWeight.w800, fontSize: 14))),
              if (streak > 0) Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('🔥', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 3),
                Text('$streak day${streak == 1 ? '' : 's'}', style: TextStyle(
                  color: isDark ? const Color(0xFFFFB800) : const Color(0xFFC05600),
                  fontWeight: FontWeight.w700, fontSize: 11)),
              ]),
            ]),
            const SizedBox(height: 3),
            Text(goalLabel(profile.goal), style: TextStyle(color: subColor, fontSize: 11)),
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: chipAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: chipAccent.withValues(alpha: 0.35), width: 1),
              ),
              child: Text(
                _checkedIn ? '✓  Checked in today' : 'Tap to check in →',
                style: TextStyle(
                  color: fc.accentFg(chipAccent),
                  fontWeight: FontWeight.w700, fontSize: 10),
              ),
            ),
          ])),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NEON BOTTOM NAV — 100% unchanged
// ══════════════════════════════════════════════════════════════════════════════
class _NeonBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final int unreadCount;
  const _NeonBottomNav({required this.currentIndex, required this.onTap, required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final items = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.sports_esports_rounded, 'label': 'Play'},
      {'icon': Icons.campaign_rounded, 'label': 'Buzz'},
      {'icon': Icons.chat_bubble_rounded, 'label': 'Chat'},
      {'icon': Icons.fitness_center_rounded, 'label': 'Buddy'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];
    final neonColors = [
      const Color(0xFF6C63FF), const Color(0xFFFF375F), const Color(0xFF00B8A3),
      const Color(0xFF3D5AFE), const Color(0xFF00B8A3), const Color(0xFFFFB800),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1020) : Colors.white,
        border: Border(top: BorderSide(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.08), width: 1)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.4 : 0.08), blurRadius: 20, offset: const Offset(0, -5))]),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final isSelected = currentIndex == i;
              final color = neonColors[i];
              final icon  = items[i]['icon'] as IconData;
              final label = items[i]['label'] as String;
              final showBadge = i == 3 && unreadCount > 0;

              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isSelected ? 4 : 0, height: isSelected ? 4 : 0,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                        boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.8), blurRadius: 6)] : [])),
                    const SizedBox(height: 3),
                    Stack(clipBehavior: Clip.none, children: [
                      Icon(icon, color: isSelected ? color : context.textSec, size: i == 5 ? 22 : 24),
                      if (showBadge)
                        Positioned(top: -4, right: -6,
                          child: Container(
                            padding: unreadCount > 9
                              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                              : const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF375F), borderRadius: BorderRadius.circular(10),
                              boxShadow: [BoxShadow(color: const Color(0xFFFF375F).withOpacity(0.5), blurRadius: 6)]),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, height: 1),
                              textAlign: TextAlign.center))),
                    ]),
                    const SizedBox(height: 3),
                    Text(label, style: TextStyle(
                      color: isSelected ? color : context.textSec,
                      fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                  ])));
            })))));
  }
}