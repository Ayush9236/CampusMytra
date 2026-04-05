import '../../settings/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/dsa_service.dart';

class DsaLeaderboardScreen extends StatefulWidget {
  const DsaLeaderboardScreen({Key? key}) : super(key: key);

  @override
  State<DsaLeaderboardScreen> createState() => _DsaLeaderboardScreenState();
}

class _DsaLeaderboardScreenState extends State<DsaLeaderboardScreen> {
  final supabase = Supabase.instance.client;
  String? _myId;

  List<Map<String, dynamic>> _board = [];
  bool _loading = true;
  String? _error;

  static const _kPurple = Color(0xFF6C63FF);
  static const _kTeal   = Color(0xFF00B8A3);
  static const _kAmber  = Color(0xFFFFB800);

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await DsaService.fetchDsaLeaderboard();
      if (mounted) setState(() { _board = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Helpers ─────────────────────────────────────────

  String _formatTime(dynamic seconds) {
    final s = (seconds as num?)?.toInt() ?? 0;
    if (s <= 0) return 'N/A';
    final m = s ~/ 60;
    final rem = s % 60;
    return m > 0 ? '${m}m ${rem}s' : '${rem}s';
  }

  Color _scoreColor(int score) {
    if (score >= 700) return const Color(0xFFFFD700);
    if (score >= 450) return const Color(0xFF818CF8);
    if (score >= 200) return _kTeal;
    return AppColors.textHint(context);
  }

  String _scoreTier(int score) {
    if (score >= 700) return 'Elite';
    if (score >= 450) return 'Advanced';
    if (score >= 200) return 'Rising';
    return 'Beginner';
  }

  // ── Build ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Find current user's rank
    int myRank = -1;
    Map<String, dynamic>? myEntry;
    for (int i = 0; i < _board.length; i++) {
      if (_board[i]['user_id']?.toString() == _myId) {
        myRank  = i + 1;
        myEntry = _board[i];
        break;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.background(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppColors.icon(context), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DSA Rankings',
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.bold, fontSize: 18)),
          Text('Efficiency = Win Rate + Speed + Breadth',
              style: TextStyle(color: AppColors.textHint(context), fontSize: 10)),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: AppColors.textHint(context), size: 20),
            onPressed: _showFormulaSheet,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _kPurple))
          : _error != null
              ? _buildError(_error!)
              : _board.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _kPurple,
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      // My rank card
                      if (myEntry != null) ...[
                        _buildMyRankCard(myRank, myEntry),
                        const SizedBox(height: 20),
                      ],

                      // Podium (top 3)
                      if (_board.length >= 2) ...[
                        const _SectionLabel('TOP PLAYERS'),
                        const SizedBox(height: 12),
                        _buildPodium(),
                        const SizedBox(height: 24),
                      ],

