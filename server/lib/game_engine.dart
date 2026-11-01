import 'dart:math';
import 'package:cabo_shared/models/card_model.dart';
import 'package:cabo_shared/models/player_model.dart';
import 'package:cabo_shared/models/game_state.dart';
import 'package:cabo_shared/models/messages.dart';

/// Pure game logic — no I/O.
class GameEngine {
  static const maxPlayers = 4;

  final GameState state;
  final Random _rng;
  /// How many times the discard pile has been shuffled into a new deck.
  int reshuffleCount = 0;
  /// Where the latest penalty card landed, if one was dealt.
  (int, int)? lastPenaltySlot;

  GameEngine({Random? random})
      : state = GameState(),
        _rng = random ?? Random();

  // ─── Deck ────────────────────────────────────────────────────────────────────

  static List<CaboCard> buildDeck() {
    final deck = <CaboCard>[];
    for (final suit in Suit.values) {       // 4 suits
      for (final rank in Rank.values) {    // 13 ranks each
        deck.add(CaboCard(suit: suit, rank: rank));
      }
    }
    // Hard assertions — these must never fail
    assert(deck.length == 52,
        'Deck size wrong: ${deck.length} (expected 52)');
    assert(deck.toSet().length == 52,
        'Deck contains duplicates! Unique: ${deck.toSet().length}');
    return deck;
  }

  void _shuffle(List<CaboCard> deck) {
    for (int i = deck.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final tmp = deck[i];
      deck[i] = deck[j];
      deck[j] = tmp;
    }
  }

  // ─── Lobby ───────────────────────────────────────────────────────────────────

  /// Returns the new player.
  Player addPlayer(String id, String name) {
    if (state.players.length >= maxPlayers) throw Exception('Game is full');
    final player = Player(id: id, name: name);
    state.players.add(player);
    return player;
  }

  void removePlayer(String id) {
    // In the lobby, free the seat. The first remaining player becomes host.
    if (state.phase == GamePhase.lobby) {
      state.players.removeWhere((p) => p.id == id);
      return;
    }
    final p = state.getPlayer(id);
    if (p != null) p.isConnected = false;
  }

  String get hostId => state.players.isNotEmpty ? state.players.first.id : '';

  // ─── Start game ──────────────────────────────────────────────────────────────

  void startGame() {
    if (state.players.length < 2) throw Exception('Need at least 2 players');

    final deck = buildDeck();
    _shuffle(deck);

    state.drawPile.clear();
    state.drawPile.addAll(deck);
    state.discardPile.clear();

    // Deal 4 cards to each player in 2x2 matrix
    for (final player in state.players) {
      for (int r = 0; r < 2; r++) {
        for (int c = 0; c < 2; c++) {
          player.setCard(r, c, state.drawPile.removeLast());
        }
      }
    }

    final dealtCards = state.players.length * 4;
    final drawCount = state.drawPile.length;
    assert(dealtCards + drawCount == 52,
        'Card count mismatch: $dealtCards dealt + $drawCount draw = ${dealtCards + drawCount} (expected 52)');
    print('[Game] Deck verified: 52 cards | '
        '${state.players.length} players × 4 = $dealtCards dealt | '
        '$drawCount in draw pile | 0 in discard');

    state.phase = GamePhase.initialPeek;
    state.turnPhase = TurnPhase.waitingForDraw;
    state.currentPlayerId = state.players.first.id;
    state.caboCallerId = null;
    state.turnsRemainingAfterCabo = -1;
  }

  /// Returns the two bottom-row cards the player is allowed to peek at start.
  List<PeekRevealPayload> initialPeekCards(String playerId) {
    final player = state.getPlayer(playerId);
    if (player == null) return [];
    // Bottom row = row 1
    return [
      PeekRevealPayload(
        targetPlayerId: playerId,
        row: 1,
        col: 0,
        card: player.hand[1][0]!,
        isInitialPeek: true,
      ),
      PeekRevealPayload(
        targetPlayerId: playerId,
        row: 1,
        col: 1,
        card: player.hand[1][1]!,
        isInitialPeek: true,
      ),
    ];
  }

  /// Called when a player confirms they've seen their initial peek.
  /// Returns true when ALL players have confirmed and the game can start.
  final Set<String> _initialPeekDone = {};

  bool confirmInitialPeek(String playerId) {
    _initialPeekDone.add(playerId);
    final connectedIds = state.players.where((p) => p.isConnected).map((p) => p.id).toSet();
    if (_initialPeekDone.containsAll(connectedIds)) {
      state.phase = GamePhase.playing;
      return true;
    }
    return false;
  }

  // ─── Turn: draw ──────────────────────────────────────────────────────────────

