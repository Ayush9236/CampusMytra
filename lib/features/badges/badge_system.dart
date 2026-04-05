import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/theme_provider.dart';
import 'dart:math' as math;
const String kOwnerUserId = '44d16843-2c42-44c3-aeaf-62a3eb469637';

enum BadgeTier { bronze, silver, gold, diamond, animated }

class BadgeModel {
  final String id, label, subtitle, description;
  final BadgeTier tier;
  final Color primaryColor, accentColor;
  final IconData icon;
  const BadgeModel({required this.id, required this.label, required this.subtitle, required this.description, required this.tier, required this.primaryColor, required this.accentColor, required this.icon});
}

class MissionModel {
  final String badgeId, title, description;
  final IconData icon;
  final int current, target;
  final Color color;
  final BadgeTier rewardTier;
  const MissionModel({required this.badgeId, required this.title, required this.description, required this.icon, required this.current, required this.target, required this.color, required this.rewardTier});
  double get progress => (current / target).clamp(0.0, 1.0);
}

class _B {
  static const owner = BadgeModel(id: 'owner', label: 'SOVEREIGN', subtitle: 'FOUNDER', description: 'Built CampusMytra from nothing', tier: BadgeTier.animated, primaryColor: Color(0xFFFFB800), accentColor: Color(0xFFFF6B00), icon: Icons.auto_awesome);
  static const collegeAdmin = BadgeModel(id: 'college_admin', label: 'GUARDIAN', subtitle: 'COLLEGE ADMIN', description: 'Entrusted to govern this campus', tier: BadgeTier.animated, primaryColor: Color(0xFF818CF8), accentColor: Color(0xFF4F46E5), icon: Icons.shield_rounded);
  static const branchAdmin = BadgeModel(id: 'branch_admin', label: 'SENTINEL', subtitle: 'BRANCH MOD', description: 'Keeper of the branch order', tier: BadgeTier.gold, primaryColor: Color(0xFF00B8A3), accentColor: Color(0xFF007A6E), icon: Icons.balance_rounded);
  static const pioneer = BadgeModel(id: 'pioneer', label: 'PIONEER', subtitle: 'EARLY ACCESS · TOP 100', description: 'Among the first 100 users on CampusMytra', tier: BadgeTier.diamond, primaryColor: Color(0xFFE879F9), accentColor: Color(0xFF9333EA), icon: Icons.rocket_launch_rounded);
  static const verified = BadgeModel(id: 'verified', label: 'VERIFIED', subtitle: 'STUDENT ID', description: 'Identity confirmed by institution', tier: BadgeTier.silver, primaryColor: Color(0xFF818CF8), accentColor: Color(0xFF4F46E5), icon: Icons.verified_rounded);
  static const unoElite = BadgeModel(id: 'uno_elite', label: 'CARD ELITE', subtitle: 'UNO · RANK II', description: '25+ UNO victories', tier: BadgeTier.silver, primaryColor: Color(0xFFFF375F), accentColor: Color(0xFF9B0022), icon: Icons.style_rounded);
  static const unoWarlord = BadgeModel(id: 'uno_warlord', label: 'WARLORD', subtitle: 'UNO · RANK III', description: '75+ UNO victories', tier: BadgeTier.gold, primaryColor: Color(0xFFFFB800), accentColor: Color(0xFFFF6B00), icon: Icons.military_tech_rounded);
  static const unoPhantom = BadgeModel(id: 'uno_phantom', label: 'PHANTOM KING', subtitle: 'UNO · RANK IV', description: '150+ UNO victories — feared by all', tier: BadgeTier.diamond, primaryColor: Color(0xFFE879F9), accentColor: Color(0xFF9333EA), icon: Icons.workspace_premium_rounded);
  static const dsaSlayer = BadgeModel(id: 'dsa_slayer', label: 'CODE SLAYER', subtitle: 'DSA · RANK II', description: '25+ DSA Combat victories', tier: BadgeTier.silver, primaryColor: Color(0xFF4ADE80), accentColor: Color(0xFF166534), icon: Icons.code_rounded);
  static const dsaApex = BadgeModel(id: 'dsa_apex', label: 'APEX CODER', subtitle: 'DSA · RANK III', description: '75+ DSA Combat victories', tier: BadgeTier.gold, primaryColor: Color(0xFFFFB800), accentColor: Color(0xFF92400E), icon: Icons.terminal_rounded);
  static const dsaVoid = BadgeModel(id: 'dsa_void', label: 'VOID BREAKER', subtitle: 'DSA · RANK IV', description: '150+ DSA Combat victories', tier: BadgeTier.diamond, primaryColor: Color(0xFF818CF8), accentColor: Color(0xFF312E81), icon: Icons.flash_on_rounded);
  static const buzzVoice = BadgeModel(id: 'buzz_voice', label: 'VOICE', subtitle: 'BUZZ · RANK II', description: '25+ posts on Campus Buzz', tier: BadgeTier.silver, primaryColor: Color(0xFF00B8A3), accentColor: Color(0xFF065F46), icon: Icons.campaign_rounded);
  static const buzzIconoclast = BadgeModel(id: 'buzz_iconoclast', label: 'ICONOCLAST', subtitle: 'BUZZ · RANK III', description: '100+ posts — you own this feed', tier: BadgeTier.gold, primaryColor: Color(0xFFE879F9), accentColor: Color(0xFF7E22CE), icon: Icons.auto_fix_high_rounded);
  static const inferno = BadgeModel(id: 'inferno', label: 'INFERNO', subtitle: 'VIRAL · 50 LIKES', description: 'One post crossed 50 likes', tier: BadgeTier.gold, primaryColor: Color(0xFFFF375F), accentColor: Color(0xFF7F1D1D), icon: Icons.local_fire_department_rounded);
  static const obliterator = BadgeModel(id: 'obliterator', label: 'OBLITERATOR', subtitle: 'VIRAL · 200 LIKES', description: 'One post crossed 200 likes', tier: BadgeTier.animated, primaryColor: Color(0xFFFF375F), accentColor: Color(0xFFFFB800), icon: Icons.whatshot_rounded);
  static const networked = BadgeModel(id: 'networked', label: 'NETWORKED', subtitle: 'SOCIAL · RANK II', description: '25+ campus connections', tier: BadgeTier.silver, primaryColor: Color(0xFF818CF8), accentColor: Color(0xFF312E81), icon: Icons.hub_rounded);
  static const overlord = BadgeModel(id: 'overlord', label: 'OVERLORD', subtitle: 'SOCIAL · RANK III', description: '100+ campus connections', tier: BadgeTier.gold, primaryColor: Color(0xFFFFB800), accentColor: Color(0xFF92400E), icon: Icons.diversity_3_rounded);
  static const machine = BadgeModel(id: 'machine', label: 'THE MACHINE', subtitle: 'GRIND · ELITE', description: '200+ total game wins (UNO + DSA)', tier: BadgeTier.diamond, primaryColor: Color(0xFF818CF8), accentColor: Color(0xFF1E1B4B), icon: Icons.bolt_rounded);
  static const campusLegend = BadgeModel(id: 'campus_legend', label: 'LEGEND', subtitle: 'ALL CATEGORIES · MAX', description: 'Maxed every category — true CampusMytra legend', tier: BadgeTier.animated, primaryColor: Color(0xFFE879F9), accentColor: Color(0xFFFFB800), icon: Icons.emoji_events_rounded);
}

class BadgeUtils {
  static int _int(Map<String, dynamic> p, String k) => (p[k] as num?)?.toInt() ?? 0;

