import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo/providers/game_provider.dart';
import 'package:cabo/features/rules/rules_sheet.dart';

/// Compact single-line status bar. Tap the history icon to see the full log.
class StatusBox extends StatelessWidget {
  final GameStateModel gs;
  final String localPlayerId;
  final VoidCallback onHistoryTap;
  final VoidCallback onExitTap;

  const StatusBox({
    super.key,
    required this.gs,
    required this.localPlayerId,
    required this.onHistoryTap,
    required this.onExitTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMyTurn = gs.currentPlayerId == localPlayerId;
    final phase = _phaseLabel(isMyTurn);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1F0F),
        border: Border(
          bottom: BorderSide(
            color: isMyTurn
                ? AppColors.highlight.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.07),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Turn indicator dot
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMyTurn ? AppColors.highlight : AppColors.textSecondary,
              boxShadow: isMyTurn
                  ? [BoxShadow(
                      color: AppColors.highlight.withValues(alpha: 0.7),
                      blurRadius: 5,
                    )]
                  : null,
            ),
          ),
          const SizedBox(width: 8),

          // Turn + phase label
          Expanded(
            child: Text(
              phase,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isMyTurn ? AppColors.highlight : AppColors.textPrimary,
              ),
            ),
          ),

          // CABO badge
          if (gs.isCaboCalled) ...[
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
              ),
              child: Text(
                'CABO! ${gs.turnsRemainingAfterCabo}↓',
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],

          // Rules
          const RulesButton(compact: true),
          const SizedBox(width: 6),

          // History icon button
          GestureDetector(
            onTap: onHistoryTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 3),
                  Text(
                    '${gs.actionLog.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Leave the game
          Tooltip(
            message: 'Leave game',
            child: GestureDetector(
              onTap: onExitTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.logout, size: 14, color: AppColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(bool isMyTurn) {
    final currentName = _nameOf(gs.currentPlayerId);
    final prefix = isMyTurn ? 'Your turn' : "$currentName's turn";

    final suffix = switch (gs.turnPhase) {
      'waitingForDraw' => isMyTurn ? '— Draw a card or call CABO' : '— waiting to draw',
      'cardDrawn'      => isMyTurn ? '— Swap with hand or discard' : '— deciding...',
      'usingPower'     => isMyTurn ? '— Using power' : '— using power...',
      _                => '',
    };

    return '$prefix $suffix'.trim();
  }

  String _nameOf(String? id) {
    if (id == null) return '';
    try {
      final p = gs.players.firstWhere((p) => p['id'] == id);
      final name = p['name'] as String;
      return id == localPlayerId ? 'You' : name;
    } catch (_) {
      return '';
    }
  }
}

/// Full history log — shown as a modal bottom sheet.
class HistorySheet extends StatelessWidget {
  final List<String> log;
  const HistorySheet({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1F0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'MATCH HISTORY',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Flexible(
            child: log.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No actions yet.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: log.length,
                    separatorBuilder: (_, __) => const Divider(
                      color: Colors.white10,
                      height: 1,
                    ),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 5, right: 8),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == 0
                                  ? AppColors.highlight
                                  : AppColors.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              log[i],
                              style: TextStyle(
                                fontSize: 12,
                                color: i == 0
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
