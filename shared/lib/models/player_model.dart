import 'card_model.dart';

class CardSlot {
  final int row; // 0 or 1
  final int col; // 0 or 1
  final String playerId;

  const CardSlot({
    required this.row,
    required this.col,
    required this.playerId,
  });

  Map<String, dynamic> toJson() => {
        'row': row,
        'col': col,
        'playerId': playerId,
      };

  factory CardSlot.fromJson(Map<String, dynamic> json) => CardSlot(
        row: json['row'] as int,
        col: json['col'] as int,
        playerId: json['playerId'] as String,
      );

  @override
  String toString() => 'CardSlot($playerId, row:$row, col:$col)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardSlot &&
          row == other.row &&
          col == other.col &&
          playerId == other.playerId;

  @override
  int get hashCode => row.hashCode ^ col.hashCode ^ playerId.hashCode;
}

class Player {
  final String id;
  final String name;
  /// 2x2 matrix. null means the card slot is empty (card was removed).
  final List<List<CaboCard?>> hand;
  bool isConnected;

  Player({
    required this.id,
    required this.name,
    List<List<CaboCard?>>? hand,
    this.isConnected = true,
  }) : hand = hand ?? [
          [null, null],
          [null, null],
        ];

  int get cardCount =>
      hand.expand((row) => row).where((c) => c != null).length;

  int get totalValue =>
      hand.expand((row) => row).whereType<CaboCard>().fold(0, (sum, c) => sum + c.value);

  CaboCard? getCard(int row, int col) => hand[row][col];

  void setCard(int row, int col, CaboCard? card) {
    hand[row][col] = card;
  }

  CaboCard? removeCard(int row, int col) {
    final card = hand[row][col];
    hand[row][col] = null;
    return card;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hand': hand
            .map((row) => row.map((c) => c?.toJson()).toList())
            .toList(),
        'isConnected': isConnected,
      };

  factory Player.fromJson(Map<String, dynamic> json) {
    final handJson = json['hand'] as List<dynamic>;
    final hand = handJson
        .map((row) => (row as List<dynamic>)
            .map((c) => c != null ? CaboCard.fromJson(c as Map<String, dynamic>) : null)
            .toList())
        .toList();
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      hand: hand,
      isConnected: json['isConnected'] as bool? ?? true,
    );
  }

  /// Create a sanitized version that hides all card values (for sending to opponents).
  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'name': name,
        'hand': hand
            .map((row) => row.map((c) => c != null ? {'hidden': true} : null).toList())
            .toList(),
        'isConnected': isConnected,
      };
}
