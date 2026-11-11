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
  static const clockPing = 'clockPing'; // measures the gap to the server clock
  static const activateSlap = 'activateSlap'; // current player wants to slap mid-turn
  static const startPower = 'startPower'; // done letting everyone slap; power begins
  static const rejoin = 'rejoin'; // take back a seat after a dropped connection

  // Server → Client
  static const lobbyState = 'lobbyState';
  static const gameStateUpdate = 'gameStateUpdate';
  static const peekReveal = 'peekReveal'; // server reveals a card to ONE player
  static const cardsPicked = 'cardsPicked'; // Queen/King: card positions, to everyone
  static const clockPong = 'clockPong'; // answer to clockPing
  static const slapActivated = 'slapActivated'; // banner for everyone, maybe with a countdown
  static const rejoinFailed = 'rejoinFailed'; // the seat is gone, e.g. the round ended
  static const seatTaken = 'seatTaken'; // the same seat connected from somewhere else
  static const slapRanking = 'slapRanking'; // who tried to slap this card, in order
  static const tableAnimation = 'tableAnimation'; // card movements for every screen to play
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
  /// Which card position is being looked at. Never the card itself.
  final int? peekHoldRow;
  final int? peekHoldCol;
  /// The current player is away: how long until the game plays for them.
  final int? awayActionInMs;
  /// The current player discarded a power card and is letting everyone slap
  /// it before they use the power.
  final bool slapBeforePower;
  /// A 3-2-1 is running: how long until slapping opens.
  final int? slapOpensInMs;

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
    this.peekHoldRow,
    this.peekHoldCol,
    this.awayActionInMs,
    this.slapBeforePower = false,
    this.slapOpensInMs,
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
        'peekHoldRow': peekHoldRow,
        'peekHoldCol': peekHoldCol,
        'awayActionInMs': awayActionInMs,
        'slapBeforePower': slapBeforePower,
        'slapOpensInMs': slapOpensInMs,
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
      peekHoldRow: json['peekHoldRow'] as int?,
      peekHoldCol: json['peekHoldCol'] as int?,
      awayActionInMs: json['awayActionInMs'] as int?,
      slapBeforePower: json['slapBeforePower'] as bool? ?? false,
      slapOpensInMs: json['slapOpensInMs'] as int?,
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

/// A card's position in a hand, in words. Rows past the first two are extras.
String cardPositionName(int row, int col) {
  if (row > 1) return 'extra';
  return '${row == 0 ? 'top' : 'bottom'}-${col == 0 ? 'left' : 'right'}';
}

/// Which card positions a Queen or King picked. Sent to everyone, and on purpose
/// says nothing about the cards themselves or whether a swap actually happened.
/// A place on the table a card can move from or to.
class CardSpot {
  static const deck = 'deck';
  static const discard = 'discard';
  static const held = 'held'; // the card a player has drawn
  static const slot = 'slot';

  final String kind;
  final String? playerId;
  final int? row;
  final int? col;

  const CardSpot.deckPile()
      : kind = deck,
        playerId = null,
        row = null,
        col = null;
  const CardSpot.discardPile()
      : kind = discard,
        playerId = null,
        row = null,
        col = null;
  const CardSpot.heldBy(String this.playerId)
      : kind = held,
        row = null,
        col = null;
  const CardSpot.inHand(String this.playerId, int this.row, int this.col)
      : kind = slot;
  const CardSpot._(this.kind, this.playerId, this.row, this.col);

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'playerId': playerId,
        'row': row,
        'col': col,
      };

  factory CardSpot.fromJson(Map<String, dynamic> json) => CardSpot._(
        json['kind'] as String,
        json['playerId'] as String?,
        json['row'] as int?,
        json['col'] as int?,
      );
}

/// One card travelling across the table.
class CardMove {
  final CardSpot from;
  final CardSpot to;
  /// The card's face, only when everyone may see it. Null travels face down.
  final CaboCard? card;
  final int delayMs;

  const CardMove({
    required this.from,
    required this.to,
    this.card,
    this.delayMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'from': from.toJson(),
        'to': to.toJson(),
        'card': card?.toJson(),
        'delayMs': delayMs,
      };

  factory CardMove.fromJson(Map<String, dynamic> json) => CardMove(
        from: CardSpot.fromJson(json['from'] as Map<String, dynamic>),
        to: CardSpot.fromJson(json['to'] as Map<String, dynamic>),
        card: json['card'] != null
            ? CaboCard.fromJson(json['card'] as Map<String, dynamic>)
            : null,
        delayMs: json['delayMs'] as int? ?? 0,
      );
}

/// A slapped card, shown face up to everyone whatever the result.
class SlapReveal {
  final String playerId;
  final String targetId;
  final int row;
  final int col;
  final CaboCard card;
  /// 'right', 'wrong', or 'late'.
  final String result;

