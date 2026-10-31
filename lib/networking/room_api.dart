import 'dart:convert';

import 'package:cabo/core/server_config.dart';
import 'package:http/http.dart' as http;

class RoomInfo {
  final String code;
  final int players;
  final int maxPlayers;
  final String status; // open | full | playing

  const RoomInfo({
    required this.code,
    required this.players,
    required this.maxPlayers,
    required this.status,
  });

  bool get isJoinable => status == 'open';

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
        code: json['code'] as String,
        players: json['players'] as int,
        maxPlayers: json['maxPlayers'] as int,
        status: json['status'] as String,
      );
}

Future<List<RoomInfo>> fetchRooms() async {
  final response =
      await http.get(roomsUri).timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    throw Exception('Could not load games: ${response.statusCode}');
  }
  return (jsonDecode(response.body) as List<dynamic>)
      .map((e) => RoomInfo.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Turns what a player typed ("G3", " g3 ", "3") into a room path, or null if
/// it isn't a valid code.
String? normalizeRoomCode(String input) {
  final code = input.trim().toLowerCase();
  if (RegExp(r'^\d+$').hasMatch(code)) return 'g$code';
  return RegExp(r'^g\d+$').hasMatch(code) ? code : null;
}
