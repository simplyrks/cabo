import 'dart:math' as math;

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

/// The turn timer's seconds, in a box the size of the slap badge that sits
/// above it: a ring that empties as time runs out, and whose turn it is.
/// Red for the last 3 seconds.
class TurnCountdown extends StatefulWidget {
  final DateTime deadline;
  final Duration total;
  /// "You" or the player's name
  final String who;

  const TurnCountdown({
    super.key,
    required this.deadline,
    required this.total,
    required this.who,
  });

  /// Height of the box, so whatever sits above it can make room.
  static const height = 84.0;

  @override
  State<TurnCountdown> createState() => _TurnCountdownState();
}

class _TurnCountdownState extends State<TurnCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TurnCountdown old) {
    super.didUpdateWidget(old);
    if (old.deadline != widget.deadline || old.total != widget.total) _sync();
  }

  void _sync() {
    final totalMs = math.max(widget.total.inMilliseconds, 1);
    final leftMs = widget.deadline.difference(DateTime.now()).inMilliseconds;
    _ctrl.duration = Duration(milliseconds: totalMs);
    _ctrl.value = 1 - (leftMs / totalMs).clamp(0.0, 1.0);
    if (leftMs > 0) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final left = 1 - _ctrl.value;
        final seconds = (left * widget.total.inMilliseconds / 1000).ceil();
        final color = seconds <= 3 ? AppColors.danger : AppColors.highlight;
        return Container(
          width: 58,
          height: TurnCountdown.height,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: left,
                      strokeWidth: 3,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.15),
                    ),
                    Text(
                      '$seconds',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  widget.who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
