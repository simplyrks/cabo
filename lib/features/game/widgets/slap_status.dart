import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';

/// Shows whether this player can slap right now.
class SlapStatus extends StatelessWidget {
  final bool isActive;

  const SlapStatus({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.highlight : AppColors.textSecondary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: isActive ? 0.8 : 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.flash_on : Icons.flash_off,
            size: 20,
            color: color,
          ),
          const SizedBox(height: 2),
          const Text(
            'SLAP',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            isActive ? 'ON' : 'OFF',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
