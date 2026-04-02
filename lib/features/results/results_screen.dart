import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo/providers/game_provider.dart';
import 'package:cabo_shared/models/messages.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roundEnd = ref.watch(roundEndProvider);

    if (roundEnd == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.highlight)),
      );
    }

    final localPlayer = ref.read(localPlayerProvider);
    final winner = roundEnd.scores.firstWhere((s) => s.isWinner);
    final iWon = localPlayer?.id == winner.playerId;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  iWon ? '🎉 You Win!' : '${winner.playerName} Wins!',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Round Over',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                ),
                const SizedBox(height: 40),

                // Scoreboard
                ...roundEnd.scores.map((s) => _ScoreRow(
                      score: s,
                      isLocalPlayer: s.playerId == localPlayer?.id,
                    )),

                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: () {
                    ref.read(roundEndProvider.notifier).state = null;
                    ref.read(gameStateProvider.notifier).clear();
                    context.go('/');
                  },
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final PlayerScore score;
  final bool isLocalPlayer;

  const _ScoreRow({required this.score, this.isLocalPlayer = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: score.isWinner
            ? AppColors.gold.withValues(alpha: 0.15)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: score.isWinner
              ? AppColors.gold
              : isLocalPlayer
                  ? AppColors.highlight
                  : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          if (score.isWinner)
            const Icon(Icons.emoji_events, color: AppColors.gold, size: 20)
          else
            const SizedBox(width: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              score.playerName + (isLocalPlayer ? ' (You)' : ''),
              style: TextStyle(
                color: score.isWinner ? AppColors.gold : AppColors.textPrimary,
                fontWeight:
                    score.isWinner ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (score.calledCabo)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'CABO',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.danger,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${score.totalValue} pts',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: score.isWinner ? AppColors.gold : AppColors.textPrimary,
                ),
              ),
              Text(
                '${score.cardCount} cards',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
