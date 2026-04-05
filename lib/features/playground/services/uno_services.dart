// lib/features/playground/services/uno_service.dart

import 'dart:math';

import '../models/uno_card.dart';

class UnoService {
  // ──────────────────────────────────────────────────────────
  //  DECK BUILDING
  // ──────────────────────────────────────────────────────────

  /// Build a complete 108-card UNO deck
  static List<UnoCard> buildDeck() {
    List<UnoCard> deck = [];

    for (CardColor color in [
      CardColor.red,
      CardColor.blue,
      CardColor.green,
      CardColor.yellow,
    ]) {
      deck.add(UnoCard(color: color, value: CardValue.zero));

      for (CardValue value in [
        CardValue.one,   CardValue.two,   CardValue.three,
        CardValue.four,  CardValue.five,  CardValue.six,
        CardValue.seven, CardValue.eight, CardValue.nine,
        CardValue.skip,  CardValue.reverse, CardValue.drawTwo,
      ]) {
        deck.add(UnoCard(color: color, value: value));
        deck.add(UnoCard(color: color, value: value));
      }
    }

    for (int i = 0; i < 4; i++) {
      deck.add(const UnoCard(color: CardColor.wild, value: CardValue.wild));
      deck.add(const UnoCard(color: CardColor.wild, value: CardValue.wildDrawFour));
    }

    return deck; // 108 cards
  }

  // ──────────────────────────────────────────────────────────
  //  SHUFFLE  (two aliases so both calling styles work)
  // ──────────────────────────────────────────────────────────

  /// Shuffle a deck (returns a new list)
  static List<UnoCard> shuffleDeck(List<UnoCard> deck) {
    final shuffled = List<UnoCard>.from(deck);
    shuffled.shuffle(Random());
    return shuffled;
  }

  /// Alias used by the new screens
  static List<UnoCard> shuffle(List<UnoCard> deck) => shuffleDeck(deck);

  // ──────────────────────────────────────────────────────────
  //  DEALING
  // ──────────────────────────────────────────────────────────

  /// Deal 7 cards to each player. Returns {playerId → hand}.
  static Map<String, List<UnoCard>> dealCards(
    List<UnoCard> deck,
    List<String> playerIds,
  ) {
    final hands = <String, List<UnoCard>>{};
    for (final id in playerIds) hands[id] = [];

    int idx = 0;
    for (int i = 0; i < 7; i++) {
      for (final id in playerIds) {
        hands[id]!.add(deck[idx++]);
      }
    }
    return hands;
  }

  /// Return the portion of the deck that wasn't dealt.
  static List<UnoCard> getRemainingDeck(List<UnoCard> deck, int numPlayers) {
    return deck.sublist(numPlayers * 7);
  }

  /// Pick the first valid starting card (not Wild Draw Four).
  /// [startIndex] is the offset into [deck] to begin searching.
  static UnoCard getFirstCard(List<UnoCard> deck, int startIndex) {
    for (int i = startIndex; i < deck.length; i++) {
      if (deck[i].value != CardValue.wildDrawFour) return deck[i];
    }
    return deck[startIndex];
  }

  // ──────────────────────────────────────────────────────────
  //  PLAYABILITY
  // ──────────────────────────────────────────────────────────

  /// Return cards from [hand] that can legally be played on [topCard].
  static List<UnoCard> getPlayableCards(
    List<UnoCard> hand,
    UnoCard topCard,
    CardColor? activeWildColor,
  ) {
    return hand.where((c) => c.canPlayOn(topCard, activeWildColor)).toList();
  }

  // ──────────────────────────────────────────────────────────
  //  JSON SERIALISATION
  // ──────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> deckToJson(List<UnoCard> deck) =>
      deck.map((c) => c.toJson()).toList();

  static List<UnoCard> deckFromJson(List<dynamic> json) =>
      json.map((c) => UnoCard.fromJson(c as Map<String, dynamic>)).toList();

  // ──────────────────────────────────────────────────────────
  //  ROOM CODE
  // ──────────────────────────────────────────────────────────

  static String generateRoomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
    );
  }
}