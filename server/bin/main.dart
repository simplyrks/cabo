import 'dart:io';
import 'package:cabo_server/server.dart';

void main(List<String> args) async {
  // Cloud platforms (Railway, Fly.io, Render) inject PORT via environment.
  // Fall back to CLI arg, then 8080 for local dev.
  final envPort = int.tryParse(Platform.environment['PORT'] ?? '');
  final argPort = args.isNotEmpty ? int.tryParse(args[0]) : null;
  final port = envPort ?? argPort ?? 8080;
  final server = CaboServer(port: port);
  await server.start();
}
