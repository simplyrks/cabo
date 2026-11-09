import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo/providers/game_provider.dart';
import 'package:cabo_shared/models/messages.dart';
import 'widgets/card_widget.dart';
import 'widgets/player_hand.dart';
import 'widgets/card_pick_overlay.dart';
import 'widgets/slap_ranking.dart';
import 'widgets/slap_status.dart';
import 'widgets/status_box.dart' show StatusBox, HistorySheet;
import 'widgets/table_animations.dart';

// ─── Power selection state ────────────────────────────────────────────────────

enum PowerStep {
  none,
  peekOwn,
  peekOpponent,
  blindSwapSelf,     // pick my card
  blindSwapTarget,   // pick opponent card
  blindSwapConfirm,  // both picked — awaiting confirm
  smartSwapTarget,   // pick opponent card to peek
  smartSwapDecide,   // opponent card peeked — pick your card to swap
  smartSwapConfirm,  // both cards chosen — confirm or cancel
}

class PowerSelectionState {
  final PowerStep step;
  final String? targetPlayerId;
  final int? myRow;
  final int? myCol;
  final int? theirRow;
  final int? theirCol;

  const PowerSelectionState({
    this.step = PowerStep.none,
    this.targetPlayerId,
    this.myRow,
    this.myCol,
    this.theirRow,
    this.theirCol,
  });

  PowerSelectionState copyWith({
    PowerStep? step,
    String? targetPlayerId,
    int? myRow,
    int? myCol,
    int? theirRow,
    int? theirCol,
  }) => PowerSelectionState(
        step: step ?? this.step,
        targetPlayerId: targetPlayerId ?? this.targetPlayerId,
        myRow: myRow ?? this.myRow,
        myCol: myCol ?? this.myCol,
        theirRow: theirRow ?? this.theirRow,
        theirCol: theirCol ?? this.theirCol,
      );
}

final _powerStateProvider =
    StateProvider<PowerSelectionState>((_) => const PowerSelectionState());

// ─── Game screen ──────────────────────────────────────────────────────────────

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameStateProvider);
    final localPlayer = ref.watch(localPlayerProvider);
    final roundEnd = ref.watch(roundEndProvider);
    final roundEndState = ref.watch(roundEndGameStateProvider);

    if (localPlayer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.highlight)),
      );
    }

    // Show inline round-end screen (no navigation — keeps revealed cards visible)
    if (roundEnd != null && roundEndState != null) {
      return _RoundEndScreen(
        gameState: roundEndState,
        localPlayer: localPlayer,
        roundEnd: roundEnd,
      );
    }

    if (gameState == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.highlight)),
      );
    }

    if (gameState.phase == 'initialPeek') {
      return _InitialPeekScreen(gameState: gameState, localPlayer: localPlayer);
    }

    return _PlayingScreen(gameState: gameState, localPlayer: localPlayer);
  }
}

// ─── Initial peek ──────────────────────────────────────────────────────────────

class _InitialPeekScreen extends ConsumerStatefulWidget {
  final GameStateModel gameState;
  final LocalPlayer localPlayer;
  const _InitialPeekScreen({required this.gameState, required this.localPlayer});

  @override
  ConsumerState<_InitialPeekScreen> createState() => _InitialPeekScreenState();
}

class _InitialPeekScreenState extends ConsumerState<_InitialPeekScreen> {
  bool _confirmed = false;