  static List<BadgeModel> computeBadges(Map<String, dynamic> profile) {
    final badges = <BadgeModel>[];
    final userId = profile['user_id']?.toString() ?? '';
    final adminRole = profile['admin_role']?.toString();
    final status = profile['college_status']?.toString() ?? '';
    final signupRank = _int(profile, 'signup_rank');
    final unoWins = _int(profile, 'uno_wins');
    final dsaWins = _int(profile, 'dsa_wins');
    final postCount = _int(profile, 'post_count');
    final maxLikes = _int(profile, 'max_post_likes');
    final friendCount = _int(profile, 'friend_count');
    final isOwner = userId == kOwnerUserId;
    if (isOwner) badges.add(_B.owner);
    if (!isOwner && adminRole == 'college') badges.add(_B.collegeAdmin);
    if (adminRole == 'branch') badges.add(_B.branchAdmin);
    final rank = signupRank == 0 ? 999999 : signupRank;
    if (rank <= 100) badges.add(_B.pioneer);
    if (status == 'verified') badges.add(_B.verified);
    if (unoWins >= 150) badges.add(_B.unoPhantom);
    else if (unoWins >= 75) badges.add(_B.unoWarlord);
    else if (unoWins >= 25) badges.add(_B.unoElite);
    if (dsaWins >= 150) badges.add(_B.dsaVoid);
    else if (dsaWins >= 75) badges.add(_B.dsaApex);
    else if (dsaWins >= 25) badges.add(_B.dsaSlayer);
    if (postCount >= 100) badges.add(_B.buzzIconoclast);
    else if (postCount >= 25) badges.add(_B.buzzVoice);
    if (maxLikes >= 200) badges.add(_B.obliterator);
    else if (maxLikes >= 50) badges.add(_B.inferno);
    if (friendCount >= 100) badges.add(_B.overlord);
    else if (friendCount >= 25) badges.add(_B.networked);
    if (unoWins + dsaWins >= 200) badges.add(_B.machine);
    if (unoWins >= 75 && dsaWins >= 75 && postCount >= 100 && maxLikes >= 50 && friendCount >= 100) badges.add(_B.campusLegend);
    badges.sort((a, b) => b.tier.index.compareTo(a.tier.index));
    return badges;
  }

  static List<MissionModel> computeMissions(Map<String, dynamic> profile) {
    final missions = <MissionModel>[];
    final unoWins = _int(profile, 'uno_wins');
    final dsaWins = _int(profile, 'dsa_wins');
    final postCount = _int(profile, 'post_count');
    final maxLikes = _int(profile, 'max_post_likes');
    final friendCount = _int(profile, 'friend_count');
    if (unoWins < 25) missions.add(MissionModel(badgeId: 'uno_elite', icon: Icons.style_rounded, title: 'Win 25 UNO games', description: 'Unlock CARD ELITE — no shortcuts', current: unoWins, target: 25, color: const Color(0xFFFF375F), rewardTier: BadgeTier.silver));
    else if (unoWins < 75) missions.add(MissionModel(badgeId: 'uno_warlord', icon: Icons.military_tech_rounded, title: 'Win 75 UNO games', description: 'Claim WARLORD — most never reach this', current: unoWins, target: 75, color: const Color(0xFFFFB800), rewardTier: BadgeTier.gold));
    else if (unoWins < 150) missions.add(MissionModel(badgeId: 'uno_phantom', icon: Icons.workspace_premium_rounded, title: 'Win 150 UNO games', description: 'Become PHANTOM KING — rarest UNO badge', current: unoWins, target: 150, color: const Color(0xFFE879F9), rewardTier: BadgeTier.diamond));
    if (dsaWins < 25) missions.add(MissionModel(badgeId: 'dsa_slayer', icon: Icons.code_rounded, title: 'Win 25 DSA Combats', description: 'Unlock CODE SLAYER — out-think everyone', current: dsaWins, target: 25, color: const Color(0xFF4ADE80), rewardTier: BadgeTier.silver));
    else if (dsaWins < 75) missions.add(MissionModel(badgeId: 'dsa_apex', icon: Icons.terminal_rounded, title: 'Win 75 DSA Combats', description: 'Become APEX CODER — top 1% of campus', current: dsaWins, target: 75, color: const Color(0xFFFFB800), rewardTier: BadgeTier.gold));
    else if (dsaWins < 150) missions.add(MissionModel(badgeId: 'dsa_void', icon: Icons.flash_on_rounded, title: 'Win 150 DSA Combats', description: 'Become VOID BREAKER — campus coding god', current: dsaWins, target: 150, color: const Color(0xFF818CF8), rewardTier: BadgeTier.diamond));
    if (postCount < 25) missions.add(MissionModel(badgeId: 'buzz_voice', icon: Icons.campaign_rounded, title: 'Post 25 times on Buzz', description: 'Earn VOICE — show up consistently', current: postCount, target: 25, color: const Color(0xFF00B8A3), rewardTier: BadgeTier.silver));
    else if (postCount < 100) missions.add(MissionModel(badgeId: 'buzz_iconoclast', icon: Icons.auto_fix_high_rounded, title: 'Post 100 times on Buzz', description: 'Earn ICONOCLAST — you own this feed', current: postCount, target: 100, color: const Color(0xFFE879F9), rewardTier: BadgeTier.gold));
    if (maxLikes < 50) missions.add(MissionModel(badgeId: 'inferno', icon: Icons.local_fire_department_rounded, title: 'Get 50 likes on one post', description: 'Earn INFERNO — post something that hits', current: maxLikes, target: 50, color: const Color(0xFFFF375F), rewardTier: BadgeTier.gold));
    else if (maxLikes < 200) missions.add(MissionModel(badgeId: 'obliterator', icon: Icons.whatshot_rounded, title: 'Get 200 likes on one post', description: 'Earn OBLITERATOR — the rarest Buzz badge', current: maxLikes, target: 200, color: const Color(0xFFFF375F), rewardTier: BadgeTier.animated));
    if (friendCount < 25) missions.add(MissionModel(badgeId: 'networked', icon: Icons.hub_rounded, title: 'Connect with 25 people', description: 'Earn NETWORKED — build your campus circle', current: friendCount, target: 25, color: const Color(0xFF818CF8), rewardTier: BadgeTier.silver));
    else if (friendCount < 100) missions.add(MissionModel(badgeId: 'overlord', icon: Icons.diversity_3_rounded, title: 'Connect with 100 people', description: 'Become OVERLORD — everyone knows your name', current: friendCount, target: 100, color: const Color(0xFFFFB800), rewardTier: BadgeTier.gold));
    final totalWins = unoWins + dsaWins;
    if (totalWins < 200) missions.add(MissionModel(badgeId: 'machine', icon: Icons.bolt_rounded, title: 'Grind 200 total game wins', description: 'UNO + DSA combined — become THE MACHINE', current: totalWins, target: 200, color: const Color(0xFF818CF8), rewardTier: BadgeTier.diamond));
    final legendDone = [unoWins >= 75, dsaWins >= 75, postCount >= 100, maxLikes >= 50, friendCount >= 100].where((b) => b).length;
    if (legendDone < 5) {
      final parts = <String>[];
      if (unoWins < 75) parts.add('${75 - unoWins} UNO wins');
      if (dsaWins < 75) parts.add('${75 - dsaWins} DSA wins');
      if (postCount < 100) parts.add('${100 - postCount} posts');
      if (maxLikes < 50) parts.add('50-like post');
      if (friendCount < 100) parts.add('${100 - friendCount} friends');
      missions.add(MissionModel(badgeId: 'campus_legend', icon: Icons.emoji_events_rounded, title: 'Become LEGEND ($legendDone/5)', description: 'Need: ${parts.take(2).join(' · ')}${parts.length > 2 ? ' +${parts.length - 2} more' : ''}', current: legendDone, target: 5, color: const Color(0xFFE879F9), rewardTier: BadgeTier.animated));
    }
    // ── Banner missions (shown only until that banner tier is earned) ──
    final bannerRank = computeBannerRank(profile);
    final totalWinsB = unoWins + dsaWins;

    if (bannerRank == BannerRank.none) {
      // Next target: BRONZE — any single stat hits 50
      final bronzeBest = [unoWins, dsaWins, postCount, friendCount].reduce((a, b) => a > b ? a : b);
      missions.add(MissionModel(
        badgeId: 'banner_bronze',
        icon: Icons.hexagon_outlined,
        title: 'Earn the BRONZE Banner',
        description: '50 UNO wins, 50 DSA wins, 50 posts, or 50 friends — pick your grind',
        current: bronzeBest,
        target: 50,
        color: const Color(0xFFCD7F32),
        rewardTier: BadgeTier.bronze,
      ));
    } else if (bannerRank == BannerRank.pioneer) {
      // Pioneer can also earn BRONZE via stats
      final bronzeBest = [unoWins, dsaWins, postCount, friendCount].reduce((a, b) => a > b ? a : b);
      missions.add(MissionModel(
        badgeId: 'banner_bronze',
        icon: Icons.hexagon_outlined,
        title: 'Earn the BRONZE Banner',
        description: '50 UNO wins, 50 DSA wins, 50 posts, or 50 friends',
        current: bronzeBest,
        target: 50,
        color: const Color(0xFFCD7F32),
        rewardTier: BadgeTier.bronze,
      ));
    } else if (bannerRank == BannerRank.bronze) {
      // Next target: SILVER
      final silverBest = [unoWins, dsaWins, postCount, friendCount].reduce((a, b) => a > b ? a : b);
      missions.add(MissionModel(
        badgeId: 'banner_silver',
        icon: Icons.shield_outlined,
        title: 'Earn the SILVER Banner',
        description: '100 UNO/DSA wins, 150 posts, 75 friends, or 100 likes on one post',
        current: silverBest,
        target: 100,
        color: const Color(0xFFCBD5E1),
        rewardTier: BadgeTier.silver,
      ));
    } else if (bannerRank == BannerRank.silver) {
      // Next target: GOLD
      final goldBest = [unoWins, dsaWins, postCount, friendCount, totalWinsB].reduce((a, b) => a > b ? a : b);
      missions.add(MissionModel(
        badgeId: 'banner_gold',
        icon: Icons.star_rounded,
        title: 'Earn the GOLD Banner',
        description: '200 UNO/DSA wins, 300 posts, 150 friends, 300 likes, or 300 total wins',
        current: goldBest,
        target: 200,
        color: const Color(0xFFFFB800),
        rewardTier: BadgeTier.gold,
      ));
    } else if (bannerRank == BannerRank.gold) {
      // Next target: DIAMOND — hardest gate
      final diamondScore = [unoWins, dsaWins].reduce((a, b) => a > b ? a : b);
      missions.add(MissionModel(
        badgeId: 'banner_diamond',
        icon: Icons.diamond_rounded,
        title: 'Earn the DIAMOND Banner',
        description: '350 UNO or DSA wins solo, OR 500 total wins + 300 posts + 150 friends',
        current: diamondScore,
        target: 350,
        color: const Color(0xFFE879F9),
        rewardTier: BadgeTier.diamond,
      ));
    }

    return missions;
  }

