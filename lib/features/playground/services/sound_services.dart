import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════
// 🔊 SOUND SERVICE
// Plays game sound effects using audioplayers.
// Each call creates its own AudioPlayer so
// sounds can overlap (e.g. rapid card plays).
// ══════════════════════════════════════════════

class SoundService {
  static bool _soundEnabled = true;
  static bool _initialized = false;

  /// Call once at app start (or before first game).
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool('soundEnabled') ?? true;
  }

  static Future<void> toggleSound() async {
    _soundEnabled = !_soundEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('soundEnabled', _soundEnabled);
  }

  static bool get isSoundEnabled => _soundEnabled;

  // ── Internal play helper ──
  static Future<void> _play(String fileName) async {
    if (!_soundEnabled) return;
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sound/$fileName'));
      // Release player after sound finishes
      player.onPlayerComplete.listen((_) => player.dispose());
    } catch (_) {}
  }

  // ── Public API ──

  /// Played when a card is placed on the pile.
  static void playCardSound() => _play('card_play.mp3');

  /// Played when a player draws a card.
  static void playDrawSound() => _play('draw_card.mp3');

  /// Played when the local player wins.
  static void playWinSound() => _play('rename.mp3');

  /// Played when the local player loses.
  static void playLoseSound() => _play('lose.mp3');

  /// Played when someone calls UNO.
  static void playUnoSound() => _play('uno_call.mp3');
}
