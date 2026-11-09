import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';
import 'card_widget.dart';

/// Everything here plays on top of the table and ignores touches, so the game
/// and slapping carry on underneath. Destinations are read on every frame,
/// because a hand can change shape while a card is on its way to it.

const _cardWidth = 64.0;
const _cardHeight = 92.0;

Widget _cardFace(Map<String, dynamic>? card) => SizedBox(
      width: _cardWidth,
      height: _cardHeight,
      child: CardWidget(
        cardJson: card,
        cardState: card != null ? CardState.faceUp : CardState.faceDown,
        animateFlip: false,
        width: _cardWidth,
        height: _cardHeight,
      ),
    );

/// A card scaled to fit any size on the table.
Widget _fitted(Widget card) => FittedBox(fit: BoxFit.fill, child: card);

/// A gold glow around a card; [strength] runs from 0 (faint) to 1 (bright).
Widget _goldGlow(Widget child, double strength) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.35 + 0.5 * strength),
            blurRadius: 8 + 12 * strength,
            spreadRadius: 1 + 3 * strength,
          ),
        ],
      ),
      child: child,
    );

/// A drawn card waiting beside the deck, face down and gently pulsing, so
/// everyone can see a card is in play before it's swapped in or discarded.
class HeldCardGlow extends StatefulWidget {
  const HeldCardGlow({super.key});

  @override
  State<HeldCardGlow> createState() => _HeldCardGlowState();
}

class _HeldCardGlowState extends State<HeldCardGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => _goldGlow(child!, _ctrl.value),
      child: _fitted(_cardFace(null)),
    );
  }
}

/// One card travelling from one place to another.
class FlyingCard extends StatefulWidget {
  final Rect from;
  final Rect? Function() to;

  /// The face, or null to travel face down.
  final Map<String, dynamic>? card;
  final Duration delay;
  final VoidCallback onLanded;

  /// Stays visible at its starting point during the delay, instead of hidden.
  final bool visibleWhileWaiting;

  const FlyingCard({
    super.key,
    required this.from,
    required this.to,
    this.card,
    this.delay = Duration.zero,
    required this.onLanded,
    this.visibleWhileWaiting = false,
  });

  static const flightTime = Duration(milliseconds: 380);

  @override
  State<FlyingCard> createState() => _FlyingCardState();
}

class _FlyingCardState extends State<FlyingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Rect _lastTo = widget.from;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: FlyingCard.flightTime)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onLanded();
      });
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
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
        if (_ctrl.isCompleted) return const SizedBox.shrink();
        if (_ctrl.value == 0) {
          if (!widget.visibleWhileWaiting) return const SizedBox.shrink();
          // Still the card held beside the deck, glowing until it moves
          return Positioned.fromRect(
            rect: widget.from,
            child: _goldGlow(_fitted(_cardFace(widget.card)), 0.7),
          );
        }
        _lastTo = widget.to() ?? _lastTo;
        final t = Curves.easeInOutCubic.transform(_ctrl.value);
        // A little lift in the middle of the flight
        final lift = 1 + 0.18 * math.sin(math.pi * t);
        final rect = Rect.lerp(widget.from, _lastTo, t)!;
        return Positioned.fromRect(
          rect: Rect.fromCenter(
            center: rect.center,
            width: rect.width * lift,
            height: rect.height * lift,
          ),
          child: _fitted(_cardFace(widget.card)),
        );
      },
    );
  }
}

/// A slapped card, brought up front and turned over for everyone. The right
/// card then goes to the discard pile; any other goes back where it came from.
class SlapRevealCard extends StatefulWidget {
  final Rect from;
  final Rect Function() spot;
  final Rect? Function() goesTo;
  final Map<String, dynamic> card;
  final String result;
  final String name;
  final VoidCallback onDone;

  /// How long the card stays up front, counted from the moment of the slap.
  static const showTime = Duration(milliseconds: 1500);
  static const _total = Duration(milliseconds: 1900);

  const SlapRevealCard({
    super.key,
    required this.from,
    required this.spot,
    required this.goesTo,
    required this.card,
    required this.result,
    required this.name,
    required this.onDone,
  });

  @override
  State<SlapRevealCard> createState() => _SlapRevealCardState();
}