  CaboCard drawFromPile(String playerId) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.waitingForDraw);

    if (state.drawPile.isEmpty) _reshuffleDiscard();
    final card = state.drawPile.removeLast();
    state.drawnCard = card;
    state.turnPhase = TurnPhase.cardDrawn;
    return card;
  }

  // ─── Turn: after drawing ─────────────────────────────────────────────────────

  /// Player discards the drawn card (and may use its power).
  void discardDrawn(String playerId) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.cardDrawn);

    final card = state.drawnCard!;
    state.discardPile.add(card);
    state.drawnCard = null;

    if (card.power == CardPower.skipTurn) {
      // Jack: automatically skip the next player, no power phase
      _endTurnSkipping();
    } else if (card.hasPower) {
      state.turnPhase = TurnPhase.usingPower;
    } else {
      _endTurn();
    }
  }

  /// Player swaps drawn card with one of their own hand slots.
  /// The displaced hand card goes to discard. Power is forfeited.
  CaboCard swapDrawnWithHand(String playerId, int row, int col) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.cardDrawn);

    final player = state.getPlayer(playerId)!;
    final handCard = player.hand[row][col];
    if (handCard == null) throw Exception('No card at that slot');

    player.setCard(row, col, state.drawnCard);
    state.discardPile.add(handCard);
    state.drawnCard = null;
    _endTurn();
    return handCard; // returned to discard visually
  }

  // ─── Turn: skip power ────────────────────────────────────────────────────────

  void skipPower(String playerId) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.usingPower);
    _endTurn();
  }

  // ─── Powers ──────────────────────────────────────────────────────────────────

  /// 7/8 – peek one of YOUR cards. Returns the peeked card.
  PeekRevealPayload usePeekOwn(String playerId, int row, int col) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.usingPower);

    final player = state.getPlayer(playerId)!;
    final card = player.hand[row][col];
    if (card == null) throw Exception('No card at slot');

    final reveal = PeekRevealPayload(
      targetPlayerId: playerId,
      row: row,
      col: col,
      card: card,
    );
    return reveal;
  }

  /// 9/10 – peek one of an opponent's cards. Returns the peeked card.
  PeekRevealPayload usePeekOpponent(String playerId, String targetId, int row, int col) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.usingPower);
    if (targetId == playerId) throw Exception('Must target an opponent');

    final target = state.getPlayer(targetId);
    if (target == null) throw Exception('Player not found');
    final card = target.hand[row][col];
    if (card == null) throw Exception('No card at slot');

    final reveal = PeekRevealPayload(
      targetPlayerId: targetId,
      row: row,
      col: col,
      card: card,
    );
    return reveal;
  }

  /// 7/8/9/10 – the player has finished looking at the peeked card.
  void finishPeek() => _endTurn();

  /// Queen – blindly swap your card at (myRow,myCol) with target's (theirRow,theirCol).
  void useBlindSwap(
    String playerId,
    int myRow, int myCol,
    String targetId, int theirRow, int theirCol,
  ) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.usingPower);

    final me = state.getPlayer(playerId)!;
    final them = state.getPlayer(targetId);
    if (them == null) throw Exception('Player not found');

    final myCard = me.hand[myRow][myCol];
    final theirCard = them.hand[theirRow][theirCol];

    me.setCard(myRow, myCol, theirCard);
    them.setCard(theirRow, theirCol, myCard);
    _endTurn();
  }

  /// Red King – peek opponent card, then optionally swap.
  /// Step 1: reveal the card to the acting player.
  PeekRevealPayload useSmartSwapPeek(
    String playerId,
    String targetId, int theirRow, int theirCol,
  ) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.usingPower);

    final target = state.getPlayer(targetId);
    if (target == null) throw Exception('Player not found');
    final card = target.hand[theirRow][theirCol];
    if (card == null) throw Exception('No card at slot');

    // Stay in usingPower phase until player decides to swap or skip.
    return PeekRevealPayload(
      targetPlayerId: targetId,
      row: theirRow,
      col: theirCol,
      card: card,
    );
  }

  /// Red King – Step 2: commit the swap (or pass null myRow/myCol to decline).
  /// A random card position in the player's hand, or null if they have none.
  (int, int)? randomOccupiedSlot(String playerId) {
    final hand = state.getPlayer(playerId)!.hand;
    final slots = <(int, int)>[
      for (int r = 0; r < hand.length; r++)
        for (int c = 0; c < hand[r].length; c++)
          if (hand[r][c] != null) (r, c),
    ];
    return slots.isEmpty ? null : slots[_rng.nextInt(slots.length)];
  }

  void useSmartSwapCommit(
    String playerId,
    int? myRow, int? myCol,
    String targetId, int theirRow, int theirCol,
  ) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.usingPower);

    if (myRow != null && myCol != null) {
      final me = state.getPlayer(playerId)!;
      final them = state.getPlayer(targetId)!;
      final myCard = me.hand[myRow][myCol];
      final theirCard = them.hand[theirRow][theirCol];
      me.setCard(myRow, myCol, theirCard);
      them.setCard(theirRow, theirCol, myCard);
    }
    _endTurn();
  }

  // ─── Match (slap mechanic) ────────────────────────────────────────────────────

  /// A player claims a card in targetPlayer's hand matches the top discard.
  /// Returns the result. If wrong, a penalty card is dealt to the attacker.
  MatchAttemptResultPayload attemptMatch(
    String attackerId,
    String targetId,
    int row,
    int col,
  ) {
    final topDiscard = state.topDiscard;
    if (topDiscard == null) throw Exception('No discard card');

    final target = state.getPlayer(targetId);
    if (target == null) throw Exception('Player not found');

    lastPenaltySlot = null;
    final card = target.hand[row][col];
    if (card == null) {
      return MatchAttemptResultPayload(
        attemptingPlayerId: attackerId,
        targetPlayerId: targetId,
        row: row,
        col: col,
        success: false,
        revealedCard: null,
      );
    }

    final success = card.matchesRank(topDiscard);
    if (success) {
      target.removeCard(row, col);
      state.discardPile.add(card);
    } else {
      // Penalty: attacker gets a new card in any open slot
      _dealPenaltyCard(attackerId);
    }

    return MatchAttemptResultPayload(
      attemptingPlayerId: attackerId,
      targetPlayerId: targetId,
      row: row,
      col: col,
      success: success,
      revealedCard: card,
    );
  }

  /// Deals one penalty card to the player.
  /// Returns true if the player was eliminated (already at 8-card maximum).
  bool _dealPenaltyCard(String playerId) {
    lastPenaltySlot = null;
    final player = state.getPlayer(playerId)!;

    // Count filled slots across all rows
    final filled = player.hand
        .expand((row) => row)
        .where((c) => c != null)
        .length;

    // Max 8 cards (4 original + 4 penalties). A 5th penalty = elimination.
    if (filled >= 8) {
      player.isEliminated = true;
      return true;
    }

    if (state.drawPile.isEmpty) _reshuffleDiscard();
    if (state.drawPile.isEmpty) return false; // no cards left — skip penalty
    final penalty = state.drawPile.removeLast();

    // Scan ALL rows (including any overflow rows) left-to-right, top-to-bottom
    // so new penalty cards fill horizontally before starting a new row.
    for (int r = 0; r < player.hand.length; r++) {
      for (int c = 0; c < player.hand[r].length; c++) {
        if (player.hand[r][c] == null) {
          player.setCard(r, c, penalty);
          lastPenaltySlot = (r, c);
          return false;
        }
      }
    }

    // Every existing slot is occupied — add a new overflow row.
    player.hand.add([penalty, null]);
    lastPenaltySlot = (player.hand.length - 1, 0);
    return false;
  }

  // ─── Cabo ────────────────────────────────────────────────────────────────────

  void callCabo(String playerId) {
    _assertTurn(playerId);
    _assertTurnPhase(TurnPhase.waitingForDraw);
    if (state.isCaboCalled) throw Exception('Cabo already called');

    state.caboCallerId = playerId;
    // End the round immediately when CABO is called
    state.turnsRemainingAfterCabo = 0;
    _endTurn();
  }

  // ─── Round end ───────────────────────────────────────────────────────────────

  List<PlayerScore> computeScores() {
    final scores = state.players.map((p) {
      return PlayerScore(
        playerId: p.id,
        playerName: p.name,
        totalValue: p.totalValue,
        cardCount: p.cardCount,
        calledCabo: p.id == state.caboCallerId,
        isWinner: false,
      );
    }).toList();

    // Eliminated players sort to the bottom; among active players: fewest cards then lowest total
    final eliminatedIds = state.players
        .where((p) => p.isEliminated)
        .map((p) => p.id)
        .toSet();

    scores.sort((a, b) {
      final aElim = eliminatedIds.contains(a.playerId);
      final bElim = eliminatedIds.contains(b.playerId);
      if (aElim != bElim) return aElim ? 1 : -1;
      if (a.cardCount != b.cardCount) return a.cardCount.compareTo(b.cardCount);
      return a.totalValue.compareTo(b.totalValue);
    });

    final winner = scores.first;
    return scores
        .map((s) => PlayerScore(
              playerId: s.playerId,
              playerName: s.playerName,
              totalValue: s.totalValue,
              cardCount: s.cardCount,
              calledCabo: s.calledCabo,
              isWinner: s.playerId == winner.playerId,
            ))
        .toList();
  }

  /// True when only one (or zero) active players remain — round should end.
  bool get onlyOneActivePlayerLeft => state.activePlayerCount <= 1;

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  void _endTurn() {
    state.drawnCard = null;
    state.turnPhase = TurnPhase.waitingForDraw;

    if (state.isCaboCalled) {
      state.turnsRemainingAfterCabo--;
      if (state.turnsRemainingAfterCabo <= 0) {
        state.phase = GamePhase.roundEnd;
        return;
      }
    }

    state.currentPlayerId = state.getNextPlayerId(state.currentPlayerId!);
  }

  /// Jack power: skip the next player in turn order.
  void _endTurnSkipping() {
    state.drawnCard = null;
    state.turnPhase = TurnPhase.waitingForDraw;

    if (state.isCaboCalled) {
      // Current player and skipped player both consume a remaining turn
      state.turnsRemainingAfterCabo -= 2;
      if (state.turnsRemainingAfterCabo <= 0) {
        state.phase = GamePhase.roundEnd;
        return;
      }
    }

    // Advance two slots: skip the immediate next player
    final skippedId = state.getNextPlayerId(state.currentPlayerId!);
    state.currentPlayerId = state.getNextPlayerId(skippedId!);
  }

  void _reshuffleDiscard() {
    if (state.discardPile.length <= 1) return;
    reshuffleCount++;
    final top = state.discardPile.removeLast();
    _shuffle(state.discardPile);
    state.drawPile.addAll(state.discardPile);
    state.discardPile
      ..clear()
      ..add(top);
  }

  void _assertTurn(String playerId) {
    if (state.currentPlayerId != playerId) {
      throw Exception('Not your turn');
    }
  }

  void _assertTurnPhase(TurnPhase expected) {
    if (state.turnPhase != expected) {
      throw Exception('Wrong phase: ${state.turnPhase}, expected $expected');
    }
  }

  // ─── Serialisation helpers ────────────────────────────────────────────────────

  Set<String> get confirmedPeekIds => Set.unmodifiable(_initialPeekDone);

  /// Move one card from attacker's hand slot to the target's hand.
  /// Fills an existing empty slot in the target's hand before adding a new row.
  /// Returns where the card landed.
  (int, int) giveCard(String attackerId, String targetId, int row, int col) {
    final attacker = state.getPlayer(attackerId)!;
    final target = state.getPlayer(targetId)!;
    final card = attacker.hand[row][col];
    if (card == null) throw Exception('No card at that slot');
    attacker.removeCard(row, col);
    // Fill first available empty slot, same logic as penalty card dealing
    for (int r = 0; r < target.hand.length; r++) {
      for (int c = 0; c < target.hand[r].length; c++) {
        if (target.hand[r][c] == null) {
          target.setCard(r, c, card);
          return (r, c);
        }
      }
    }
    // No empty slot — add overflow row
    target.hand.add([card, null]);
    return (target.hand.length - 1, 0);
  }

  /// Build personalised GameStatePayload for one player.
  GameStatePayload buildStateFor(
    String viewerId, {
    List<String> actionLog = const [],
    bool matchWindowOpen = false,
    String? pendingGiveCardAttackerId,
    String? pendingGiveCardTargetId,
    String? peekHoldActorId,
    String? peekHoldTargetId,
    int? peekHoldRow,
    int? peekHoldCol,
  }) {
    // At round end reveal ALL cards to everyone
    final revealAll = state.phase == GamePhase.roundEnd;
    final playerMaps = state.players.map((p) {
      if (p.id == viewerId || revealAll) return p.toJson();
      return p.toPublicJson();
    }).toList();

    return GameStatePayload(
      phase: state.phase.name,
      turnPhase: state.turnPhase.name,
      currentPlayerId: state.currentPlayerId,
      caboCallerId: state.caboCallerId,
      turnsRemainingAfterCabo: state.turnsRemainingAfterCabo,
      drawPileCount: state.drawPileCount,
      topDiscard: state.topDiscard,
      drawnCard: state.currentPlayerId == viewerId ? state.drawnCard : null,
      players: playerMaps,
      isCaboCalled: state.isCaboCalled,
      actionLog: List.unmodifiable(actionLog),
      peekConfirmedIds: List.unmodifiable(_initialPeekDone.toList()),
      matchWindowOpen: matchWindowOpen,
      pendingGiveCardAttackerId: pendingGiveCardAttackerId,
      pendingGiveCardTargetId: pendingGiveCardTargetId,
      peekHoldActorId: peekHoldActorId,
      peekHoldTargetId: peekHoldTargetId,
      peekHoldRow: peekHoldRow,
      peekHoldCol: peekHoldCol,
    );
  }
}
