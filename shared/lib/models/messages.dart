/// All WebSocket message types between client and server.
library;

import 'card_model.dart';
import 'player_model.dart';
import 'game_state.dart';

// ─── Message type constants ───────────────────────────────────────────────────

class MsgType {
  // Client → Server
  static const joinLobby = 'joinLobby';
  static const startGame = 'startGame';
  static const callCabo = 'callCabo';
  static const drawFromPile = 'drawFromPile';
  static const discardDrawn = 'discardDrawn';
  static const swapDrawnWithHand = 'swapDrawnWithHand';
  static const usePower = 'usePower';
  static const skipPower = 'skipPower';
  static const matchCard = 'matchCard'; // slap mechanic
  static const giveCard = 'giveCard';   // after successful opponent slap
  static const peekResult = 'peekResult'; // client acks a peek
  static const initialPeekDone = 'initialPeekDone';

  // Server → Client
  static const lobbyState = 'lobbyState';
  static const gameStateUpdate = 'gameStateUpdate';
  static const peekReveal = 'peekReveal'; // server reveals a card to ONE player
  static const cardsPicked = 'cardsPicked'; // Queen/King: card positions, to everyone
  static const matchAttemptResult = 'matchAttemptResult';
  static const error = 'error';
  static const roundEnd = 'roundEnd';
  static const gameOver = 'gameOver';
}

// ─── Base message ─────────────────────────────────────────────────────────────

class GameMessage {
  final String type;
  final Map<String, dynamic> payload;

  const GameMessage({required this.type, required this.payload});

  Map<String, dynamic> toJson() => {'type': type, 'payload': payload};

  factory GameMessage.fromJson(Map<String, dynamic> json) => GameMessage(
        type: json['type'] as String,
        payload: (json['payload'] as Map<String, dynamic>?) ?? {},
      );
}

// ─── Lobby state (server → all clients) ──────────────────────────────────────

class LobbyStatePayload {
  final List<Map<String, dynamic>> players; // id + name + isConnected
  final String hostId;
  final bool canStart;

  const LobbyStatePayload({
    required this.players,
    required this.hostId,
    required this.canStart,
  });

  Map<String, dynamic> toJson() => {
        'players': players,
        'hostId': hostId,
        'canStart': canStart,
      };
}

// ─── Game state update (server → each client, personalised) ──────────────────

/// The server sends each player their own hand in full,
/// and all opponents' hands masked (hidden:true).
class GameStatePayload {
  final String phase;
  final String turnPhase;
  final String? currentPlayerId;
  final String? caboCallerId;
  final int turnsRemainingAfterCabo;
  final int drawPileCount;
  final CaboCard? topDiscard;
  final CaboCard? drawnCard; // only non-null for the drawing player
  final List<Map<String, dynamic>> players; // mixed full/masked hands
  final bool isCaboCalled;
  /// Rolling commentary log — last 6 actions, newest first.
  final List<String> actionLog;
  /// Player IDs who confirmed initial peek.
  final List<String> peekConfirmedIds;
  /// Whether the match/slap window is currently open.
  final bool matchWindowOpen;
  /// Set to the attacker's player ID when they must give a card after a successful opponent slap.
  final String? pendingGiveCardAttackerId;
  /// The target player (opponent) for a pending give-card action.
  final String? pendingGiveCardTargetId;
  /// Set to the player looking at a peeked card. The game holds until it clears.
  final String? peekHoldActorId;
  /// The player whose card is being looked at, which may be the actor.
  final String? peekHoldTargetId;

  const GameStatePayload({
    required this.phase,
    required this.turnPhase,
    this.currentPlayerId,
    this.caboCallerId,
    required this.turnsRemainingAfterCabo,
    required this.drawPileCount,
    this.topDiscard,
    this.drawnCard,
    required this.players,
    required this.isCaboCalled,
    this.actionLog = const [],
    this.peekConfirmedIds = const [],
    this.matchWindowOpen = false,
    this.pendingGiveCardAttackerId,
    this.pendingGiveCardTargetId,
    this.peekHoldActorId,
    this.peekHoldTargetId,
  });

  Map<String, dynamic> toJson() => {
        'phase': phase,
        'turnPhase': turnPhase,
        'currentPlayerId': currentPlayerId,
        'caboCallerId': caboCallerId,
        'turnsRemainingAfterCabo': turnsRemainingAfterCabo,
        'drawPileCount': drawPileCount,
        'topDiscard': topDiscard?.toJson(),
        'drawnCard': drawnCard?.toJson(),
        'players': players,
        'isCaboCalled': isCaboCalled,
        'actionLog': actionLog,
        'peekConfirmedIds': peekConfirmedIds,
        'matchWindowOpen': matchWindowOpen,
        'pendingGiveCardAttackerId': pendingGiveCardAttackerId,
        'pendingGiveCardTargetId': pendingGiveCardTargetId,
        'peekHoldActorId': peekHoldActorId,
        'peekHoldTargetId': peekHoldTargetId,
      };

