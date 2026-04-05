import 'dart:async';
import 'package:campusmytra/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_screen.dart';
import '../playground/playground_screen.dart';
import '../buzz/buzz_screen.dart';
import '../chatter/chatter_screen.dart';
import 'package:provider/provider.dart';
import '../settings/theme_provider.dart';
import '../buzz/notification_service.dart';
import '../auth/login_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    PlaygroundScreen(),
    ChatterScreen(),
    CampusBuzzScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.sports_esports), label: "Playground"),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: "Chatter"),
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: "Buzz"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}

// ── SETTINGS SCREEN ──
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final bg = AppColors.background(context);
    final surface = AppColors.surface(context);
    final text = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final border = AppColors.border(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Settings'), backgroundColor: bg, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Appearance', textColor: textSecondary),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: surface,
              borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isDark ? Colors.indigo.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(isDark ? Icons.dark_mode : Icons.light_mode,
                  color: isDark ? Colors.indigo : Colors.amber)),
              title: Text('Dark Mode', style: TextStyle(color: text, fontWeight: FontWeight.w600)),
              subtitle: Text(isDark ? 'Currently using dark theme' : 'Currently using light theme',
                style: TextStyle(color: textSecondary, fontSize: 12)),
              trailing: Switch(
                value: isDark, onChanged: (_) => themeProvider.toggleTheme(),
                activeColor: const Color(0xFF6C63FF),
                inactiveTrackColor: Colors.grey.withOpacity(0.3)),
            )),
          const SizedBox(height: 24),
          _SectionHeader(title: 'About', textColor: textSecondary),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: surface,
              borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
            child: Column(children: [
              _SettingsTile(icon: Icons.info_outline, iconColor: Colors.blue,
                title: 'App Version',
                trailing: Text('v1.0.0', style: TextStyle(color: textSecondary, fontSize: 14)),
                textColor: text, borderColor: border, showDivider: true),
              _SettingsTile(icon: Icons.school_outlined, iconColor: Colors.green,
                title: 'College',
                trailing: Text('AKGEC', style: TextStyle(color: textSecondary, fontSize: 14)),
                textColor: text, borderColor: border, showDivider: false),
            ])),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Privacy', textColor: textSecondary),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: surface,
              borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
            child: _SettingsTile(
              icon: Icons.block_rounded, iconColor: Colors.redAccent,
              title: 'Blocked Users',
              trailing: Icon(Icons.chevron_right, color: textSecondary),
              textColor: text, borderColor: border, showDivider: false,
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BlockedUsersScreen())))),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Account', textColor: textSecondary),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: surface,
              borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
            child: Column(children: [
              _SettingsTile(
                icon: Icons.lock_reset_rounded, iconColor: Colors.orange,
                title: 'Change Password',
                trailing: Icon(Icons.chevron_right, color: textSecondary),
                textColor: text, borderColor: border, showDivider: true,
                onTap: () => _changePassword(context)),
              _SettingsTile(
                icon: Icons.logout, iconColor: Colors.red, title: 'Logout',
                trailing: const Icon(Icons.chevron_right, color: Colors.red),
                textColor: Colors.red, borderColor: border, showDivider: false,
                onTap: () => _confirmLogout(context)),
            ])),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('🎨', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Theme Active', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(isDark ? 'Dark mode is ON' : 'Light mode is ON',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ])),
              Switch(value: isDark, onChanged: (_) => themeProvider.toggleTheme(),
                activeColor: Colors.white, activeTrackColor: Colors.white30),
            ])),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    const weekKey = 'last_password_change';
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(weekKey);
    if (lastMs != null) {
      final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
      if (diff.inDays < 7) {
        final remaining = 7 - diff.inDays;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('You can change your password again in $remaining day${remaining == 1 ? '' : 's'}.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.orange,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
        }
        return;
      }
    }

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? errorMsg;
    bool isLoading = false;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: AppColors.surface(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Text('🔒', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text('Change Password', style: TextStyle(
                color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              _PwField(controller: currentCtrl, hint: 'Current password', obscure: obscureCurrent,
                  onToggle: () => setStateDialog(() => obscureCurrent = !obscureCurrent)),
              const SizedBox(height: 12),
              _PwField(controller: newCtrl, hint: 'New password (min 6 chars)', obscure: obscureNew,
                  onToggle: () => setStateDialog(() => obscureNew = !obscureNew)),
              const SizedBox(height: 12),
              _PwField(controller: confirmCtrl, hint: 'Confirm new password', obscure: obscureConfirm,
                  onToggle: () => setStateDialog(() => obscureConfirm = !obscureConfirm)),
              const SizedBox(height: 4),
              Text('⚠️ You can only change your password once per week.',
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11)),
            ]),
          ),
          actions: [
            TextButton(onPressed: isLoading ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: isLoading ? null : () async {
                final current = currentCtrl.text;
                final newPass = newCtrl.text;
                final confirm = confirmCtrl.text;
                if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
                  setStateDialog(() => errorMsg = 'All fields are required.'); return;
                }
                if (newPass.length < 6) {
                  setStateDialog(() => errorMsg = 'New password must be at least 6 characters.'); return;
                }
                if (newPass != confirm) {
                  setStateDialog(() => errorMsg = 'Passwords do not match.'); return;
                }
                if (newPass == current) {
                  setStateDialog(() => errorMsg = 'New password must be different.'); return;
                }
                setStateDialog(() => isLoading = true);
                try {
                  final sb = Supabase.instance.client;
                  final email = sb.auth.currentUser?.email ?? '';
                  await sb.auth.signInWithPassword(email: email, password: current);
                  await sb.auth.updateUser(UserAttributes(password: newPass));
                  await prefs.setInt(weekKey, DateTime.now().millisecondsSinceEpoch);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('✅ Password changed successfully!'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.green,
                    ));
                  }
                } on AuthException catch (e) {
                  setStateDialog(() {
                    isLoading = false;
                    errorMsg = e.message.contains('Invalid') ? 'Current password is incorrect.' : e.message;
                  });
                } catch (_) {
                  setStateDialog(() { isLoading = false; errorMsg = 'Something went wrong. Try again.'; });
                }
              },
              child: isLoading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Logout?', style: TextStyle(color: AppColors.text(context))),
        content: Text('Are you sure you want to logout?',
          style: TextStyle(color: AppColors.textSecondary(context))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await NotificationService.instance.clearToken();
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout')),
        ],
      ));
  }
}

