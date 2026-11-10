import 'dart:async';
import 'dart:math';

import 'package:cabo/core/server_config.dart';
import 'package:cabo/networking/game_client.dart';
import 'package:cabo/networking/seat_store.dart';
import 'package:cabo_shared/models/messages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Client provider ──────────────────────────────────────────────────────────

final gameClientProvider = Provider<GameClient>((ref) {
  final client = GameClient();
  ref.onDispose(client.dispose);
  return client;
});

// ─── Connection state ─────────────────────────────────────────────────────────

enum ConnectionStatus { disconnected, connecting, connected, error }

class ConnectionState {
  final ConnectionStatus status;
  final String? error;
  const ConnectionState(this.status, [this.error]);
}

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  final GameClient client;

  ConnectionNotifier(this.client)
      : super(const ConnectionState(ConnectionStatus.disconnected));

  /// Connects synchronously — the WebSocket sink buffers messages until open.
  /// Connection success is confirmed reactively via the 'welcome' message.
  void connect(String room) {
    state = const ConnectionState(ConnectionStatus.connected);
    client.connect(roomSocketUri(room));
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>((ref) {
  return ConnectionNotifier(ref.watch(gameClientProvider));
});

// ─── Local player info ────────────────────────────────────────────────────────

class LocalPlayer {
  final String id;
  final String name;
  const LocalPlayer({required this.id, required this.name});
}

final localPlayerProvider = StateProvider<LocalPlayer?>((_) => null);

/// The code of the table this player is sitting at, as sent by the server.
final roomCodeProvider = StateProvider<String?>((_) => null);

/// Why a player couldn't get or keep a seat. The lobby shows it and goes home.
final lobbyErrorProvider = StateProvider<String?>((_) => null);

// ─── Saved seat and reconnecting ──────────────────────────────────────────────

/// Device storage for the seat. Opened in main() before the app starts.
final seatStoreProvider = Provider<SeatStore>((_) => const SeatStore(null));

class SavedSeatNotifier extends StateNotifier<SavedSeat?> {
  final SeatStore _store;

  SavedSeatNotifier(this._store) : super(_store.load());

  void save(SavedSeat seat) {
    _store.save(seat);
    state = seat;
  }

  void clear() {
    _store.clear();
    state = null;
  }
}

/// The game seat this device can get back into, if any.
final savedSeatProvider = StateNotifierProvider<SavedSeatNotifier, SavedSeat?>(
    (ref) => SavedSeatNotifier(ref.watch(seatStoreProvider)));

enum ReconnectStatus { idle, reconnecting, failed, replaced }

class ReconnectState {
  final ReconnectStatus status;
  final int attempt;
  final String? message;

  const ReconnectState(this.status, {this.attempt = 0, this.message});
}

/// Gets a dropped player back into their seat: tries straight away, then again
/// after 1, 2, 4 and 8 seconds, and keeps trying every 8 seconds for a minute.
class ReconnectNotifier extends StateNotifier<ReconnectState> {
  final Ref _ref;
  Timer? _retry;
  DateTime? _startedAt;
  static const _giveUpAfter = Duration(seconds: 60);

  ReconnectNotifier(this._ref) : super(const ReconnectState(ReconnectStatus.idle));

  bool get isActive => state.status == ReconnectStatus.reconnecting;

  void start() {
    if (isActive) return;
    if (_ref.read(savedSeatProvider) == null) {
      fail('There is no game to get back into.');
      return;
    }
    _startedAt = DateTime.now();
    state = const ReconnectState(ReconnectStatus.reconnecting);
    _schedule(Duration.zero);
  }

  /// The last try failed, or the new connection dropped again.
  void onConnectionLost() {
    if (!isActive) return;
    if (DateTime.now().difference(_startedAt!) >= _giveUpAfter) {
      fail("Couldn't reconnect to the game. Check your internet, then use "
          'Rejoin on the home screen.');
      return;
    }
    _schedule(Duration(seconds: 1 << min(max(state.attempt - 1, 0), 3)));
  }

  void _schedule(Duration wait) {
    _retry?.cancel();
    _retry = Timer(wait, _tryOnce);
  }

  void _tryOnce() {
    final seat = _ref.read(savedSeatProvider);
    if (seat == null || !isActive) return;
    state = ReconnectState(ReconnectStatus.reconnecting, attempt: state.attempt + 1);
    final client = _ref.read(gameClientProvider);
    client.connect(roomSocketUri(seat.room));
    client.rejoin(seat.playerId, seat.seatKey);
  }

  void connected() => _settle(const ReconnectState(ReconnectStatus.idle));

  void fail(String message) =>
      _settle(ReconnectState(ReconnectStatus.failed, message: message));

  void replaced(String message) =>
      _settle(ReconnectState(ReconnectStatus.replaced, message: message));

  void stop() => _settle(const ReconnectState(ReconnectStatus.idle));

  void _settle(ReconnectState next) {
    _retry?.cancel();
    _retry = null;
    state = next;
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }
}

final reconnectProvider =
    StateNotifierProvider<ReconnectNotifier, ReconnectState>(ReconnectNotifier.new);

// ─── Lobby state ──────────────────────────────────────────────────────────────

class LobbyState {
  final List<Map<String, dynamic>> players;
  final String hostId;
  final bool canStart;

  const LobbyState({
    this.players = const [],
    this.hostId = '',
    this.canStart = false,
  });
}

class LobbyNotifier extends StateNotifier<LobbyState> {
  LobbyNotifier() : super(const LobbyState());

  void update(LobbyStatePayload p) => state = LobbyState(
        players: p.players,
        hostId: p.hostId,
        canStart: p.canStart,
      );

  void reset() => state = const LobbyState();
}

final lobbyProvider = StateNotifierProvider<LobbyNotifier, LobbyState>(
    (_) => LobbyNotifier());

// ─── Game state ───────────────────────────────────────────────────────────────

class GameStateModel {
  final String phase;
  final String turnPhase;
  final String? currentPlayerId;
  final String? caboCallerId;
  final int turnsRemainingAfterCabo;
  final int drawPileCount;
  final Map<String, dynamic>? topDiscard;
  final Map<String, dynamic>? drawnCard;
  final List<Map<String, dynamic>> players;
  final bool isCaboCalled;
  final List<String> actionLog;
  final List<String> peekConfirmedIds;
  final bool matchWindowOpen;
  final String? pendingGiveCardAttackerId;
  final String? pendingGiveCardTargetId;
  final String? peekHoldActorId;
  final String? peekHoldTargetId;
  final int? peekHoldRow;
  final int? peekHoldCol;
  /// The current player is away: how long until the game plays for them.
  final int? awayActionInMs;
  /// When this state arrived, to count down from.
  final DateTime receivedAt;

  GameStateModel({
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
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  factory GameStateModel.fromPayload(GameStatePayload p) => GameStateModel(
        phase: p.phase,
        turnPhase: p.turnPhase,
        currentPlayerId: p.currentPlayerId,
        caboCallerId: p.caboCallerId,
        turnsRemainingAfterCabo: p.turnsRemainingAfterCabo,
        drawPileCount: p.drawPileCount,
        topDiscard: p.topDiscard?.toJson(),
        drawnCard: p.drawnCard?.toJson(),
        players: p.players,
        isCaboCalled: p.isCaboCalled,
        actionLog: p.actionLog,
        peekConfirmedIds: p.peekConfirmedIds,
        matchWindowOpen: p.matchWindowOpen,
        pendingGiveCardAttackerId: p.pendingGiveCardAttackerId,
        pendingGiveCardTargetId: p.pendingGiveCardTargetId,
        peekHoldActorId: p.peekHoldActorId,
        peekHoldTargetId: p.peekHoldTargetId,
        peekHoldRow: p.peekHoldRow,
        peekHoldCol: p.peekHoldCol,
        awayActionInMs: p.awayActionInMs,
      );

  Map<String, dynamic>? playerById(String id) {
    try {
      return players.firstWhere((p) => p['id'] == id);
    } catch (_) {
      return null;
    }
  }
}

class GameNotifier extends StateNotifier<GameStateModel?> {
  GameNotifier() : super(null);

  void update(GameStatePayload p) => state = GameStateModel.fromPayload(p);
  void clear() => state = null;
}

final gameStateProvider =
    StateNotifierProvider<GameNotifier, GameStateModel?>((_) => GameNotifier());

// ─── Peek reveal ─────────────────────────────────────────────────────────────

/// Stores the last peek reveal so the UI can show a brief card flash.
final peekRevealProvider = StateProvider<PeekRevealPayload?>((_) => null);

// ─── Queen / King picks ───────────────────────────────────────────────────────

/// The last card positions picked with a Queen or King, shown to everyone.
final cardsPickedProvider = StateProvider<CardsPickedPayload?>((_) => null);

// ─── Slap ranking ─────────────────────────────────────────────────────────────

/// Who has tried to slap the current card, fastest first.
final slapRankingProvider = StateProvider<SlapRankingPayload?>((_) => null);

/// The current player switching to slap mid-turn, announced to everyone.
final slapActivatedProvider = StateProvider<SlapActivatedPayload?>((_) => null);

// ─── Table animations ─────────────────────────────────────────────────────────

/// The latest card movements for this screen to play.
final tableAnimationProvider = StateProvider<TableAnimationPayload?>((_) => null);

// ─── Round end scores ─────────────────────────────────────────────────────────

final roundEndProvider = StateProvider<RoundEndPayload?>((_) => null);

/// Snapshot of the game state when phase=roundEnd — preserves revealed cards
/// even after the server resets and sends lobby state.
final roundEndGameStateProvider = StateProvider<GameStateModel?>((_) => null);

/// Clears everything left over from the previous round.
void resetGameSession(WidgetRef ref) {
  ref.read(gameStateProvider.notifier).clear();
  ref.read(roundEndProvider.notifier).state = null;
  ref.read(roundEndGameStateProvider.notifier).state = null;
  ref.read(lobbyProvider.notifier).reset();
  ref.read(localPlayerProvider.notifier).state = null;
  ref.read(peekRevealProvider.notifier).state = null;
  ref.read(cardsPickedProvider.notifier).state = null;
  ref.read(slapRankingProvider.notifier).state = null;
  ref.read(tableAnimationProvider.notifier).state = null;
  ref.read(slapActivatedProvider.notifier).state = null;
}

// ─── Message listener ─────────────────────────────────────────────────────────

/// Attach once at app start to route incoming messages to the right providers.
class MessageRouter {
  final Ref _ref;
  StreamSubscription? _sub;
  /// A lobby seat, saved on the device only once its game starts: a lobby
  /// seat is given up as soon as the player leaves, so there'd be nothing to rejoin.
  SavedSeat? _seatToSave;

  MessageRouter(this._ref);

  void start() {
    _sub?.cancel(); // cancel previous subscription before starting a new one
    final client = _ref.read(gameClientProvider);
    _sub = client.messages.listen(
      _route,
      onError: (_) => _onConnectionLost(),
      cancelOnError: false,
    );
  }

  void _onConnectionLost() {
    final reconnect = _ref.read(reconnectProvider.notifier);
    if (reconnect.isActive) {
      reconnect.onConnectionLost();
      return;
    }
    // Told to stop already, e.g. the seat was opened somewhere else
    if (_ref.read(reconnectProvider).status != ReconnectStatus.idle) return;
    final game = _ref.read(gameStateProvider);
    final inGame = game != null &&
        (game.phase == 'initialPeek' || game.phase == 'playing') &&
        _ref.read(roundEndProvider) == null;
    if (inGame && _ref.read(savedSeatProvider) != null) {
      reconnect.start();
      return;
    }
    // Keep a more specific error from the server if it sent one before closing.
    final error = _ref.read(lobbyErrorProvider.notifier);
    error.state ??= 'Lost connection to the game server.';
  }

  void _route(GameMessage msg) {
    switch (msg.type) {
      case 'welcome':
        final id = msg.payload['playerId'] as String;
        final name = msg.payload['playerName'] as String;
        final room = msg.payload['roomCode'] as String?;
        final seatKey = msg.payload['seatKey'] as String?;
        _ref.read(localPlayerProvider.notifier).state =
            LocalPlayer(id: id, name: name);
        _ref.read(roomCodeProvider.notifier).state = room;
        if (room != null && seatKey != null) {
          final seat = SavedSeat(room: room, playerId: id, seatKey: seatKey, name: name);
          if (msg.payload['rejoined'] == true) {
            _ref.read(savedSeatProvider.notifier).save(seat);
          } else {
            _seatToSave = seat;
          }
        }
        _ref.read(reconnectProvider.notifier).connected();
        _ref.read(gameClientProvider).startClockSync();

      case MsgType.rejoinFailed:
        _ref.read(savedSeatProvider.notifier).clear();
        _ref.read(reconnectProvider.notifier).fail(
            msg.payload['message'] as String? ?? "Couldn't get back into the game.");

      case MsgType.seatTaken:
        _ref.read(reconnectProvider.notifier).replaced(
            msg.payload['message'] as String? ?? 'You opened this game somewhere else.');

      case MsgType.lobbyState:
        final p = LobbyStatePayload(
          players: (msg.payload['players'] as List<dynamic>)
              .map((e) => e as Map<String, dynamic>)
              .toList(),
          hostId: msg.payload['hostId'] as String,
          canStart: msg.payload['canStart'] as bool,
        );
        _ref.read(lobbyProvider.notifier).update(p);

      case MsgType.gameStateUpdate:
        final p = GameStatePayload.fromJson(msg.payload);
        if (_seatToSave != null && (p.phase == 'initialPeek' || p.phase == 'playing')) {
          _ref.read(savedSeatProvider.notifier).save(_seatToSave!);
          _seatToSave = null;
        }
        _ref.read(gameStateProvider.notifier).update(p);
        // Cache the revealed state at round end so UI can show it even after reset
        if (p.phase == 'roundEnd') {
          _ref.read(roundEndGameStateProvider.notifier).state =
              GameStateModel.fromPayload(p);
        }

      case MsgType.peekReveal:
        final p = PeekRevealPayload.fromJson(msg.payload);
        _ref.read(peekRevealProvider.notifier).state = p;

      case MsgType.cardsPicked:
        _ref.read(cardsPickedProvider.notifier).state =
            CardsPickedPayload.fromJson(msg.payload);

      case MsgType.slapRanking:
        _ref.read(slapRankingProvider.notifier).state =
            SlapRankingPayload.fromJson(msg.payload);

      case MsgType.slapActivated:
        _ref.read(slapActivatedProvider.notifier).state =
            SlapActivatedPayload.fromJson(msg.payload);

      case MsgType.tableAnimation:
        _ref.read(tableAnimationProvider.notifier).state =
            TableAnimationPayload.fromJson(msg.payload);

      case MsgType.roundEnd:
        final p = RoundEndPayload.fromJson(msg.payload);
        _ref.read(roundEndProvider.notifier).state = p;
        // The round is over, so there's no seat to come back to
        _ref.read(savedSeatProvider.notifier).clear();

      case MsgType.matchAttemptResult:
        // gameStateUpdate follows immediately; no extra state needed
        break;

      case MsgType.error:
        // Rejoining a table that no longer exists, e.g. after a server restart
        if (_ref.read(reconnectProvider.notifier).isActive) {
          _ref.read(savedSeatProvider.notifier).clear();
          _ref.read(reconnectProvider.notifier).fail(
              msg.payload['message'] as String? ?? "Couldn't get back into the game.");
          return;
        }
        // No seat yet means the join failed, e.g. a wrong code or a full table.
        if (_ref.read(localPlayerProvider) == null) {
          _ref.read(lobbyErrorProvider.notifier).state =
              msg.payload['message'] as String? ?? 'Could not join the game.';
        }
        // TODO: surface in-game errors to UI
    }
  }

  void dispose() => _sub?.cancel();
}

final messageRouterProvider = Provider<MessageRouter>((ref) {
  final router = MessageRouter(ref);
  ref.onDispose(router.dispose);
  return router;
});
