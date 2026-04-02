import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo/providers/game_provider.dart';

class StatusBox extends StatelessWidget {
  final GameStateModel gs;
  final String localPlayerId;

  const StatusBox({super.key, required this.gs, required this.localPlayerId});

  @override
  Widget build(BuildContext context) {
    final isMyTurn = gs.currentPlayerId == localPlayerId;
    final currentName = _nameOf(gs.currentPlayerId);
    final turnLabel = isMyTurn ? 'Your turn' : "$currentName's turn";
    final waitingLabel = _waitingLabel(isMyTurn);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1F0F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMyTurn
              ? AppColors.highlight.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isMyTurn
                ? AppColors.highlight.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Turn header ──
          _TurnHeader(
            turnLabel: turnLabel,
            waitingLabel: waitingLabel,
            isMyTurn: isMyTurn,
            isCaboCalled: gs.isCaboCalled,
            turnsRemaining: gs.turnsRemainingAfterCabo,
            caboCallerName: _nameOf(gs.caboCallerId),
          ),

          if (gs.actionLog.isNotEmpty) ...[
            const Divider(color: Colors.white10, height: 1),
            // ── Commentary log ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MATCH LOG',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...gs.actionLog.take(4).toList().asMap().entries.map((e) {
                    final isLatest = e.key == 0;
                    return _LogEntry(text: e.value, isLatest: isLatest);
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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

  String _waitingLabel(bool isMyTurn) {
    if (gs.phase == 'initialPeek') return 'Memorise your bottom 2 cards!';
    switch (gs.turnPhase) {
      case 'waitingForDraw':
        return isMyTurn
            ? 'Draw a card or call CABO'
            : 'Waiting for ${_nameOf(gs.currentPlayerId)} to draw...';
      case 'cardDrawn':
        return isMyTurn
            ? 'Swap with your hand, or discard to use power'
            : '${_nameOf(gs.currentPlayerId)} is deciding what to do...';
      case 'usingPower':
        return isMyTurn
            ? 'Use your card\'s special power'
            : '${_nameOf(gs.currentPlayerId)} is using a power...';
      case 'swappingWithHand':
        return isMyTurn
            ? 'Choose a card in your hand to swap'
            : '${_nameOf(gs.currentPlayerId)} is swapping...';
      default:
        return '';
    }
  }
}

// ─── Turn header ─────────────────────────────────────────────────────────────

class _TurnHeader extends StatelessWidget {
  final String turnLabel;
  final String waitingLabel;
  final bool isMyTurn;
  final bool isCaboCalled;
  final int turnsRemaining;
  final String caboCallerName;

  const _TurnHeader({
    required this.turnLabel,
    required this.waitingLabel,
    required this.isMyTurn,
    required this.isCaboCalled,
    required this.turnsRemaining,
    required this.caboCallerName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          // Pulsing dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMyTurn ? AppColors.highlight : AppColors.textSecondary,
              boxShadow: isMyTurn
                  ? [BoxShadow(color: AppColors.highlight.withValues(alpha: 0.7), blurRadius: 6)]
                  : [],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  turnLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isMyTurn ? AppColors.highlight : AppColors.textPrimary,
                  ),
                ),
                if (waitingLabel.isNotEmpty)
                  Text(
                    waitingLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (isCaboCalled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  const Text(
                    'CABO!',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    '$turnsRemaining left',
                    style: const TextStyle(color: AppColors.danger, fontSize: 9),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Log entry ────────────────────────────────────────────────────────────────

class _LogEntry extends StatelessWidget {
  final String text;
  final bool isLatest;

  const _LogEntry({required this.text, required this.isLatest});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: isLatest ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 5, right: 6),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLatest ? AppColors.highlight : AppColors.textSecondary,
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: isLatest ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: isLatest ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
