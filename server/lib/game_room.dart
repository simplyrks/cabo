import 'dart:convert';
import 'dart:io';

import 'package:cabo_shared/models/messages.dart';
import 'package:cabo_shared/models/game_state.dart';
import 'game_engine.dart';

class ClientSession {
  final String playerId;
  final WebSocket socket;
  ClientSession({required this.playerId, required this.socket});
}

/// One isolated game table. Every room has its own engine, players and log, so
/// games in different rooms can't affect each other.
class GameRoom {
  final String code;
  final void Function(GameRoom room) onEmpty;
  GameEngine _engine = GameEngine();
  final Map<String, ClientSession> _sessions = {};
  /// Every open socket in this room, including players who aren't seated yet
  /// or are still looking at the scores from the last round.
  final Set<WebSocket> _connections = {};
  final List<String> _actionLog = [];

  // ─── Match window ─────────────────────────────────────────────────────────────
  bool _matchWindowOpen = false;
  /// Players who have already used their one slap attempt this window.
  final Set<String> _slapAttemptedIds = {};

  // ─── Pending give-card (after successful opponent slap) ───────────────────────
  String? _pendingGiveCardAttackerId;
  String? _pendingGiveCardTargetId;

  GameRoom({required this.code, required this.onEmpty});

  // ─── Lifecycle ────────────────────────────────────────────────────────────────

  int get playerCount => _engine.state.players.where((p) => p.isConnected).length;

  Map<String, dynamic> toSummary() {
    final String status;
    if (_engine.state.phase != GamePhase.lobby) {
      status = 'playing';
    } else if (playerCount >= GameEngine.maxPlayers) {
      status = 'full';
    } else {
      status = 'open';
    }
    return {
      'code': code,
      'players': playerCount,
      'maxPlayers': GameEngine.maxPlayers,
      'status': status,
    };
  }

