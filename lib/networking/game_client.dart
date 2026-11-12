import 'dart:async';
import 'dart:convert';

import 'package:cabo_shared/models/messages.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'server_clock.dart';

/// Thin WebSocket wrapper. All business logic lives in providers.
class GameClient {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  final _controller = StreamController<GameMessage>.broadcast();
  final clock = ServerClock();
  Timer? _clockTimer;

  Stream<GameMessage> get messages => _controller.stream;
  bool get isConnected => _channel != null;

  /// Connects to the server. Closes any existing connection first so
  /// reconnects don't leak channels or duplicate subscriptions.
  void connect(Uri uri) {
    disconnect();
    _channel = WebSocketChannel.connect(uri);
    // A failed connect also ends the stream below, which is where it's handled
    _channel!.ready.catchError((_) {});
    _channelSub = _channel!.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final msg = GameMessage.fromJson(json);
          if (msg.type == MsgType.clockPong) {
            clock.addSample(
              msg.payload['sentAt'] as int,
              msg.payload['serverAt'] as int,
            );
            return;
          }
          _controller.add(msg);
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

  void disconnect() {
    _clockTimer?.cancel();
    _clockTimer = null;
    clock.reset();
    // Cancel the old channel listener BEFORE closing it so the onDone
    // callback doesn't fire an error into the broadcast controller.
    _channelSub?.cancel();
    _channelSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  /// A burst of measurements right away, then one every few seconds so the
  /// gap to the server clock stays accurate.
  void startClockSync() {
    _clockTimer?.cancel();
    var burst = 5;
    _clockTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      _sendClockPing();
      if (--burst == 0) {
        timer.cancel();
        _clockTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _sendClockPing(),
        );
      }
    });
  }

  void _sendClockPing() => send(GameMessage(
        type: MsgType.clockPing,
        payload: {'sentAt': clock.localNowUs},
      ));

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

  /// [slapFirst]: everyone gets a 3-2-1 and a slap at the card before its power.
  void discardDrawn({bool slapFirst = false}) => send(GameMessage(
        type: MsgType.discardDrawn,
        payload: {if (slapFirst) 'slapFirst': true},
      ));

  void leaveGame() =>
      send(GameMessage(type: MsgType.leaveGame, payload: {}));

  void startPower() =>
      send(GameMessage(type: MsgType.startPower, payload: {}));

  void rejoin(String playerId, String seatKey) => send(GameMessage(
        type: MsgType.rejoin,
        payload: {'playerId': playerId, 'seatKey': seatKey},
      ));

  void activateSlap() =>
      send(GameMessage(type: MsgType.activateSlap, payload: {}));

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

  /// [seenRank] is the top discard on screen when the player tapped, and
  /// [tappedAtUs] is when their finger touched the card, on this device's clock.
  void matchCard(
    String targetId,
    int row,
    int col,
    String? seenRank,
    int tappedAtUs,
  ) =>
      send(GameMessage(
        type: MsgType.matchCard,
        payload: {
          'targetId': targetId,
          'row': row,
          'col': col,
          'seenRank': seenRank,
          'tapAt': clock.toServerUs(tappedAtUs),
        },
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