                      // Full ranked list
                      const _SectionLabel('ALL RANKINGS'),
                      const SizedBox(height: 12),
                      ..._board.asMap().entries.map((e) =>
                          _buildRankRow(e.key + 1, e.value)),
                    ],
                  ),
                ),
    );
  }

  // ── My rank card ─────────────────────────────────────

  Widget _buildMyRankCard(int rank, Map<String, dynamic> entry) {
    final score = (entry['efficiency_score'] as num?)?.toInt() ?? 0;
    final color = _scoreColor(score);
    final tier  = _scoreTier(score);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPurple.withOpacity(0.25), color.withOpacity(0.12)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPurple.withOpacity(0.5), width: 1.5),
      ),
      child: Row(children: [
        // Rank badge
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: _kPurple.withOpacity(0.2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kPurple.withOpacity(0.5)),
          ),
          child: Center(child: Text('#$rank',
              style: TextStyle(color: AppColors.text(context),
                  fontWeight: FontWeight.w900, fontSize: 14))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('You', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(tier,
                  style: TextStyle(color: color, fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _MiniStat('${entry['win_rate']}%', 'Win Rate', _kTeal),
            const SizedBox(width: 12),
            _MiniStat(_formatTime(entry['avg_solve_seconds']), 'Avg Speed', _kAmber),
            const SizedBox(width: 12),
            _MiniStat('${entry['total_battles']}', 'Battles', AppColors.textHint(context)),
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$score',
              style: TextStyle(color: color,
                  fontSize: 28, fontWeight: FontWeight.w900)),
          Text('/ 1000', style: TextStyle(
              color: AppColors.textHint(context), fontSize: 10)),
        ]),
      ]),
    );
  }

  // ── Podium ───────────────────────────────────────────

  Widget _buildPodium() {
    final has3 = _board.length >= 3;
    final p1   = _board[0];
    final p2   = _board[1];
    final p3   = has3 ? _board[2] : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 2nd place
        Expanded(child: _buildPodiumCard(2, p2,
            const Color(0xFFC0C0C0), height: 134)),
        const SizedBox(width: 8),
        // 1st place — tallest
        Expanded(child: _buildPodiumCard(1, p1,
            const Color(0xFFFFD700), height: 148)),
        const SizedBox(width: 8),
        // 3rd place
        Expanded(child: p3 != null
            ? _buildPodiumCard(3, p3, const Color(0xFFCD7F32), height: 120)
            : const SizedBox()),
      ],
    );
  }

  Widget _buildPodiumCard(int rank, Map<String, dynamic> entry,
      Color medalColor, {required double height}) {
    final score   = (entry['efficiency_score'] as num?)?.toInt() ?? 0;
    final name    = entry['username']?.toString() ?? 'Unknown';
    final isMe    = entry['user_id']?.toString() == _myId;
    final medals  = {1: '🥇', 2: '🥈', 3: '🥉'};

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? _kPurple.withOpacity(0.6) : medalColor.withOpacity(0.35),
          width: isMe ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(
          color: medalColor.withOpacity(0.12),
          blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(medals[rank]!, style: TextStyle(
              fontSize: rank == 1 ? 28 : 22)),
          const SizedBox(height: 6),
          Text(
            isMe ? 'You' : (name.length > 10 ? '${name.substring(0, 9)}…' : name),
            style: TextStyle(color: AppColors.text(context),
                fontWeight: FontWeight.w700, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text('$score',
              style: TextStyle(color: medalColor,
                  fontWeight: FontWeight.w900,
                  fontSize: rank == 1 ? 18 : 14)),
          Text('pts', style: TextStyle(
              color: medalColor.withOpacity(0.6), fontSize: 9)),
        ],
      ),
    );
  }

  // ── Rank row ─────────────────────────────────────────

  Widget _buildRankRow(int rank, Map<String, dynamic> entry) {
    final score  = (entry['efficiency_score'] as num?)?.toInt() ?? 0;
    final name   = entry['username']?.toString() ?? 'Unknown';
    final isMe   = entry['user_id']?.toString() == _myId;
    final color  = _scoreColor(score);
    final medals = {1: '🥇', 2: '🥈', 3: '🥉'};

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? _kPurple.withOpacity(0.08) : AppColors.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? _kPurple.withOpacity(0.4)
              : AppColors.border(context),
        ),
      ),
      child: Row(children: [
        // Rank
        SizedBox(
          width: 36,
          child: Text(
            medals[rank] ?? '#$rank',
            style: TextStyle(
              color: rank <= 3 ? null : AppColors.textHint(context),
              fontSize: rank <= 3 ? 20 : 13,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 10),
        // Avatar
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isMe
                ? _kPurple.withOpacity(0.2)
                : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isMe ? _kPurple : color.withOpacity(0.3)),
          ),
          child: Center(child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: isMe ? Colors.white : color,
                fontWeight: FontWeight.w800, fontSize: 14),
          )),
        ),
        const SizedBox(width: 10),
        // Name + secondary stats
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            isMe ? '$name (You)' : name,
            style: TextStyle(
              color: isMe ? Colors.white : AppColors.text(context),
              fontWeight: FontWeight.w600, fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Row(children: [
            Text('${entry['win_rate']}% WR',
                style: TextStyle(color: AppColors.textHint(context), fontSize: 10)),
            const SizedBox(width: 8),
            Text(_formatTime(entry['avg_solve_seconds']),
                style: TextStyle(color: AppColors.textHint(context), fontSize: 10)),
            const SizedBox(width: 8),
            Text('${entry['total_battles']} battles',
                style: TextStyle(color: AppColors.textHint(context), fontSize: 10)),
          ]),
        ])),
        // Score
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$score',
              style: TextStyle(color: color,
                  fontSize: 20, fontWeight: FontWeight.w900)),
          Text('pts', style: TextStyle(
              color: color.withOpacity(0.5), fontSize: 9)),
        ]),
      ]),
    );
  }

  // ── Empty state ──────────────────────────────────────

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('🏆', style: TextStyle(fontSize: 52)),
      const SizedBox(height: 16),
      Text('No rankings yet',
          style: TextStyle(color: AppColors.text(context),
              fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text('Play battles to appear on the leaderboard',
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
    ]));
  }

  Widget _buildError(String error) {
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('⚠️', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        Text('Could not load rankings',
            style: TextStyle(color: AppColors.text(context),
                fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(error,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _load,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPurple,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Retry', style: TextStyle(color: AppColors.text(context))),
        ),
      ]),
    ));
  }

  // ── Formula info sheet ───────────────────────────────

  void _showFormulaSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border(context),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('Efficiency Score Formula',
              style: TextStyle(color: AppColors.text(context),
                  fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          _FormulaRow('Win Rate', '500 pts',
              'wins ÷ battles × 500', const Color(0xFFFFD700)),
          const SizedBox(height: 12),
          _FormulaRow('Speed', '300 pts',
              'faster avg solve time (cap 5 min)', _kTeal),
          const SizedBox(height: 12),
          _FormulaRow('Breadth', '200 pts',
              '10 pts per unique problem (max 20)', _kPurple),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Text(
              'Total: 1000 pts max\n'
              'Minimum 1 battle required to appear',
              style: TextStyle(color: AppColors.textHint(context),
                  fontSize: 12, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ── Helper widgets ───────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(color: AppColors.textHint(context), fontSize: 10,
          fontWeight: FontWeight.w800, letterSpacing: 2.5));
}

class _MiniStat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _MiniStat(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: TextStyle(color: color,
          fontSize: 12, fontWeight: FontWeight.w700)),
      Text(label, style: TextStyle(
          color: AppColors.textHint(context), fontSize: 9)),
    ],
  );
}

class _FormulaRow extends StatelessWidget {
  final String title, pts, desc;
  final Color color;
  const _FormulaRow(this.title, this.pts, this.desc, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 6, height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: TextStyle(
            color: AppColors.text(context), fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(width: 8),
        Text(pts, style: TextStyle(color: color,
            fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
      Text(desc, style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11)),
    ])),
  ]);
}