  void addConnection(WebSocket ws) {
    print('[Room $code] New connection');
    _connections.add(ws);
    ws.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final msg = GameMessage.fromJson(json);
          _handleMessage(ws, msg);
        } catch (e) {
          _sendError(ws, 'Invalid message: $e');
        }
      },
      onDone: () => _handleDisconnect(ws),
      onError: (e) => print('[Room $code] Error: $e'),
    );
  }

  void _handleMessage(WebSocket ws, GameMessage msg) {
    try {
      switch (msg.type) {
        case MsgType.joinLobby:      _onJoinLobby(ws, msg.payload);
        case MsgType.startGame:      _onStartGame(ws, msg.payload);
        case MsgType.initialPeekDone: _onInitialPeekDone(ws, msg.payload);
        case MsgType.callCabo:       _onCallCabo(ws, msg.payload);
        case MsgType.drawFromPile:   _onDrawFromPile(ws, msg.payload);
        case MsgType.discardDrawn:   _onDiscardDrawn(ws, msg.payload);
        case MsgType.swapDrawnWithHand: _onSwapDrawnWithHand(ws, msg.payload);
        case MsgType.usePower:       _onUsePower(ws, msg.payload);
        case MsgType.skipPower:      _onSkipPower(ws, msg.payload);
        case MsgType.matchCard:      _onMatchCard(ws, msg.payload);
        case MsgType.giveCard:       _onGiveCard(ws, msg.payload);
        default: _sendError(ws, 'Unknown message type: ${msg.type}');
      }
    } catch (e) {
      _sendError(ws, e.toString());
    }
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────────

  void _onJoinLobby(WebSocket ws, Map<String, dynamic> payload) {
    if (_sessionFor(ws) != null) return; // already seated, e.g. a double tap
    if (_engine.state.phase != GamePhase.lobby) {
      _sendError(ws, 'Game already in progress');
      return;
    }
    final name = payload['name'] as String? ?? 'Player';
    final player = _engine.addPlayer(_newId(), name);
    _sessions[player.id] = ClientSession(playerId: player.id, socket: ws);

    _send(ws, GameMessage(
      type: 'welcome',
      payload: {'playerId': player.id, 'playerName': player.name, 'roomCode': code},
    ));
    _broadcastLobby();
  }

  void _onStartGame(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    if (session.playerId != _engine.hostId) {
      _sendError(ws, 'Only the host can start the game');
      return;
    }
    _engine.startGame();
    _log('🎮 Game started! Memorise your bottom 2 cards.');

    // Broadcast state FIRST so clients enter initialPeek phase and create listeners
    _broadcastState();

    // Then send peek reveals — clients are now ready to hear them
    for (final s in _sessions.values) {
      final peeks = _engine.initialPeekCards(s.playerId);
      for (final peek in peeks) {
        _send(s.socket, GameMessage(type: MsgType.peekReveal, payload: peek.toJson()));
      }
    }
  }

  void _onInitialPeekDone(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _log('$name is ready.');
    final allReady = _engine.confirmInitialPeek(session.playerId);
    if (allReady) {
      _log("Everyone's ready — let's play! ${_nameOf(_engine.state.currentPlayerId!)} goes first.");
    }
    // Always broadcast so all clients see the updated ready list
    _broadcastState();
  }

  void _onCallCabo(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _engine.callCabo(session.playerId);
    _log('🚨 $name called CABO! Last round for everyone.');
    _broadcastState();
    _checkRoundEnd();
  }

  void _onDrawFromPile(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _engine.drawFromPile(session.playerId);
    _log('$name drew a card from the pile.');
    _broadcastState();
  }

  void _onDiscardDrawn(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    // Capture drawn card BEFORE discarding
    final drawnCard = _engine.state.drawnCard;
    final drawnRank = drawnCard?.rank.name ?? '';
    final cardName = drawnCard != null
        ? _cardLabel(drawnCard.rank.name, drawnCard.suit.name)
        : 'a card';
    // For Jack: the skipped player is whoever was next before we advance
    final wouldBeNextId = _engine.state.getNextPlayerId(session.playerId);

    _engine.discardDrawn(session.playerId);

    // Using a power is the one time slapping stops.
    if (_engine.state.turnPhase == TurnPhase.usingPower) _closeMatchWindow();

    if (_engine.state.turnPhase == TurnPhase.usingPower) {
      final powerDesc = _powerDescription(drawnRank);
      _log('$name discarded $cardName — $powerDesc activated!');
    } else if (drawnRank == 'jack') {
      final skippedName = wouldBeNextId != null ? _nameOf(wouldBeNextId) : 'someone';
      final nowName = _engine.state.currentPlayerId != null
          ? _nameOf(_engine.state.currentPlayerId!)
          : '?';
      _log('$name played Jack ♠ — $skippedName is SKIPPED! $nowName goes next.');
    } else {
      _log('$name discarded $cardName. Next: ${_nameOf(_engine.state.currentPlayerId!)}\'s turn.');
    }
    _broadcastState();
    _checkRoundEnd();
    // A power card's slap window waits until the power is finished.
    if (_engine.state.turnPhase != TurnPhase.usingPower) _openMatchWindow();
  }

  void _onSwapDrawnWithHand(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _engine.swapDrawnWithHand(session.playerId, payload['row'] as int, payload['col'] as int);
    _log('$name swapped their drawn card with one of their own cards.');
    _broadcastState();
    _checkRoundEnd();
    if (_engine.state.phase != GamePhase.roundEnd) _openMatchWindow();
  }

  void _onSkipPower(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _engine.skipPower(session.playerId);
    _log('$name skipped their power. Next: ${_nameOf(_engine.state.currentPlayerId!)}\'s turn.');
    _broadcastState();
    _checkRoundEnd();
    _openMatchWindow();
  }

  void _onUsePower(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final pid = session.playerId;
    final name = _nameOf(pid);
    final action = payload['action'] as String;

    switch (action) {
      case 'peekOwn':
        final reveal = _engine.usePeekOwn(pid, payload['row'] as int, payload['col'] as int);
        _send(ws, GameMessage(type: MsgType.peekReveal, payload: reveal.toJson()));
        _log('$name peeked at one of their own hidden cards.');

      case 'peekOpponent':
        final targetName = _nameOf(payload['targetId'] as String);
        final reveal = _engine.usePeekOpponent(
          pid, payload['targetId'] as String,
          payload['row'] as int, payload['col'] as int,
        );
        _send(ws, GameMessage(type: MsgType.peekReveal, payload: reveal.toJson()));
        _log('$name secretly peeked at one of $targetName\'s cards.');

      case 'blindSwap':
        final targetName = _nameOf(payload['targetId'] as String);
        _engine.useBlindSwap(
          pid,
          payload['myRow'] as int, payload['myCol'] as int,
          payload['targetId'] as String,
          payload['theirRow'] as int, payload['theirCol'] as int,
        );
        _log('$name used the Queen on $targetName\'s card.');
        _broadcastCardsPicked(
          pid, payload['myRow'] as int, payload['myCol'] as int,
          payload['targetId'] as String,
          payload['theirRow'] as int, payload['theirCol'] as int,
        );

      case 'smartSwapPeek':
        final targetName = _nameOf(payload['targetId'] as String);
        final reveal = _engine.useSmartSwapPeek(
          pid, payload['targetId'] as String,
          payload['row'] as int, payload['col'] as int,
        );
        _send(ws, GameMessage(type: MsgType.peekReveal, payload: reveal.toJson()));
        _log('$name (Red King) peeked at $targetName\'s card — deciding whether to swap...');
        _broadcastState();
        return;

      case 'smartSwapCommit':
        final targetName = _nameOf(payload['targetId'] as String);
        // Everyone sees the same thing whether or not cards were swapped, so
        // if none was chosen, show a random position of the player's own.
        final myRow = payload['myRow'] as int?;
        final myCol = payload['myCol'] as int?;
        final shownSlot = myRow != null && myCol != null
            ? (myRow, myCol)
            : _engine.randomOccupiedSlot(pid);
        _engine.useSmartSwapCommit(
          pid,
          myRow, myCol,
          payload['targetId'] as String,
          payload['theirRow'] as int, payload['theirCol'] as int,
        );
        _log('$name used the Red King on $targetName\'s card.');
        _broadcastCardsPicked(
          pid, shownSlot?.$1, shownSlot?.$2,
          payload['targetId'] as String,
          payload['theirRow'] as int, payload['theirCol'] as int,
        );

      default:
        _sendError(ws, 'Unknown power action: $action');
        return;
    }

    _broadcastState();
    _checkRoundEnd();
    _openMatchWindow();
  }

  void _onGiveCard(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    if (_pendingGiveCardAttackerId != session.playerId) return; // not their turn to give

    final row = payload['row'] as int;
    final col = payload['col'] as int;
    final targetId = _pendingGiveCardTargetId!;
    final attackerName = _nameOf(session.playerId);
    final targetName = _nameOf(targetId);

    try {
      _engine.giveCard(session.playerId, targetId, row, col);
      _log('$attackerName gave a card to $targetName.');
    } catch (e) {
      _sendError(ws, e.toString());
      return;
    }

    _pendingGiveCardAttackerId = null;
    _pendingGiveCardTargetId = null;
    _broadcastState();
    _checkRoundEnd();
  }

  void _onMatchCard(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    final row = payload['row'] as int;
    final col = payload['col'] as int;

    // Target may be the player themselves or an opponent
    final targetId = payload['targetId'] as String? ?? session.playerId;

    // Window is closed — no penalty
    if (!_matchWindowOpen) {
      _send(ws, GameMessage(
        type: MsgType.matchAttemptResult,
        payload: MatchAttemptResultPayload(
          attemptingPlayerId: session.playerId,
          targetPlayerId: targetId,
          row: row, col: col,
          success: false,
        ).toJson(),
      ));
      return;
    }

    // Player already used their one attempt this window — silent reject, no penalty
    if (_slapAttemptedIds.contains(session.playerId)) {
      _send(ws, GameMessage(
        type: MsgType.matchAttemptResult,
        payload: MatchAttemptResultPayload(
          attemptingPlayerId: session.playerId,
          targetPlayerId: targetId,
          row: row, col: col,
          success: false,
        ).toJson(),
      ));
      return;
    }

    // Consume this player's one attempt
    _slapAttemptedIds.add(session.playerId);

    final result = _engine.attemptMatch(session.playerId, targetId, row, col);
    _broadcast(GameMessage(type: MsgType.matchAttemptResult, payload: result.toJson()));

    if (result.success) {
      // Correct slap — FCFS winner, close window immediately
      _closeMatchWindow();
      final cardLabel = result.revealedCard != null
          ? _cardLabel(result.revealedCard!.rank.name, result.revealedCard!.suit.name)
          : 'a card';
      final isOpponentSlap = targetId != session.playerId;
      if (isOpponentSlap) {
        final targetName = _nameOf(targetId);
        _pendingGiveCardAttackerId = session.playerId;
        _pendingGiveCardTargetId = targetId;
        _log('⚡ $name slapped $cardLabel from $targetName — correct! Now give one of your cards to $targetName.');
      } else {
        _log('⚡ $name slapped $cardLabel — matches the discard! Card removed.');
      }
    } else if (result.revealedCard == null) {
      _log('$name tried to slap an empty slot — no penalty.');
      _checkAllAttempted();
    } else {
      final cardLabel = _cardLabel(
          result.revealedCard!.rank.name, result.revealedCard!.suit.name);
      // Check if the wrong slap triggered elimination (too many penalty cards)
      final eliminated =
          _engine.state.getPlayer(session.playerId)?.isEliminated ?? false;
      if (eliminated) {
        _log('❌ $name slapped $cardLabel — WRONG! Too many penalties — $name is ELIMINATED! 💀');
        // If it was their turn, advance to next active player
        if (_engine.state.currentPlayerId == session.playerId) {
          // They may have been holding a drawn card. Keep it in the game, under
          // the top discard so it doesn't change what can be slapped.
          final drawn = _engine.state.drawnCard;
          if (drawn != null) {
            _engine.state.discardPile.insert(0, drawn);
            _engine.state.drawnCard = null;
          }
          _engine.state.currentPlayerId =
              _engine.state.getNextPlayerId(session.playerId);
          _engine.state.turnPhase = TurnPhase.waitingForDraw;
        }
        _checkAllAttempted();
      } else {
        _log('❌ $name slapped $cardLabel — WRONG! Penalty card added.');
        _checkAllAttempted();
      }
    }
    _broadcastState();
    // Elimination may leave only one active player → force round end
    if (_engine.onlyOneActivePlayerLeft &&
        _engine.state.phase == GamePhase.playing) {
      _engine.state.phase = GamePhase.roundEnd;
      _checkRoundEnd();
    }
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────────

  void _handleDisconnect(WebSocket ws) {
    _connections.remove(ws);
    _removeSession(ws);
    if (_connections.isEmpty) onEmpty(this);
  }

  void _removeSession(WebSocket ws) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _sessions.remove(session.playerId);
    _engine.removePlayer(session.playerId);
    print('[Room $code] $name disconnected');
    _log('$name disconnected.');

    // If no one is seated anymore, reset to a fresh lobby so new players can join.
    if (_sessions.isEmpty) {
      _engine = GameEngine();
      _actionLog.clear();
      _closeMatchWindow();
      _pendingGiveCardAttackerId = null;
      _pendingGiveCardTargetId = null;
      print('[Room $code] All players disconnected — reset to lobby.');
      return;
    }

    if (_engine.state.phase == GamePhase.lobby) {
      _broadcastLobby();
    } else {
      _broadcastState();
    }
  }

  // ─── Round end ────────────────────────────────────────────────────────────────

  void _checkRoundEnd() {
    if (_engine.state.phase == GamePhase.roundEnd) {
      final scores = _engine.computeScores();
      final winner = scores.firstWhere((s) => s.isWinner);
      _log('🏆 Round over! ${winner.playerName} wins!');
      // Broadcast state FIRST with all cards revealed (phase=roundEnd reveals all)
      _broadcastState();
      // Then send roundEnd scores
      final payload = RoundEndPayload(scores: scores, winnerId: winner.playerId);
      _broadcast(GameMessage(type: MsgType.roundEnd, payload: payload.toJson()));
      _closeMatchWindow();
      _pendingGiveCardAttackerId = null;
      _pendingGiveCardTargetId = null;
      _engine = GameEngine();
      _actionLog.clear();
      // Everyone has to re-join to sit at the next round. Sockets stay open so
      // "Play Again" keeps them at this table.
      _sessions.clear();
    }
  }

  // ─── Match window helpers ─────────────────────────────────────────────────────

  /// Open the slap window for the card now on top of the discard pile. Slapping
  /// runs in the background and never holds up the game. Each player gets one
  /// attempt per card, and the first correct slap takes it.
  /// Window closes when: a correct slap lands, all players have attempted, or a
  /// power is being used. Otherwise it stays open until the next discard.
  void _openMatchWindow() {
    if (_engine.state.phase != GamePhase.playing) return;
    _matchWindowOpen = true;
    _slapAttemptedIds.clear();
    _broadcastState();
  }

  void _closeMatchWindow() {
    _matchWindowOpen = false;
    _slapAttemptedIds.clear();
  }

  /// After each slap attempt, check if every connected player has had their
  /// one shot. If so, close the window automatically.
  void _checkAllAttempted() {
    // Eliminated players can't slap, so don't wait for them.
    final activeIds = _engine.state.players
        .where((p) => p.isConnected && !p.isEliminated)
        .map((p) => p.id)
        .toSet();
    if (_slapAttemptedIds.containsAll(activeIds)) {
      _closeMatchWindow();
      _broadcastState();
    }
  }

  // ─── Broadcast helpers ────────────────────────────────────────────────────────

  void _broadcastLobby() {
    final players = _engine.state.players
        .map((p) => {'id': p.id, 'name': p.name, 'isConnected': p.isConnected})
        .toList();
    final payload = LobbyStatePayload(
      players: players,
      hostId: _engine.hostId,
      canStart: _engine.state.players.length >= 2,
    );
    _broadcast(GameMessage(type: MsgType.lobbyState, payload: payload.toJson()));
  }

  void _broadcastState() {
    for (final session in _sessions.values) {
      final statePayload = _engine.buildStateFor(
        session.playerId,
        actionLog: _actionLog,
        pendingGiveCardAttackerId: _pendingGiveCardAttackerId,
        pendingGiveCardTargetId: _pendingGiveCardTargetId,
        // Closed for anyone who has already used their attempt on this card.
        matchWindowOpen:
            _matchWindowOpen && !_slapAttemptedIds.contains(session.playerId),
      );
      _send(session.socket, GameMessage(
        type: MsgType.gameStateUpdate,
        payload: statePayload.toJson(),
      ));
    }
  }

  void _broadcastCardsPicked(
    String actorId, int? actorRow, int? actorCol,
    String targetId, int targetRow, int targetCol,
  ) {
    _broadcast(GameMessage(
      type: MsgType.cardsPicked,
      payload: CardsPickedPayload(
        actorId: actorId,
        targetId: targetId,
        actorRow: actorRow,
        actorCol: actorCol,
        targetRow: targetRow,
        targetCol: targetCol,
      ).toJson(),
    ));
  }

  void _broadcast(GameMessage msg) {
    for (final s in _sessions.values) {
      _send(s.socket, msg);
    }
  }

  void _send(WebSocket ws, GameMessage msg) {
    try {
      ws.add(jsonEncode(msg.toJson()));
    } catch (_) {}
  }

  void _sendError(WebSocket ws, String message) {
    _send(ws, GameMessage(type: MsgType.error, payload: {'message': message}));
  }

  // ─── Log helpers ──────────────────────────────────────────────────────────────

  void _log(String entry) {
    _actionLog.insert(0, entry);
    if (_actionLog.length > 50) _actionLog.removeLast();
    print('[Room $code] $entry');
  }

  String _nameOf(String playerId) {
    try {
      return _engine.state.players.firstWhere((p) => p.id == playerId).name;
    } catch (_) {
      return 'Someone';
    }
  }

  String _cardLabel(String rank, String suit) {
    const rankMap = {
      'ace': 'A', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
      'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
      'jack': 'J', 'queen': 'Q', 'king': 'K',
    };
    const suitMap = {
      'hearts': '♥', 'diamonds': '♦', 'spades': '♠', 'clubs': '♣',
    };
    return '${rankMap[rank] ?? rank}${suitMap[suit] ?? suit}';
  }

  String _powerDescription(String rank) {
    return switch (rank) {
      'seven' || 'eight' => 'Peek Own Card',
      'nine' || 'ten'    => 'Peek Opponent Card',
      'jack'             => 'Skip Next Player',
      'queen'            => 'Blind Swap',
      'king'             => 'Smart Swap (Red King)',
      _                  => 'Power',
    };
  }

  ClientSession? _sessionFor(WebSocket ws) {
    return _sessions.values.cast<ClientSession?>().firstWhere(
      (s) => s?.socket == ws,
      orElse: () => null,
    );
  }

  String _newId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return ts.toRadixString(36);
  }
}
