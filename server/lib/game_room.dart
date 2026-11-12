import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cabo_shared/models/card_model.dart';
import 'package:cabo_shared/models/messages.dart';
import 'package:cabo_shared/models/game_state.dart';
import 'game_engine.dart';

class ClientSession {
  final String playerId;
  final WebSocket socket;
  ClientSession({required this.playerId, required this.socket});
}

/// One player's attempt to slap the current discard.
class _SlapAttempt {
  final String playerId;
  final String targetId;
  final int row;
  final int col;
  /// When the player touched the card, on the server's clock.
  final int tapAtUs;
  /// When the slap reached the server. Breaks exact ties.
  final int arrivedAtUs;
  String result;

  _SlapAttempt({
    required this.playerId,
    required this.targetId,
    required this.row,
    required this.col,
    required this.tapAtUs,
    required this.arrivedAtUs,
    this.result = 'pending',
  });
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

  // ─── Slap order ───────────────────────────────────────────────────────────────
  /// How long a slap waits before it's judged, so that an earlier slap coming
  /// over a slower connection still gets to rank first.
  static const _slapSettle = Duration(milliseconds: 300);
  /// A slap can't claim to have happened longer ago than this.
  static const _maxTapAgeUs = 1000000;
  /// The room's own clock. It only ever moves forward, unlike the time of day.
  final _clock = Stopwatch()..start();
  /// Every attempt on the current card, fastest first.
  final List<_SlapAttempt> _slapAttempts = [];
  Timer? _slapSettleTimer;
  int _slapCardNo = 0;
  /// Counting down to a slap window the current player asked for.
  Timer? _slapCountdownTimer;
  int _slapCountdownEndsUs = 0;
  static const _slapCountdown = Duration(seconds: 3);
  /// The current player discarded a power card with "slap first": everyone
  /// gets to slap it before they start the power.
  bool _slapBeforePower = false;
  /// That slap has had its turn, so the window doesn't reopen after the power.
  bool _skipReopenAfterPower = false;
  int _windowOpenedAtUs = 0;
  /// A correct slap has taken the current card.
  bool _slapTaken = false;

  // ─── Auto CABO ──────────────────────────────────────────────────────────────────
  /// A player has discarded all their cards. The table holds while everyone
  /// sees it happen, then CABO is called for them.
  String? _autoCaboFor;
  Timer? _autoCaboTimer;
  /// Time for the last card to fly to the discard pile, then each notice.
  static const _autoCaboAfterMove = Duration(milliseconds: 1800);
  static const _autoCaboNotice = Duration(milliseconds: 2600);
  /// How long a slapped card stays up front on every screen before it moves on.
  static const _slapRevealMs = 1500;
  /// How long a swapped card stays lifted and highlighted before it moves.
  static const _swapHighlightMs = 900;

  // ─── Pending give-card (after successful opponent slap) ───────────────────────
  String? _pendingGiveCardAttackerId;
  String? _pendingGiveCardTargetId;

  // ─── Peek hold (the whole table waits while a 7/8/9/10 peek is on screen) ─────
  static const _peekHoldDuration = Duration(seconds: 4);
  String? _peekHoldActorId;
  String? _peekHoldTargetId;
  int? _peekHoldRow;
  int? _peekHoldCol;
  Timer? _peekHoldTimer;

  // ─── Rejoining ─────────────────────────────────────────────────────────────────
  /// Each seated player's secret key. Only that player's device ever gets it, so
  /// it proves a reconnecting player owns the seat (player ids are public).
  final Map<String, String> _seatKeys = {};
  final _random = Random.secure();

  // ─── Turn timers ───────────────────────────────────────────────────────────────
  static const _drawTime = Duration(seconds: 20);
  static const _decideTime = Duration(seconds: 30);
  static const _powerTime = Duration(seconds: 30);
  /// Queen and King swaps take longer: two cards to pick, and a decision.
  static const _swapPowerTime = Duration(seconds: 45);
  /// The power being used, e.g. 'queen'. A slap can land on top of its card,
  /// so the discard pile can't be relied on for this.
  String? _powerRank;
  /// Every timer for a player who isn't connected: the table doesn't wait
  /// long for someone who isn't there.
  static const _awayTime = Duration(seconds: 5);
  Timer? _turnTimer;
  /// What the timer is waiting on, e.g. 'turn:<id>:cardDrawn'.
  String? _turnTimerFor;
  int _turnDeadlineUs = 0;
  Duration _turnTimerTotal = Duration.zero;