  static Color tierColor(BadgeTier tier) {
    switch (tier) {
      case BadgeTier.animated: return const Color(0xFFFFB800);
      case BadgeTier.diamond:  return const Color(0xFFE879F9);
      case BadgeTier.gold:     return const Color(0xFFFFB800);
      case BadgeTier.silver:   return const Color(0xFFB0B8C8);
      case BadgeTier.bronze:   return const Color(0xFFCD7F32);
    }
  }

  static String tierLabel(BadgeTier tier) {
    switch (tier) {
      case BadgeTier.animated: return 'LEGENDARY';
      case BadgeTier.diamond:  return 'DIAMOND';
      case BadgeTier.gold:     return 'GOLD';
      case BadgeTier.silver:   return 'SILVER';
      case BadgeTier.bronze:   return 'BRONZE';
    }
  }
}

// ══════════════════════════════════════════════════════════════════
// BadgeSection — badges always visible; missions behind a single
// collapsible "MISSIONS" tab header (tap to expand/collapse)
// ══════════════════════════════════════════════════════════════════
class BadgeSection extends StatefulWidget {
  final Map<String, dynamic> profile;
  const BadgeSection({super.key, required this.profile});

  @override
  State<BadgeSection> createState() => _BadgeSectionState();
}

class _BadgeSectionState extends State<BadgeSection> {
  bool _missionsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final badges   = BadgeUtils.computeBadges(widget.profile);
    final missions = BadgeUtils.computeMissions(widget.profile);
    final textColor     = AppColors.text(context);
    final textSecondary = AppColors.textSecondary(context);
    final surfaceVar    = AppColors.surfaceVariant(context);
    final surface       = AppColors.surface(context);
    final borderColor   = AppColors.border(context);
    const missionColor  = Color(0xFF4ADE80);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── Badges (always visible) ──
      if (badges.isNotEmpty) ...[
        _SectionHeader(icon: Icons.military_tech_rounded, label: 'BADGES', count: badges.length, color: const Color(0xFFFFB800), textColor: textColor),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 10, runSpacing: 10, children: badges.map((b) => _BadgeChip(badge: b)).toList()),
        ),
        const SizedBox(height: 20),
      ],

      // ── Missions: single collapsible tab ──
      if (missions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(children: [

              // ── Tap header to toggle ──
              GestureDetector(
                onTap: () => setState(() => _missionsExpanded = !_missionsExpanded),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.track_changes_rounded, color: missionColor, size: 16),
                    const SizedBox(width: 6),
                    Text('MISSIONS', style: TextStyle(
                      color: textColor, fontSize: 12,
                      fontWeight: FontWeight.w900, letterSpacing: 2.0,
                    )),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: missionColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${missions.length}', style: TextStyle(
                        color: missionColor, fontSize: 10, fontWeight: FontWeight.w900,
                      )),
                    ),
                    const Spacer(),
                    Icon(
                      _missionsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: textSecondary, size: 20,
                    ),
                  ]),
                ),
              ),

              // ── Expanded list ──
              if (_missionsExpanded) ...[
                Divider(height: 1, color: borderColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Column(
                    children: missions.map((m) => _MissionTile(mission: m)).toList(),
                  ),
                ),
              ],

            ]),
          ),
        ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════
// Section Header
// ══════════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color, textColor;
  const _SectionHeader({required this.icon, required this.label, required this.count, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
          child: Text('$count', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Badge Chip
// ══════════════════════════════════════════════════════════════════
class _BadgeChip extends StatelessWidget {
  final BadgeModel badge;
  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    final isAnim = badge.tier == BadgeTier.animated || badge.tier == BadgeTier.diamond;
    return Tooltip(
      message: badge.description, preferBelow: false,
      child: isAnim ? _AnimatedBadgeChip(badge: badge) : _StaticBadgeChip(badge: badge),
    );
  }
}

class _StaticBadgeChip extends StatelessWidget {
  final BadgeModel badge;
  const _StaticBadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    final tierCol = BadgeUtils.tierColor(badge.tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [badge.primaryColor.withOpacity(0.18), badge.accentColor.withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badge.primaryColor.withOpacity(0.35), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [badge.primaryColor, badge.accentColor], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: badge.primaryColor.withOpacity(0.3), blurRadius: 6)]),
          child: Icon(badge.icon, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(badge.label, style: TextStyle(color: badge.primaryColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          Text(badge.subtitle, style: TextStyle(color: tierCol.withOpacity(0.75), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
      ]),
    );
  }
}

class _AnimatedBadgeChip extends StatefulWidget {
  final BadgeModel badge;
  const _AnimatedBadgeChip({required this.badge});
  @override
  State<_AnimatedBadgeChip> createState() => _AnimatedBadgeChipState();
}

class _AnimatedBadgeChipState extends State<_AnimatedBadgeChip> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final b = widget.badge;
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, __) {
        final v = _glow.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [b.primaryColor.withOpacity(0.22 + 0.12 * v), b.accentColor.withOpacity(0.10)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: b.primaryColor.withOpacity(0.5 + 0.3 * v), width: 1.2),
            boxShadow: [BoxShadow(color: b.primaryColor.withOpacity(0.15 + 0.25 * v), blurRadius: 8 + 10 * v, spreadRadius: v)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [b.primaryColor, Color.lerp(b.primaryColor, b.accentColor, 0.5 + 0.5 * v)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(color: b.primaryColor.withOpacity(0.4 + 0.3 * v), blurRadius: 6 + 8 * v, spreadRadius: v)],
              ),
              child: Icon(b.icon, color: Colors.white, size: 15),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(colors: [b.primaryColor, b.accentColor]).createShader(bounds),
                child: Text(b.label, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              ),
              Text(b.subtitle, style: TextStyle(color: b.primaryColor.withOpacity(0.7 + 0.3 * v), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            ]),
          ]),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Mission Tile
