import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            
            // App Icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.deepPurple, Colors.purpleAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '🎮',
                  style: TextStyle(fontSize: 60),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // App Name
            const Text(
              'CampusMytra',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Version
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
              ),
              child: Text(
                'Version 1.0.0',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Tagline
            const Text(
              'Campus Social Gaming Platform',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Play, Compete, Connect',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 40),
            
            // Features
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✨ Features',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem('🃏', 'Real-time UNO Multiplayer'),
                  _buildFeatureItem('⚡', 'Quick Match with Random Players'),
                  _buildFeatureItem('🪙', 'Coin Rewards System'),
                  _buildFeatureItem('🏆', 'Campus-wide Leaderboards'),
                  _buildFeatureItem('📊', 'Player Statistics & Match History'),
                  _buildFeatureItem('👥', 'Play with Friends via Room Codes'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Campus Info
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.withOpacity(0.1),
                    Colors.purpleAccent.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.school,
                    size: 48,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Built for College Students',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ajay Kumar Garg Engineering College\nGhaziabad, Uttar Pradesh',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Developer Info
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Made with ❤️ by',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '[AYUSH PRATAP]',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ECE Department • AKGEC',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildTechBadge('Flutter'),
                      const SizedBox(width: 8),
                      _buildTechBadge('Supabase'),
                      const SizedBox(width: 8),
                      _buildTechBadge('Dart'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Contact Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.contact_mail, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Get in Touch',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildContactTile(
                    Icons.email,
                    'Email',
                    'karmatechis01@gmail.com',
                    'karmatechis01@gmail.com',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Social Links
            const Text(
              'Follow Us',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSocialButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Instagram',
                  color: const Color(0xFFE1306C),
                  url: 'https://www.instagram.com/kaarma_techis?igsh=MXE0NGkzanY2a3hrNA==',
                ),
                const SizedBox(width: 12),
                _buildSocialButton(
                  icon: Icons.work_outline_rounded,
                  label: 'LinkedIn',
                  color: const Color(0xFF0A66C2),
                  url: 'https://www.linkedin.com/in/ayush-pratap-069845317',
                ),
                const SizedBox(width: 12),
                _buildSocialButton(
                  icon: Icons.email_rounded,
                  label: 'Gmail',
                  color: const Color(0xFFEA4335),
                  url: 'mailto:business.ayush22@gmail.com',
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            // Credits
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '© 2026 CampusMytra',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'All rights reserved',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Version Info
            Text(
              'Build: 1.0.0+1 • Release: Feb 2026',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechBadge(String tech) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
      ),
      child: Text(
        tech,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.deepPurple,
        ),
      ),
    );
  }

  Widget _buildContactTile(IconData icon, String label, String value, String copyText) {
    return Builder(
      builder: (context) => InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: copyText));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$label copied to clipboard!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ));
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(children: [
            Icon(icon, size: 20, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(child: Text(value, style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontWeight: FontWeight.w500))),
            Icon(Icons.copy_rounded, size: 16, color: Colors.grey[500]),
          ]),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required String url,
  }) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}