  /// Extract the bottom-row cards from own hand JSON.
  /// The server always sends the local player's own cards fully (not masked),
  /// so we can read them directly — no timing dependency on peek reveals.
  Map<(int, int), Map<String, dynamic>> _getBottomCards(Map<String, dynamic> myData) {
    final result = <(int, int), Map<String, dynamic>>{};
    final hand = myData['hand'] as List<dynamic>?;
    if (hand == null || hand.length < 2) return result;
    final bottomRow = hand[1] as List<dynamic>?;
    if (bottomRow == null) return result;
    for (int c = 0; c < bottomRow.length; c++) {
      final card = bottomRow[c];
      if (card is Map<String, dynamic> && card['hidden'] != true) {
        result[(1, c)] = card;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final gs = widget.gameState;
    final myData = gs.playerById(widget.localPlayer.id);
    if (myData == null) return const SizedBox();

    final bottomCards = _getBottomCards(myData);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Memorise Your Cards!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your two bottom cards are shown. Remember them!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 28),
                PlayerHand(
                  playerJson: myData,
                  isLocalPlayer: true,
                  peekedCardData: bottomCards,
                  dealIn: true,
                  flipStart: const Duration(milliseconds: 650),
                  flipStagger: const Duration(milliseconds: 80),
                ),
                const SizedBox(height: 32),
                // ── Who's ready? ──
                _ReadyList(gs: gs, localId: widget.localPlayer.id),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _confirmed
                      ? null
                      : () {
                          setState(() => _confirmed = true);
                          ref.read(gameClientProvider).initialPeekDone();
                        },
                  child: Text(_confirmed ? 'Waiting for others...' : "I've memorised my cards"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadyList extends StatelessWidget {
  final GameStateModel gs;
  final String localId;
  const _ReadyList({required this.gs, required this.localId});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Waiting for:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: gs.players.map((p) {
            final pid = p['id'] as String;
            final name = p['name'] as String;
            final isReady = gs.peekConfirmedIds.contains(pid);
            final isYou = pid == localId;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isReady
                    ? AppColors.highlight.withValues(alpha: 0.2)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isReady ? AppColors.highlight : Colors.white24,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isReady ? Icons.check_circle : Icons.hourglass_empty,
                    size: 13,
                    color: isReady ? AppColors.highlight : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isYou ? 'You' : name,
                    style: TextStyle(
                      fontSize: 12,
                      color: isReady ? AppColors.highlight : AppColors.textSecondary,
                      fontWeight: isReady ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Main playing screen ───────────────────────────────────────────────────────

class _PlayingScreen extends ConsumerStatefulWidget {
  final GameStateModel gameState;
  final LocalPlayer localPlayer;

  const _PlayingScreen({required this.gameState, required this.localPlayer});

  @override
  ConsumerState<_PlayingScreen> createState() => _PlayingScreenState();
}

class _PlayingScreenState extends ConsumerState<_PlayingScreen> {
  /// playerId → {(row,col) → cardJson} — stores actual card data while peeked
  final Map<String, Map<(int, int), Map<String, dynamic>>> _peekedCards = {};
  /// The opponent's card peeked via Red King — persisted for the swap decision
  Map<String, dynamic>? _smartSwapPeekedCard;
  /// Flash "SWAPPED!" top banner for N ms when a swap occurs
  bool _showSwapFlash = false;
  String _swapFlashText = '';
  int _swapFlashId = 0;
  /// Briefly shows red dot on discard after someone else grabs the slap
  bool _slapTaken = false;
  /// Whether the local player must give a card to an opponent after a successful slap
  bool _pendingGiveCard = false;
  String? _pendingGiveCardTargetId;
  /// When the server last confirmed the end of my move
  DateTime? _myMoveEndedAt;
  static const _repeatTapGuard = Duration(milliseconds: 800);
  /// When a finger last touched the screen, on this device's clock
  int _lastTouchUs = 0;
  /// Who tried to slap the current card, and when each one first appeared here
  SlapRankingPayload? _slapRanking;
  final Map<String, DateTime> _slapRowShownAt = {};
  static const _slapRowTime = Duration(seconds: 4);
  // Table animations
  final _deckKey = GlobalKey();
  final _discardKey = GlobalKey();
  final _drawnCardKey = GlobalKey();
  final Map<String, GlobalKey> _handKeys = {};
  final List<Widget> _tableAnimations = [];
  int _nextAnimationId = 0;
  /// 'playerId:row:col' → how many moving cards are using that slot right now
  final Map<String, int> _slotsInMotion = {};
  int _flightsToDiscard = 0;
  /// The discard shown until a card flying to the pile lands on it
  Map<String, dynamic>? _discardUnderFlight;
  int _flightsToMyDrawnCard = 0;
  /// The Queen/King pick being shown to everyone right now
  CardsPickedPayload? _activePick;
  final _tableKey = GlobalKey();
  final Map<String, GlobalKey> _slotKeys = {};

  GlobalKey _slotKey(String playerId, int row, int col) =>
      _slotKeys.putIfAbsent('$playerId:$row:$col', GlobalKey.new);

  /// Where a card slot is drawn right now, relative to the table.
  Rect? _slotRect(String playerId, int row, int col) {
    final slot = _slotKeys['$playerId:$row:$col']?.currentContext?.findRenderObject();
    final table = _tableKey.currentContext?.findRenderObject();
    if (slot is! RenderBox || table is! RenderBox || !slot.hasSize) return null;
    return slot.localToGlobal(Offset.zero, ancestor: table) & slot.size;
  }

  String _playerName(String id) =>
      gs.playerById(id)?['name'] as String? ?? 'Someone';

  GlobalKey _handKey(String playerId) =>
      _handKeys.putIfAbsent(playerId, GlobalKey.new);

  Rect? _keyRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    final table = _tableKey.currentContext?.findRenderObject();
    if (box is! RenderBox || table is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: table) & box.size;
  }

  /// A card-sized space in the middle of a player's hand.
  Rect? _handRect(String playerId) {
    final hand = _keyRect(_handKey(playerId));
    if (hand == null) return null;
    final size = playerId == myId ? const Size(64, 92) : const Size(46, 66);
    return Rect.fromCenter(center: hand.center, width: size.width, height: size.height);
  }

  /// Where a place on the table is on this screen right now. Your own drawn
  /// card sits in its panel; anyone else's is held at their hand.
  Rect? _spotRect(CardSpot spot) {
    switch (spot.kind) {
      case CardSpot.deck:
        return _keyRect(_deckKey);
      case CardSpot.discard:
        return _keyRect(_discardKey);
      case CardSpot.held:
        if (spot.playerId == myId) {
          return _keyRect(_drawnCardKey) ?? _handRect(myId);
        }
        return _handRect(spot.playerId!);
      default:
        return _slotRect(spot.playerId!, spot.row!, spot.col!);
    }
  }

  String _slotName(String playerId, int row, int col) => '$playerId:$row:$col';

  void _holdSlot(String name) =>
      _slotsInMotion[name] = (_slotsInMotion[name] ?? 0) + 1;

  void _releaseSlot(String name) {
    final left = (_slotsInMotion[name] ?? 1) - 1;
    if (left <= 0) {
      _slotsInMotion.remove(name);
    } else {
      _slotsInMotion[name] = left;
    }
  }

  Set<(int, int)> _hiddenSlotsOf(String playerId) => {
        for (final name in _slotsInMotion.keys)
          if (name.startsWith('$playerId:'))
            () {
              final parts = name.split(':');
              return (int.parse(parts[parts.length - 2]), int.parse(parts.last));
            }(),
      };

  /// What the discard pile shows: a card still in the air hasn't landed yet.
  Map<String, dynamic>? get _shownDiscard =>
      _flightsToDiscard > 0 ? _discardUnderFlight : gs.topDiscard;

  /// Runs before the game state that this animation leads to, so every card is
  /// still where it started and each flight can take its starting point now.
  void _playTableAnimation(TableAnimationPayload animation) {
    setState(() {
      for (final move in animation.moves) {
        _addFlight(move);
      }
      if (animation.highlight != null) {
        _addAnimation((key, remove) => LiftedCard(
              key: key,
              slot: () => _spotRect(animation.highlight!),
              duration: Duration(milliseconds: animation.highlightMs),
              onDone: remove,
            ));
      }
      if (animation.slapReveals.isNotEmpty) {
        for (final reveal in animation.slapReveals) {
          _addSlapReveal(reveal);
        }
      }
      if (animation.skippedPlayerId != null) _addSkippedBadge(animation.skippedPlayerId!);
      if (animation.reshuffled) _addReshuffle();
    });
  }

  void _addAnimation(Widget Function(Key key, void Function() remove) build) {
    final key = ValueKey(_nextAnimationId++);
    late final Widget widget;
    widget = build(key, () {
      if (mounted) setState(() => _tableAnimations.remove(widget));
    });
    _tableAnimations.add(widget);
  }

  void _addFlight(CardMove move) {
    final from = _spotRect(move.from);
    final landing = <VoidCallback>[];

    for (final spot in [move.from, move.to]) {
      if (spot.kind == CardSpot.slot) {
        final name = _slotName(spot.playerId!, spot.row!, spot.col!);
        _holdSlot(name);
        landing.add(() => _releaseSlot(name));
      }
    }
    if (move.to.kind == CardSpot.discard) {
      if (_flightsToDiscard == 0) _discardUnderFlight = gs.topDiscard;
      _flightsToDiscard++;
      landing.add(() => _flightsToDiscard--);
    }
    if (move.to.kind == CardSpot.held && move.to.playerId == myId) {
      _flightsToMyDrawnCard++;
      landing.add(() => _flightsToMyDrawnCard--);
    }

    // Started off-screen somehow: skip the flight but keep the game correct.
    if (from == null) {
      for (final undo in landing) {
        undo();
      }
      return;
    }
    _addAnimation((key, remove) => FlyingCard(
          key: key,
          from: from,
          to: () => _spotRect(move.to),
          card: move.card?.toJson(),
          delay: Duration(milliseconds: move.delayMs),
          // A drawn card stays in the player's hand until it's time to swap it in
          visibleWhileWaiting: move.from.kind == CardSpot.held,
          onLanded: () {
            for (final done in landing) {
              done();
            }
            remove();
          },
        ));
  }

  /// A spot above your own hand, side by side when several cards are up.
  Rect _revealSpot(int index) {
    const size = Size(56, 80);
    const gap = 8.0;
    final table = _keyRect(_tableKey) ?? Rect.zero;
    final hand = _keyRect(_handKey(myId));
    final top = (hand?.top ?? table.center.dy + 40) - size.height - 26;
    final count = _revealCount;
    final centerX = table.width / 2 +
        (index - (count - 1) / 2) * (size.width + gap);
    return Rect.fromLTWH(centerX - size.width / 2, top, size.width, size.height);
  }

  int _revealCount = 0;
  int _revealsFinished = 0;

  void _addSlapReveal(SlapReveal reveal) {
    final from = _slotRect(reveal.targetId, reveal.row, reveal.col) ??
        _handRect(reveal.targetId);
    if (from == null) return;
    final slot = _slotName(reveal.targetId, reveal.row, reveal.col);
    _holdSlot(slot);
    final isRight = reveal.result == 'right';
    // Spots fill left to right, and start over once the cards up front are gone.
    if (_revealCount == _revealsFinished) {
      _revealCount = 0;
      _revealsFinished = 0;
    }
    final index = _revealCount++;

    _addAnimation((key, remove) => SlapRevealCard(
          key: key,
          from: from,
          spot: () => _revealSpot(index),
          goesTo: () => isRight
              ? _keyRect(_discardKey)
              : _slotRect(reveal.targetId, reveal.row, reveal.col),
          card: reveal.card.toJson(),
          result: reveal.result,
          name: reveal.playerId == myId ? 'You' : _playerName(reveal.playerId),
          onDone: () {
            _releaseSlot(slot);
            _revealsFinished++;
            remove();
          },
        ));
  }

  void _addSkippedBadge(String playerId) {
    _addAnimation((key, remove) => SkippedBadge(
          key: key,
          hand: () => _keyRect(_handKey(playerId)),
          onDone: remove,
        ));
  }

  /// The discard pile sweeping back into the deck.
  void _addReshuffle() {
    final from = _keyRect(_discardKey);
    if (from == null) return;
    for (var i = 0; i < 6; i++) {
      _addAnimation((key, remove) => FlyingCard(
            key: key,
            from: from,
            to: () => _keyRect(_deckKey),
            delay: Duration(milliseconds: 70 * i),
            onLanded: remove,
          ));
    }
    _triggerSwapFlash('Discard pile shuffled into a new deck');
  }

  /// The ranking rows that haven't reached their 4 seconds yet.
  List<SlapRankRow> _visibleSlapRows() {
    final entries = _slapRanking?.entries ?? const <SlapRankEntry>[];
    final now = DateTime.now();
    return [
      for (var i = 0; i < entries.length; i++)
        if (now.difference(_slapRowShownAt[entries[i].playerId] ?? now) < _slapRowTime)
          SlapRankRow(
            rank: i + 1,
            name: entries[i].playerId == myId ? 'You' : _playerName(entries[i].playerId),
            gapMs: entries[i].gapMs,
            result: entries[i].result,
          ),
    ];
  }

  void _sendSlap(String targetId, int row, int col) {
    ref.read(gameClientProvider).matchCard(
          targetId, row, col, _shownDiscard?['rank'] as String?, _lastTouchUs);
  }

  String _peekHoldMessage(String actorId, String targetId) {
    final position = gs.peekHoldRow != null && gs.peekHoldCol != null
        ? '${cardPositionName(gs.peekHoldRow!, gs.peekHoldCol!)} '
        : '';
    final String looking;
    if (actorId == myId) {
      looking = targetId == myId
          ? 'You are looking at your own ${position}card'
          : "You are looking at ${_playerName(targetId)}'s ${position}card";
    } else if (targetId == actorId) {
      looking = '${_playerName(actorId)} is looking at their own ${position}card';
    } else if (targetId == myId) {
      looking = '${_playerName(actorId)} is looking at your ${position}card';
    } else {
      looking = "${_playerName(actorId)} is looking at ${_playerName(targetId)}'s ${position}card";
    }
    return '$looking — game on hold';
  }

  String _pickMessage(CardsPickedPayload pick) {
    if (pick.actorId == myId) {
      return 'You picked a card from ${_playerName(pick.targetId)}';
    }
    if (pick.targetId == myId) {
      return '${_playerName(pick.actorId)} picked one of your cards';
    }
    return '${_playerName(pick.actorId)} picked a card from ${_playerName(pick.targetId)}';
  }

  @override
  void initState() {
    super.initState();
    // Listen to peek reveals — store actual card data
    ref.listenManual(peekRevealProvider, (_, reveal) {
      if (reveal == null || reveal.isInitialPeek) return;
      final key = reveal.targetPlayerId;
      final cardJson = reveal.card.toJson();
      final isSmartSwapPeek =
          ref.read(_powerStateProvider).step == PowerStep.smartSwapDecide;
      setState(() {
        _peekedCards[key] = {...?_peekedCards[key], (reveal.row, reveal.col): cardJson};
        // Cache for smart swap decision (persists until swap is resolved)
        if (isSmartSwapPeek) _smartSwapPeekedCard = cardJson;
      });
      // A 7/8/9/10 peek is covered again when the server ends the hold
    });

    // Card movements announced by the server, played the same on every screen
    ref.listenManual(tableAnimationProvider, (_, animation) {
      if (animation != null) _playTableAnimation(animation);
    });

    // Slap ranking: each row shows for 4 seconds, and a new card starts a new list
    ref.listenManual(slapRankingProvider, (_, ranking) {
      if (ranking == null) return;
      setState(() {
        if (ranking.cardNo != _slapRanking?.cardNo) _slapRowShownAt.clear();
        _slapRanking = ranking;
        for (final entry in ranking.entries) {
          _slapRowShownAt.putIfAbsent(entry.playerId, DateTime.now);
        }
      });
      Future.delayed(_slapRowTime, () {
        if (mounted) setState(() {});
      });
    });

    // Queen/King: show everyone which positions were picked
    ref.listenManual(cardsPickedProvider, (_, pick) {
      if (pick == null) return;
      setState(() => _activePick = pick);
      _triggerSwapFlash(_pickMessage(pick));
    });

    // Listen for swap actions, successful slaps, and pending give-card state
    ref.listenManual(gameStateProvider, (prev, next) {
      if (next == null) return;
      final prevLog = prev?.actionLog ?? [];
      final nextLog = next.actionLog;
      if (nextLog.isNotEmpty && (prevLog.isEmpty || nextLog.first != prevLog.first)) {
        final latest = nextLog.first;
        if (latest.contains('swap') || latest.contains('Swap')) {
          _triggerSwapFlash(latest);
        }
        // A wrong slap adds a card, so make sure everyone sees why
        if (latest.contains('❌')) {
          _triggerSwapFlash(latest);
        }
        // Successful slap by someone else → briefly show red dot on discard
        if (latest.contains('⚡') && !next.matchWindowOpen) {
          setState(() => _slapTaken = true);
          Future.delayed(const Duration(milliseconds: 1800), () {
            if (mounted) setState(() => _slapTaken = false);
          });
        }
      }
      // Track pending give-card state
      final myId = ref.read(localPlayerProvider)?.id;
      // The peek hold is over: cover the card again
      if (prev?.peekHoldActorId != null && next.peekHoldActorId == null) {
        setState(_peekedCards.clear);
      }
      // Note when my move lands, so a repeat tap on my card isn't taken as a slap.
      // Not after a peek hold: that move was 4 seconds ago, and everyone's slap
      // opens together.
      if (prev != null &&
          prev.peekHoldActorId == null &&
          prev.currentPlayerId == myId &&
          prev.turnPhase != 'waitingForDraw' &&
          (next.currentPlayerId != myId || next.turnPhase == 'waitingForDraw')) {
        _myMoveEndedAt = DateTime.now();
      }
      final needsGive = next.pendingGiveCardAttackerId != null &&
          next.pendingGiveCardAttackerId == myId;
      if (_pendingGiveCard != needsGive) {
        setState(() {
          _pendingGiveCard = needsGive;
          _pendingGiveCardTargetId = needsGive ? next.pendingGiveCardTargetId : null;
        });
      }
    });
  }

  String _giveCardTargetName() {
    if (_pendingGiveCardTargetId == null) return 'opponent';
    final player = gs.players.firstWhere(
      (p) => p['id'] == _pendingGiveCardTargetId,
      orElse: () => <String, dynamic>{},
    );
    return player['name'] as String? ?? 'opponent';
  }

  void _triggerSwapFlash(String msg) {
    // Each banner gets its full time, even if it replaced an earlier one
    final flashId = ++_swapFlashId;
    setState(() {
      _showSwapFlash = true;
      _swapFlashText = msg;
    });
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted && flashId == _swapFlashId) {
        setState(() => _showSwapFlash = false);
      }
    });
  }

  bool get isMyTurn =>
      widget.gameState.currentPlayerId == widget.localPlayer.id;
  String get myId => widget.localPlayer.id;
  GameStateModel get gs => widget.gameState;

  void _openHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => HistorySheet(log: gs.actionLog),
    );
  }

  @override
  Widget build(BuildContext context) {
    final powerSel = ref.watch(_powerStateProvider);
    final slapRows = _visibleSlapRows();

    return Scaffold(
      body: SafeArea(
        child: Listener(
          // The moment of touch decides slap order, not the moment of lifting
          onPointerDown: (_) =>
              _lastTouchUs = ref.read(gameClientProvider).clock.localNowUs,
          child: Stack(
          key: _tableKey,
          children: [
            Column(
              children: [
                StatusBox(
                  gs: gs,
                  localPlayerId: myId,
                  onHistoryTap: () => _openHistory(context),
                ),
                Expanded(child: _buildTable(powerSel)),
                _buildActionBar(powerSel),
              ],
            ),
            // Slap status — on the side, and never blocks taps on the cards
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: const Alignment(1, 0.2), // below the power instructions
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SlapStatus(
                          isActive: gs.matchWindowOpen && !_iAmEliminated,
                        ),
                        // Above the badge, without moving it
                        if (slapRows.isNotEmpty)
                          Positioned(
                            right: 0,
                            bottom: 78,
                            child: SlapRanking(
                              triedCount: _slapRanking!.entries.length,
                              rows: slapRows,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Card movements — play over the table without holding up the game
            Positioned.fill(
              child: IgnorePointer(
                child: Stack(
                  children: [
                    if (gs.peekHoldTargetId != null &&
                        gs.peekHoldRow != null &&
                        gs.peekHoldCol != null)
                      SlotPulse(
                        glow: gs.peekHoldActorId != myId,
                        slot: () => _slotRect(
                          gs.peekHoldTargetId!,
                          gs.peekHoldRow!,
                          gs.peekHoldCol!,
                        ),
                      ),
                    ..._tableAnimations,
                  ],
                ),
              ),
            ),
            // Queen/King pick — plays over the table without holding up the game
            if (_activePick != null)
              Positioned.fill(
                child: CardPickOverlay(
                  key: ObjectKey(_activePick),
                  slots: [
                    if (_activePick!.actorRow != null &&
                        _activePick!.actorCol != null)
                      () => _slotRect(
                            _activePick!.actorId,
                            _activePick!.actorRow!,
                            _activePick!.actorCol!,
                          ),
                    () => _slotRect(
                          _activePick!.targetId,
                          _activePick!.targetRow,
                          _activePick!.targetCol,
                        ),
                  ],
                  onDone: () => setState(() => _activePick = null),
                ),
              ),
            // Give-card prompt — shown when attacker must give a card after opponent slap
            if (_pendingGiveCard)
              Positioned(
                top: 44,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  color: AppColors.highlight.withValues(alpha: 0.92),
                  child: Text(
                    'Tap one of YOUR cards to give to ${_giveCardTargetName()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            // Swap flash — slim top banner
            if (_showSwapFlash)
              Positioned(
                top: 44,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    color: AppColors.gold.withValues(alpha: 0.88),
                    child: Text(
                      _swapFlashText,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            // Peek hold — shown to everyone while a peeked card is on screen
            if (gs.peekHoldActorId != null && gs.peekHoldTargetId != null)
              Positioned(
                top: 44,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    color: AppColors.highlight.withValues(alpha: 0.92),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.visibility, size: 15, color: Colors.black87),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _peekHoldMessage(gs.peekHoldActorId!, gs.peekHoldTargetId!),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          ),
        ),
      ),
    );
  }

  bool get _iAmEliminated =>
      gs.playerById(myId)?['isEliminated'] as bool? ?? false;

  Widget _buildTable(PowerSelectionState powerSel) {
    final myData = gs.playerById(myId);
    final opponents = gs.players.where((p) => p['id'] != myId).toList();

    final myHighlighted = (powerSel.step == PowerStep.blindSwapTarget ||
            powerSel.step == PowerStep.blindSwapConfirm ||
            powerSel.step == PowerStep.smartSwapConfirm) &&
        powerSel.myRow != null && powerSel.myCol != null
        ? {(powerSel.myRow!, powerSel.myCol!)}
        : <(int, int)>{};

    return Column(
      children: [
        // ── Opponents (top) ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: opponents.map((opp) {
              final oid = opp['id'] as String;
              return _buildOpponentHand(opp, oid, gs.currentPlayerId == oid, powerSel);
            }).toList(),
          ),
        ),

        // ── Centre: draw pile + discard ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDrawPile(),
              const SizedBox(width: 20),
              _buildDiscardPile(),
            ],
          ),
        ),

        // ── Mid-turn UI (power / drawn card) — compact horizontal layout ─────
        if (isMyTurn && gs.drawnCard != null) _buildDrawnCardCompact(powerSel),
        if (isMyTurn && gs.turnPhase == 'usingPower' && gs.peekHoldActorId == null) ...[
          _buildPowerInstructions(powerSel),
          if (powerSel.step == PowerStep.smartSwapConfirm)
            _buildSmartSwapComparison(powerSel),
        ],

        // ── Push my hand to the bottom ───────────────────────────────────────
        const Spacer(),

        // ── My hand ──────────────────────────────────────────────────────────
        if (myData != null) ...[
          if (_iAmEliminated)
            Container(
              margin: const EdgeInsets.only(bottom: 6, left: 12, right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cancel, color: AppColors.danger, size: 13),
                  SizedBox(width: 6),
                  Text(
                    'Eliminated — too many wrong slaps!',
                    style: TextStyle(color: AppColors.danger, fontSize: 11),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KeyedSubtree(
              key: _handKey(myId),
              child: PlayerHand(
                playerJson: myData,
                isLocalPlayer: true,
                isCurrentTurn: isMyTurn && !_iAmEliminated,
                peekedCardData: _peekedCards[myId] ?? {},
                highlightedSlots: myHighlighted,
                slotKey: (row, col) => _slotKey(myId, row, col),
                hiddenSlots: _hiddenSlotsOf(myId),
                onCardTap: _iAmEliminated ? null : _onMyCardTap(powerSel),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Power instructions banner — shown whenever in usingPower phase.
  Widget _buildPowerInstructions(PowerSelectionState powerSel) {
    String instruction;
    switch (powerSel.step) {
      case PowerStep.peekOwn:
        instruction = 'Tap one of YOUR cards to peek at it';
      case PowerStep.peekOpponent:
        instruction = "Tap any opponent's card to secretly peek";
      case PowerStep.blindSwapSelf:
        instruction = 'Step 1/2 — Tap YOUR card to swap';
      case PowerStep.blindSwapTarget:
        instruction = "Step 2/2 — Now tap an OPPONENT'S card";
      case PowerStep.blindSwapConfirm:
        instruction = 'Both cards selected. Confirm or change below.';
      case PowerStep.smartSwapTarget:
        instruction = "Tap an opponent's card to peek it";
      case PowerStep.smartSwapDecide:
        instruction = 'Now tap YOUR card to compare — or skip below';
      case PowerStep.smartSwapConfirm:
        instruction = 'Both cards shown. Confirm swap or cancel.';
      default:
        instruction = 'Choose your action';
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.highlight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.highlight.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app, color: AppColors.highlight, size: 16),
          const SizedBox(width: 8),
          Text(
            instruction,
            style: const TextStyle(color: AppColors.highlight, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Shows both selected cards side-by-side during Red King confirm step.
  Widget _buildSmartSwapComparison(PowerSelectionState powerSel) {
    final myData = gs.playerById(myId);
    if (myData == null ||
        powerSel.myRow == null ||
        powerSel.myCol == null) return const SizedBox();

    // Own card: server always sends our cards as full JSON
    final myHand = myData['hand'] as List<dynamic>;
    final myCardJson = myHand[powerSel.myRow!][powerSel.myCol!]
        as Map<String, dynamic>?;

    // Opponent's card: cached when the peek reveal arrived
    final theirCardJson = _smartSwapPeekedCard;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.highlight.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your card',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 6),
              CardWidget(
                cardJson: myCardJson,
                cardState: myCardJson != null
                    ? CardState.faceUp
                    : CardState.faceDown,
                width: 64,
                height: 90,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz, color: AppColors.highlight, size: 28),
                SizedBox(height: 4),
                Text('swap?',
                    style: TextStyle(
                        color: AppColors.highlight, fontSize: 11)),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Their card",
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 6),
              CardWidget(
                cardJson: theirCardJson,
                cardState: theirCardJson != null
                    ? CardState.faceUp
                    : CardState.faceDown,
                width: 64,
                height: 90,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpponentHand(
    Map<String, dynamic> opp,
    String oid,
    bool isTheirTurn,
    PowerSelectionState powerSel,
  ) {
    final isTargetable = _isOpponentTargetable(powerSel);
    // In confirm step, highlight the chosen opponent card slot
    final isConfirmStep = powerSel.step == PowerStep.blindSwapConfirm ||
        powerSel.step == PowerStep.smartSwapConfirm;
    final theirHighlighted = (isConfirmStep &&
            powerSel.targetPlayerId == oid &&
            powerSel.theirRow != null &&
            powerSel.theirCol != null)
        ? {(powerSel.theirRow!, powerSel.theirCol!)}
        : <(int, int)>{};

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: isTargetable
            ? Border.all(
                color: AppColors.highlight.withValues(alpha: 0.5), width: 1.5)
            : null,
        borderRadius: BorderRadius.circular(12),
        color: isTargetable
            ? AppColors.highlight.withValues(alpha: 0.05)
            : null,
      ),
      child: KeyedSubtree(
        key: _handKey(oid),
        child: PlayerHand(
          playerJson: opp,
          isLocalPlayer: false,
          isCurrentTurn: isTheirTurn,
          peekedCardData: _peekedCards[oid] ?? {},
          highlightedSlots: theirHighlighted,
          slotKey: (row, col) => _slotKey(oid, row, col),
          hiddenSlots: _hiddenSlotsOf(oid),
          onCardTap: _canTapOpponentCard(powerSel, oid)
              ? (row, col) => _onOpponentCardTap(oid, row, col, powerSel)
              : null,
        ),
      ),
    );
  }

  Widget _buildDrawPile() {
    return GestureDetector(
      onTap: isMyTurn && gs.turnPhase == 'waitingForDraw'
          ? () => ref.read(gameClientProvider).drawFromPile()
          : null,
      child: Column(
        children: [
          Stack(
            key: _deckKey,
            children: [
              for (int i = 0; i < 3 && i < gs.drawPileCount; i++)
                Positioned(
                  top: i * 1.5,
                  left: i * 0.5,
                  child: const _BackFaceSmall(),
                ),
              const _BackFaceSmall(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${gs.drawPileCount} cards',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          if (isMyTurn && gs.turnPhase == 'waitingForDraw')
            const Text(
              'TAP TO DRAW',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.highlight,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscardPile() {
    final canSlap = gs.matchWindowOpen;
    final dotColor = _slapTaken
        ? AppColors.danger
        : canSlap
            ? AppColors.highlight
            : Colors.transparent;
    final dotGlow = canSlap && !_slapTaken;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            KeyedSubtree(
              key: _discardKey,
              child: CardWidget(
                cardJson: _shownDiscard,
                cardState: _shownDiscard != null ? CardState.faceUp : CardState.empty,
                animateFlip: false,
                width: 52,
                height: 74,
              ),
            ),
            // Status dot — top-right corner of discard card
            if (canSlap || _slapTaken)
              Positioned(
                top: -4,
                right: -4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    boxShadow: dotGlow
                        ? [BoxShadow(
                            color: AppColors.highlight.withValues(alpha: 0.8),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )]
                        : null,
                    border: Border.all(color: Colors.black45, width: 1),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Discard',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            if (canSlap) ...[
              const SizedBox(width: 4),
              const Text(
                'SLAP!',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.highlight,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Compact horizontal drawn-card row: [card] [label + button]
  Widget _buildDrawnCardCompact(PowerSelectionState powerSel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.highlight.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyedSubtree(
              key: _drawnCardKey,
              child: Opacity(
                opacity: _flightsToMyDrawnCard > 0 ? 0 : 1,
                child: CardWidget(
                  cardJson: gs.drawnCard,
                  cardState: CardState.faceUp,
                  width: 52,
                  height: 74,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (gs.turnPhase == 'cardDrawn') ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'You drew this card',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  ElevatedButton(
                    onPressed: () {
                      final card = gs.drawnCard;
                      if (card != null) {
                        _initPowerStep(
                          card['rank'] as String? ?? '',
                          card['suit'] as String? ?? '',
                        );
                      }
                      ref.read(gameClientProvider).discardDrawn();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Discard & use power', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'or tap your card below to swap',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(PowerSelectionState powerSel) {
    if (!isMyTurn || _iAmEliminated) return const SizedBox(height: 16);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Blind swap confirm ──
          if (powerSel.step == PowerStep.blindSwapConfirm) ...[
            Text(
              'Swap your card (row ${powerSel.myRow! + 1}, col ${powerSel.myCol! + 1}) '
              'with their card (row ${powerSel.theirRow! + 1}, col ${powerSel.theirCol! + 1})?',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(gameClientProvider).useBlindSwap(
                      powerSel.myRow!, powerSel.myCol!,
                      powerSel.targetPlayerId!,
                      powerSel.theirRow!, powerSel.theirCol!,
                    );
                    ref.read(_powerStateProvider.notifier).state =
                        const PowerSelectionState();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.highlight,
                    foregroundColor: Colors.black87,
                  ),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Confirm Swap'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    // Reset — let player pick again
                    ref.read(_powerStateProvider.notifier).state =
                        const PowerSelectionState(step: PowerStep.blindSwapSelf);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.textSecondary),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Change Cards'),
                ),
              ],
            ),
          ],

          // ── Smart swap confirm ──
          if (powerSel.step == PowerStep.smartSwapConfirm) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    final tid = powerSel.targetPlayerId!;
                    final tr = powerSel.theirRow!;
                    final tc = powerSel.theirCol!;
                    ref.read(gameClientProvider).useSmartSwapCommit(
                      powerSel.myRow!, powerSel.myCol!, tid, tr, tc,
                    );
                    setState(() {
                      _smartSwapPeekedCard = null;
                      _peekedCards[tid]?.remove((tr, tc));
                    });
                    ref.read(_powerStateProvider.notifier).state =
                        const PowerSelectionState();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.highlight,
                    foregroundColor: Colors.black87,
                  ),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Confirm Swap'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final tid = powerSel.targetPlayerId!;
                    final tr = powerSel.theirRow!;
                    final tc = powerSel.theirCol!;
                    ref.read(gameClientProvider).useSmartSwapCommit(
                      null, null, tid, tr, tc,
                    );
                    setState(() {
                      _smartSwapPeekedCard = null;
                      _peekedCards[tid]?.remove((tr, tc));
                    });
                    ref.read(_powerStateProvider.notifier).state =
                        const PowerSelectionState();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.textSecondary),
                  ),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancel'),
                ),
              ],
            ),
          ],

          // ── Smart swap decide: skip without swapping ──
          if (gs.turnPhase == 'usingPower' &&
              powerSel.step == PowerStep.smartSwapDecide)
            OutlinedButton.icon(
              onPressed: () {
                final tid = powerSel.targetPlayerId!;
                final tr = powerSel.theirRow!;
                final tc = powerSel.theirCol!;
                ref.read(gameClientProvider).useSmartSwapCommit(
                  null, null, tid, tr, tc,
                );
                setState(() {
                  _smartSwapPeekedCard = null;
                  _peekedCards[tid]?.remove((tr, tc));
                });
                ref.read(_powerStateProvider.notifier).state =
                    const PowerSelectionState();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.textSecondary),
              ),
              icon: const Icon(Icons.close, size: 16),
              label: const Text("Don't Swap — Skip"),
            ),

          // ── Skip power (for non-confirm, non-smartSwap steps) ──
          if (gs.turnPhase == 'usingPower' &&
              powerSel.step != PowerStep.none &&
              powerSel.step != PowerStep.blindSwapConfirm &&
              powerSel.step != PowerStep.smartSwapDecide &&
              powerSel.step != PowerStep.smartSwapConfirm)
            TextButton(
              onPressed: () {
                ref.read(_powerStateProvider.notifier).state =
                    const PowerSelectionState();
                ref.read(gameClientProvider).skipPower();
              },
              child: const Text('Skip power',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),

          // ── Call CABO ──
          if (gs.turnPhase == 'waitingForDraw' && !gs.isCaboCalled)
            ElevatedButton(
              onPressed: () => ref.read(gameClientProvider).callCabo(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
              ),
              child: const Text('Call CABO'),
            ),
        ],
      ),
    );
  }

  // ─── Tap handlers ──────────────────────────────────────────────────────────

  void Function(int, int)? _onMyCardTap(PowerSelectionState powerSel) {
    // Pending give-card comes first: slapping runs throughout the turn, so the
    // player owing a card may also be holding a drawn card.
    if (_pendingGiveCard) {
      return (row, col) => ref.read(gameClientProvider).giveCard(row, col);
    }
    // Swap drawn card with hand
    if (isMyTurn && gs.turnPhase == 'cardDrawn') {
      return (row, col) =>
          ref.read(gameClientProvider).swapDrawnWithHand(row, col);
    }
    // Power: peek own
    if (isMyTurn &&
        gs.turnPhase == 'usingPower' &&
        powerSel.step == PowerStep.peekOwn) {
      return (row, col) {
        ref.read(gameClientProvider).usePeekOwn(row, col);
        ref.read(_powerStateProvider.notifier).state =
            const PowerSelectionState();
      };
    }
    // Power: blind swap self-selection
    if (isMyTurn &&
        gs.turnPhase == 'usingPower' &&
        powerSel.step == PowerStep.blindSwapSelf) {
      return (row, col) {
        ref.read(_powerStateProvider.notifier).state = powerSel.copyWith(
          step: PowerStep.blindSwapTarget,
          myRow: row,
          myCol: col,
        );
      };
    }
    // Power: smart swap (Red King) — pick your card, then show comparison + confirm
    if (isMyTurn &&
        gs.turnPhase == 'usingPower' &&
        powerSel.step == PowerStep.smartSwapDecide) {
      return (row, col) {
        ref.read(_powerStateProvider.notifier).state = powerSel.copyWith(
          step: PowerStep.smartSwapConfirm,
          myRow: row,
          myCol: col,
        );
      };
    }
    // Match window: any player can slap their own cards (not during active power step)
    if (gs.matchWindowOpen && powerSel.step == PowerStep.none) {
      return (row, col) {
        if (_isRepeatTapAfterMyMove) return;
        _sendSlap(myId, row, col);
      };
    }
    return null;
  }

  bool get _isRepeatTapAfterMyMove {
    final endedAt = _myMoveEndedAt;
    return endedAt != null &&
        DateTime.now().difference(endedAt) < _repeatTapGuard;
  }

  bool _isOpponentTargetable(PowerSelectionState powerSel) {
    return isMyTurn &&
        gs.turnPhase == 'usingPower' &&
        (powerSel.step == PowerStep.peekOpponent ||
            powerSel.step == PowerStep.blindSwapTarget ||
            powerSel.step == PowerStep.smartSwapTarget);
    // Note: blindSwapConfirm is NOT targetable — locked in confirm step
  }

  bool _canTapOpponentCard(PowerSelectionState powerSel, String oid) {
    // During match window: any player can slap an opponent's card
    if (gs.matchWindowOpen && powerSel.step == PowerStep.none && !_iAmEliminated) {
      return true;
    }
    if (!isMyTurn || gs.turnPhase != 'usingPower') return false;
    return powerSel.step == PowerStep.peekOpponent ||
        powerSel.step == PowerStep.blindSwapTarget ||
        powerSel.step == PowerStep.smartSwapTarget;
  }

  void _selectOpponentTarget(String oid, PowerSelectionState powerSel) {
    ref.read(_powerStateProvider.notifier).state =
        powerSel.copyWith(targetPlayerId: oid);
  }

  void _onOpponentCardTap(
    String oid,
    int row,
    int col,
    PowerSelectionState powerSel,
  ) {
    final client = ref.read(gameClientProvider);
    // Match window: slap an opponent's card
    if (gs.matchWindowOpen && powerSel.step == PowerStep.none) {
      _sendSlap(oid, row, col);
      return;
    }
    switch (powerSel.step) {
      case PowerStep.peekOpponent:
        client.usePeekOpponent(oid, row, col);
        ref.read(_powerStateProvider.notifier).state =
            const PowerSelectionState();

      case PowerStep.blindSwapTarget:
        // Don't execute yet — go to confirm step so player can verify or change
        ref.read(_powerStateProvider.notifier).state = powerSel.copyWith(
          step: PowerStep.blindSwapConfirm,
          targetPlayerId: oid,
          theirRow: row,
          theirCol: col,
        );

      case PowerStep.smartSwapTarget:
        client.useSmartSwapPeek(oid, row, col);
        ref.read(_powerStateProvider.notifier).state = powerSel.copyWith(
          step: PowerStep.smartSwapDecide,
          targetPlayerId: oid,
          theirRow: row,
          theirCol: col,
        );

      default:
        break;
    }
  }

  void _initPowerStep(String rank, String suit) {
    PowerStep step;
    switch (rank) {
      case 'seven':
      case 'eight':
        step = PowerStep.peekOwn;
      case 'nine':
      case 'ten':
        step = PowerStep.peekOpponent;
      case 'queen':
        step = PowerStep.blindSwapSelf;
      case 'king':
        step = (suit == 'hearts' || suit == 'diamonds')
            ? PowerStep.smartSwapTarget
            : PowerStep.none;
      default:
        step = PowerStep.none;
    }
    ref.read(_powerStateProvider.notifier).state =
        PowerSelectionState(step: step);
  }
}

// ─── Round end screen ────────────────────────────────────────────────────────

class _RoundEndScreen extends ConsumerWidget {
  final GameStateModel gameState;
  final LocalPlayer localPlayer;
  final RoundEndPayload roundEnd;

  const _RoundEndScreen({
    required this.gameState,
    required this.localPlayer,
    required this.roundEnd,
  });

  Map<(int, int), Map<String, dynamic>> _extractAllCards(
      Map<String, dynamic> playerJson) {
    final result = <(int, int), Map<String, dynamic>>{};
    final hand = playerJson['hand'] as List<dynamic>?;
    if (hand == null) return result;
    for (int r = 0; r < hand.length; r++) {
      final row = hand[r] as List<dynamic>?;
      if (row == null) continue;
      for (int c = 0; c < (row.length); c++) {
        final card = row[c];
        if (card is Map<String, dynamic> && card['hidden'] != true) {
          result[(r, c)] = card;
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final winner = roundEnd.scores.firstWhere((s) => s.isWinner);
    final iWon = localPlayer.id == winner.playerId;
    final scoreMap = {for (final s in roundEnd.scores) s.playerId: s};

    final caller = gameState.caboCallerId == null
        ? null
        : gameState.playerById(gameState.caboCallerId!);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
          children: [
            // ── Winner banner ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                border: const Border(
                  bottom: BorderSide(color: AppColors.gold, width: 1),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    iWon ? '🎉 You Win!' : '🏆 ${winner.playerName} Wins!',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Round Over — all cards revealed',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),

            // ── All player hands + scores ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: gameState.players.map((pData) {
                    final pid = pData['id'] as String;
                    final score = scoreMap[pid];
                    final allCards = _extractAllCards(pData);
                    return _PlayerRevealCard(
                      playerJson: pData,
                      isLocalPlayer: pid == localPlayer.id,
                      score: score,
                      allCards: allCards,
                      // One player's cards after another, once CABO! has shown
                      flipStart: Duration(
                        milliseconds: (caller != null ? 1100 : 200) +
                            500 * gameState.players.indexOf(pData),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // ── Next round ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      final name = localPlayer.name;
                      resetGameSession(ref);
                      ref.read(gameClientProvider).joinLobby(name);
                      context.go('/lobby');
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: const Text('Play Again'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      resetGameSession(ref);
                      context.go('/');
                    },
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          ],
            ),
            if (caller != null)
              Positioned.fill(
                child: CaboSplash(name: 'called by ${caller['name']}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRevealCard extends StatelessWidget {
  final Map<String, dynamic> playerJson;
  final bool isLocalPlayer;
  final PlayerScore? score;
  final Map<(int, int), Map<String, dynamic>> allCards;
  final Duration flipStart;

  const _PlayerRevealCard({
    required this.playerJson,
    required this.isLocalPlayer,
    required this.score,
    required this.allCards,
    required this.flipStart,
  });

  @override
  Widget build(BuildContext context) {
    final isWinner = score?.isWinner ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWinner
            ? AppColors.gold.withValues(alpha: 0.1)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWinner ? AppColors.gold : Colors.white24,
          width: isWinner ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerHand(
            playerJson: playerJson,
            isLocalPlayer: isLocalPlayer,
            peekedCardData: allCards,
            flipStart: flipStart,
            flipStagger: const Duration(milliseconds: 90),
          ),
          const SizedBox(height: 10),
          if (score != null) ...[
            if (isWinner)
              const Icon(Icons.emoji_events, color: AppColors.gold, size: 18),
            Text(
              '${score!.totalValue} pts',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isWinner ? AppColors.gold : AppColors.textPrimary,
              ),
            ),
            if (score!.calledCabo)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CABO',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// Mini card back for draw pile stack
class _BackFaceSmall extends StatelessWidget {
  const _BackFaceSmall();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 74,
      decoration: BoxDecoration(
        color: AppColors.cardBack,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
    );
  }
}