// ══════════════════════════════════════════════════════════════════
class _MissionTile extends StatelessWidget {
  final MissionModel mission;
  const _MissionTile({required this.mission});

  @override
  Widget build(BuildContext context) {
    final tierColor = BadgeUtils.tierColor(mission.rewardTier);
    final tierLabel = BadgeUtils.tierLabel(mission.rewardTier);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [mission.color.withOpacity(0.08), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mission.color.withOpacity(0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: mission.color.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: mission.color.withOpacity(0.3))),
            child: Icon(mission.icon, color: mission.color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mission.title, style: TextStyle(color: AppColors.text(context), fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: tierColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(tierLabel, style: TextStyle(color: tierColor, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(mission.description, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSecondary(context), fontSize: 10, fontWeight: FontWeight.w500))),
            ]),
          ])),
          const SizedBox(width: 8),
          Text('${mission.current}/${mission.target}', style: TextStyle(color: mission.color, fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        Stack(children: [
          Container(height: 4, decoration: BoxDecoration(color: mission.color.withOpacity(0.12), borderRadius: BorderRadius.circular(4))),
          FractionallySizedBox(
            widthFactor: mission.progress,
            child: Container(height: 4, decoration: BoxDecoration(gradient: LinearGradient(colors: [mission.color, mission.color.withOpacity(0.6)]), borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: mission.color.withOpacity(0.4), blurRadius: 4)])),
          ),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// AsyncBadgeRow
// ══════════════════════════════════════════════════════════════════
final _badgeCache = <String, List<BadgeModel>>{};
final _sb = Supabase.instance.client;

class AsyncBadgeRow extends StatefulWidget {
  final String userId;
  final int maxVisible;
  final double chipSize;
  const AsyncBadgeRow({super.key, required this.userId, this.maxVisible = 3, this.chipSize = 20});
  @override
  State<AsyncBadgeRow> createState() => _AsyncBadgeRowState();
}

class _AsyncBadgeRowState extends State<AsyncBadgeRow> {
  List<BadgeModel>? _badges;
  @override void initState() { super.initState(); _load(); }
  @override void didUpdateWidget(AsyncBadgeRow old) { super.didUpdateWidget(old); if (old.userId != widget.userId) _load(); }

  Future<void> _load() async {
    if (_badgeCache.containsKey(widget.userId)) {
      if (mounted) setState(() => _badges = _badgeCache[widget.userId]);
      return;
    }
    try {
      final uid = widget.userId;
      final result = await _sb.rpc('get_user_badge_data', params: {'p_user_id': uid});
      if (result == null) return;
      final row = (result is List && result.isNotEmpty) ? Map<String, dynamic>.from(result.first as Map) : Map<String, dynamic>.from(result as Map);
      final merged = <String, dynamic>{
        'user_id': uid, 'admin_role': row['admin_role'], 'signup_rank': (row['signup_rank'] as num?)?.toInt() ?? 999999,
        'college_status': row['college_status'], 'uno_wins': (row['uno_wins'] as num?)?.toInt() ?? 0,
        'dsa_wins': (row['dsa_wins'] as num?)?.toInt() ?? 0, 'post_count': (row['post_count'] as num?)?.toInt() ?? 0,
        'max_post_likes': (row['max_post_likes'] as num?)?.toInt() ?? 0, 'friend_count': (row['friend_count'] as num?)?.toInt() ?? 0,
      };
      final badges = BadgeUtils.computeBadges(merged);
      _badgeCache[uid] = badges;
      if (mounted) setState(() => _badges = badges);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final badges = _badges?.take(widget.maxVisible).toList() ?? [];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: badges.map((b) {
        final isAnim = b.tier == BadgeTier.animated || b.tier == BadgeTier.diamond;
        return Padding(padding: const EdgeInsets.only(right: 4), child: Tooltip(
          message: '${b.label} · ${b.description}', preferBelow: false,
          child: isAnim ? _MiniAnimBadge(badge: b, size: widget.chipSize) : _MiniBadge(badge: b, size: widget.chipSize),
        ));
      }).toList(),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final BadgeModel badge; final double size;
  const _MiniBadge({required this.badge, required this.size});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [badge.primaryColor, badge.accentColor], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: badge.primaryColor.withOpacity(0.35), blurRadius: 4)]),
    child: Icon(badge.icon, color: Colors.white, size: size * 0.52),
  );
}

class _MiniAnimBadge extends StatefulWidget {
  final BadgeModel badge; final double size;
  const _MiniAnimBadge({required this.badge, required this.size});
  @override State<_MiniAnimBadge> createState() => _MiniAnimBadgeState();
}

class _MiniAnimBadgeState extends State<_MiniAnimBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true); _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final b = widget.badge;
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, __) {
        final v = _glow.value;
        return Container(
          width: widget.size, height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [b.primaryColor, b.accentColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: b.primaryColor.withOpacity(0.25 + 0.4 * v), blurRadius: 4 + 10 * v, spreadRadius: v)],
          ),
          child: Icon(b.icon, color: Colors.white, size: widget.size * 0.52),
        );
      },
    );
  }
}


// ══════════════════════════════════════════════════════════════════
// ██████████████  BUZZ BANNER SYSTEM  ██████████████████████████████
//
// Provides identity banners for Owner, College Admin, Branch Admin,
// and high-tier mission achievers. Appears on:
//   • Buzz post cards (PostBannerHeader)
//   • Own profile hero card (ProfileBannerWidget)
//   • User profile sliver header (_AnimatedSliverBanner) — defined
//     in user_profile_screen.dart which reads BannerRank + kBanners
//   • Nameplate under bio on both profile screens (BannerNameplate)
//
// ══════════════════════════════════════════════════════════════════



// ── Banner tier enum ──────────────────────────────────────────────
enum BannerRank {
  none,
  bronze,       // Tier 1 — earned by stats
  pioneer,      // Special — first 100 users (non-owner, non-admin)
  silver,       // Tier 2 — earned by normal users
  gold,         // Tier 3 — earned by normal users
  diamond,      // Tier 4 — earned by normal users
  branchAdmin,  // Branch admin
  collegeAdmin, // College admin
  founder,      // Owner / Founder
}

// ── Per-rank metadata ─────────────────────────────────────────────
class BannerMeta {
  final String title;
  final String subtitle;
  final String sigil;           // decorative character / emoji
  final Color primary;
  final Color secondary;
  final Color glow;
  final IconData icon;
  final bool animated;
  final List<Color> gradientStops;

  const BannerMeta({
    required this.title,
    required this.subtitle,
    required this.sigil,
    required this.primary,
    required this.secondary,
    required this.glow,
    required this.icon,
    required this.gradientStops,
    this.animated = false,
  });
}