class _PwField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  const _PwField({required this.controller, required this.hint, required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller, obscureText: obscure,
    style: TextStyle(color: AppColors.text(context), fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
      filled: true, fillColor: AppColors.background(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border(context))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange, width: 1.5)),
      suffixIcon: IconButton(
        icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: AppColors.textSecondary(context), size: 20),
        onPressed: onToggle),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title; final Color textColor;
  const _SectionHeader({required this.title, required this.textColor});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 4),
    child: Text(title.toUpperCase(), style: TextStyle(
      color: textColor, fontSize: 11,
      fontWeight: FontWeight.bold, letterSpacing: 1.2)));
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title;
  final Widget trailing; final Color textColor; final Color borderColor;
  final bool showDivider; final VoidCallback? onTap;
  const _SettingsTile({required this.icon, required this.iconColor,
    required this.title, required this.trailing, required this.textColor,
    required this.borderColor, required this.showDivider, this.onTap});

  @override
  Widget build(BuildContext context) => Column(children: [
    ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20)),
      title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
      trailing: trailing),
    if (showDivider)
      Divider(height: 1, color: borderColor, indent: 72, endIndent: 20),
  ]);
}

// ── BLOCKED USERS SCREEN ──────────────────────────────────────────

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({Key? key}) : super(key: key);
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) { if (mounted) setState(() => _loading = false); return; }
    try {
      final rows = await _sb
          .from('blocked_users')
          .select('blocked_id, profiles:blocked_id(id, username, emoji)')
          .eq('blocker_id', myId);
      if (mounted) setState(() { _blocked = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(String blockedId) async {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;
    await _sb.from('blocked_users').delete()
        .eq('blocker_id', myId).eq('blocked_id', blockedId);
    setState(() => _blocked.removeWhere((r) => r['blocked_id'] == blockedId));
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background(context);
    final surface = AppColors.surface(context);
    final text = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final border = AppColors.border(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Blocked Users', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
        backgroundColor: bg, elevation: 0,
        iconTheme: IconThemeData(color: text)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocked.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🚫', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text('No blocked users', style: TextStyle(color: text,
                      fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Users you block will appear here',
                      style: TextStyle(color: textSecondary, fontSize: 13)),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _blocked.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final profile = _blocked[i]['profiles'] as Map<String, dynamic>? ?? {};
                    final username = profile['username']?.toString() ?? 'Unknown';
                    final emoji = profile['emoji']?.toString() ?? '👤';
                    final blockedId = _blocked[i]['blocked_id'].toString();
                    return Container(
                      decoration: BoxDecoration(color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: border)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: Center(child: Text(emoji,
                              style: const TextStyle(fontSize: 22)))),
                        title: Text(username, style: TextStyle(
                            color: text, fontWeight: FontWeight.w600)),
                        trailing: TextButton(
                          onPressed: () => _unblock(blockedId),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              backgroundColor: Colors.redAccent.withOpacity(0.1),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8))),
                          child: const Text('Unblock',
                              style: TextStyle(fontWeight: FontWeight.w700))),
                      ));
                  }),
    );
  }
}