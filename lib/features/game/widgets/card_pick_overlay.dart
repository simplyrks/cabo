import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';

/// Shows everyone which card positions a Queen or King picked: a ring around
/// each one, then two face-down cards crossing between them. It plays the same
/// whether or not cards were really swapped, and draws only card backs on top
/// of the table, so it can't reveal a card or stop anyone from tapping.
class CardPickOverlay extends StatefulWidget {
  /// Where each picked slot is right now. Read on every frame, because the
  /// table can shift while this plays. A slot that can't be found returns null.
  final List<Rect? Function()> slots;
  final VoidCallback onDone;

  const CardPickOverlay({super.key, required this.slots, required this.onDone});

  @override
  State<CardPickOverlay> createState() => _CardPickOverlayState();
}

class _CardPickOverlayState extends State<CardPickOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final rects = widget.slots
              .map((slot) => slot())
              .whereType<Rect>()
              .toList();
          // Pulse the rings, and cross the cards in the middle of the animation
          final pulse = 0.5 + 0.5 * (1 - (((_ctrl.value * 6) % 2) - 1).abs());
          final isCrossing = rects.length == 2 &&
              _ctrl.value > _crossStart &&
              _ctrl.value < _crossEnd;
          final cross = Curves.easeInOut.transform(
            ((_ctrl.value - _crossStart) / (_crossEnd - _crossStart))
                .clamp(0.0, 1.0),
          );

          return Stack(
            children: [
              for (final rect in rects)
                Positioned.fromRect(
                  rect: rect.inflate(4),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.gold, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.7 * pulse),
                          blurRadius: 14 * pulse,
                          spreadRadius: 2 * pulse,
                        ),
                      ],
                    ),
                  ),
                ),
              if (isCrossing) ...[
                _movingCard(Rect.lerp(rects[0], rects[1], cross)!),
                _movingCard(Rect.lerp(rects[1], rects[0], cross)!),
              ],
            ],
          );
        },
      ),
    );
  }

  static const _crossStart = 0.25;
  static const _crossEnd = 0.8;

  Widget _movingCard(Rect rect) {
    return Positioned.fromRect(
      rect: rect,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBack,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(2, 3),
            ),
          ],
        ),
      ),
    );
  }
}
