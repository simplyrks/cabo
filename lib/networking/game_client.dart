import 'dart:async';
import 'dart:convert';

import 'package:cabo_shared/models/messages.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Thin WebSocket wrapper. All business logic lives in providers.
class GameClient {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  final _controller = StreamController<GameMessage>.broadcast();

  Stream<GameMessage> get messages => _controller.stream;
  bool get isConnected => _channel != null;

  /// Connects to the server. Closes any existing connection first so
  /// reconnects don't leak channels or duplicate subscriptions.
  ///
  /// Automatically uses `wss://` when the app is served over HTTPS (production)
  /// so the browser doesn't block mixed-content WebSocket connections.
  void connect(String host, int port) {
    // Cancel the old channel listener BEFORE closing it so the onDone
    // callback doesn't fire an error into the broadcast controller.
    _channelSub?.cancel();
    _channelSub = null;
    _channel?.sink.close();
    _channel = null;

    // On HTTPS (Netlify, Vercel, etc.) use wss:// — cloud proxies (Railway,
    // Fly.io) handle TLS termination and forward plain WS internally.
    // On HTTP (local dev) use ws://host:port as before.
    final isSecure = Uri.base.scheme == 'https';
    final uri = isSecure
        ? Uri.parse('wss://$host')   // port 443 by default; proxy handles it
        : Uri.parse('ws://$host:$port');
    _channel = WebSocketChannel.connect(uri);
    _channelSub = _channel!.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          _controller.add(GameMessage.fromJson(json));
        } catch (_) {}
      },
      onDone: () {
        // Server-initiated close — notify listeners
        if (!_controller.isClosed) _controller.addError('disconnected');
      },
      onError: (e) {
        if (!_controller.isClosed) _controller.addError(e);
      },
      cancelOnError: false,
    );
  }

  void send(GameMessage msg) {
    _channel?.sink.add(jsonEncode(msg.toJson()));
  }

  void joinLobby(String name) =>
      send(GameMessage(type: MsgType.joinLobby, payload: {'name': name}));

  void startGame() =>
      send(GameMessage(type: MsgType.startGame, payload: {}));

  void initialPeekDone() =>
      send(GameMessage(type: MsgType.initialPeekDone, payload: {}));

  void callCabo() =>
      send(GameMessage(type: MsgType.callCabo, payload: {}));

  void drawFromPile() =>
      send(GameMessage(type: MsgType.drawFromPile, payload: {}));

  void discardDrawn() =>
      send(GameMessage(type: MsgType.discardDrawn, payload: {}));

  void swapDrawnWithHand(int row, int col) => send(GameMessage(
        type: MsgType.swapDrawnWithHand,
        payload: {'row': row, 'col': col},
      ));

  void skipPower() =>
      send(GameMessage(type: MsgType.skipPower, payload: {}));

  void usePeekOwn(int row, int col) => send(GameMessage(
        type: MsgType.usePower,
        payload: {'action': 'peekOwn', 'row': row, 'col': col},
      ));

  void usePeekOpponent(String targetId, int row, int col) => send(GameMessage(
        type: MsgType.usePower,
        payload: {'action': 'peekOpponent', 'targetId': targetId, 'row': row, 'col': col},
      ));

  void useBlindSwap(
    int myRow, int myCol,
    String targetId, int theirRow, int theirCol,
  ) =>
      send(GameMessage(
        type: MsgType.usePower,
        payload: {
          'action': 'blindSwap',
          'myRow': myRow,
          'myCol': myCol,
          'targetId': targetId,
          'theirRow': theirRow,
          'theirCol': theirCol,
        },
      ));

  void useSmartSwapPeek(String targetId, int row, int col) => send(GameMessage(
        type: MsgType.usePower,
        payload: {'action': 'smartSwapPeek', 'targetId': targetId, 'row': row, 'col': col},
      ));

  void useSmartSwapCommit(
    int? myRow, int? myCol,
    String targetId, int theirRow, int theirCol,
  ) =>
      send(GameMessage(
        type: MsgType.usePower,
        payload: {
          'action': 'smartSwapCommit',
          'myRow': myRow,
          'myCol': myCol,
          'targetId': targetId,
          'theirRow': theirRow,
          'theirCol': theirCol,
        },
      ));

  void matchCard(String targetId, int row, int col) => send(GameMessage(
        type: MsgType.matchCard,
        payload: {'targetId': targetId, 'row': row, 'col': col},
      ));

  void giveCard(int row, int col) => send(GameMessage(
        type: MsgType.giveCard,
        payload: {'row': row, 'col': col},
      ));

  void dispose() {
    _channelSub?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
