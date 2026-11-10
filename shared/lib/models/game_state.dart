import 'card_model.dart';
import 'player_model.dart';

enum GamePhase { lobby, initialPeek, playing, roundEnd, gameOver }

enum TurnPhase {
  waitingForDraw,
  cardDrawn,
  usingPower,
  swappingWithHand,
  discarding,
  waitingForMatch,
}

class GameState {
  GamePhase phase;
  TurnPhase turnPhase;
  final List<Player> players;
  final List<CaboCard> drawPile;
  final List<CaboCard> discardPile;
  String? currentPlayerId;
  CaboCard? drawnCard;
  String? caboCallerId; // player who called Cabo
  int turnsRemainingAfterCabo; // turns left after Cabo is called
  int matchWindowEndTime; // timestamp when match window closes

  GameState({
    this.phase = GamePhase.lobby,
    this.turnPhase = TurnPhase.waitingForDraw,
    List<Player>? players,
    List<CaboCard>? drawPile,
    List<CaboCard>? discardPile,
    this.currentPlayerId,
    this.drawnCard,
    this.caboCallerId,
    this.turnsRemainingAfterCabo = -1,
    this.matchWindowEndTime = 0,
  })  : players = players ?? [],
        drawPile = drawPile ?? [],
        discardPile = discardPile ?? [];

  Player? get currentPlayer {
    if (currentPlayerId == null) return null;
    try {
      return players.firstWhere((p) => p.id == currentPlayerId);
    } catch (_) {
      return null;
    }
  }

  Player? getPlayer(String id) {
    try {
      return players.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  CaboCard? get topDiscard =>
      discardPile.isNotEmpty ? discardPile.last : null;

  int get drawPileCount => drawPile.length;

  bool get isCaboCalled => caboCallerId != null;

  /// Get the next active (connected & not eliminated) player in turn order.
  String? getNextPlayerId(String currentId) {
    // Away players keep their turn; the game plays it for them if they don't return
    final activePlayers = players.where((p) => !p.isEliminated).toList();
    if (activePlayers.isEmpty) return null;
    final currentIndex = activePlayers.indexWhere((p) => p.id == currentId);
    if (currentIndex == -1) return activePlayers.first.id;
    return activePlayers[(currentIndex + 1) % activePlayers.length].id;
  }

  /// Number of players still in the round. Away players keep their seat.
  int get activePlayerCount => players.where((p) => !p.isEliminated).length;
}
