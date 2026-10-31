import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'package:cabo_shared/models/messages.dart';

/// Countdown ring for the slap window. The server decides when the window
/// closes; this only shows the time left.
class SlapTimer extends StatefulWidget {
  final int remainingMs;

  const SlapTimer({super.key, required this.remainingMs});

  @override
  State<SlapTimer> createState() => _SlapTimerState();
}

class _SlapTimerState extends State<SlapTimer> {
  late DateTime _endsAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncDeadline();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void didUpdateWidget(SlapTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remainingMs != widget.remainingMs) _syncDeadline();
  }

  void _syncDeadline() {
    _endsAt = DateTime.now().add(Duration(milliseconds: widget.remainingMs));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = _endsAt.difference(DateTime.now()).inMilliseconds.clamp(0, 1 << 31);
    final seconds = (ms / 1000).ceil();
    final isEnding = seconds <= 2;
    final color = isEnding ? AppColors.danger : AppColors.highlight;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: (ms / (slapWindowSeconds * 1000)).clamp(0.0, 1.0),
                  strokeWidth: 4,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
                Center(
                  child: Text(
                    '$seconds',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SLAP',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
