import 'package:flutter/material.dart';
import 'screens/uno_lobby_screen.dart';
import 'screens/dsa_lobby_screen.dart';
import 'screens/playground_leaderboard_screen.dart';
import '../settings/theme_provider.dart';

class PlaygroundScreen extends StatelessWidget {
  const PlaygroundScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final textColor = AppColors.text(context);
    final subColor  = AppColors.textSecondary(context);
    final hintColor = AppColors.textHint(context);
    final surface   = AppColors.surfaceVariant(context);
    final border    = AppColors.border(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Playground 🎮',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your game',
                style: TextStyle(fontSize: 16, color: subColor),
              ),
              const SizedBox(height: 24),

              // UNO Card
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const UnoLobbyScreen())),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Colors.redAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                      color: Colors.red.withValues(alpha: 0.3),
                      blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('🃏 UNO', style: TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold,
                              color: Colors.white)),
                          Icon(Icons.play_circle_filled,
                              color: Colors.white, size: 40),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text('2 Players • Real-time', style: TextStyle(
                          color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // DSA Combat Card
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DsaLobbyScreen())),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                      blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('⚔️ DSA Combat', style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold,
                              color: Colors.white)),
                          Icon(Icons.code, color: Colors.white, size: 40),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text('1v1 Coding Battle • Fastest wins 🏆',
                          style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _buildComingSoonCard(context, '♟️ Chess', 'Strategy Game • Coming Soon'),
              const SizedBox(height: 28),

              // Rankings header
              Text('RANKINGS', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800,
                  color: hintColor, letterSpacing: 2.0)),
              const SizedBox(height: 10),

              // Leaderboard row
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const PlaygroundLeaderboardScreen())),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10)),
                      child: const Center(
                          child: Text('🏆', style: TextStyle(fontSize: 20)))),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Leaderboard', style: TextStyle(
                            color: textColor, fontWeight: FontWeight.w700,
                            fontSize: 15)),
                        const SizedBox(height: 2),
                        Text('UNO & DSA top players',
                            style: TextStyle(color: hintColor, fontSize: 12)),
                      ])),
                    Icon(Icons.chevron_right_rounded,
                        color: hintColor, size: 22),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComingSoonCard(BuildContext context, String title, String subtitle) {
    final isDark   = AppColors.isDark(context);
    final subColor = AppColors.textSecondary(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D2E) : Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold, color: subColor)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.orange, borderRadius: BorderRadius.circular(20)),
              child: const Text('Coming Soon', style: TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          ]),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(color: subColor, fontSize: 14)),
      ]),
    );
  }
}