  /// With nobody connected mid-game, how long the game is kept for them.
  static const _abandonAfter = Duration(minutes: 2);
  Timer? _abandonTimer;

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
    if (msg.type == MsgType.clockPing) {
      _send(ws, GameMessage(type: MsgType.clockPong, payload: {
        'sentAt': msg.payload['sentAt'],
        'serverAt': _clock.elapsedMicroseconds,
      }));
      return;
    }
    // Nothing happens at the table during a peek hold, slaps included.
    if ((_peekHoldActorId != null || _autoCaboFor != null) &&
        msg.type != MsgType.joinLobby &&
        msg.type != MsgType.rejoin &&
        msg.type != MsgType.leaveGame) {
      return;
    }
    // Slaps waiting to be judged go first if this move could change a hand or
    // the discard. Drawing changes neither, so it doesn't cut their wait short.
    if (msg.type != MsgType.matchCard &&
        msg.type != MsgType.joinLobby &&
        msg.type != MsgType.rejoin &&
        msg.type != MsgType.drawFromPile) {
      _resolveSlaps();
      // That slap may have emptied a hand: the table is now holding for auto CABO
      if (_autoCaboFor != null) return;
    }
    try {
      switch (msg.type) {
        case MsgType.joinLobby:      _onJoinLobby(ws, msg.payload);
        case MsgType.rejoin:         _onRejoin(ws, msg.payload);
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
        case MsgType.activateSlap:   _onActivateSlap(ws);
        case MsgType.startPower:     _onStartPower(ws);
        case MsgType.leaveGame:      _onLeaveGame(ws);
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
    final seatKey = _newSeatKey();
    _seatKeys[player.id] = seatKey;

    _send(ws, GameMessage(
      type: 'welcome',
      payload: {
        'playerId': player.id,
        'playerName': player.name,
        'roomCode': code,
        'seatKey': seatKey,
      },
    ));
    _broadcastLobby();
  }

  /// A player whose connection dropped takes their seat back, proving it's
  /// theirs with the seat key they were given when they joined.
  void _onRejoin(WebSocket ws, Map<String, dynamic> payload) {
    final playerId = payload['playerId'] as String?;
    final seatKey = payload['seatKey'] as String?;
    final phase = _engine.state.phase;
    final inGame = phase == GamePhase.initialPeek || phase == GamePhase.playing;
    final player = playerId == null ? null : _engine.state.getPlayer(playerId);
    if (!inGame || player == null || seatKey == null || _seatKeys[playerId] != seatKey) {
      _send(ws, GameMessage(type: MsgType.rejoinFailed, payload: {
        'message': inGame
            ? "Couldn't find your seat at this table."
            : 'That game has finished.',
      }));
      return;
    }

    // Open somewhere else too: the newest connection takes the seat
    final old = _sessions.remove(playerId);
    if (old != null && old.socket != ws) {
      _send(old.socket, GameMessage(type: MsgType.seatTaken, payload: {
        'message': 'You opened this game somewhere else.',
      }));
      old.socket.close();
    }
    _sessions[playerId!] = ClientSession(playerId: playerId, socket: ws);
    player.isConnected = true;
    _abandonTimer?.cancel();
    _abandonTimer = null;

    _send(ws, GameMessage(type: 'welcome', payload: {
      'playerId': playerId,
      'playerName': player.name,
      'roomCode': code,
      'seatKey': seatKey,
      'rejoined': true,
    }));
    _log('🔌 ${player.name} is back.');
    _broadcastState();
    // Still on the memorise screen: show them their bottom cards again
    if (phase == GamePhase.initialPeek &&
        !_engine.confirmedPeekIds.contains(playerId)) {
      for (final peek in _engine.initialPeekCards(playerId)) {
        _send(ws, GameMessage(type: MsgType.peekReveal, payload: peek.toJson()));
      }
    }
  }

  String _newSeatKey() => [
        for (var i = 0; i < 16; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();

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
    final reshufflesBefore = _engine.reshuffleCount;
    _engine.drawFromPile(session.playerId);
    _log('$name drew a card from the pile.');
    _animate(TableAnimationPayload(
      moves: [
        CardMove(
          from: const CardSpot.deckPile(),
          to: CardSpot.heldBy(session.playerId),
        ),
      ],
      reshuffled: _engine.reshuffleCount != reshufflesBefore,
    ));
    _broadcastState();
  }

  /// The current player, holding a drawn card, wants to slap. If they can
  /// slap right now, everyone is told; otherwise a slap window opens for
  /// everyone after a short countdown.
  void _onActivateSlap(WebSocket ws) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final state = _engine.state;
    final playerId = session.playerId;
    if (state.phase != GamePhase.playing ||
        state.currentPlayerId != playerId ||
        state.turnPhase != TurnPhase.cardDrawn ||
        _slapCountdownTimer != null) {
      return;
    }
    if (state.discardPile.isEmpty) {
      _sendError(ws, 'There is nothing to slap yet');
      return;
    }
    final canSlapNow = _matchWindowOpen && !_slapAttemptedIds.contains(playerId);
    if (canSlapNow) {
      // Everyone can see whose turn it is, so the banner and log name nobody
      _broadcast(GameMessage(
        type: MsgType.slapActivated,
        payload: SlapActivatedPayload(playerId: playerId).toJson(),
      ));
      _restartTurnTimer();
      _broadcastState();
      return;
    }
    _startSlapCountdown(playerId);
  }

  /// A 3-2-1 for everyone, then the slap window opens on the top discard.
  void _startSlapCountdown(String playerId) {
    _cancelSlapCountdown();
    _log('🖐 Slapping opens for everyone in 3 seconds.');
    _restartTurnTimer();
    _broadcast(GameMessage(
      type: MsgType.slapActivated,
      payload: SlapActivatedPayload(
        playerId: playerId,
        countdownMs: _slapCountdown.inMilliseconds,
      ).toJson(),
    ));
    _slapCountdownEndsUs =
        _clock.elapsedMicroseconds + _slapCountdown.inMicroseconds;
    _slapCountdownTimer = Timer(_slapCountdown, () {
      _slapCountdownTimer = null;
      _openMatchWindow();
    });
    _broadcastState();
  }

  /// The held card has been dealt with, so a slap countdown is no longer needed:
  /// the move opens its own window, or a power holds it back until it's done.
  void _cancelSlapCountdown() {
    _slapCountdownTimer?.cancel();
    _slapCountdownTimer = null;
  }

  int? get _slapOpensInMs => _slapCountdownTimer == null
      ? null
      : max(0, (_slapCountdownEndsUs - _clock.elapsedMicroseconds) ~/ 1000);

  /// The player who chose "slap first" is ready for their power: slapping
  /// closes until the power is done, and doesn't reopen on the same card.
  /// False while the countdown is still running.
  bool _beginPower() {
    if (!_slapBeforePower) return true;
    if (_slapCountdownTimer != null) return false;
    _slapBeforePower = false;
    _skipReopenAfterPower = true;
    _closeMatchWindow();
    return true;
  }

  /// The power is finished. The slap window opens on its card, unless that
  /// card already had its window before the power.
  void _openMatchWindowAfterPower() {
    if (_skipReopenAfterPower) {
      _skipReopenAfterPower = false;
      return;
    }
    _openMatchWindow();
  }

  void _clearSlapFirst() {
    _slapBeforePower = false;
    _skipReopenAfterPower = false;
  }

  /// A player quits mid-game. They're out of the round, like an eliminated
  /// player, and their seat is given up: there's no coming back to it.
  void _onLeaveGame(WebSocket ws) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final state = _engine.state;
    if (state.phase != GamePhase.initialPeek && state.phase != GamePhase.playing) {
      return;
    }
    final playerId = session.playerId;
    final player = state.getPlayer(playerId);
    if (player == null) return;
    final name = _nameOf(playerId);

    _sessions.remove(playerId);
    _seatKeys.remove(playerId);
    player.isConnected = false;
    player.isEliminated = true;
    _log('🚪 $name left the game.');

    // Nothing more is owed to or by them
    if (_pendingGiveCardAttackerId == playerId ||
        _pendingGiveCardTargetId == playerId) {
      _pendingGiveCardAttackerId = null;
      _pendingGiveCardTargetId = null;
    }
    if (_autoCaboFor == playerId) _clearAutoCabo();

    if (state.phase == GamePhase.playing && state.currentPlayerId == playerId) {
      if (_peekHoldActorId == playerId) _clearPeekHold();
      _cancelSlapCountdown();
      _clearSlapFirst();
      // A card they were holding stays in the game, under the top discard so
      // it doesn't change what can be slapped
      final drawn = state.drawnCard;
      if (drawn != null) {
        state.discardPile.insert(0, drawn);
        state.drawnCard = null;
        _animate(TableAnimationPayload(moves: [
          CardMove(
            from: CardSpot.heldBy(playerId),
            to: const CardSpot.discardPile(),
          ),
        ]));
      }
      state.currentPlayerId = state.getNextPlayerId(playerId);
      state.turnPhase = TurnPhase.waitingForDraw;
      _log("${_nameOf(state.currentPlayerId!)}'s turn.");
    }

    if (_engine.onlyOneActivePlayerLeft) {
      state.phase = GamePhase.roundEnd;
      _checkRoundEnd();
      return;
    }
    if (_engine.checkInitialPeekReady()) {
      _log("Everyone's ready — let's play! ${_nameOf(_engine.state.currentPlayerId!)} goes first.");
    }
    _broadcastState();
    if (_sessions.isEmpty) _abandonTimer ??= Timer(_abandonAfter, _abandonGame);
  }

