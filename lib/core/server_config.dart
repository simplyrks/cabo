/// The game server. For local development, override it with:
///   flutter run -d chrome --dart-define=CABO_SERVER_URL=http://localhost:8080
const _serverUrl = String.fromEnvironment(
  'CABO_SERVER_URL',
  defaultValue: 'https://cabo-production.up.railway.app',
);

/// Room path that asks the server to create a new table.
const newRoomPath = 'new';

Uri roomSocketUri(String room) {
  final base = Uri.parse(_serverUrl);
  return base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '/$room',
  );
}

Uri get roomsUri => Uri.parse('$_serverUrl/rooms');
