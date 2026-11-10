import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The seat this device holds in a game, kept so the player can get back in
/// after a dropped connection, a closed tab or a restarted phone.
class SavedSeat {
  final String room;
  final String playerId;
  final String seatKey;
  final String name;

  const SavedSeat({
    required this.room,
    required this.playerId,
    required this.seatKey,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
        'room': room,
        'playerId': playerId,
        'seatKey': seatKey,
        'name': name,
      };

  static SavedSeat? fromJson(Map<String, dynamic> json) {
    final room = json['room'], id = json['playerId'], key = json['seatKey'];
    if (room is! String || id is! String || key is! String) return null;
    return SavedSeat(
      room: room,
      playerId: id,
      seatKey: key,
      name: json['name'] as String? ?? '',
    );
  }
}

/// Reads and writes the saved seat in the device's storage (browser storage on
/// the web). Storage can be missing, e.g. in a private window, so every call
/// quietly does nothing rather than failing.
class SeatStore {
  static const _key = 'cabo.seat';
  final SharedPreferences? _prefs;

  const SeatStore(this._prefs);

  static Future<SeatStore> open() async {
    try {
      return SeatStore(await SharedPreferences.getInstance());
    } catch (_) {
      return const SeatStore(null);
    }
  }

  SavedSeat? load() {
    try {
      final raw = _prefs?.getString(_key);
      if (raw == null) return null;
      return SavedSeat.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void save(SavedSeat seat) {
    try {
      _prefs?.setString(_key, jsonEncode(seat.toJson()));
    } catch (_) {}
  }

  void clear() {
    try {
      _prefs?.remove(_key);
    } catch (_) {}
  }
}