// ── Rank → metadata map ───────────────────────────────────────────
const kBanners = <BannerRank, BannerMeta>{
  BannerRank.founder: BannerMeta(
    title: 'FOUNDER',
    subtitle: 'CAMPUSMYTRA',
    sigil: '♔',
    primary:   Color(0xFFFFB800),
    secondary: Color(0xFF1A0800),
    glow:      Color(0xFFFFB800),
    icon: Icons.auto_awesome,
    animated: true,
    gradientStops: [
      Color(0xFF0D0500),
      Color(0xFF5C2800),
      Color(0xFFB86800),
      Color(0xFFFFD700),
    ],
  ),
  BannerRank.collegeAdmin: BannerMeta(
    title: 'COLLEGE ADMIN',
    subtitle: 'ADMIN',
    sigil: '🛡',
    primary:   Color(0xFF818CF8),
    secondary: Color(0xFF060620),
    glow:      Color(0xFF818CF8),
    icon: Icons.shield_rounded,
    animated: true,
    gradientStops: [
      Color(0xFF060620),
      Color(0xFF1E1560),
      Color(0xFF4F46E5),
      Color(0xFFA5B4FC),
    ],
  ),
  BannerRank.branchAdmin: BannerMeta(
    title: 'BRANCH ADMIN',
    subtitle: 'ADMIN',
    sigil: '⚖',
    primary:   Color(0xFF00B8A3),
    secondary: Color(0xFF001210),
    glow:      Color(0xFF00B8A3),
    icon: Icons.balance_rounded,
    animated: false,
    gradientStops: [
      Color(0xFF001210),
      Color(0xFF003D36),
      Color(0xFF007A6E),
      Color(0xFF00D9C8),
    ],
  ),
  BannerRank.diamond: BannerMeta(
    title: 'DIAMOND',
    subtitle: 'ELITE · CAMPUS LEGEND',
    sigil: '💎',
    primary:   Color(0xFFE879F9),
    secondary: Color(0xFF0A0018),
    glow:      Color(0xFFE879F9),
    icon: Icons.diamond_rounded,
    animated: true,
    gradientStops: [
      Color(0xFF0A0018),
      Color(0xFF3B0764),
      Color(0xFF7C3AED),
      Color(0xFFF0ABFC),
    ],
  ),
  BannerRank.gold: BannerMeta(
    title: 'GOLD',
    subtitle: 'VETERAN · CAMPUS FORCE',
    sigil: '★',
    primary:   Color(0xFFFFB800),
    secondary: Color(0xFF150A00),
    glow:      Color(0xFFFFB800),
    icon: Icons.star_rounded,
    animated: false,
    gradientStops: [
      Color(0xFF150A00),
      Color(0xFF4A2000),
      Color(0xFFB45309),
      Color(0xFFFDE68A),
    ],
  ),
  BannerRank.silver: BannerMeta(
    title: 'SILVER',
    subtitle: 'RISING · MAKING NOISE',
    sigil: '◈',
    primary:   Color(0xFFCBD5E1),
    secondary: Color(0xFF0F172A),
    glow:      Color(0xFF94A3B8),
    icon: Icons.shield_outlined,
    animated: false,
    gradientStops: [
      Color(0xFF0F172A),
      Color(0xFF1E293B),
      Color(0xFF475569),
      Color(0xFFCBD5E1),
    ],
  ),
  BannerRank.bronze: BannerMeta(
    title: 'BRONZE',
    subtitle: 'PROVEN · MAKING MOVES',
    sigil: '◆',
    primary:   Color(0xFFCD7F32),
    secondary: Color(0xFF100800),
    glow:      Color(0xFFCD7F32),
    icon: Icons.hexagon_outlined,
    animated: false,
    gradientStops: [
      Color(0xFF100800),
      Color(0xFF2D1500),
      Color(0xFF7C3D0E),
      Color(0xFFCD7F32),
    ],
  ),
  BannerRank.pioneer: BannerMeta(
    title: 'PIONEER',
    subtitle: 'EARLY ACCESS · TOP 100',
    sigil: '🚀',
    primary:   Color(0xFF34D399),
    secondary: Color(0xFF001A0D),
    glow:      Color(0xFF10B981),
    icon: Icons.rocket_launch_rounded,
    animated: true,
    gradientStops: [
      Color(0xFF001A0D),
      Color(0xFF064E3B),
      Color(0xFF059669),
      Color(0xFF6EE7B7),
    ],
  ),
};

// ── Resolver: profile map → BannerRank ───────────────────────────
// Banner mission thresholds (harder than badge missions):
//   BRONZE  : unoWins≥50  OR dsaWins≥50  OR postCount≥50  OR friendCount≥50
//   SILVER  : unoWins≥100 OR dsaWins≥100 OR postCount≥150 OR friendCount≥75  OR maxLikes≥100
//   GOLD    : unoWins≥200 OR dsaWins≥200 OR postCount≥300 OR friendCount≥150 OR maxLikes≥300 OR totalWins≥300
//   DIAMOND : unoWins≥350 OR dsaWins≥350 OR (totalWins≥500 AND postCount≥300 AND friendCount≥150)
BannerRank computeBannerRank(Map<String, dynamic> profile) {
  int toInt(String k) => (profile[k] as num?)?.toInt() ?? 0;

  final userId      = profile['user_id']?.toString() ?? '';
  final adminRole   = profile['admin_role']?.toString();
  final signupRank  = (profile['signup_rank'] as num?)?.toInt() ?? 999999;
  final unoWins     = toInt('uno_wins');
  final dsaWins     = toInt('dsa_wins');
  final postCount   = toInt('post_count');
  final maxLikes    = toInt('max_post_likes');
  final friendCount = toInt('friend_count');
  final totalWins   = unoWins + dsaWins;

  // Role-based ranks (always override earned ranks)
  if (userId == kOwnerUserId)  return BannerRank.founder;
  if (adminRole == 'college')  return BannerRank.collegeAdmin;
  if (adminRole == 'branch')   return BannerRank.branchAdmin;

  // DIAMOND — requires extreme dedication across multiple areas
  if ((unoWins >= 350 || dsaWins >= 350) ||
      (totalWins >= 500 && postCount >= 300 && friendCount >= 150)) {
    return BannerRank.diamond;
  }

  // GOLD — veteran-level in at least one area
  if (unoWins >= 200 || dsaWins >= 200 ||
      postCount >= 300 || friendCount >= 150 ||
      maxLikes >= 300 || totalWins >= 300) {
    return BannerRank.gold;
  }

  // SILVER — consistent grinder
  if (unoWins >= 100 || dsaWins >= 100 ||
      postCount >= 150 || friendCount >= 75 || maxLikes >= 100) {
    return BannerRank.silver;
  }

  // BRONZE — shown up and proven it via stats
  if (unoWins >= 50 || dsaWins >= 50 ||
      postCount >= 50 || friendCount >= 50) {
    return BannerRank.bronze;
  }

  // PIONEER — first 100 users (non-owner, non-admin)
  if (signupRank <= 100) {
    return BannerRank.pioneer;
  }

  return BannerRank.none;
}

/// Returns all banner ranks a user has earned/qualifies for (for showcase picker).
/// Excludes BannerRank.none.
List<BannerRank> computeAvailableBanners(Map<String, dynamic> profile) {
  int toInt(String k) => (profile[k] as num?)?.toInt() ?? 0;

  final userId      = profile['user_id']?.toString() ?? '';
  final adminRole   = profile['admin_role']?.toString();
  final signupRank  = (profile['signup_rank'] as num?)?.toInt() ?? 999999;
  final unoWins     = toInt('uno_wins');
  final dsaWins     = toInt('dsa_wins');
  final postCount   = toInt('post_count');
  final maxLikes    = toInt('max_post_likes');
  final friendCount = toInt('friend_count');
  final totalWins   = unoWins + dsaWins;

  final available = <BannerRank>[];

  if (userId == kOwnerUserId)        available.add(BannerRank.founder);
  if (adminRole == 'college')        available.add(BannerRank.collegeAdmin);
  if (adminRole == 'branch')         available.add(BannerRank.branchAdmin);
  if (signupRank <= 100 && userId != kOwnerUserId) available.add(BannerRank.pioneer);
  if (unoWins >= 50 || dsaWins >= 50 || postCount >= 50 || friendCount >= 50) available.add(BannerRank.bronze);
  if (unoWins >= 100 || dsaWins >= 100 || postCount >= 150 || friendCount >= 75 || maxLikes >= 100) available.add(BannerRank.silver);
  if (unoWins >= 200 || dsaWins >= 200 || postCount >= 300 || friendCount >= 150 || maxLikes >= 300 || totalWins >= 300) available.add(BannerRank.gold);
  if ((unoWins >= 350 || dsaWins >= 350) || (totalWins >= 500 && postCount >= 300 && friendCount >= 150)) available.add(BannerRank.diamond);

  return available;
}

