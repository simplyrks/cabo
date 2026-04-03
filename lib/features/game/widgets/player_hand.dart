import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'card_widget.dart';

/// Renders a 2x2 hand grid for one player.
class PlayerHand extends StatelessWidget {
  final Map<String, dynamic> playerJson;
  final bool isLocalPlayer;
  final bool isCurrentTurn;
  final void Function(int row, int col)? onCardTap;
  final Set<(int, int)> highlightedSlots;

  /// Slots whose actual card data we know from a peek reveal.
  /// Key = (row, col), value = full card JSON {suit, rank}.
  final Map<(int, int), Map<String, dynamic>> peekedCardData;

  const PlayerHand({
    super.key,
    required this.playerJson,
    this.isLocalPlayer = false,
    this.isCurrentTurn = false,
    this.onCardTap,
    this.highlightedSlots = const {},
    this.peekedCardData = const {},
  });

  @override
  Widget build(BuildContext context) {
    final hand = playerJson['hand'] as List<dynamic>;
    final name = playerJson['name'] as String;
    final isConnected = playerJson['isConnected'] as bool? ?? true;
    final isEliminated = playerJson['isEliminated'] as bool? ?? false;

    return Opacity(
      opacity: isEliminated ? 0.45 : 1.0,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isEliminated
                ? AppColors.danger.withValues(alpha: 0.15)
                : isCurrentTurn
                    ? AppColors.highlight.withValues(alpha: 0.25)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: isEliminated
                ? Border.all(color: AppColors.danger, width: 1)
                : isCurrentTurn
                    ? Border.all(color: AppColors.highlight, width: 1)
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEliminated)
                const Icon(Icons.cancel, size: 12, color: AppColors.danger),
              if (isEliminated) const SizedBox(width: 4),
              if (!isEliminated && !isConnected)
                const Icon(Icons.wifi_off, size: 12, color: AppColors.danger),
              if (!isEliminated && !isConnected) const SizedBox(width: 4),
              Text(
                isEliminated
                    ? '${isLocalPlayer ? 'You' : name} — OUT'
                    : isLocalPlayer ? '$name (You)' : name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isEliminated
                      ? AppColors.danger
                      : isCurrentTurn
                          ? AppColors.highlight
                          : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(hand.length, (row) {
            final rowData = hand[row] as List<dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(2, (col) {
                  final cardData = rowData[col];
                  final isEmpty = cardData == null;
                  final isHidden =
                      cardData is Map && cardData['hidden'] == true;
                  final isSelected = highlightedSlots.contains((row, col));
                  final peeked = peekedCardData[(row, col)];
                  final isPeeked = peeked != null;

                  // Prefer peeked card data, then actual card data
                  Map<String, dynamic>? cardJson;
                  if (isPeeked) {
                    cardJson = peeked;
                  } else if (!isEmpty && !isHidden) {
                    cardJson = cardData as Map<String, dynamic>;
                  }

                  CardState state;
                  if (isEmpty) {
                    state = CardState.empty;
                  } else if (isSelected) {
                    state = CardState.selected;
                  } else if (isPeeked) {
                    state = CardState.faceUp; // always show peeked cards
                  } else if (cardJson != null) {
                    state = CardState.faceDown;
                  } else {
                    state = CardState.faceDown;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: CardWidget(
                      cardJson: cardJson,
                      cardState: state,
                      onTap: onCardTap != null && !isEmpty
                          ? () => onCardTap!(row, col)
                          : null,
                      width: isLocalPlayer ? 72 : 56,
                      height: isLocalPlayer ? 104 : 82,
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ],
      ),
    );
  }
}
