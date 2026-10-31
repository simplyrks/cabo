import 'dart:async';

import 'package:cabo/core/server_config.dart';
import 'package:cabo/networking/game_client.dart';
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

  const GameStateModel({
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
  });

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
}

// ─── Message listener ─────────────────────────────────────────────────────────

/// Attach once at app start to route incoming messages to the right providers.
class MessageRouter {
  final Ref _ref;
  StreamSubscription? _sub;

  MessageRouter(this._ref);

  void start() {
    _sub?.cancel(); // cancel previous subscription before starting a new one
    final client = _ref.read(gameClientProvider);
    _sub = client.messages.listen(
      _route,
      // Keep a more specific error from the server if it sent one before closing.
      onError: (_) {
        final error = _ref.read(lobbyErrorProvider.notifier);
        error.state ??= 'Lost connection to the game server.';
      },
      cancelOnError: false,
    );
  }

  void _route(GameMessage msg) {
    switch (msg.type) {
      case 'welcome':
        final id = msg.payload['playerId'] as String;
        final name = msg.payload['playerName'] as String;
        _ref.read(localPlayerProvider.notifier).state =
            LocalPlayer(id: id, name: name);
        _ref.read(roomCodeProvider.notifier).state =
            msg.payload['roomCode'] as String?;

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

      case MsgType.roundEnd:
        final p = RoundEndPayload.fromJson(msg.payload);
        _ref.read(roundEndProvider.notifier).state = p;

      case MsgType.matchAttemptResult:
        // gameStateUpdate follows immediately; no extra state needed
        break;

      case MsgType.error:
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
