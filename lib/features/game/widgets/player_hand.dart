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

  /// Lets the game screen find where a card slot is drawn.
  final GlobalKey Function(int row, int col)? slotKey;

  const PlayerHand({
    super.key,
    required this.playerJson,
    this.isLocalPlayer = false,
    this.isCurrentTurn = false,
    this.onCardTap,
    this.highlightedSlots = const {},
    this.peekedCardData = const {},
    this.slotKey,
  });

  Widget _buildPenaltySection(List<dynamic> hand) {
    final penaltyCards = <(int, int, dynamic)>[];
    for (int r = 2; r < hand.length; r++) {
      final rowData = hand[r] as List<dynamic>;
      for (int c = 0; c < rowData.length; c++) {
        if (rowData[c] != null) penaltyCards.add((r, c, rowData[c]));
      }
    }
    if (penaltyCards.isEmpty) return const SizedBox.shrink();

    // Split into columns of 2 (matching the 2 base rows)
    final penaltyCols = <List<(int, int, dynamic)>>[];
    for (int i = 0; i < penaltyCards.length; i += 2) {
      penaltyCols.add(penaltyCards.sublist(i, (i + 2).clamp(0, penaltyCards.length)));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: penaltyCols.map((col) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: col.map((entry) {
            final (r, c, cardData) = entry;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildCard(r, c, cardData),
            );
          }).toList(),
        ),
      )).toList(),
    );
  }

  Widget _buildCard(int row, int col, dynamic cardData) {
    final isEmpty = cardData == null;
    final isHidden = cardData is Map && cardData['hidden'] == true;
    final isSelected = highlightedSlots.contains((row, col));
    final peeked = peekedCardData[(row, col)];
    final isPeeked = peeked != null;

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
      state = CardState.faceUp;
    } else {
      state = CardState.faceDown;
    }

    return KeyedSubtree(
      key: slotKey?.call(row, col),
      child: CardWidget(
        cardJson: cardJson,
        cardState: state,
        onTap: onCardTap != null && !isEmpty ? () => onCardTap!(row, col) : null,
        width: isLocalPlayer ? 64 : 46,
        height: isLocalPlayer ? 92 : 66,
      ),
    );
  }

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
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Base 2x2 grid (rows 0–1)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(hand.length.clamp(0, 2), (row) {
                final rowData = hand[row] as List<dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(2, (col) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildCard(row, col, rowData[col]),
                      );
                    }),
                  ),
                );
              }),
            ),
            // Penalty cards (rows 2+): fill column-by-column, 2 per column
            if (hand.length > 2) _buildPenaltySection(hand),
          ],
        ),
      ],
      ),
    );
  }
}
