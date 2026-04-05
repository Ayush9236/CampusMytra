import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dsa_problem.dart';

final supabase = Supabase.instance.client;

class DsaService {
  static const Map<String, Map<String, String>> languageConfig = {
    'Python':     {'language': 'python',     'version': '3.10.0'},
    'Java':       {'language': 'java',       'version': '15.0.2'},
    'C++':        {'language': 'c++',        'version': '10.2.0'},
    'JavaScript': {'language': 'javascript', 'version': '18.15.0'},
    'C':          {'language': 'c',          'version': '10.2.0'},
  };

  static Map<String, int> get languageIds => {
    'Python': 71, 'Java': 62, 'C++': 54, 'JavaScript': 63, 'C': 50,
  };

  // ============================================
  // FETCH PROBLEMS
  // ============================================

  static Future<List<DsaProblem>> fetchProblems({String? difficulty}) async {
    var query = supabase.from('dsa_problems').select();
    if (difficulty != null) {
      query = query.eq('difficulty', difficulty) as dynamic;
    }
    final data = await query;
    return (data as List).map((e) => DsaProblem.fromJson(e)).toList();
  }

  static Future<DsaProblem> fetchRandomProblem({
    String difficulty = 'easy',
    String? userId,
  }) async {
    // Fetch all problems of this difficulty
    final data = await supabase
        .from('dsa_problems')
        .select()
        .eq('difficulty', difficulty);
    final all = (data as List).map((e) => DsaProblem.fromJson(e)).toList();

    if (all.isEmpty) throw Exception('No $difficulty problems found');

    // If userId provided, exclude already-solved problems
    if (userId != null) {
      try {
        final solved = await supabase
            .from('user_solved_problems')
            .select('problem_id')
            .eq('user_id', userId);
        final solvedIds = (solved as List)
            .map((e) => e['problem_id'].toString())
            .toSet();
        final unsolved = all.where((p) => !solvedIds.contains(p.id)).toList();
        // If all solved, reset and give any problem (so game never breaks)
        final pool = unsolved.isNotEmpty ? unsolved : all;
        pool.shuffle();
        return pool.first;
      } catch (_) {
        // If table doesn't exist yet, fall through to random
      }
    }

    all.shuffle();
    return all.first;
  }

  // ============================================
  // SOLVED PROBLEMS TRACKING
  // ============================================