// ══════════════════════════════════════════════════════════════════
// PostBannerHeader
// The strip shown at the very top of a Buzz card when the poster
// has an active banner rank.  For anonymous posts → thin accent line.
// ══════════════════════════════════════════════════════════════════
class PostBannerHeader extends StatefulWidget {
  final BannerRank bannerRank;
  final Color fallbackAccent;   // used for the thin accent line

  const PostBannerHeader({
    super.key,
    required this.bannerRank,
    required this.fallbackAccent,
  });

  @override
  State<PostBannerHeader> createState() => _PostBannerHeaderState();
}

class _PostBannerHeaderState extends State<PostBannerHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    final meta = kBanners[widget.bannerRank];
    if (meta != null && meta.animated) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 0.55;
    }
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.bannerRank == BannerRank.none) {
      // ── Thin accent line for ordinary posts ──
      return Container(
        height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            widget.fallbackAccent.withOpacity(0),
            widget.fallbackAccent.withOpacity(0.5),
            widget.fallbackAccent.withOpacity(0),
          ]),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
      );
    }

    final meta = kBanners[widget.bannerRank]!;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final v = _anim.value;
        return _buildBanner(meta, v, context);
      },
    );
  }

  Widget _buildBanner(BannerMeta meta, double v, BuildContext context) {
    final rank = widget.bannerRank;

    return Container(
      height: rank == BannerRank.founder ? 50
            : rank == BannerRank.collegeAdmin ? 46
            : rank == BannerRank.branchAdmin ? 42
            : 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            meta.gradientStops[0],
            Color.lerp(meta.gradientStops[1], meta.gradientStops[2], 0.2 + 0.5 * v)!,
            meta.gradientStops[3],
          ],
          stops: const [0.0, 0.45, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: meta.animated ? [
          BoxShadow(
            color: meta.glow.withOpacity(0.18 + 0.22 * v),
            blurRadius: 10 + 10 * v,
            spreadRadius: v * 0.8,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      child: Stack(children: [
        // ── Subtle pattern overlay ──
        Positioned.fill(child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: CustomPaint(painter: _BannerPatternPainter(rank: rank, v: v)),
        )),
        // ── Content ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            // Sigil icon circle
            Container(
              width: rank == BannerRank.founder ? 32 : 26,
              height: rank == BannerRank.founder ? 32 : 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    meta.primary,
                    Color.lerp(meta.primary, Colors.white, 0.15 + 0.15 * v)!,
                  ],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                boxShadow: meta.animated ? [
                  BoxShadow(
                    color: meta.primary.withOpacity(0.45 + 0.3 * v),
                    blurRadius: 6 + 8 * v,
                    spreadRadius: v * 0.5,
                  ),
                ] : [
                  BoxShadow(color: meta.primary.withOpacity(0.3), blurRadius: 6),
                ],
              ),
              child: Center(child: rank == BannerRank.founder
                ? Text(meta.sigil,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.text(context),
                      shadows: meta.animated ? [Shadow(
                        color: Colors.white.withOpacity(0.5 * v),
                        blurRadius: 6 * v,
                      )] : null,
                    ))
                : Icon(meta.icon, color: AppColors.text(context),
                    size: rank == BannerRank.branchAdmin ? 13 : 14),
              ),
            ),
            const SizedBox(width: 10),
            // Title + subtitle
            Expanded(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title with gradient text for animated ranks
                if (meta.animated)
                  ShaderMask(
                    shaderCallback: (b) => LinearGradient(
                      colors: [
                        meta.primary,
                        Color.lerp(meta.primary, Colors.white, 0.25 + 0.25 * v)!,
                      ],
                    ).createShader(b),
                    child: Text(meta.title,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: rank == BannerRank.founder ? 12 : 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: rank == BannerRank.founder ? 3.5 : 2.5,
                      )),
                  )
                else
                  Text(meta.title,
                    style: TextStyle(
                      color: meta.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    )),
                Text(meta.subtitle,
                  style: TextStyle(
                    color: meta.primary.withOpacity(0.55 + 0.2 * v),
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  )),
              ],
            )),
            // Right decorative sigil
            _RightDecoration(rank: rank, meta: meta, v: v),
            const SizedBox(width: 6),
          ]),
        ),
      ]),
    );
  }
}

// ── Right-side decoration per rank ───────────────────────────────
class _RightDecoration extends StatelessWidget {
  final BannerRank rank;
  final BannerMeta meta;
  final double v;
  const _RightDecoration({required this.rank, required this.meta, required this.v});