  factory GameStatePayload.fromJson(Map<String, dynamic> json) {
    final players = (json['players'] as List<dynamic>)
        .map((p) => p as Map<String, dynamic>)
        .toList();
    final log = (json['actionLog'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    return GameStatePayload(
      phase: json['phase'] as String,
      turnPhase: json['turnPhase'] as String,
      currentPlayerId: json['currentPlayerId'] as String?,
      caboCallerId: json['caboCallerId'] as String?,
      turnsRemainingAfterCabo: json['turnsRemainingAfterCabo'] as int,
      drawPileCount: json['drawPileCount'] as int,
      topDiscard: json['topDiscard'] != null
          ? CaboCard.fromJson(json['topDiscard'] as Map<String, dynamic>)
          : null,
      drawnCard: json['drawnCard'] != null
          ? CaboCard.fromJson(json['drawnCard'] as Map<String, dynamic>)
          : null,
      players: players,
      isCaboCalled: json['isCaboCalled'] as bool,
      actionLog: log,
      peekConfirmedIds: (json['peekConfirmedIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      matchWindowOpen: json['matchWindowOpen'] as bool? ?? false,
      pendingGiveCardAttackerId: json['pendingGiveCardAttackerId'] as String?,
      pendingGiveCardTargetId: json['pendingGiveCardTargetId'] as String?,
      peekHoldActorId: json['peekHoldActorId'] as String?,
      peekHoldTargetId: json['peekHoldTargetId'] as String?,
    );
  }
}

// ─── Peek reveal (server → ONE client only) ───────────────────────────────────

class PeekRevealPayload {
  final String targetPlayerId;
  final int row;
  final int col;
  final CaboCard card;
  final bool isInitialPeek; // true during the pre-game peek phase

  const PeekRevealPayload({
    required this.targetPlayerId,
    required this.row,
    required this.col,
    required this.card,
    this.isInitialPeek = false,
  });

  Map<String, dynamic> toJson() => {
        'targetPlayerId': targetPlayerId,
        'row': row,
        'col': col,
        'card': card.toJson(),
        'isInitialPeek': isInitialPeek,
      };

  factory PeekRevealPayload.fromJson(Map<String, dynamic> json) =>
      PeekRevealPayload(
        targetPlayerId: json['targetPlayerId'] as String,
        row: json['row'] as int,
        col: json['col'] as int,
        card: CaboCard.fromJson(json['card'] as Map<String, dynamic>),
        isInitialPeek: json['isInitialPeek'] as bool? ?? false,
      );
}

// ─── Match attempt result (server → all clients) ─────────────────────────────

/// Which card positions a Queen or King picked. Sent to everyone, and on purpose
/// says nothing about the cards themselves or whether a swap actually happened.
class CardsPickedPayload {
  final String actorId;
  final String targetId;
  final int? actorRow; // null only if the actor has no cards left
  final int? actorCol;
  final int targetRow;
  final int targetCol;

  const CardsPickedPayload({
    required this.actorId,
    required this.targetId,
    this.actorRow,
    this.actorCol,
    required this.targetRow,
    required this.targetCol,
  });

  Map<String, dynamic> toJson() => {
        'actorId': actorId,
        'targetId': targetId,
        'actorRow': actorRow,
        'actorCol': actorCol,
        'targetRow': targetRow,
        'targetCol': targetCol,
      };

  factory CardsPickedPayload.fromJson(Map<String, dynamic> json) =>
      CardsPickedPayload(
        actorId: json['actorId'] as String,
        targetId: json['targetId'] as String,
        actorRow: json['actorRow'] as int?,
        actorCol: json['actorCol'] as int?,
        targetRow: json['targetRow'] as int,
        targetCol: json['targetCol'] as int,
      );
}

class MatchAttemptResultPayload {
  final String attemptingPlayerId;
  final String targetPlayerId; // may == attemptingPlayerId
  final int row;
  final int col;
  final bool success; // true = card removed, false = penalty card added
  final CaboCard? revealedCard; // the card that was there

  const MatchAttemptResultPayload({
    required this.attemptingPlayerId,
    required this.targetPlayerId,
    required this.row,
    required this.col,
    required this.success,
    this.revealedCard,
  });

  Map<String, dynamic> toJson() => {
        'attemptingPlayerId': attemptingPlayerId,
        'targetPlayerId': targetPlayerId,
        'row': row,
        'col': col,
        'success': success,
        'revealedCard': revealedCard?.toJson(),
      };

  factory MatchAttemptResultPayload.fromJson(Map<String, dynamic> json) =>
      MatchAttemptResultPayload(
        attemptingPlayerId: json['attemptingPlayerId'] as String,
        targetPlayerId: json['targetPlayerId'] as String,
        row: json['row'] as int,
        col: json['col'] as int,
        success: json['success'] as bool,
        revealedCard: json['revealedCard'] != null
            ? CaboCard.fromJson(json['revealedCard'] as Map<String, dynamic>)
            : null,
      );
}

// ─── Round / game end (server → all clients) ─────────────────────────────────

class PlayerScore {
  final String playerId;
  final String playerName;
  final int totalValue;
  final int cardCount;
  final bool calledCabo;
  final bool isWinner;

  const PlayerScore({
    required this.playerId,
    required this.playerName,
    required this.totalValue,
    required this.cardCount,
    required this.calledCabo,
    required this.isWinner,
  });

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'playerName': playerName,
        'totalValue': totalValue,
        'cardCount': cardCount,
        'calledCabo': calledCabo,
        'isWinner': isWinner,
      };

  factory PlayerScore.fromJson(Map<String, dynamic> json) => PlayerScore(
        playerId: json['playerId'] as String,
        playerName: json['playerName'] as String,
        totalValue: json['totalValue'] as int,
        cardCount: json['cardCount'] as int,
        calledCabo: json['calledCabo'] as bool,
        isWinner: json['isWinner'] as bool,
      );
}

class RoundEndPayload {
  final List<PlayerScore> scores;
  final String winnerId;

  const RoundEndPayload({required this.scores, required this.winnerId});

  Map<String, dynamic> toJson() => {
        'scores': scores.map((s) => s.toJson()).toList(),
        'winnerId': winnerId,
      };

  factory RoundEndPayload.fromJson(Map<String, dynamic> json) =>
      RoundEndPayload(
        scores: (json['scores'] as List<dynamic>)
            .map((s) => PlayerScore.fromJson(s as Map<String, dynamic>))
            .toList(),
        winnerId: json['winnerId'] as String,
      );
}