  const SlapReveal({
    required this.playerId,
    required this.targetId,
    required this.row,
    required this.col,
    required this.card,
    required this.result,
  });

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'targetId': targetId,
        'row': row,
        'col': col,
        'card': card.toJson(),
        'result': result,
      };

  factory SlapReveal.fromJson(Map<String, dynamic> json) => SlapReveal(
        playerId: json['playerId'] as String,
        targetId: json['targetId'] as String,
        row: json['row'] as int,
        col: json['col'] as int,
        card: CaboCard.fromJson(json['card'] as Map<String, dynamic>),
        result: json['result'] as String,
      );
}

/// What every screen should play. Sent just before the game state it leads to,
/// so each screen still knows where the cards were.
class TableAnimationPayload {
  final List<CardMove> moves;
  final List<SlapReveal> slapReveals;
  final String? skippedPlayerId;
  final bool reshuffled;
  /// A card lifted and highlighted, face down, before it moves.
  final CardSpot? highlight;
  final int highlightMs;

  const TableAnimationPayload({
    this.moves = const [],
    this.slapReveals = const [],
    this.skippedPlayerId,
    this.reshuffled = false,
    this.highlight,
    this.highlightMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'moves': moves.map((m) => m.toJson()).toList(),
        'slapReveals': slapReveals.map((r) => r.toJson()).toList(),
        'skippedPlayerId': skippedPlayerId,
        'reshuffled': reshuffled,
        'highlight': highlight?.toJson(),
        'highlightMs': highlightMs,
      };

  factory TableAnimationPayload.fromJson(Map<String, dynamic> json) =>
      TableAnimationPayload(
        moves: (json['moves'] as List<dynamic>)
            .map((m) => CardMove.fromJson(m as Map<String, dynamic>))
            .toList(),
        slapReveals: (json['slapReveals'] as List<dynamic>)
            .map((r) => SlapReveal.fromJson(r as Map<String, dynamic>))
            .toList(),
        skippedPlayerId: json['skippedPlayerId'] as String?,
        reshuffled: json['reshuffled'] as bool? ?? false,
        highlight: json['highlight'] != null
            ? CardSpot.fromJson(json['highlight'] as Map<String, dynamic>)
            : null,
        highlightMs: json['highlightMs'] as int? ?? 0,
      );
}

class SlapRankEntry {
  final String playerId;
  /// Milliseconds behind the first slap on this card.
  final int gapMs;
  /// 'pending' until judged, then 'right', 'wrong', or 'late' (the card had gone).
  final String result;

  const SlapRankEntry({
    required this.playerId,
    required this.gapMs,
    required this.result,
  });

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'gapMs': gapMs,
        'result': result,
      };

  factory SlapRankEntry.fromJson(Map<String, dynamic> json) => SlapRankEntry(
        playerId: json['playerId'] as String,
        gapMs: json['gapMs'] as int,
        result: json['result'] as String,
      );
}

/// Everyone who tried to slap one discard, fastest first.
class SlapRankingPayload {
  /// Changes with every new card that can be slapped.
  final int cardNo;
  final List<SlapRankEntry> entries;

  const SlapRankingPayload({required this.cardNo, required this.entries});

  Map<String, dynamic> toJson() => {
        'cardNo': cardNo,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory SlapRankingPayload.fromJson(Map<String, dynamic> json) =>
      SlapRankingPayload(
        cardNo: json['cardNo'] as int,
        entries: (json['entries'] as List<dynamic>)
            .map((e) => SlapRankEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The current player switched to slapping while holding a drawn card. With a
/// countdown, the slap window opens for everyone once it runs out.
class SlapActivatedPayload {
  final String playerId;
  final int countdownMs;

  const SlapActivatedPayload({required this.playerId, this.countdownMs = 0});

  Map<String, dynamic> toJson() => {'playerId': playerId, 'countdownMs': countdownMs};

  factory SlapActivatedPayload.fromJson(Map<String, dynamic> json) =>
      SlapActivatedPayload(
        playerId: json['playerId'] as String,
        countdownMs: json['countdownMs'] as int? ?? 0,
      );
}

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
