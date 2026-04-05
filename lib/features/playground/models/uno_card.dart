// lib/features/playground/models/uno_card.dart
import 'package:flutter/material.dart';
enum CardColor { red, blue, green, yellow, wild }

enum CardValue {
  zero, one, two, three, four, five, six, seven, eight, nine,
  skip, reverse, drawTwo,
  wild, wildDrawFour
}

class UnoCard {
  final CardColor color;
  final CardValue value;

  const UnoCard({
    required this.color,
    required this.value,
  });

  // Convert card to JSON (for Supabase storage)
  Map<String, dynamic> toJson() {
    return {
      'color': color.name,
      'value': value.name,
    };
  }

  // Create card from JSON (from Supabase)
  factory UnoCard.fromJson(Map<String, dynamic> json) {
    return UnoCard(
      color: CardColor.values.firstWhere((c) => c.name == json['color']),
      value: CardValue.values.firstWhere((v) => v.name == json['value']),
    );
  }

  // Get display text for card
  String get displayText {
    switch (value) {
      case CardValue.zero: return '0';
      case CardValue.one: return '1';
      case CardValue.two: return '2';
      case CardValue.three: return '3';
      case CardValue.four: return '4';
      case CardValue.five: return '5';
      case CardValue.six: return '6';
      case CardValue.seven: return '7';
      case CardValue.eight: return '8';
      case CardValue.nine: return '9';
      case CardValue.skip: return '🚫';
      case CardValue.reverse: return '🔄';
      case CardValue.drawTwo: return '+2';
      case CardValue.wild: return '🌈';
      case CardValue.wildDrawFour: return '+4';
    }
  }

  // Get Flutter color for card
  Color get displayColor {
    switch (color) {
      case CardColor.red: return const Color(0xFFE53935);
      case CardColor.blue: return const Color(0xFF1E88E5);
      case CardColor.green: return const Color(0xFF43A047);
      case CardColor.yellow: return const Color(0xFFFFB300);
      case CardColor.wild: return const Color(0xFF6A1B9A);
    }
  }

  // Check if this card is an action card
  bool get isActionCard {
    return value == CardValue.skip ||
        value == CardValue.reverse ||
        value == CardValue.drawTwo;
  }

  // Check if this card is a wild card
  bool get isWild {
    return color == CardColor.wild;
  }

  // Points value for scoring
  int get points {
    if (value.index <= 9) return value.index; // 0-9 face value
    if (isActionCard) return 20;
    if (isWild) return 50;
    return 0;
  }

  // Check if this card can be played on top of another card
  bool canPlayOn(UnoCard topCard, CardColor? activeWildColor) {
    // Wild cards can always be played
    if (isWild) return true;

    // If top card is wild, match the chosen color
    if (topCard.isWild && activeWildColor != null) {
      return color == activeWildColor;
    }

    // Match by color or value
    return color == topCard.color || value == topCard.value;
  }

  @override
  String toString() => '${color.name}_${value.name}';
}