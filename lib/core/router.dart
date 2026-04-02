import 'package:go_router/go_router.dart';
import 'package:cabo/features/home/home_screen.dart';
import 'package:cabo/features/lobby/lobby_screen.dart';
import 'package:cabo/features/game/game_screen.dart';
import 'package:cabo/features/results/results_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/lobby', builder: (_, __) => const LobbyScreen()),
    GoRoute(path: '/game', builder: (_, __) => const GameScreen()),
    GoRoute(path: '/results', builder: (_, __) => const ResultsScreen()),
  ],
);
