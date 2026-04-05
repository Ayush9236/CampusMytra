import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class LeaderboardWidget extends StatefulWidget {
  const LeaderboardWidget({Key? key}) : super(key: key);

  @override
  State<LeaderboardWidget> createState() => _LeaderboardWidgetState();
}

class _LeaderboardWidgetState extends State<LeaderboardWidget> {
  List<Map<String, dynamic>> _topPlayers = [];
  bool _isLoading = true;
  int? _myRank;
  String? _myId;

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser?.id;
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    try {
      final data = await supabase
          .from('profiles')
          .select()
          .order('coins', ascending: false)
          .limit(10);

      if (_myId != null) {
        final myData = await supabase
            .from('profiles')
            .select('coins')
            .eq('id', _myId!)
            .single();

        final myCoins = myData['coins'] as int;

        final higherPlayers = await supabase
            .from('profiles')
            .select('id')
            .gt('coins', myCoins);

        _myRank = higherPlayers.length + 1;
      }

      setState(() {
        _topPlayers = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      print('Leaderboard error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_myRank != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.deepPurple, width: 2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emoji_events,
                            color: Colors.deepPurple),
                        const SizedBox(width: 8),
                        Text(
                          'Your Rank: #$_myRank',
                          style: const TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_topPlayers.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_topPlayers.length >= 2)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child:
                                _buildPodiumCard(_topPlayers[1], 2),
                          ),
                        if (_topPlayers.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child:
                                _buildPodiumCard(_topPlayers[0], 1),
                          ),
                        if (_topPlayers.length >= 3)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child:
                                _buildPodiumCard(_topPlayers[2], 3),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                if (_topPlayers.length > 3)
                  ...List.generate(
                    _topPlayers.length - 3,
                    (index) {
                      final player = _topPlayers[index + 3];
                      final rank = index + 4;
                      return _buildRankCard(player, rank);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPodiumCard(Map<String, dynamic> player, int rank) {
    final isMe = player['id'] == _myId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white70 : Colors.black54;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rank == 1 ? '🥇' : rank == 2 ? '🥈' : '🥉',
          style: TextStyle(fontSize: rank == 1 ? 48 : 40),
        ),
        const SizedBox(height: 8),
        Container(
          width: rank == 1 ? 95 : 80,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.deepPurple.withOpacity(0.15)
                : isDark ? Colors.grey.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMe ? Colors.deepPurple : isDark ? Colors.grey.withOpacity(0.3) : const Color(0xFFE0E0E0),
              width: isMe ? 3 : 1,
            ),
            boxShadow: isDark ? null : [
              BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 3))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: rank == 1 ? 22 : 18,
                backgroundColor: Colors.deepPurple.withOpacity(0.15),
                child: Text(
                  player['name'].toString()[0].toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: rank == 1 ? 18 : 14,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                player['name'].toString().split(' ')[0],
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 12),
              ),
              Text('${player['branch']}',
                style: TextStyle(color: subColor, fontSize: 10)),
              const SizedBox(height: 4),
              Text('${player['coins']} 🪙',
                style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRankCard(Map<String, dynamic> player, int rank) {
    final isMe = player['id'] == _myId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.deepPurple.withOpacity(0.1)
            : isDark ? Colors.grey.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Text('#$rank', style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Expanded(child: Text(player['name'], style: TextStyle(color: textColor))),
          Text('${player['coins']} 🪙', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
