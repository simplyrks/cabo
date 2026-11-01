import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';

class SlapRankRow {
  final int rank;
  final String name;
  final int gapMs;
  final String result;

  const SlapRankRow({
    required this.rank,
    required this.name,
    required this.gapMs,
    required this.result,
  });
}

/// Who tried to slap the current card, fastest first.
class SlapRanking extends StatelessWidget {
  final int triedCount;
  final List<SlapRankRow> rows;

  const SlapRanking({super.key, required this.triedCount, required this.rows});

  static const _ordinals = ['1st', '2nd', '3rd', '4th'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.highlight.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$triedCount tried to slap',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          for (final row in rows) _buildRow(row),
        ],
      ),
    );
  }

  Widget _buildRow(SlapRankRow row) {
    final (icon, color) = switch (row.result) {
      'right' => (Icons.check_circle, AppColors.highlight),
      'wrong' => (Icons.cancel, AppColors.danger),
      'late' => (Icons.remove_circle_outline, AppColors.textSecondary),
      _ => (Icons.hourglass_empty, AppColors.textSecondary),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(
            _ordinals[(row.rank - 1).clamp(0, _ordinals.length - 1)],
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: row.rank == 1 ? AppColors.gold : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
            ),
          ),
          if (row.rank > 1)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Text(
                '+${row.gapMs}ms',
                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(width: 3),
          Icon(icon, size: 12, color: color),
        ],
      ),
    );
  }
}