  static Future<void> markProblemSolved({
    required String userId,
    required String problemId,
    required String language,
  }) async {
    try {
      await supabase.from('user_solved_problems').upsert({
        'user_id':    userId,
        'problem_id': problemId,
        'language':   language,
        'solved_at':  DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,problem_id');
    } catch (_) {} // silently ignore if table doesn't exist yet
  }

  static Future<List<Map<String, dynamic>>> fetchSolvedProblems({
    required String userId,
  }) async {
    try {
      final data = await supabase
          .from('user_solved_problems')
          .select('problem_id, language, solved_at')
          .eq('user_id', userId)
          .order('solved_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  static Future<List<DsaProblem>> fetchAllProblems() async {
    final data = await supabase
        .from('dsa_problems')
        .select()
        .order('difficulty');
    return (data as List).map((e) => DsaProblem.fromJson(e)).toList();
  }

  static Future<DsaProblem?> fetchProblemById(String id) async {
    try {
      final data = await supabase
          .from('dsa_problems')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      return DsaProblem.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  // ============================================
  // MATCH HISTORY
  // ============================================

  static Future<List<Map<String, dynamic>>> fetchMatchHistory({
    required String userId,
    int limit = 30,
  }) async {
    try {
      // 1. Fetch finished rooms where user participated
      final rooms = await supabase
          .from('dsa_rooms')
          .select('id, player1_id, player2_id, winner_id, problem_id, player1_submitted_at, player2_submitted_at, created_at')
          .or('player1_id.eq.$userId,player2_id.eq.$userId')
          .eq('status', 'finished')
          .order('created_at', ascending: false)
          .limit(limit);

      if ((rooms as List).isEmpty) return [];

      // 2. Collect opponent IDs and problem IDs
      final opponentIds = <String>{};
      final problemIds = <String>{};
      for (final r in rooms) {
        final oppId = r['player1_id'] == userId ? r['player2_id'] : r['player1_id'];
        if (oppId != null) opponentIds.add(oppId.toString());
        if (r['problem_id'] != null) problemIds.add(r['problem_id'].toString());
      }

      // 3. Fetch opponent profiles
      final Map<String, String> profileMap = {};
      if (opponentIds.isNotEmpty) {
        final profiles = await supabase
            .from('profiles')
            .select('id, username')
            .inFilter('id', opponentIds.toList());
        for (final p in (profiles as List)) {
          profileMap[p['id'].toString()] = p['username']?.toString() ?? 'Unknown';
        }
      }

      // 4. Fetch problems
      final Map<String, Map<String, dynamic>> problemMap = {};
      if (problemIds.isNotEmpty) {
        final problems = await supabase
            .from('dsa_problems')
            .select('id, title, difficulty')
            .inFilter('id', problemIds.toList());
        for (final p in (problems as List)) {
          problemMap[p['id'].toString()] = Map<String, dynamic>.from(p);
        }
      }

      // 5. Fetch was_quit from match_history for these rooms
      final roomIds = rooms.map((r) => r['id'].toString()).toList();
      final Map<String, bool> forfeitMap = {};
      try {
        final historyRows = await supabase
            .from('match_history')
            .select('room_id, was_quit')
            .inFilter('room_id', roomIds);
        for (final h in (historyRows as List)) {
          forfeitMap[h['room_id'].toString()] = h['was_quit'] == true;
        }
      } catch (_) {}

      // 6. Assemble result
      return rooms.map<Map<String, dynamic>>((r) {
        final isPlayer1 = r['player1_id'] == userId;
        final oppId = isPlayer1 ? r['player2_id'] : r['player1_id'];
        final oppName = oppId != null ? (profileMap[oppId.toString()] ?? 'Unknown') : 'Bot';
        final problem = problemMap[r['problem_id']?.toString() ?? ''];
        final isWin = r['winner_id'] == userId;
        final isForfeit = forfeitMap[r['id'].toString()] ?? false;

        // Winner's submitted_at - created_at = actual solve time
        // Both are UTC after the markSolved fix (guard < 60 min for old local-time records)
        final winnerId = r['winner_id']?.toString();
        final winnerIsP1 = r['player1_id'] == winnerId;
        final winnerSubmitted = winnerIsP1
            ? r['player1_submitted_at']
            : r['player2_submitted_at'];

        String? timeTaken;
        if (!isForfeit && winnerSubmitted != null && r['created_at'] != null) {
          try {
            final start = DateTime.parse(r['created_at'].toString());
            final end = DateTime.parse(winnerSubmitted.toString());
            final diff = end.difference(start);
            if (diff.inSeconds > 0 && diff.inMinutes < 60) {
              final m = diff.inMinutes;
              final s = diff.inSeconds % 60;
              timeTaken = m > 0 ? '${m}m ${s}s' : '${s}s';
            }
          } catch (_) {}
        }

        return {
          'room_id': r['id'],
          'problem_id': r['problem_id']?.toString(),
          'is_win': isWin,
          'is_forfeit': isForfeit,
          'opponent_name': oppName,
          'opponent_id': oppId,
          'problem_title': problem?['title'] ?? 'Unknown Problem',
          'difficulty': problem?['difficulty'] ?? 'easy',
          'coins': isWin ? 50 : -20,
          'time_taken': timeTaken,
          'played_at': r['created_at'],
        };
      }).toList();
    } catch (e) {
      debugPrint('fetchMatchHistory error: $e');
      return [];
    }
  }

  // ============================================
  // CODE EXECUTION — routed through Supabase Edge Function proxy
  // RapidAPI key is stored server-side as a Supabase secret (never in APK)
  // ============================================

  static const String _judge0ProxyUrl =
      'https://iukxnbifojobmerspvxn.supabase.co/functions/v1/judge0-proxy';

  static Future<Map<String, dynamic>> executeCode({
    required String code,
    required String language,
    required String stdin,
  }) async {
    final langId = languageIds[language] ?? 71;
    return _callJudge0Proxy(code: code, langId: langId, stdin: stdin);
  }

  static Future<Map<String, dynamic>> _callJudge0Proxy({
    required String code,
    required int langId,
    required String stdin,
  }) async {
    const anonKey = 'YOUR_SUPABASE_ANON_KEY'; // TODO: Move to .env
    final token = supabase.auth.currentSession?.accessToken ?? anonKey;

    final res = await http.post(
      Uri.parse(_judge0ProxyUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': anonKey,
      },
      body: jsonEncode({'code': code, 'language_id': langId, 'stdin': stdin}),
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode != 200 && res.statusCode != 201) {
      return {'error': 'Judge0 proxy error ${res.statusCode}: ${res.body}'};
    }

    final result = jsonDecode(res.body);
    final statusId = (result['status']?['id'] ?? 0) as int;
    final stdout   = result['stdout'] ?? '';
    final stderr   = result['stderr'] ?? result['compile_output'] ?? '';

    return {
      'stdout':   stdout,
      'stderr':   stderr,
      'status':   statusId == 3 ? 'Accepted' : (result['status']?['description'] ?? 'Error'),
      'statusId': statusId,
    };
  }

  // ============================================
  // RUN TEST CASES
  // ============================================

  static Future<Map<String, dynamic>> runTestCases({
    required String code,
    required String language,
    required List<Map<String, dynamic>> testCases,
  }) async {
    int passed = 0;
    List<Map<String, dynamic>> results = [];

    for (final tc in testCases) {
      final result = await executeCode(
        code: code,
        language: language,
        stdin: tc['input'] ?? '',
      );

      // If execution itself failed, surface the error clearly
      if (result.containsKey('error')) {
        results.add({
          'input':    tc['input'],
          'expected': tc['expected']?.toString() ?? '',
          'actual':   '',
          'passed':   false,
          'status':   'Error',
          'error':    result['error'],
        });
        continue;
      }

      String normalize(String s) => s
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .trim()
          .toLowerCase();

      final actual   = normalize(result['stdout']?.toString() ?? '');
      final expected = normalize(tc['expected']?.toString() ?? '');
      final isCorrect = actual == expected;

      if (isCorrect) passed++;

      results.add({
        'input':    tc['input'],
        'expected': expected,
        'actual':   actual,
        'passed':   isCorrect,
        'status':   result['status'] ?? '',
        'error':    result['stderr'] ?? '',
      });
    }

    return {
      'passed':  passed,
      'total':   testCases.length,
      'allPass': passed == testCases.length,
      'results': results,
    };
  }

  // ============================================
  // PISTON EXECUTION — FREE, no RapidAPI key
  // Used exclusively for Practice mode.
  // NEVER call this from Battle/Daily — those use executeCode() above.
  // ============================================

  // Wandbox — free, no API key, runs since 2012
  // https://wandbox.org  (Piston shut down public access Feb 2026)
  static const String _wandboxUrl = 'https://wandbox.org/api/compile.json';

  // Wandbox compiler names
  static const Map<String, String> _wandboxCompilers = {
    'Python':     'cpython-3.12.0',
    'Java':       'openjdk-head',
    'C++':        'gcc-head',
    'C':          'gcc-head',
    'JavaScript': 'nodejs-head',
  };

  // C uses gcc-head but needs to compile as C not C++
  static const Map<String, String> _wandboxOptions = {
    'C': 'c11',
  };

  /// Executes code via Wandbox (free, no API key).
  /// Returns same shape as [executeCode]: {stdout, stderr, status, statusId}
  /// Use this from Practice and Vibe Coding — never from Battle/Daily.
  static Future<Map<String, dynamic>> executePiston({
    required String code,
    required String language,
    required String stdin,
  }) => _executeWandbox(code: code, language: language, stdin: stdin);

  static Future<Map<String, dynamic>> _executeWandbox({
    required String code,
    required String language,
    required String stdin,
  }) async {
    final compiler = _wandboxCompilers[language] ?? 'cpython-3.12.0';
    final options  = _wandboxOptions[language];
    try {
      final body = <String, dynamic>{
        'code':     code,
        'compiler': compiler,
        'stdin':    stdin,
        'save':     false,
      };
      if (options != null) body['options'] = options;

      final response = await http.post(
        Uri.parse(_wandboxUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return {'error': 'Executor error ${response.statusCode}: ${response.body}'};
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Wandbox returns status as string "0" for success
      final statusStr     = data['status']?.toString() ?? '1';
      final exitCode      = int.tryParse(statusStr) ?? 1;
      final stdout        = data['program_output']?.toString() ?? '';
      final stderr        = (data['program_error']?.toString() ?? '') +
                            (data['compiler_error']?.toString() ?? '');
      final compilerMsg   = data['compiler_output']?.toString() ?? '';

      // Compilation failed if there's a compiler error and no output
      if (compilerMsg.isNotEmpty && stdout.isEmpty && exitCode != 0) {
        return {
          'stdout':   '',
          'stderr':   compilerMsg,
          'status':   'Compilation Error',
          'statusId': 6,
        };
      }

      return {
        'stdout':   stdout,
        'stderr':   stderr.isNotEmpty ? stderr : compilerMsg,
        'status':   exitCode == 0 ? 'Accepted' : 'Error',
        'statusId': exitCode == 0 ? 3 : 11,
      };
    } catch (e) {
      return {'error': 'Execution error: $e'};
    }
  }

  /// Runs all test cases via Wandbox (free).
  /// Identical return shape to [runTestCases].
  /// ONLY use this from Practice mode — never from Battle/Daily.
  static Future<Map<String, dynamic>> runTestCasesPiston({
    required String code,
    required String language,
    required List<Map<String, dynamic>> testCases,
  }) async {
    int passed = 0;
    final List<Map<String, dynamic>> results = [];

    for (final tc in testCases) {
      final result = await _executeWandbox(
        code: code,
        language: language,
        stdin: tc['input'] ?? '',
      );

      if (result.containsKey('error')) {
        results.add({
          'input':    tc['input'],
          'expected': tc['expected']?.toString() ?? '',
          'actual':   '',
          'passed':   false,
          'status':   'Error',
          'error':    result['error'],
        });
        continue;
      }

      String normalize(String s) =>
          s.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim().toLowerCase();

      final actual   = normalize(result['stdout']?.toString() ?? '');
      final expected = normalize(tc['expected']?.toString() ?? '');
      final isCorrect = actual == expected;
      if (isCorrect) passed++;

      results.add({
        'input':    tc['input'],
        'expected': expected,
        'actual':   actual,
        'passed':   isCorrect,
        'status':   result['status'] ?? '',
        'error':    result['stderr'] ?? '',
      });
    }

    return {
      'passed':  passed,
      'total':   testCases.length,
      'allPass': passed == testCases.length,
      'results': results,
    };
  }

  // ============================================
  // ROOM MANAGEMENT
  // ============================================

  static Future<String> createRoom({
    required String playerId,
    required String problemId,
  }) async {
    final data = await supabase.from('dsa_rooms').insert({
      'player1_id': playerId,
      'problem_id': problemId,
      'status':     'waiting',
    }).select().single();
    return data['id'];
  }

  static Future<void> joinRoom({
    required String roomId,
    required String playerId,
  }) async {
    await supabase.from('dsa_rooms').update({
      'player2_id': playerId,
      'status':     'active',
    }).eq('id', roomId);
  }

  static Future<void> markSolved({
    required String roomId,
    required String playerId,
    required bool isPlayer1,
  }) async {
    final field     = isPlayer1 ? 'player1_solved'       : 'player2_solved';
    final timeField = isPlayer1 ? 'player1_submitted_at' : 'player2_submitted_at';
    await supabase.from('dsa_rooms').update({
      field:       true,
      timeField:   DateTime.now().toUtc().toIso8601String(),
      'winner_id': playerId,
      'status':    'finished',
    }).eq('id', roomId);
  }

  // ============================================
  // BATTLE ROOM MANAGEMENT (private rooms, max 3 players)
  // ============================================

  static String _generateBattleRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  static Future<Map<String, dynamic>> createBattleRoom({
    required String playerId,
    String difficulty = 'easy',
    String? problemId,
  }) async {
    final code = _generateBattleRoomCode();
    final row = <String, dynamic>{
      'room_code': code,
      'host_id': playerId,
      'player_ids': [playerId],
      'difficulty': difficulty,
      'status': 'waiting',
      'max_players': 3,
    };
    if (problemId != null) row['problem_id'] = problemId;
    final data = await supabase.from('dsa_battle_rooms').insert(row).select().single();
    return {'room_id': data['id'].toString(), 'room_code': code};
  }

  static Future<Map<String, dynamic>> joinBattleRoom({
    required String roomCode,
    required String playerId,
  }) async {
    final rows = await supabase
        .from('dsa_battle_rooms')
        .select()
        .eq('room_code', roomCode.toUpperCase())
        .eq('status', 'waiting');

    if ((rows as List).isEmpty) throw Exception('Room not found or already started');

    final room = Map<String, dynamic>.from(rows[0]);
    final playerIds = List<String>.from(room['player_ids'] ?? []);
    final maxPlayers = (room['max_players'] as int? ?? 3);

    if (playerIds.contains(playerId)) {
      return {
        'room_id': room['id'].toString(),
        'room_code': room['room_code'].toString(),
        'is_host': room['host_id'].toString() == playerId,
        'difficulty': room['difficulty']?.toString() ?? 'easy',
      };
    }

    if (playerIds.length >= maxPlayers) {
      throw Exception('Room is full ($maxPlayers/$maxPlayers)');
    }

    playerIds.add(playerId);
    await supabase.from('dsa_battle_rooms').update({
      'player_ids': playerIds,
    }).eq('id', room['id']);

    return {
      'room_id': room['id'].toString(),
      'room_code': room['room_code'].toString(),
      'is_host': false,
      'difficulty': room['difficulty']?.toString() ?? 'easy',
    };
  }

  static Future<void> startBattleRoom({
    required String roomId,
    required String hostId,
    required String difficulty,
  }) async {
    // Check if problem already locked in (e.g. created from Progress tab)
    final row = await supabase
        .from('dsa_battle_rooms')
        .select('problem_id')
        .eq('id', roomId)
        .single();
    final existingProblemId = row['problem_id']?.toString();
    final problemId = existingProblemId ??
        (await fetchRandomProblem(difficulty: difficulty, userId: hostId)).id;
    await supabase.from('dsa_battle_rooms').update({
      'status': 'active',
      'problem_id': problemId,
    }).eq('id', roomId);
  }

  static Future<bool> markBattleSolved({
    required String roomId,
    required String playerId,
  }) async {
    final current = await supabase
        .from('dsa_battle_rooms')
        .select('winner_id, created_at')
        .eq('id', roomId)
        .single();
    if (current['winner_id'] != null) return false;
    final createdAt = DateTime.tryParse(current['created_at']?.toString() ?? '');
    final solveSeconds = createdAt != null
        ? DateTime.now().toUtc().difference(createdAt.toUtc()).inSeconds
        : null;
    await supabase.from('dsa_battle_rooms').update({
      'winner_id': playerId,
      'winner_solve_seconds': solveSeconds,
      'status': 'finished',
    }).eq('id', roomId);
    return true;
  }

  static Future<void> leaveBattleRoom({
    required String roomId,
    required String playerId,
  }) async {
    try {
      final row = await supabase
          .from('dsa_battle_rooms')
          .select()
          .eq('id', roomId)
          .single();
      final room = Map<String, dynamic>.from(row);
      final playerIds = List<String>.from(room['player_ids'] ?? []);
      playerIds.remove(playerId);

      if (playerIds.isEmpty) {
        await supabase.from('dsa_battle_rooms').delete().eq('id', roomId);
      } else {
        final updates = <String, dynamic>{'player_ids': playerIds};
        if (room['host_id'].toString() == playerId) {
          updates['host_id'] = playerIds.first;
        }
        await supabase.from('dsa_battle_rooms').update(updates).eq('id', roomId);
      }
    } catch (_) {}
  }

  // ============================================
  // DAILY CHALLENGE
  // ============================================

  static Future<Map<String, dynamic>> fetchDailyChallenge({
    required String userId,
  }) async {
    final result = await supabase.rpc('get_daily_challenge', params: {'p_user_id': userId});
    final rows = result as List;
    if (rows.isEmpty) throw Exception('No daily challenge available');
    return Map<String, dynamic>.from(rows[0]);
  }

  static Future<void> markDailySolved({
    required String userId,
    required String problemId,
    required String challengeDate,
  }) async {
    await supabase.from('user_daily_completions').upsert({
      'user_id': userId,
      'problem_id': problemId,
      'challenge_date': challengeDate,
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,challenge_date');
  }

  static Future<List<Map<String, dynamic>>> fetchDsaLeaderboard({int limit = 50}) async {
    final result = await supabase.rpc('get_dsa_leaderboard', params: {'p_limit': limit});
    return List<Map<String, dynamic>>.from(
        (result as List).map((e) => Map<String, dynamic>.from(e)));
  }

  static Future<Map<String, String>> fetchPlayerProfiles(List<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await supabase
          .from('profiles')
          .select('id, username')
          .inFilter('id', ids);
      final map = <String, String>{};
      for (final r in (rows as List)) {
        map[r['id'].toString()] = r['username']?.toString() ?? 'Player';
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  // ============================================
  // VIBE CODING — Groq AI
  // ============================================

  static const String _vibeCodingUrl =
      'https://iukxnbifojobmerspvxn.supabase.co/functions/v1/vibe-coding';

  static Future<String> askVibeCoding({
    required List<Map<String, String>> messages,
    required String language,
  }) async {
    const anonKey = 'YOUR_SUPABASE_ANON_KEY'; // TODO: Move to .env
    final token = supabase.auth.currentSession?.accessToken ?? anonKey;

    final response = await http.post(
      Uri.parse(_vibeCodingUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': anonKey,
      },
      body: jsonEncode({'messages': messages, 'language': language}),
    ).timeout(const Duration(seconds: 40));

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Server returned invalid response (HTTP ${response.statusCode})');
    }
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? data['message'] ?? 'HTTP ${response.statusCode}');
    }
    if (data['error'] != null) throw Exception(data['error']);
    final content = data['content'];
    if (content == null) throw Exception('No response received from AI');
    return content as String;
  }

  // ============================================
  // STARTER CODE TEMPLATES
  // ============================================

  static String getStarterCode(String language, DsaProblem problem) {
    switch (language) {
      case 'Python':
        return '# ${problem.title}\n# Write your solution below\n\n';
      case 'Java':
        return '// ${problem.title}\nimport java.util.*;\n\npublic class Main {\n    public static void main(String[] args) {\n        Scanner sc = new Scanner(System.in);\n        // Write your solution here\n    }\n}\n';
      case 'C++':
        return '// ${problem.title}\n#include <bits/stdc++.h>\nusing namespace std;\n\nint main() {\n    // Write your solution here\n    return 0;\n}\n';
      case 'JavaScript':
        return '// ${problem.title}\nconst lines = require("fs").readFileSync("/dev/stdin","utf8").trim().split("\\n");\n// Write your solution here\n';
      case 'C':
        return '// ${problem.title}\n#include <stdio.h>\n\nint main() {\n    // Write your solution here\n    return 0;\n}\n';
      default:
        return '';
    }
  }
}