  /// The power player is ready to use their power after the slap window.
  void _onStartPower(WebSocket ws) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final state = _engine.state;
    if (state.currentPlayerId != session.playerId ||
        state.turnPhase != TurnPhase.usingPower ||
        !_slapBeforePower) {
      return;
    }
    if (!_beginPower()) {
      _sendError(ws, 'Slapping opens first — wait for the countdown.');
      return;
    }
    _log('${_nameOf(session.playerId)} is using their power — slapping is closed.');
    _broadcastState();
  }

  void _onDiscardDrawn(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    // "Discard, slap, then power": a 3-2-1 for everyone, a slap window on the
    // discarded card, and only then the power.
    _discardDrawn(session.playerId, slapFirst: payload['slapFirst'] == true);
  }

  void _discardDrawn(String playerId, {bool slapFirst = false}) {
    final name = _nameOf(playerId);
    // Capture drawn card BEFORE discarding
    final drawnCard = _engine.state.drawnCard;
    final drawnRank = drawnCard?.rank.name ?? '';
    final cardName = drawnCard != null
        ? _cardLabel(drawnCard.rank.name, drawnCard.suit.name)
        : 'a card';
    // For Jack: the skipped player is whoever was next before we advance
    final wouldBeNextId = _engine.state.getNextPlayerId(playerId);

    _engine.discardDrawn(playerId);
    _cancelSlapCountdown();
    _clearSlapFirst();
    final hasPower = _engine.state.turnPhase == TurnPhase.usingPower;
    _powerRank = hasPower ? drawnRank : null;

    // Using a power is the one time slapping stops. With "slap first" the old
    // card's window closes too, and the countdown opens one for this card.
    if (hasPower || slapFirst) _closeMatchWindow();
    if (hasPower && slapFirst) _slapBeforePower = true;

    if (hasPower && slapFirst) {
      final powerDesc = _powerDescription(drawnRank);
      _log('$name discarded $cardName — everyone can slap it, then the $powerDesc.');
    } else if (hasPower) {
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
    _animate(TableAnimationPayload(
      moves: [
        CardMove(
          from: CardSpot.heldBy(playerId),
          to: const CardSpot.discardPile(),
          card: drawnCard,
        ),
      ],
      skippedPlayerId: drawnRank == 'jack' ? wouldBeNextId : null,
    ));
    _broadcastState();
    _checkRoundEnd();
    if (_engine.state.phase != GamePhase.playing) return;
    if (slapFirst) {
      _startSlapCountdown(playerId);
    } else if (!hasPower) {
      // A power card's slap window waits until the power is finished.
      _openMatchWindow();
    }
  }

  void _onSwapDrawnWithHand(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    final row = payload['row'] as int;
    final col = payload['col'] as int;
    final handCard = _engine.swapDrawnWithHand(session.playerId, row, col);
    _cancelSlapCountdown();
    _clearSlapFirst();
    _log('$name swapped their ${cardPositionName(row, col)} card.');
    // Everyone sees which position it was: the card lifts and glows, face down,
    // then flips face up on its way to the discard pile as the drawn card takes its place.
    _animate(TableAnimationPayload(
      highlight: CardSpot.inHand(session.playerId, row, col),
      highlightMs: _swapHighlightMs,
      moves: [
        CardMove(
          from: CardSpot.inHand(session.playerId, row, col),
          to: const CardSpot.discardPile(),
          card: handCard,
          delayMs: _swapHighlightMs,
        ),
        CardMove(
          from: CardSpot.heldBy(session.playerId),
          to: CardSpot.inHand(session.playerId, row, col),
          delayMs: _swapHighlightMs + 120,
        ),
      ],
    ));
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
    _afterSkippedPower();
  }

  /// The power was skipped. A "slap first" window stays as it is (or opens
  /// when its countdown ends); otherwise slapping opens now.
  void _afterSkippedPower() {
    // Still in the "slap first" window, or past it: either way this card has
    // its window already
    final reopen = !_slapBeforePower && !_skipReopenAfterPower;
    _clearSlapFirst();
    _broadcastState();
    _checkRoundEnd();
    if (reopen) _openMatchWindow();
  }

  void _onUsePower(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final pid = session.playerId;
    final name = _nameOf(pid);
    final action = payload['action'] as String;
    if (_engine.state.currentPlayerId == pid && !_beginPower()) {
      _sendError(ws, 'Slapping opens first — wait for the countdown.');
      return;
    }

    switch (action) {
      case 'peekOwn':
        final reveal = _engine.usePeekOwn(pid, payload['row'] as int, payload['col'] as int);
        _send(ws, GameMessage(type: MsgType.peekReveal, payload: reveal.toJson()));
        _log('$name peeked at their own ${cardPositionName(payload['row'] as int, payload['col'] as int)} card.');
        _startPeekHold(pid, pid, payload['row'] as int, payload['col'] as int);
        return;

      case 'peekOpponent':
        final targetName = _nameOf(payload['targetId'] as String);
        final reveal = _engine.usePeekOpponent(
          pid, payload['targetId'] as String,
          payload['row'] as int, payload['col'] as int,
        );
        _send(ws, GameMessage(type: MsgType.peekReveal, payload: reveal.toJson()));
        _log('$name peeked at $targetName\'s ${cardPositionName(payload['row'] as int, payload['col'] as int)} card.');
        _startPeekHold(
          pid, payload['targetId'] as String,
          payload['row'] as int, payload['col'] as int,
        );
        return;

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
        _restartTurnTimer();
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
    _openMatchWindowAfterPower();
  }

  /// Hold the whole table while the peeked card is on screen. The turn stays
  /// with the peeking player and slapping stays closed until the hold ends.
  void _startPeekHold(String actorId, String targetId, int row, int col) {
    _peekHoldActorId = actorId;
    _peekHoldTargetId = targetId;
    _peekHoldRow = row;
    _peekHoldCol = col;
    _broadcastState();
    _peekHoldTimer = Timer(_peekHoldDuration, _endPeekHold);
  }

  void _endPeekHold() {
    _clearPeekHold();
    _engine.finishPeek();
    _broadcastState();
    _checkRoundEnd();
    _openMatchWindowAfterPower();
  }

  void _clearPeekHold() {
    _peekHoldTimer?.cancel();
    _peekHoldTimer = null;
    _peekHoldActorId = null;
    _peekHoldTargetId = null;
    _peekHoldRow = null;
    _peekHoldCol = null;
  }

  void _onGiveCard(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    _giveCard(session.playerId, payload['row'] as int, payload['col'] as int, ws: ws);
  }

  void _giveCard(String playerId, int row, int col, {WebSocket? ws}) {
    if (_pendingGiveCardAttackerId != playerId) return; // not their turn to give

    final targetId = _pendingGiveCardTargetId!;
    final attackerName = _nameOf(playerId);
    final targetName = _nameOf(targetId);

    try {
      final landed = _engine.giveCard(playerId, targetId, row, col);
      _log('$attackerName gave a card to $targetName.');
      _animate(TableAnimationPayload(moves: [
        CardMove(
          from: CardSpot.inHand(playerId, row, col),
          to: CardSpot.inHand(targetId, landed.$1, landed.$2),
        ),
      ]));
    } catch (e) {
      if (ws != null) _sendError(ws, e.toString());
      return;
    }

    _pendingGiveCardAttackerId = null;
    _pendingGiveCardTargetId = null;
    _restartTurnTimer();
    _broadcastState();
    _checkRoundEnd();
    _checkEmptyHand(); // giving away their last card leaves the giver with none
  }

  void _onMatchCard(WebSocket ws, Map<String, dynamic> payload) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final row = payload['row'] as int;
    final col = payload['col'] as int;

    // Target may be the player themselves or an opponent
    final targetId = payload['targetId'] as String? ?? session.playerId;

    // The discard changed before this tap arrived, so it was aimed at an older
    // card. Eliminated players are out of the game.
    final seenRank = payload['seenRank'] as String?;
    final isStaleTap =
        seenRank != null && seenRank != _engine.state.topDiscard?.rank.name;
    final isEliminated =
        _engine.state.getPlayer(session.playerId)?.isEliminated ?? false;

    // The card has just been taken and this tap was already on its way. It
    // changes nothing, but it still gets its place in the ranking, behind
    // everyone already judged so the list never reorders.
    if (_slapTaken &&
        !isStaleTap &&
        !isEliminated &&
        !_slapAttempts.any((a) => a.playerId == session.playerId)) {
      _slapAttempts.add(_SlapAttempt(
        playerId: session.playerId,
        targetId: targetId,
        row: row,
        col: col,
        tapAtUs: max(_tapTime(payload), _slapAttempts.map((a) => a.tapAtUs).reduce(max)),
        arrivedAtUs: _clock.elapsedMicroseconds,
        result: 'late',
      ));
      _broadcastSlapRanking();
      final card = _cardAt(targetId, row, col);
      if (card != null) {
        _animate(TableAnimationPayload(slapReveals: [
          SlapReveal(
            playerId: session.playerId,
            targetId: targetId,
            row: row,
            col: col,
            card: card,
            result: 'late',
          ),
        ]));
      }
    }

    // Window is closed — no penalty
    if (!_matchWindowOpen || isStaleTap || isEliminated) {
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

    // Consume this player's one attempt, and show straight away that they tried
    _slapAttemptedIds.add(session.playerId);
    _restartTurnTimer();
    _slapAttempts.add(_SlapAttempt(
      playerId: session.playerId,
      targetId: targetId,
      row: row,
      col: col,
      tapAtUs: _tapTime(payload),
      arrivedAtUs: _clock.elapsedMicroseconds,
    ));
    _broadcastState();
    _broadcastSlapRanking();
    _slapSettleTimer ??= Timer(_slapSettle, _resolveSlaps);
  }

  /// When the player touched the card, on the server's clock. It has to fall
  /// after the card appeared and before the slap arrived, whatever the device says.
  int _tapTime(Map<String, dynamic> payload) {
    final arrivedAtUs = _clock.elapsedMicroseconds;
    final earliestUs = max(_windowOpenedAtUs, arrivedAtUs - _maxTapAgeUs);
    final claimedUs = payload['tapAt'] as int? ?? arrivedAtUs;
    return claimedUs.clamp(earliestUs, arrivedAtUs);
  }

  void _sortSlapAttempts() {
    _slapAttempts.sort((a, b) {
      final byTap = a.tapAtUs.compareTo(b.tapAtUs);
      return byTap != 0 ? byTap : a.arrivedAtUs.compareTo(b.arrivedAtUs);
    });
  }

  /// Judge the waiting slaps, fastest first. The first correct one takes the
  /// card, and anyone behind it is out of time with no penalty.
  void _resolveSlaps() {
    _slapSettleTimer?.cancel();
    _slapSettleTimer = null;
    _sortSlapAttempts();
    final waiting = _slapAttempts.where((a) => a.result == 'pending').toList();
    if (waiting.isEmpty) return;

    final reveals = <SlapReveal>[];
    final moves = <CardMove>[];
    final reshufflesBefore = _engine.reshuffleCount;
    for (final attempt in waiting) {
      if (!_matchWindowOpen) {
        attempt.result = 'late';
        final card = _cardAt(attempt.targetId, attempt.row, attempt.col);
        if (card != null) reveals.add(_slapReveal(attempt, card));
        continue;
      }
      try {
        _applySlap(attempt, reveals, moves);
      } catch (e) {
        attempt.result = 'late';
        print('[Room $code] Slap failed: $e');
      }
    }
    _animate(TableAnimationPayload(
      moves: moves,
      slapReveals: reveals,
      reshuffled: _engine.reshuffleCount != reshufflesBefore,
    ));
    if (_matchWindowOpen) _checkAllAttempted();

    _printSlapOrder();
    _broadcastSlapRanking();
    _broadcastState();
    // Elimination may leave only one active player → force round end
    if (_engine.onlyOneActivePlayerLeft &&
        _engine.state.phase == GamePhase.playing) {
      _engine.state.phase = GamePhase.roundEnd;
      _checkRoundEnd();
      return;
    }
    _checkEmptyHand();
  }

  /// Someone has no cards left: show the table what happened, then call CABO
  /// for them, which ends the round. A player about to be given a card isn't
  /// out of cards.
  void _checkEmptyHand() {
    final state = _engine.state;
    if (state.phase != GamePhase.playing || _autoCaboFor != null) return;
    final empty = state.players.where((p) =>
        !p.isEliminated &&
        p.cardCount == 0 &&
        p.id != _pendingGiveCardTargetId);
    if (empty.isEmpty) return;
    final playerId = empty.first.id;
    final name = _nameOf(playerId);

    _autoCaboFor = playerId;
    _closeMatchWindow();
    _cancelSlapCountdown();
    _clearSlapFirst();
    _clearSlaps();
    _broadcastState(); // stops the turn timer and slapping on every screen

    void announce(String text) {
      _log(text);
      _broadcast(GameMessage(type: MsgType.announcement, payload: {'text': text}));
      _broadcastState();
    }

    // The last card lands on the discard pile first
    _autoCaboTimer = Timer(_autoCaboAfterMove, () {
      announce('🃏 $name has discarded all their cards!');
      _autoCaboTimer = Timer(_autoCaboNotice, () {
        announce('📣 CABO called automatically — $name has no cards left.');
        _autoCaboTimer = Timer(_autoCaboNotice, () {
          _autoCaboTimer = null;
          if (_autoCaboFor != playerId) return;
          _engine.autoCabo(playerId);
          _checkRoundEnd();
        });
      });
    });
  }

  void _clearAutoCabo() {
    _autoCaboTimer?.cancel();
    _autoCaboTimer = null;
    _autoCaboFor = null;
  }

  SlapReveal _slapReveal(_SlapAttempt attempt, CaboCard card) => SlapReveal(
        playerId: attempt.playerId,
        targetId: attempt.targetId,
        row: attempt.row,
        col: attempt.col,
        card: card,
        result: attempt.result,
      );

  CaboCard? _cardAt(String playerId, int row, int col) {
    final hand = _engine.state.getPlayer(playerId)?.hand;
    if (hand == null || row < 0 || row >= hand.length) return null;
    if (col < 0 || col >= hand[row].length) return null;
    return hand[row][col];
  }

  void _applySlap(
    _SlapAttempt attempt,
    List<SlapReveal> reveals,
    List<CardMove> moves,
  ) {
    final playerId = attempt.playerId;
    final targetId = attempt.targetId;
    final name = _nameOf(playerId);

    final result = _engine.attemptMatch(playerId, targetId, attempt.row, attempt.col);
    attempt.result = result.success ? 'right' : 'wrong';
    _broadcast(GameMessage(type: MsgType.matchAttemptResult, payload: result.toJson()));

    if (result.revealedCard != null) {
      reveals.add(_slapReveal(attempt, result.revealedCard!));
    }
    // The penalty card comes out once the wrong card has been shown.
    final penaltySlot = _engine.lastPenaltySlot;
    if (!result.success && result.revealedCard != null && penaltySlot != null) {
      moves.add(CardMove(
        from: const CardSpot.deckPile(),
        to: CardSpot.inHand(playerId, penaltySlot.$1, penaltySlot.$2),
        delayMs: _slapRevealMs,
      ));
    }

    if (result.success) {
      // Correct slap — fastest one wins, close window immediately
      _closeMatchWindow();
      _slapTaken = true;
      final cardLabel = result.revealedCard != null
          ? _cardLabel(result.revealedCard!.rank.name, result.revealedCard!.suit.name)
          : 'a card';
      final isOpponentSlap = targetId != playerId;
      if (isOpponentSlap) {
        final targetName = _nameOf(targetId);
        _pendingGiveCardAttackerId = playerId;
        _pendingGiveCardTargetId = targetId;
        _log('⚡ $name slapped $cardLabel from $targetName — correct! Now give one of your cards to $targetName.');
      } else {
        _log('⚡ $name slapped $cardLabel — matches the discard! Card removed.');
      }
    } else if (result.revealedCard == null) {
      _log('$name tried to slap an empty slot — no penalty.');
    } else {
      final cardLabel = _cardLabel(
          result.revealedCard!.rank.name, result.revealedCard!.suit.name);
      final owner = targetId == playerId
          ? 'their own'
          : "${_nameOf(targetId)}'s";
      // Check if the wrong slap triggered elimination (too many penalty cards)
      final eliminated =
          _engine.state.getPlayer(playerId)?.isEliminated ?? false;
      if (eliminated) {
        _log('❌ $name slapped $owner $cardLabel — WRONG! Too many penalties — $name is ELIMINATED! 💀');
        // If it was their turn, advance to next active player
        if (_engine.state.currentPlayerId == playerId) {
          // They may have been holding a drawn card. Keep it in the game, under
          // the top discard so it doesn't change what can be slapped.
          final drawn = _engine.state.drawnCard;
          if (drawn != null) {
            _engine.state.discardPile.insert(0, drawn);
            _engine.state.drawnCard = null;
            // It leaves the spot beside the deck, face down, for the discard pile
            moves.add(CardMove(
              from: CardSpot.heldBy(playerId),
              to: const CardSpot.discardPile(),
              delayMs: _slapRevealMs,
            ));
          }
          _engine.state.currentPlayerId =
              _engine.state.getNextPlayerId(playerId);
          _engine.state.turnPhase = TurnPhase.waitingForDraw;
        }
      } else {
        _log('❌ $name slapped $owner $cardLabel — WRONG! Penalty card added.');
      }
    }
  }

  void _animate(TableAnimationPayload animation) {
    _broadcast(GameMessage(
      type: MsgType.tableAnimation,
      payload: animation.toJson(),
    ));
  }

  void _broadcastSlapRanking() {
    _sortSlapAttempts();
    final firstTapUs = _slapAttempts.first.tapAtUs;
    _broadcast(GameMessage(
      type: MsgType.slapRanking,
      payload: SlapRankingPayload(
        cardNo: _slapCardNo,
        entries: [
          for (final a in _slapAttempts)
            SlapRankEntry(
              playerId: a.playerId,
              gapMs: ((a.tapAtUs - firstTapUs) / 1000).round(),
              result: a.result,
            ),
        ],
      ).toJson(),
    ));
  }

  void _printSlapOrder() {
    final firstTapUs = _slapAttempts.first.tapAtUs;
    final order = [
      for (final (i, a) in _slapAttempts.indexed)
        '${i + 1}. ${_nameOf(a.playerId)} +${((a.tapAtUs - firstTapUs) / 1000).toStringAsFixed(1)}ms ${a.result}',
    ].join(', ');
    print('[Room $code] Slap order: $order');
  }

  void _clearSlaps() {
    _slapSettleTimer?.cancel();
    _slapSettleTimer = null;
    _slapAttempts.clear();
    _slapTaken = false;
  }

  // ─── Disconnect ───────────────────────────────────────────────────────────────

  void _handleDisconnect(WebSocket ws) {
    _connections.remove(ws);
    _removeSession(ws);
    // A game everyone dropped out of is kept for a while, in case they come back
    if (_connections.isEmpty && _abandonTimer == null) onEmpty(this);
  }

  void _removeSession(WebSocket ws) {
    final session = _sessionFor(ws);
    if (session == null) return;
    final name = _nameOf(session.playerId);
    _sessions.remove(session.playerId);
    _engine.removePlayer(session.playerId);
    final inLobby = _engine.state.phase == GamePhase.lobby;
    print('[Room $code] $name disconnected');
    if (inLobby) {
      _seatKeys.remove(session.playerId);
      _log('$name disconnected.');
    } else {
      _log('📵 $name lost connection — their seat is kept for them.');
    }

    if (_sessions.isEmpty) {
      if (inLobby) {
        _resetTable();
        print('[Room $code] All players disconnected — reset to lobby.');
      } else {
        // Mid-game: give everyone a chance to come back before giving up
        _abandonTimer ??= Timer(_abandonAfter, _abandonGame);
        print('[Room $code] All players disconnected — keeping the game for '
            '${_abandonAfter.inMinutes} minutes.');
      }
      return;
    }

    if (inLobby) {
      _broadcastLobby();
    } else {
      // Don't keep the memorise screen waiting for someone who has gone
      if (_engine.checkInitialPeekReady()) {
        _log("Everyone's ready — let's play! ${_nameOf(_engine.state.currentPlayerId!)} goes first.");
      }
      _broadcastState();
    }
  }

  /// Back to an empty lobby, forgetting the game and every seat.
  void _resetTable() {
    _engine = GameEngine();
    _actionLog.clear();
    _closeMatchWindow();
    _pendingGiveCardAttackerId = null;
    _pendingGiveCardTargetId = null;
    _clearPeekHold();
    _clearSlaps();
    _cancelSlapCountdown();
    _clearSlapFirst();
    _clearAutoCabo();
    _stopTurnTimer();
    _abandonTimer?.cancel();
    _abandonTimer = null;
    _seatKeys.clear();
  }

  void _abandonGame() {
    _abandonTimer = null;
    if (_sessions.isNotEmpty) return;
    print('[Room $code] Nobody came back — reset to lobby.');
    _resetTable();
    if (_connections.isEmpty) onEmpty(this);
  }

  // ─── Turn timers ───────────────────────────────────────────────────────────────

  /// What the game is waiting on, if it's timed: the current player's draw,
  /// decision or power, or a card owed by a player who is away.
  String? _timedWait() {
    final state = _engine.state;
    if (state.phase != GamePhase.playing ||
        _peekHoldActorId != null ||
        _autoCaboFor != null) {
      return null;
    }
    final giver = _pendingGiveCardAttackerId;
    if (giver != null && !(state.getPlayer(giver)?.isConnected ?? true)) {
      return 'give:$giver';
    }
    final current = state.currentPlayerId;
    final player = current == null ? null : state.getPlayer(current);
    if (player == null || player.isEliminated) return null;
    // Letting everyone slap before the power, then the power itself, are timed apart
    final stage = _slapBeforePower ? ':slapFirst' : '';
    // Dropping out or coming back starts the timer again, short or full
    final away = player.isConnected ? '' : ':away';
    return 'turn:$current:${state.turnPhase.name}$stage$away';
  }

  Duration _timeFor(String waitingOn) {
    if (waitingOn.startsWith('give:') || waitingOn.endsWith(':away')) {
      return _awayTime;
    }
    return switch (_engine.state.turnPhase) {
      TurnPhase.waitingForDraw => _drawTime,
      TurnPhase.cardDrawn => _decideTime,
      // Starting a power after "slap first" is quick; a swap itself is not
      _ when _slapBeforePower => _powerTime,
      _ when _powerRank == 'queen' || _powerRank == 'king' => _swapPowerTime,
      _ => _powerTime,
    };
  }

  /// Starts, keeps or stops the timer for whatever the game is waiting on.
  void _scheduleTurnTimer() {
    final waitingOn = _timedWait();
    if (waitingOn == _turnTimerFor) return;
    _turnTimer?.cancel();
    _turnTimer = null;
    _turnTimerFor = waitingOn;
    if (waitingOn == null) return;
    _turnTimerTotal = _timeFor(waitingOn);
    _turnDeadlineUs = _clock.elapsedMicroseconds + _turnTimerTotal.inMicroseconds;
    _turnTimer = Timer(_turnTimerTotal, () => _onTurnTimeout(waitingOn));
  }

  /// Someone did something at the table: the current timer starts over, so the
  /// player it's running for isn't rushed by what happened. The next state
  /// broadcast starts it again.
  void _restartTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
    _turnTimerFor = null;
  }

  void _stopTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = null;
    _turnTimerFor = null;
  }

  int? get _turnTimeLeftMs => _turnTimerFor == null
      ? null
      : max(0, (_turnDeadlineUs - _clock.elapsedMicroseconds) ~/ 1000);

  /// Time ran out, so the game makes the move: skip the turn, discard the
  /// drawn card (its power still usable), skip the power, or give a random card
  /// for an away player. An away player's drawn card goes without its power.
  void _onTurnTimeout(String waitingOn) {
    _turnTimer = null;
    _turnTimerFor = null;
    if (_timedWait() != waitingOn) {
      _broadcastState(); // things moved on; time whatever comes next
      return;
    }
    _resolveSlaps();
    if (_autoCaboFor != null) return;
    final parts = waitingOn.split(':');
    final playerId = parts[1];
    final name = _nameOf(playerId);
    final away = !(_engine.state.getPlayer(playerId)?.isConnected ?? false);
    try {
      if (parts[0] == 'give') {
        final slot = _engine.randomOccupiedSlot(playerId);
        if (slot == null) {
          _pendingGiveCardAttackerId = null;
          _pendingGiveCardTargetId = null;
          _broadcastState();
          return;
        }
        _log('⏭ $name is away — a random card was given for them.');
        _giveCard(playerId, slot.$1, slot.$2);
        return;
      }
      if (!away) {
        switch (_engine.state.turnPhase) {
          case TurnPhase.waitingForDraw:
            _engine.skipTurn(playerId);
            _log('⏰ $name ran out of time — turn skipped.');
            _broadcastState();
            _checkRoundEnd();
          case TurnPhase.cardDrawn:
            _log('⏰ $name ran out of time — their card is discarded.');
            _discardDrawn(playerId);
          case TurnPhase.usingPower:
            _engine.skipPower(playerId);
            _log('⏰ $name ran out of time — power skipped.');
            _afterSkippedPower();
          default:
            break; // other phases aren't used by the game
        }
        return;
      }
      switch (_engine.state.turnPhase) {
        case TurnPhase.waitingForDraw:
          _engine.skipTurn(playerId);
          _log('⏭ $name is away — turn skipped.');
          _broadcastState();
          _checkRoundEnd();
        case TurnPhase.cardDrawn:
          _cancelSlapCountdown();
          _clearSlapFirst();
          final card = _engine.discardDrawnWithoutPower(playerId);
          _log('⏭ $name is away — discarded ${_cardLabel(card.rank.name, card.suit.name)}, power not used.');
          _animate(TableAnimationPayload(moves: [
            CardMove(
              from: CardSpot.heldBy(playerId),
              to: const CardSpot.discardPile(),
              card: card,
            ),
          ]));
          _broadcastState();
          _checkRoundEnd();
          if (_engine.state.phase != GamePhase.roundEnd) _openMatchWindow();
        case TurnPhase.usingPower:
          _engine.skipPower(playerId);
          _log('⏭ $name is away — power skipped.');
          _afterSkippedPower();
        default:
          break; // other phases aren't used by the game
      }
    } catch (e) {
      print('[Room $code] Could not move for $name: $e');
      _broadcastState();
    }
  }

  // ─── Round end ────────────────────────────────────────────────────────────────

  void _checkRoundEnd() {
    if (_engine.state.phase == GamePhase.roundEnd) {
      final scores = _engine.computeScores();
      final winners = scores.where((s) => s.isWinner).toList();
      final winner = winners.first;
      if (winners.length > 1) {
        _log("🤝 Round over! It's a tie — ${winners.map((w) => w.playerName).join(' & ')}.");
      } else {
        _log('🏆 Round over! ${winner.playerName} wins!');
      }
      // Broadcast state FIRST with all cards revealed (phase=roundEnd reveals all)
      _broadcastState();
      // Then send roundEnd scores
      final payload = RoundEndPayload(scores: scores, winnerId: winner.playerId);
      _broadcast(GameMessage(type: MsgType.roundEnd, payload: payload.toJson()));
      _closeMatchWindow();
      _cancelSlapCountdown();
      _clearSlapFirst();
      _clearAutoCabo();
      _pendingGiveCardAttackerId = null;
      _pendingGiveCardTargetId = null;
      _clearSlaps();
      _engine = GameEngine();
      _actionLog.clear();
      // Everyone has to re-join to sit at the next round. Sockets stay open so
      // "Play Again" keeps them at this table.
      _sessions.clear();
      _seatKeys.clear();
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
    _slapAttempts.clear();
    _slapCardNo++;
    _slapTaken = false;
    _windowOpenedAtUs = _clock.elapsedMicroseconds;
    _broadcastState();
  }

  void _closeMatchWindow() {
    _matchWindowOpen = false;
    _slapAttemptedIds.clear();
    _slapTaken = false;
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
    _scheduleTurnTimer();
    final turnTimeLeftMs = _turnTimeLeftMs;
    final slapOpensInMs = _slapOpensInMs;
    for (final session in _sessions.values) {
      final statePayload = _engine.buildStateFor(
        session.playerId,
        actionLog: _actionLog,
        pendingGiveCardAttackerId: _pendingGiveCardAttackerId,
        pendingGiveCardTargetId: _pendingGiveCardTargetId,
        peekHoldActorId: _peekHoldActorId,
        peekHoldTargetId: _peekHoldTargetId,
        peekHoldRow: _peekHoldRow,
        peekHoldCol: _peekHoldCol,
        turnTimeLeftMs: turnTimeLeftMs,
        turnTimeTotalMs: turnTimeLeftMs == null ? null : _turnTimerTotal.inMilliseconds,
        slapBeforePower: _slapBeforePower,
        slapOpensInMs: slapOpensInMs,
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
