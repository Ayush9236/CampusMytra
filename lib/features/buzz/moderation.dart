import 'package:supabase_flutter/supabase_flutter.dart';

class PostModerationResult {
  final bool allowed;
  final String? reason;
  final Map<String, double> scores;

  const PostModerationResult({
    required this.allowed,
    this.reason,
    this.scores = const {},
  });
}

class PostModerationService {
  final _supabase = Supabase.instance.client;

  // ── Client-side pre-check (instant, no API call) ──
  PostModerationResult quickCheck(String text) {
    final lower = text.toLowerCase().trim();

    // ── 1. Hard-blocked exact substrings ──
    const blockedPhrases = [
      // Sexual content
      'porn', 'pornography', 'nude', 'naked', 'sex tape',
      'onlyfans', 'xxx', 'nsfw', 'sex chat', 'sex video',
      'have sex', 'wants sex', 'need sex', 'send nudes',
      'dick pic', 'suck my', 'suck it', 'blow me',
      'rape you', 'i will rape', 'gonna rape', 'molest',
      'masturbat', 'fingering', 'dildo', 'vibrator',
      // Severe English slurs
      'nigger', 'nigga', 'faggot', 'chink', 'spic', 'kike',
      'retard', 'tranny', 'bitch ass', 'motherfuck',
      'fuck you', 'f you', 'fuuck', 'fuk you', 'fck you',
      'i will fuck', 'ill fuck', 'gonna fuck', 'going to fuck',
      // Hindi / Hinglish slurs (full phrases)
      'madarchod', 'madar chod', 'bhenchod', 'bhen chod',
      'bhosdike', 'bhosdiwale', 'randi', 'randwa',
      'chutiya', 'chut mara', 'lund mara', 'gaand mara',
      'teri maa', 'maa ki', 'maa ko',
      // Threats
      'i will kill', 'ill kill', 'gonna kill', 'going to kill',
      'bomb threat', 'shoot you', 'i will beat', 'gonna beat you',
      'will hurt you',
      // Doxxing patterns
      'aadhar', 'pan card', 'account number', 'ifsc',
    ];

    for (final phrase in blockedPhrases) {
      if (lower.contains(phrase)) {
        return const PostModerationResult(
          allowed: false,
          reason: 'Your post contains prohibited content.',
        );
      }
    }

    // ── 2. Word-boundary blocked words (standalone use) ──
    // These use \b so "class" won't be blocked by "ass", etc.
    const wordBoundaryBlocked = [
      'fuck', 'shit', 'bitch', 'cunt', 'cock',
      'dick', 'pussy', 'ass', 'bastard',
      // Sexual use
      'sex', 'sexy', 'sexting',
      // Hindi short forms
      'chod', 'chodu', 'lund', 'gaand', 'chut',
      'harami', 'kamina', 'gandu', 'lodu', 'bhosdi',
      'maderchod', 'bc', 'mc',
    ];

    for (final word in wordBoundaryBlocked) {
      if (RegExp(r'\b' + RegExp.escape(word) + r'\b',
              caseSensitive: false)
          .hasMatch(lower)) {
        return const PostModerationResult(
          allowed: false,
          reason: 'Your post contains prohibited content.',
        );
      }
    }

    // ── 3. Obfuscated profanity: f*ck, f**k, f@ck, sh!t, etc. ──
    const obfuscatedPatterns = [
      r'f[\*@#!\$u][\*@#!\$c]k',
      r'f[\*@#!\$][\*@#!\$][\*@#!\$]',
      r's[\*@#!\$][\*@#!\$]t',
      r'b[\*@#!\$]tch',
      r'a[\*@#!\$\s]hole',
      r'c[\*@#!\$]nt',
      r'd[\*@#!\$]ck',
      r'p[\*@#!\$]ssy',
    ];
    for (final pattern in obfuscatedPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lower)) {
        return const PostModerationResult(
          allowed: false,
          reason: 'Your post contains prohibited content.',
        );
      }
    }

    // ── 4. Repeated characters spam ──
    if (RegExp(r'(.)\1{6,}').hasMatch(lower)) {
      return const PostModerationResult(
        allowed: false,
        reason: 'Your post looks like spam (repeated characters).',
      );
    }

    // ── 5. All caps (more than 10 chars) ──
    if (text.trim().length > 10 &&
        text.trim() == text.trim().toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(text.trim())) {
      return const PostModerationResult(
        allowed: false,
        reason: 'Avoid posting in all caps.',
      );
    }

    // ── 6. Too many URLs ──
    final urlCount = RegExp(r'https?://').allMatches(lower).length;
    if (urlCount > 2) {
      return const PostModerationResult(
        allowed: false,
        reason: 'Too many links in your post.',
      );
    }

    // ── 7. Repeated words spam ──
    final words = lower.split(RegExp(r'\s+'));
    final wordFreq = <String, int>{};
    for (final w in words) {
      if (w.length > 2) {
        wordFreq[w] = (wordFreq[w] ?? 0) + 1;
        if (wordFreq[w]! > 5) {
          return const PostModerationResult(
            allowed: false,
            reason: 'Your post looks like spam (repeated words).',
          );
        }
      }
    }

    // ── 8. Too short ──
    if (text.trim().length < 3) {
      return const PostModerationResult(
        allowed: false,
        reason: 'Post is too short.',
      );
    }

    // ── 9. Subtle toxic phrases ──
    const toxicPhrases = [
      'worthless person', 'you are worthless', "you're worthless",
      'you are useless', "you're useless", 'piece of shit', 'piece of crap',
      'you are pathetic', "you're pathetic", 'you are trash', "you're trash",
      'you are garbage', "you're garbage", 'you are nothing', "you're nothing",
      'you are stupid', "you're stupid", 'you are an idiot', "you're an idiot",
      'you are ugly', "you're ugly", 'you are fat', "you're fat",
      'nobody likes you', 'no one likes you', 'everyone hates you',
      'go kill yourself', 'kys', 'kill yourself', 'end your life',
      'you should die', 'die already', 'go die',
      'you will never amount', 'you are a loser', "you're a loser",
      'you are a failure', "you're a failure", 'you are disgusting',
      "you're disgusting", 'you make me sick', 'you are embarrassing',
      "you're embarrassing", 'such a worthless', 'such a loser',
      'such a failure', 'such a waste',
      'i know where you live', 'i will find you', 'watch your back',
      'you will regret', 'stay away or else', 'leave or else',
    ];

    for (final phrase in toxicPhrases) {
      if (lower.contains(phrase)) {
        return const PostModerationResult(
          allowed: false,
          reason: 'Your post contains content that may be hurtful to others.',
        );
      }
    }

    return const PostModerationResult(allowed: true);
  }

  // ── Server-side check via Edge Function (Perspective API) ──
  Future<PostModerationResult> serverCheck(String text) async {
    try {
      final response = await _supabase.functions.invoke(
        'moderate-post',
        body: {'text': text},
      );

      final data = response.data as Map<String, dynamic>;
      final allowed = data['allowed'] as bool? ?? true;
      final reason = data['reason']?.toString();
      final rawScores =
          data['scores'] as Map<String, dynamic>? ?? {};

      return PostModerationResult(
        allowed: allowed,
        reason: reason,
        scores: rawScores
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
      );
    } catch (e) {
      return const PostModerationResult(allowed: true);
    }
  }

  // ── Master method: client warns instantly, server enforces ──
  Future<PostModerationResult> moderate(String text) async {
    final quick = quickCheck(text);
    if (!quick.allowed) return quick;
    return await serverCheck(text);
  }
}