  @override
  Widget build(BuildContext context) {
    switch (rank) {
      case BannerRank.founder:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Text('★',
            style: TextStyle(
              color: meta.primary.withOpacity(0.3 + 0.5 * v), fontSize: 9)),
          const SizedBox(width: 2),
          Text('♔',
            style: TextStyle(
              color: meta.primary.withOpacity(0.4 + 0.4 * v), fontSize: 16)),
          const SizedBox(width: 2),
          Text('★',
            style: TextStyle(
              color: meta.primary.withOpacity(0.3 + 0.5 * v), fontSize: 9)),
        ]);
      case BannerRank.collegeAdmin:
        return Opacity(
          opacity: 0.3 + 0.4 * v,
          child: Text('⬡ ⬡',
            style: TextStyle(color: Color(0xFF818CF8), fontSize: 9, letterSpacing: 2)),
        );
      case BannerRank.branchAdmin:
        return Opacity(
          opacity: 0.45,
          child: Text('⚖', style: TextStyle(color: Color(0xFF00B8A3), fontSize: 14)),
        );
      case BannerRank.diamond:
        return Text('💎',
          style: TextStyle(fontSize: 14,
            shadows: [Shadow(color: const Color(0xFFE879F9).withOpacity(0.5 + 0.4 * v), blurRadius: 8 * v)]));
      case BannerRank.gold:
        return Text('★',
          style: TextStyle(color: const Color(0xFFFFB800).withOpacity(0.5 + 0.4 * v), fontSize: 15,
            shadows: [Shadow(color: const Color(0xFFFFB800).withOpacity(0.3 * v), blurRadius: 6 * v)]));
      case BannerRank.silver:
        return Text('◈',
          style: TextStyle(color: const Color(0xFFCBD5E1).withOpacity(0.5 + 0.3 * v), fontSize: 14));
      case BannerRank.bronze:
        return Text('◆',
          style: TextStyle(color: const Color(0xFFCD7F32).withOpacity(0.5 + 0.3 * v), fontSize: 13));
      case BannerRank.pioneer:
        return Text('🚀', style: const TextStyle(fontSize: 12));
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Custom painter: subtle background pattern per rank ─────────────
class _BannerPatternPainter extends CustomPainter {
  final BannerRank rank;
  final double v;
  const _BannerPatternPainter({required this.rank, required this.v});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04 + 0.03 * v)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    switch (rank) {
      case BannerRank.founder:
        // Diagonal hatching
        for (double x = -size.height; x < size.width + size.height; x += 20) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
        }
        // Diamond accents
        _drawDiamond(canvas, Offset(size.width * 0.82, size.height * 0.5), 5,
          Paint()..color = Colors.white.withOpacity(0.07 + 0.06 * v)..style = PaintingStyle.fill);
        _drawDiamond(canvas, Offset(size.width * 0.14, size.height * 0.5), 3,
          Paint()..color = Colors.white.withOpacity(0.04 + 0.04 * v)..style = PaintingStyle.fill);
        break;
      case BannerRank.collegeAdmin:
        // Small hex rings
        final hp = Paint()
          ..color = Colors.white.withOpacity(0.05 + 0.04 * v)
          ..style = PaintingStyle.stroke..strokeWidth = 0.8;
        _drawHexRing(canvas, Offset(size.width * 0.9, size.height * 0.5), 14, hp);
        _drawHexRing(canvas, Offset(size.width * 0.85, size.height * 0.5), 22, hp);
        break;
      case BannerRank.branchAdmin:
        // Horizontal circuit lines
        for (double y = size.height * 0.3; y < size.height; y += size.height * 0.4) {
          canvas.drawLine(
            Offset(size.width * 0.6, y),
            Offset(size.width * 0.95, y),
            paint..strokeWidth = 0.6,
          );
        }
        break;
      case BannerRank.diamond:
        // Dense starfield
        final starDots = [
          [0.68, 0.2], [0.74, 0.7], [0.80, 0.35], [0.86, 0.65],
          [0.92, 0.25], [0.96, 0.55], [0.72, 0.5], [0.88, 0.8],
        ];
        for (final d in starDots) {
          canvas.drawCircle(
            Offset(size.width * d[0], size.height * d[1]),
            1.2 + 0.8 * v,
            Paint()..color = Colors.white.withOpacity(0.08 + 0.12 * v),
          );
        }
        break;
      case BannerRank.gold:
        // Diagonal double-hatch
        for (double x = -size.height; x < size.width + size.height; x += 32) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height),
            paint..strokeWidth = 0.5);
          canvas.drawLine(Offset(x + 8, 0), Offset(x + 8 + size.height, size.height),
            paint..strokeWidth = 0.3);
        }
        break;
      case BannerRank.silver:
        // Horizontal dashes
        for (double y = size.height * 0.25; y < size.height; y += size.height * 0.25) {
          for (double x = size.width * 0.65; x < size.width * 0.98; x += 10) {
            canvas.drawLine(
              Offset(x, y), Offset(x + 5, y),
              paint..strokeWidth = 0.5,
            );
          }
        }
        break;
      case BannerRank.bronze:
        // Small diamond accents
        _drawDiamond(canvas, Offset(size.width * 0.84, size.height * 0.5), 4,
          Paint()..color = Colors.white.withOpacity(0.06 + 0.04 * v)..style = PaintingStyle.fill);
        _drawDiamond(canvas, Offset(size.width * 0.92, size.height * 0.3), 2.5,
          Paint()..color = Colors.white.withOpacity(0.04 + 0.03 * v)..style = PaintingStyle.fill);
        break;
      default:
        break;
    }
  }

  void _drawDiamond(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.6, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r * 0.6, c.dy)
      ..close();
    canvas.drawPath(path, p);
  }

  void _drawHexRing(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final a = (i * 60 - 30) * math.pi / 180;
      final x = c.dx + r * math.cos(a);
      final y = c.dy + r * math.sin(a);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_BannerPatternPainter o) => o.v != v || o.rank != rank;
}

// ══════════════════════════════════════════════════════════════════
// ProfileBannerWidget
// Wraps the profile HeroCard and applies a banner-themed gradient
// background instead of the user's regular colour gradient.
// ══════════════════════════════════════════════════════════════════
class ProfileBannerWidget extends StatefulWidget {
  final BannerRank bannerRank;
  final List<Color> fallbackGradient;
  final Widget child;

  const ProfileBannerWidget({
    super.key,
    required this.bannerRank,
    required this.fallbackGradient,
    required this.child,
  });

  @override
  State<ProfileBannerWidget> createState() => _ProfileBannerWidgetState();
}

class _ProfileBannerWidgetState extends State<ProfileBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    final meta = kBanners[widget.bannerRank];
    if (meta != null && meta.animated) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 0.55;
    }
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.bannerRank == BannerRank.none) {
      return _plainCard(context);
    }

    final meta = kBanners[widget.bannerRank]!;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final v = _anim.value;
        final rank = widget.bannerRank;
        final borderOpacity = 0.4 + 0.45 * v;
        final shadowBlur    = 22.0 + 18 * v;
        final shadowSpread  = v * 1.5;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: rank == BannerRank.founder
                  ? [
                      meta.gradientStops[0],
                      Color.lerp(meta.gradientStops[1], meta.gradientStops[2], 0.3 + 0.4 * v)!,
                      meta.gradientStops[3],
                    ]
                  : [
                      meta.gradientStops[0],
                      Color.lerp(meta.gradientStops[1], meta.gradientStops[2], 0.2 + 0.5 * v)!,
                      meta.gradientStops[3],
                    ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: meta.primary.withOpacity(borderOpacity),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: meta.glow.withOpacity(0.2 + 0.3 * v),
                blurRadius: shadowBlur,
                spreadRadius: shadowSpread,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(children: [
            // ── Rich background pattern ──
            Positioned.fill(child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: CustomPaint(
                painter: _ProfileBannerBgPainter(rank: rank, v: v),
              ),
            )),
            // ── Rank crown/sigil in top-right ──
            Positioned(top: 16, right: 20,
              child: _ProfileRankSigil(rank: rank, meta: meta, v: v)),
            // ── User content ──
            child!,
          ]),
        );
      },
      child: widget.child,
    );
  }

  Widget _plainCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.fallbackGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: widget.fallbackGradient.length >= 3
              ? const [0.0, 0.5, 1.0] : null,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(
          color: widget.fallbackGradient[0].withOpacity(0.45),
          blurRadius: 24,
          offset: const Offset(0, 10),
        )],
      ),
      child: Stack(children: [
        Positioned.fill(child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: CustomPaint(painter: _NeutralBgPainter()),
        )),
        widget.child,
      ]),
    );
  }
}

// ── Profile card rank sigil (corner decoration) ──────────────────
class _ProfileRankSigil extends StatelessWidget {
  final BannerRank rank;
  final BannerMeta meta;
  final double v;
  const _ProfileRankSigil({required this.rank, required this.meta, required this.v});

