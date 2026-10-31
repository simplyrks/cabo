import 'dart:convert';
import 'dart:io';

import 'package:cabo_shared/models/messages.dart';
import 'game_room.dart';

/// Routes each connection to a room by URL path:
///   ws  /new    creates a room with the next free code and joins it
///   ws  /g1     joins an existing room
///   GET /rooms  lists the rooms that have players, as JSON
class CaboServer {
  static const maxRooms = 100;

  final int port;
  final Map<String, GameRoom> _rooms = {};

  CaboServer({this.port = 8080});

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Server] Listening on ws://0.0.0.0:$port');

    await for (final request in server) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        _handleUpgrade(request);
      } else {
        _handleHttp(request);
      }
    }
  }

  Future<void> _handleUpgrade(HttpRequest request) async {
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (e) {
      // One bad handshake must not take down every running game.
      print('[Server] Upgrade failed: $e');
      return;
    }
    // Pings detect dead sockets, so abandoned rooms still get cleaned up.
    ws.pingInterval = const Duration(seconds: 30);

    final path = request.uri.path.replaceAll('/', '').toLowerCase();
    if (path == 'new') {
      final room = _createRoom();
      if (room == null) {
        _reject(ws, 'All game tables are busy. Please try again soon.');
      } else {
        room.addConnection(ws);
      }
      return;
    }

    final room = _rooms[path];
    if (room == null) {
      _reject(ws, 'No game found with that code.');
    } else {
      room.addConnection(ws);
    }
  }

  void _handleHttp(HttpRequest request) {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    if (request.uri.path == '/rooms') {
      final rooms = _rooms.values.where((r) => r.playerCount > 0).toList()
        ..sort((a, b) => _roomNumber(a.code).compareTo(_roomNumber(b.code)));
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(rooms.map((r) => r.toSummary()).toList()))
        ..close();
      return;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..write('Cabo server running')
      ..close();
  }

  /// Uses the lowest free number so codes stay short enough to read out.
  GameRoom? _createRoom() {
    if (_rooms.length >= maxRooms) return null;
    var n = 1;
    while (_rooms.containsKey('g$n')) {
      n++;
    }
    final room = GameRoom(code: 'g$n', onEmpty: _removeRoom);
    _rooms[room.code] = room;
    print('[Server] Created room ${room.code} (${_rooms.length} active)');
    return room;
  }

  void _removeRoom(GameRoom room) {
    _rooms.remove(room.code);
    print('[Server] Removed room ${room.code} (${_rooms.length} active)');
  }

  int _roomNumber(String code) => int.parse(code.substring(1));

  void _reject(WebSocket ws, String message) {
    ws.add(jsonEncode(
        GameMessage(type: MsgType.error, payload: {'message': message}).toJson()));
    ws.close();
  }
}
