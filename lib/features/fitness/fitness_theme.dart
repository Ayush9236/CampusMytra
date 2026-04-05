import 'package:flutter/material.dart';

// ─── Shared vivid accent palette ─────────────────────────────────────────────
// Used for backgrounds/borders in both modes; for text use fc.accentFg()
const kFitGreen  = Color(0xFF00E5A0);
const kFitRed    = Color(0xFFFF4757);
const kFitPurple = Color(0xFF7C3AED);
const kFitOrange = Color(0xFFFF8C42);
const kFitBlue   = Color(0xFF4FC3F7);
const kFitGold   = Color(0xFFFFD700);

// Darker accent variants for light-mode — each ≥ 4.5:1 contrast on white
const _kGreenDark  = Color(0xFF047857); // 7.5:1
const _kBlueDark   = Color(0xFF0369A1); // 7.2:1
const _kOrangeDark = Color(0xFFC2410C); // 5.1:1
const _kRedDark    = Color(0xFFB91C1C); // 5.9:1
const _kPurpleDark = Color(0xFF6D28D9); // 6.8:1

/// Theme-aware color helper for all Fitness screens.
///
/// Usage in every build():
/// ```dart
/// final fc = FitnessColors.of(context);
/// ```
class FitnessColors {
  final bool isDark;
  const FitnessColors._(this.isDark);

  factory FitnessColors.of(BuildContext context) =>
      FitnessColors._(Theme.of(context).brightness == Brightness.dark);

  // ── Scaffold / card backgrounds ──────────────────────────────────────────
  Color get bg        => isDark ? const Color(0xFF0A0E1A) : const Color(0xFFF0F6FF);
  Color get card      => isDark ? const Color(0xFF111827) : Colors.white;
  /// Subtle tint for inner card sections (e.g. stat rows)
  Color get surface   => isDark
      ? Colors.white.withValues(alpha: 0.05)
      : const Color(0xFFF8FAFC);
  Color get surfaceHigh => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFF1F5F9);

  // ── Borders ──────────────────────────────────────────────────────────────
  Color get border    => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFE2E8F0);
  Color get borderMid => isDark
      ? Colors.white.withValues(alpha: 0.14)
      : const Color(0xFFCBD5E1);

  // ── Text ─────────────────────────────────────────────────────────────────
  Color get textPrimary   => isDark ? Colors.white           : const Color(0xFF0F172A);
  Color get textSecondary => isDark ? Colors.white70         : const Color(0xFF475569);
  Color get textTertiary  => isDark ? Colors.white54         : const Color(0xFF64748B);
  Color get textHint      => isDark ? Colors.white38         : const Color(0xFF94A3B8);
  Color get textDisabled  => isDark ? Colors.white24         : const Color(0xFFCBD5E1);

  // ── Accent foreground (text / icon drawn in an accent color) ─────────────
  // Dark: vivid as-is.  Light: darkened counterpart for WCAG AA on white.
  Color accentFg(Color accent) {
    if (isDark) return accent;
    if (accent == kFitGreen)  return _kGreenDark;
    if (accent == kFitBlue)   return _kBlueDark;
    if (accent == kFitOrange) return _kOrangeDark;
    if (accent == kFitRed)    return _kRedDark;
    if (accent == kFitPurple) return _kPurpleDark;
    // Generic fallback: lower lightness to ~35%
    final hsl = HSLColor.fromColor(accent);
    return hsl.withLightness((hsl.lightness * 0.55).clamp(0.20, 0.40)).toColor();
  }

  // ── Accent background fill (tinted card) ─────────────────────────────────
  Color accentBg(Color accent)       => accent.withValues(alpha: isDark ? 0.08 : 0.09);
  Color accentBgStrong(Color accent) => accent.withValues(alpha: isDark ? 0.13 : 0.14);

  // ── Accent border ─────────────────────────────────────────────────────────
  Color accentBorder(Color accent)       => accent.withValues(alpha: isDark ? 0.25 : 0.40);
  Color accentBorderStrong(Color accent) => accent.withValues(alpha: isDark ? 0.45 : 0.60);

  // ── Accent glow / box-shadow ──────────────────────────────────────────────
  Color accentGlow(Color accent)       => accent.withValues(alpha: isDark ? 0.28 : 0.18);
  Color accentGlowStrong(Color accent) => accent.withValues(alpha: isDark ? 0.45 : 0.28);

  // ── Radial gradient background overlay ───────────────────────────────────
  Color radialBg(Color accent) => accent.withValues(alpha: isDark ? 0.10 : 0.06);

  // ── Shadow / elevation ────────────────────────────────────────────────────
  Color get shadow => isDark
      ? Colors.black.withValues(alpha: 0.40)
      : Colors.black.withValues(alpha: 0.08);

  // ── Input field fill ─────────────────────────────────────────────────────
  Color get inputFill => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : const Color(0xFFF8FAFC);

  // ── Dimmed overlay (e.g. disabled buttons) ────────────────────────────────
  Color get dimOverlay => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.black.withValues(alpha: 0.04);
}
