enum Suit { hearts, diamonds, spades, clubs }

enum Rank { ace, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king }

enum CardPower { none, peekOwn, peekOpponent, blindSwap, smartSwap, skipTurn }

class CaboCard {
  final Suit suit;
  final Rank rank;

  const CaboCard({required this.suit, required this.rank});

  int get value {
    switch (rank) {
      case Rank.ace:
        return 1;
      case Rank.two:
        return 2;
      case Rank.three:
        return 3;
      case Rank.four:
        return 4;
      case Rank.five:
        return 5;
      case Rank.six:
        return 6;
      case Rank.seven:
        return 7;
      case Rank.eight:
        return 8;
      case Rank.nine:
        return 9;
      case Rank.ten:
        return 10;
      case Rank.jack:
        return 11;
      case Rank.queen:
        return 12;
      case Rank.king:
        return isRedKing ? 13 : 0;
    }
  }

  bool get isRedKing =>
      rank == Rank.king && (suit == Suit.hearts || suit == Suit.diamonds);

  bool get isBlackKing =>
      rank == Rank.king && (suit == Suit.spades || suit == Suit.clubs);

  CardPower get power {
    switch (rank) {
      case Rank.seven:
      case Rank.eight:
        return CardPower.peekOwn;
      case Rank.nine:
      case Rank.ten:
        return CardPower.peekOpponent;
      case Rank.jack:
        return CardPower.skipTurn;
      case Rank.queen:
        return CardPower.blindSwap;
      case Rank.king:
        return isRedKing ? CardPower.smartSwap : CardPower.none;
      default:
        return CardPower.none;
    }
  }

  bool get hasPower => power != CardPower.none;

  /// Two cards match if they have the same rank.
  bool matchesRank(CaboCard other) => rank == other.rank;

  Map<String, dynamic> toJson() => {
        'suit': suit.name,
        'rank': rank.name,
      };

  factory CaboCard.fromJson(Map<String, dynamic> json) => CaboCard(
        suit: Suit.values.byName(json['suit'] as String),
        rank: Rank.values.byName(json['rank'] as String),
      );

  @override
  String toString() => '${rank.name} of ${suit.name}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaboCard && suit == other.suit && rank == other.rank;

  @override
  int get hashCode => suit.hashCode ^ rank.hashCode;
}