class _SlapRevealCardState extends State<SlapRevealCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Rect? _lastGoesTo;

  bool get _isRight => widget.result == 'right';

  (String, Color) get _label => switch (widget.result) {
        'right' => ('RIGHT!', AppColors.highlight),
        'wrong' => ('WRONG', AppColors.danger),
        _ => ('TOO LATE', AppColors.textSecondary),
      };

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: SlapRevealCard._total)
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

  double _phase(double ms, double startMs, double endMs) =>
      ((ms - startMs) / (endMs - startMs)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final ms = _ctrl.value * SlapRevealCard._total.inMilliseconds;
        final spot = widget.spot();
        _lastGoesTo = widget.goesTo() ?? _lastGoesTo;
        final leave = Curves.easeInOutCubic.transform(_phase(ms, 1500, 1900));
        final rect = leave > 0
            ? Rect.lerp(spot, _lastGoesTo ?? spot, leave)!
            : Rect.lerp(
                widget.from,
                spot,
                Curves.easeOutCubic.transform(_phase(ms, 0, 250)),
              )!;

        // Turn face up on the way in. Only a card going back to a hand turns over again.
        var turn = _phase(ms, 200, 450);
        if (!_isRight) turn -= _phase(ms, 1500, 1680);
        final angle = turn * math.pi;
        final showFace = turn > 0.5;

        // A wrong card shakes; a right one pops.
        var shake = 0.0;
        var scale = 1.0;
        if (widget.result == 'wrong' && ms > 450 && ms < 800) {
          shake = 6 * math.sin((ms - 450) / 350 * 6 * math.pi);
        }
        if (_isRight && ms > 450 && ms < 800) {
          scale = 1 + 0.12 * math.sin((ms - 450) / 350 * math.pi);
        }

        final (label, color) = _label;
        final captionOpacity = _phase(ms, 300, 450) * (1 - _phase(ms, 1400, 1500));

        return Positioned.fromRect(
          rect: rect,
          child: Transform.translate(
            offset: Offset(shake, 0),
            child: Transform.scale(
              scale: scale,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(showFace ? angle - math.pi : angle),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.75 * captionOpacity),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: _fitted(_cardFace(showFace ? widget.card : null)),
                      ),
                    ),
                  ),
                  if (captionOpacity > 0) ...[
                    _caption(top: -19, opacity: captionOpacity, text: widget.name, color: AppColors.textPrimary),
                    _caption(bottom: -19, opacity: captionOpacity, text: label, color: color),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _caption({
    double? top,
    double? bottom,
    required double opacity,
    required String text,
    required Color color,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: -8,
      right: -8,
      child: Opacity(
        opacity: opacity,
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: color,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

/// A card lifted out of its place, face down and glowing, so everyone can see
/// which position is about to move.
class LiftedCard extends StatefulWidget {
  final Rect? Function() slot;
  final Duration duration;
  final VoidCallback onDone;

  const LiftedCard({
    super.key,
    required this.slot,
    required this.duration,
    required this.onDone,
  });

  @override
  State<LiftedCard> createState() => _LiftedCardState();
}

class _LiftedCardState extends State<LiftedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Rect? _lastSlot;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        _lastSlot = widget.slot() ?? _lastSlot;
        final rect = _lastSlot;
        if (rect == null) return const SizedBox.shrink();
        final rise = Curves.easeOutBack.transform((_ctrl.value / 0.45).clamp(0.0, 1.0));
        return Positioned.fromRect(
          rect: rect,
          child: Transform.translate(
            offset: Offset(0, -10 * rise),
            child: Transform.scale(
              scale: 1 + 0.14 * rise,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.gold, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.85),
                      blurRadius: 18,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: _fitted(_cardFace(null)),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A pulsing ring and an eye on the card someone is looking at, without showing it.
class SlotPulse extends StatefulWidget {
  final Rect? Function() slot;

  /// Off for the player reading the card, because the glow tints what's inside the ring.
  final bool glow;

  const SlotPulse({super.key, required this.slot, this.glow = true});

  @override
  State<SlotPulse> createState() => _SlotPulseState();
}

class _SlotPulseState extends State<SlotPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
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
        final rect = widget.slot();
        if (rect == null) return const SizedBox.shrink();
        return Positioned.fromRect(
          rect: rect.inflate(5),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppColors.gold, width: 4),
                    boxShadow: widget.glow
                        ? [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.4 + 0.5 * _ctrl.value),
                              blurRadius: 8 + 14 * _ctrl.value,
                              spreadRadius: 1 + 3 * _ctrl.value,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              Positioned(
                top: -9,
                right: -9,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.visibility, size: 14, color: Colors.black87),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "SKIPPED" stamped over the hand of a player the Jack has skipped.
class SkippedBadge extends StatefulWidget {
  final Rect? Function() hand;
  final VoidCallback onDone;

  const SkippedBadge({super.key, required this.hand, required this.onDone});

  @override
  State<SkippedBadge> createState() => _SkippedBadgeState();
}

class _SkippedBadgeState extends State<SkippedBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final rect = widget.hand();
        if (rect == null) return const SizedBox.shrink();
        final t = _ctrl.value;
        final scale = Curves.elasticOut.transform((t / 0.4).clamp(0.0, 1.0));
        final opacity = 1 - ((t - 0.75) / 0.25).clamp(0.0, 1.0);
        return Positioned.fromRect(
          rect: rect,
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: -0.14,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                    ),
                    child: const Text(
                      'SKIPPED',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "CABO!" bursting over the screen as the round ends.
class CaboSplash extends StatefulWidget {
  final String name;

  const CaboSplash({super.key, required this.name});

  @override
  State<CaboSplash> createState() => _CaboSplashState();
}

class _CaboSplashState extends State<CaboSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
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
          final t = _ctrl.value;
          if (t >= 1) return const SizedBox.shrink();
          final scale = Curves.elasticOut.transform((t / 0.45).clamp(0.0, 1.0));
          final opacity = 1 - ((t - 0.75) / 0.25).clamp(0.0, 1.0);
          return Container(
            color: Colors.black.withValues(alpha: 0.55 * opacity),
            alignment: Alignment.center,
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'CABO!',
                      style: TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        color: AppColors.danger,
                      ),
                    ),
                    Text(
                      widget.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
