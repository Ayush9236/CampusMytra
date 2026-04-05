import 'package:flutter/material.dart';
import '../settings/theme_provider.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background(context);
    final text = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surface = AppColors.surface(context);
    final border = AppColors.border(context);
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Privacy Policy', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: text),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          Text('CampusMytra Privacy Policy',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: text)),
          const SizedBox(height: 6),
          Text('Last updated: March 20, 2026',
              style: TextStyle(color: textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Text('Developed by Ayush Pratap · Ajay Kumar Garg Engineering College',
              style: TextStyle(color: textSecondary, fontSize: 12)),
          const SizedBox(height: 24),

          _Section(title: '1. Introduction', content:
              'Welcome to CampusMytra — a campus social and gaming platform built for college students. '
              'We are committed to protecting your privacy. This policy explains what data we collect, '
              'how we use it, and your rights over it.',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '2. Information We Collect', content:
              'When you sign up and use CampusMytra, we collect:\n\n'
              '• Full name and username\n'
              '• Email address (used for login and OTP verification)\n'
              '• College name and year of study\n'
              '• Student ID (optional)\n'
              '• Profile photo (if uploaded)\n'
              '• Game statistics (wins, losses, match history)\n'
              '• Coin balance and transactions\n'
              '• Posts, comments, and buzz content you create\n'
              '• Device push notification token (for alerts)',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '3. How We Use Your Data', content:
              'Your data is used solely to:\n\n'
              '• Authenticate your account securely via OTP\n'
              '• Provide game matchmaking and leaderboards\n'
              '• Display your profile to other campus users\n'
              '• Send in-app and push notifications (game results, friend requests, etc.)\n'
              '• Track missions, badges, and achievements\n'
              '• Improve app features and fix bugs',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '4. Data Sharing', content:
              'We DO NOT:\n\n'
              '• Sell your personal data to any third party\n'
              '• Share your email address with other users\n'
              '• Use your data for advertising\n\n'
              'We DO:\n\n'
              '• Display your name, username, and game stats on public leaderboards\n'
              '• Show your profile to other verified campus users\n'
              '• Store all data securely on Supabase infrastructure',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '5. Third-Party Services', content:
              'CampusMytra uses the following trusted third-party services:\n\n'
              '• Supabase — Database, authentication, and storage\n'
              '  (supabase.com/privacy)\n\n'
              '• Firebase — Push notifications via FCM\n'
              '  (firebase.google.com/support/privacy)\n\n'
              '• Resend — Transactional email delivery\n'
              '  (resend.com/privacy)\n\n'
              'Each service has its own privacy policy which we recommend reviewing.',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '6. Data Security', content:
              '• All data is encrypted in transit (HTTPS/TLS)\n'
              '• Passwords are hashed — never stored in plain text\n'
              '• Email OTP verification required at signup\n'
              '• Supabase Row Level Security (RLS) ensures users can only access their own data\n'
              '• Push notification tokens are cleared on logout',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '7. Your Rights', content:
              'You have the right to:\n\n'
              '• Access your personal data at any time via your profile\n'
              '• Correct inaccurate information via Edit Profile\n'
              '• Request deletion of your account and all associated data\n'
              '• Opt-out of push notifications via device settings\n\n'
              'To exercise any of these rights, contact us at business.ayush22@gmail.com',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '8. Data Retention', content:
              '• Active accounts: Data retained while account is active\n'
              '• Deleted accounts: All personal data removed within 30 days\n'
              '• Game statistics may be anonymized after deletion\n'
              '• Unverified signups (no OTP) are auto-deleted after 1 hour',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '9. Age Requirement', content:
              'CampusMytra is designed for college students (18+). '
              'We do not knowingly collect data from anyone under 13. '
              'If you believe a minor has created an account, please contact us immediately.',
              text: text, surface: surface, border: border, primary: primary),

          _Section(title: '10. Changes to This Policy', content:
              'We may update this policy from time to time. Changes will be reflected by updating '
              'the "Last updated" date above. Continued use of the app after changes '
              'constitutes acceptance of the updated policy.',
              text: text, surface: surface, border: border, primary: primary),

          const SizedBox(height: 8),

          // Contact card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary.withValues(alpha: 0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.contact_mail_rounded, color: primary),
                const SizedBox(width: 10),
                Text('Contact Us', style: TextStyle(
                    color: text, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 16),
              _ContactRow(icon: Icons.person_outline, label: 'Developer', value: 'Ayush Pratap', text: text, sub: textSecondary),
              const SizedBox(height: 8),
              _ContactRow(icon: Icons.email_outlined, label: 'Email', value: 'business.ayush22@gmail.com', text: text, sub: textSecondary),
              const SizedBox(height: 8),
              _ContactRow(icon: Icons.school_outlined, label: 'College', value: 'Ajay Kumar Garg Engineering College', text: text, sub: textSecondary),
              const SizedBox(height: 12),
              Text('For privacy concerns, data requests, or account deletion, email us with your registered email address.',
                  style: TextStyle(color: textSecondary, fontSize: 12, height: 1.5)),
            ]),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.verified_user_rounded, color: Colors.green),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'Your privacy is protected. We only use your data to make your campus experience better.',
                style: TextStyle(color: textSecondary, fontSize: 13, height: 1.5))),
            ]),
          ),

          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String content;
  final Color text;
  final Color surface;
  final Color border;
  final Color primary;

  const _Section({required this.title, required this.content,
      required this.text, required this.surface, required this.border, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primary)),
        const SizedBox(height: 8),
        Text(content, style: TextStyle(fontSize: 13, color: text, height: 1.6)),
        const SizedBox(height: 4),
        Divider(color: border),
      ]),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color text;
  final Color sub;

  const _ContactRow({required this.icon, required this.label,
      required this.value, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: sub),
      const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: sub))),
    ]);
  }
}