  @override
  Widget build(BuildContext context) {
    switch (rank) {
      case BannerRank.founder:
        return Column(children: [
          Text('★', style: TextStyle(color: meta.primary.withOpacity(0.4 + 0.4 * v), fontSize: 9)),
          Text('♔', style: TextStyle(color: meta.primary.withOpacity(0.5 + 0.4 * v), fontSize: 26,
            shadows: [Shadow(color: meta.primary.withOpacity(0.4 * v), blurRadius: 12 * v)])),
          Text('★', style: TextStyle(color: meta.primary.withOpacity(0.4 + 0.4 * v), fontSize: 9)),
        ]);
      case BannerRank.collegeAdmin:
        return Opacity(
          opacity: 0.3 + 0.4 * v,
          child: Column(children: [
            Text('⬡', style: TextStyle(color: meta.primary, fontSize: 18)),
            Text('⬡', style: TextStyle(color: meta.primary, fontSize: 12)),
          ]),
        );
      case BannerRank.branchAdmin:
        return Opacity(
          opacity: 0.4,
          child: Text('⚖', style: TextStyle(color: meta.primary, fontSize: 22)),
        );
      case BannerRank.diamond:
        return Text('💎', style: TextStyle(fontSize: 22,
          shadows: [Shadow(color: meta.primary.withOpacity(0.5 + 0.4 * v), blurRadius: 12 * v)]));
      case BannerRank.gold:
        return Text('★', style: TextStyle(color: meta.primary.withOpacity(0.6 + 0.3 * v), fontSize: 22,
          shadows: [Shadow(color: meta.primary.withOpacity(0.4 * v), blurRadius: 8 * v)]));
      case BannerRank.silver:
        return Text('◈', style: TextStyle(color: meta.primary.withOpacity(0.55 + 0.3 * v), fontSize: 20));
      case BannerRank.bronze:
        return Text('◆', style: TextStyle(color: meta.primary.withOpacity(0.5 + 0.3 * v), fontSize: 18));
      case BannerRank.pioneer:
        return Text('🚀', style: TextStyle(fontSize: 22,
          shadows: [Shadow(color: const Color(0xFF10B981).withOpacity(0.4 + 0.3 * v), blurRadius: 10 * v)]));
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Background painter for ProfileBannerWidget ────────────────────
class _ProfileBannerBgPainter extends CustomPainter {
  final BannerRank rank;
  final double v;
  const _ProfileBannerBgPainter({required this.rank, required this.v});

  @override
  void paint(Canvas canvas, Size size) {
    switch (rank) {
      case BannerRank.founder:
        // Diagonal gold hatch lines
        final p = Paint()
          ..color = Colors.white.withOpacity(0.04 + 0.03 * v)
          ..style = PaintingStyle.stroke..strokeWidth = 0.8;
        for (double x = -size.height; x < size.width + size.height; x += 28) {
          canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
        }
        // Gold shimmer orb
        final op = Paint()..shader = RadialGradient(
          colors: [const Color(0xFFFFD700).withOpacity(0.12 + 0.1 * v), Colors.transparent],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.85, size.height * 0.2), radius: 120));
        canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.2), 120, op);
        // Large crown watermark
        _drawDiamond(canvas, Offset(size.width * 0.08, size.height * 0.82), 22,
          Paint()..color = Colors.white.withOpacity(0.04 + 0.04 * v)..style = PaintingStyle.fill);
        break;

      case BannerRank.collegeAdmin:
        // Hex grid in top-right
        final hp = Paint()
          ..color = Colors.white.withOpacity(0.05 + 0.04 * v)
          ..style = PaintingStyle.stroke..strokeWidth = 0.9;
        for (int row = 0; row < 3; row++) {
          for (int col = 0; col < 3; col++) {
            final cx = size.width * 0.82 + col * 28.0;
            final cy = size.height * 0.12 + row * 26.0;
            _drawHex(canvas, Offset(cx, cy), 12, hp);
          }
        }
        // Indigo glow orb
        final gp = Paint()..shader = RadialGradient(
          colors: [const Color(0xFF4F46E5).withOpacity(0.15 + 0.12 * v), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(size.width * 0.1, size.height * 0.15), radius: 100));
        canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.15), 100, gp);
        break;

      case BannerRank.branchAdmin:
        // Circuit-board horizontal lines
        final cp = Paint()
          ..color = Colors.white.withOpacity(0.04)
          ..style = PaintingStyle.stroke..strokeWidth = 0.7;
        for (double y = 0; y < size.height; y += size.height / 4) {
          canvas.drawLine(Offset(size.width * 0.55, y), Offset(size.width, y), cp);
        }
        break;

      case BannerRank.none:
        // Star-field dots
        final stars = [[0.78, 0.1], [0.86, 0.5], [0.92, 0.8], [0.72, 0.7], [0.96, 0.3]];
        for (final s in stars) {
          canvas.drawCircle(
            Offset(size.width * s[0], size.height * s[1]), 1.8,
            Paint()..color = Colors.white.withOpacity(0.1 + 0.15 * v));
        }
        // Purple glow
        canvas.drawCircle(
          Offset(size.width * 0.88, size.height * 0.4), 80,
          Paint()..shader = RadialGradient(
            colors: [const Color(0xFFE879F9).withOpacity(0.12 + 0.1 * v), Colors.transparent],
          ).createShader(Rect.fromCircle(
            center: Offset(size.width * 0.88, size.height * 0.4), radius: 80)));
        break;

      default:
        // Default: simple highlight orb
        final hp = Paint()..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.06 + 0.04 * v), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(size.width * 0.85, size.height * 0.15), radius: 80));
        canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 80, hp);
        break;
    }
  }

  void _drawDiamond(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.6, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r * 0.6, c.dy)
      ..close();
    canvas.drawPath(path, p);
  }

  void _drawHex(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final a = (i * 60 - 30) * math.pi / 180;
      final x = c.dx + r * math.cos(a);
      final y = c.dy + r * math.sin(a);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ProfileBannerBgPainter o) => o.v != v || o.rank != rank;
}

// ── _HeroBgPainter (kept here for ProfileBannerWidget._plainCard) ─
// (Already defined in profile_screen.dart — duplicate removed,
//  profile_screen will keep its own copy.)

// ══════════════════════════════════════════════════════════════════
// BannerNameplate
// A full-width decorative nameplate shown below the user's badges /
// bio on both profile screens.  Only rendered when rank != none.
// ══════════════════════════════════════════════════════════════════
class BannerNameplate extends StatefulWidget {
  final BannerRank bannerRank;
  const BannerNameplate({super.key, required this.bannerRank});

  @override
  State<BannerNameplate> createState() => _BannerNameplateState();
}

class _BannerNameplateState extends State<BannerNameplate>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
    final meta = kBanners[widget.bannerRank];
    if (meta != null && meta.animated) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 0.55;
    }
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.bannerRank == BannerRank.none) return const SizedBox.shrink();
    final meta = kBanners[widget.bannerRank]!;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final v = _anim.value;
        return Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                meta.gradientStops[0],
                Color.lerp(meta.gradientStops[1], meta.gradientStops[2], 0.3 + 0.4 * v)!,
                meta.gradientStops[3],
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: meta.primary.withOpacity(0.4 + 0.35 * v),
              width: 1.3,
            ),
            boxShadow: meta.animated ? [
              BoxShadow(
                color: meta.glow.withOpacity(0.18 + 0.22 * v),
                blurRadius: 14 + 12 * v,
                spreadRadius: v * 1.2,
              ),
            ] : [
              BoxShadow(
                color: meta.glow.withOpacity(0.12),
                blurRadius: 10,
              ),
            ],
          ),
          child: Stack(children: [
            Positioned.fill(child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(painter: _BannerPatternPainter(rank: widget.bannerRank, v: v)),
            )),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                // Icon orb
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        meta.primary,
                        Color.lerp(meta.primary, Colors.white, 0.2 + 0.2 * v)!,
                      ],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    boxShadow: [BoxShadow(
                      color: meta.primary.withOpacity(0.4 + 0.3 * v),
                      blurRadius: 10 + 8 * v,
                    )],
                  ),
                  child: Center(
                    child: widget.bannerRank == BannerRank.founder
                      ? Text(meta.sigil,
                          style: TextStyle(
                            fontSize: 18, color: AppColors.text(context),
                            shadows: [Shadow(color: Colors.white.withOpacity(0.4 * v), blurRadius: 6 * v)]))
                      : Icon(meta.icon, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (meta.animated)
                      ShaderMask(
                        shaderCallback: (b) => LinearGradient(
                          colors: [
                            meta.primary,
                            Color.lerp(meta.primary, Colors.white, 0.25 + 0.25 * v)!,
                          ],
                        ).createShader(b),
                        child: Text(meta.title,
                          style: TextStyle(
                            color: Colors.white, fontSize: 14,
                            fontWeight: FontWeight.w900, letterSpacing: 3.0,
                          )),
                      )
                    else
                      Text(meta.title,
                        style: TextStyle(
                          color: meta.primary, fontSize: 14,
                          fontWeight: FontWeight.w900, letterSpacing: 2.5,
                        )),
                    const SizedBox(height: 2),
                    Text(meta.subtitle,
                      style: TextStyle(
                        color: meta.primary.withOpacity(0.55 + 0.2 * v),
                        fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5,
                      )),
                  ],
                )),
                // Right sigil
                _RightDecoration(rank: widget.bannerRank, meta: meta, v: v),
                const SizedBox(width: 6),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ── Neutral background painter (used by ProfileBannerWidget._plainCard) ──
class _NeutralBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 80, paint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), 60, paint);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.8), 40, paint);
  }
  @override bool shouldRepaint(_) => false;
}