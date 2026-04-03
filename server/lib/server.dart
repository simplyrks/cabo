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

class CaboServer {
  final int port;
  GameEngine _engine = GameEngine();
  final Map<String, ClientSession> _sessions = {};
  final List<String> _actionLog = [];

  // ─── Match window ─────────────────────────────────────────────────────────────
  bool _matchWindowOpen = false;
  /// Players who have already used their one slap attempt this window.
  final Set<String> _slapAttemptedIds = {};

  CaboServer({this.port = 8080});

  // ─── Lifecycle ────────────────────────────────────────────────────────────────

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Server] Listening on ws://0.0.0.0:$port');

    await for (final request in server) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final ws = await WebSocketTransformer.upgrade(request);
        _handleConnection(ws, request);
      } else {
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response
          ..statusCode = HttpStatus.ok
          ..write('Cabo server running')
          ..close();
      }
    }
  }

  void _handleConnection(WebSocket ws, HttpRequest request) {
    print('[Server] New connection');
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
      onError: (e) => print('[Server] Error: $e'),
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
        default: _sendError(ws, 'Unknown message type: ${msg.type}');
      }
    } catch (e) {
      _sendError(ws, e.toString());
    }
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────────

  void _onJoinLobby(WebSocket ws, Map<String, dynamic> payload) {
    if (_engine.state.phase != GamePhase.lobby) {
      _sendError(ws, 'Game already in progress');
      return;
    }
    final name = payload['name'] as String? ?? 'Player';
    final player = _engine.addPlayer(_newId(), name);
    _sessions[player.id] = ClientSession(playerId: player.id, socket: ws);

    _send(ws, GameMessage(
      type: 'welcome',
      payload: {'playerId': player.id, 'playerName': player.name},
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
    _closeMatchWindow(); // calling cabo ends the slap window
    _engine.callCabo(session.playerId);
    _log('🚨 $name called CABO! Last round for everyone.');
    _broadcastState();
    _checkRoundEnd();
  }

  void _onDrawFromPile(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _closeMatchWindow(); // drawing starts a new turn — slap window ends
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
    if (_engine.state.phase != GamePhase.roundEnd) _openMatchWindow();
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
        _log('$name blindly swapped one of their cards with $targetName\'s card!');

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
        final didSwap = payload['myRow'] != null;
        _engine.useSmartSwapCommit(
          pid,
          payload['myRow'] as int?, payload['myCol'] as int?,
          payload['targetId'] as String,
          payload['theirRow'] as int, payload['theirCol'] as int,
        );
        if (didSwap) {
          _log('$name decided to swap with $targetName using the Red King!');
        } else {
          _log('$name peeked at $targetName\'s card but chose not to swap.');
        }

      default:
        _sendError(ws, 'Unknown power action: $action');
        return;
    }

    _broadcastState();
    _checkRoundEnd();
  }

  void _onMatchCard(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    final row = payload['row'] as int;
    final col = payload['col'] as int;

    // Players can only slap their OWN cards
    final targetId = session.playerId;

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
      _log('⚡ $name slapped $cardLabel — matches the discard! Card removed.');
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
        _closeMatchWindow();
        // If it was their turn, advance to next active player
        if (_engine.state.currentPlayerId == session.playerId) {
          _engine.state.currentPlayerId =
              _engine.state.getNextPlayerId(session.playerId);
          _engine.state.turnPhase = TurnPhase.waitingForDraw;
        }
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
    final session = _sessions.values.cast<ClientSession?>().firstWhere(
      (s) => s?.socket == ws,
      orElse: () => null,
    );
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _sessions.remove(session.playerId);
    _engine.removePlayer(session.playerId);
    print('[Server] $name disconnected');
    _log('$name disconnected.');
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
      _engine = GameEngine();
      _actionLog.clear();
    }
  }

  // ─── Match window helpers ─────────────────────────────────────────────────────

  /// Open the slap window. Each player gets one attempt per window (FCFS).
  /// Window closes when: a correct slap lands, all players have attempted,
  /// or the next turn action starts (draw / cabo).
  void _openMatchWindow() {
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
    final connectedIds =
        _engine.state.players.where((p) => p.isConnected).map((p) => p.id).toSet();
    if (_slapAttemptedIds.containsAll(connectedIds)) {
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
        matchWindowOpen: _matchWindowOpen,
      );
      _send(session.socket, GameMessage(
        type: MsgType.gameStateUpdate,
        payload: statePayload.toJson(),
      ));
    }
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
    if (_actionLog.length > 8) _actionLog.removeLast();
    print('[Action] $entry');
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
