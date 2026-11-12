import 'dart:math' as math;

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

  /// Slots drawn invisibly while a card is flying to or from them. They keep
  /// their place, and they can still be tapped.
  final Set<(int, int)> hiddenSlots;

  /// Deals the cards in one after another when this hand first appears.
  final bool dealIn;

  /// When known cards turn face up: [flipStart], then [flipStagger] per card.
  final Duration flipStart;
  final Duration flipStagger;

  /// The game is waiting on this player: their turn timer runs out at
  /// [timerDeadline], shown as a line around their name that shrinks away.
  final DateTime? timerDeadline;
  final Duration? timerTotal;

  const PlayerHand({
    super.key,
    required this.playerJson,
    this.isLocalPlayer = false,
    this.isCurrentTurn = false,
    this.onCardTap,
    this.highlightedSlots = const {},
    this.peekedCardData = const {},
    this.slotKey,
    this.hiddenSlots = const {},
    this.dealIn = false,
    this.flipStart = Duration.zero,
    this.flipStagger = Duration.zero,
    this.timerDeadline,
    this.timerTotal,
  });

  static const _dealGap = Duration(milliseconds: 130);

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

    final index = row * 2 + col;
    Widget card = CardWidget(
      cardJson: cardJson,
      cardState: state,
      onTap: onCardTap != null && !isEmpty ? () => onCardTap!(row, col) : null,
      width: isLocalPlayer ? 64 : 46,
      height: isLocalPlayer ? 92 : 66,
      flipDelay: flipStart + flipStagger * index,
    );
    if (dealIn) card = _DealIn(delay: _dealGap * index, child: card);
    if (hiddenSlots.contains((row, col))) {
      card = Opacity(opacity: 0, child: card);
    }

    return KeyedSubtree(key: slotKey?.call(row, col), child: card);
  }

  @override
  Widget build(BuildContext context) {
    final hand = playerJson['hand'] as List<dynamic>;
    final name = playerJson['name'] as String;
    final isConnected = playerJson['isConnected'] as bool? ?? true;
    final isEliminated = playerJson['isEliminated'] as bool? ?? false;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: isEliminated ? 0.45 : 1.0,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NameTimer(
          deadline: isEliminated ? null : timerDeadline,
          total: timerTotal,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
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

/// A line around the name pill that shrinks back to the top as the turn timer
/// runs down, with the seconds left beside the pill. Red for the last 3 seconds.
class _NameTimer extends StatefulWidget {
  final DateTime? deadline;
  final Duration? total;
  final Widget child;

  const _NameTimer({required this.deadline, required this.total, required this.child});

  @override
  State<_NameTimer> createState() => _NameTimerState();
}

class _NameTimerState extends State<_NameTimer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_NameTimer old) {
    super.didUpdateWidget(old);
    if (old.deadline != widget.deadline) _sync();
  }

  /// Run the line from where it is now down to empty at the deadline.
  void _sync() {
    final deadline = widget.deadline;
    if (deadline == null) {
      _ctrl.stop();
      return;
    }
    final totalMs = (widget.total ?? const Duration(seconds: 10)).inMilliseconds;
    final leftMs = deadline.difference(DateTime.now()).inMilliseconds;
    _ctrl.duration = Duration(milliseconds: math.max(totalMs, 1));
    _ctrl.value = 1 - (leftMs / math.max(totalMs, 1)).clamp(0.0, 1.0);
    if (leftMs > 0) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deadline == null) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (_, child) {
        final left = 1 - _ctrl.value;
        final totalMs = (widget.total ?? const Duration(seconds: 10)).inMilliseconds;
        final seconds = (left * totalMs / 1000).ceil();
        final color = seconds <= 3 ? AppColors.danger : AppColors.highlight;
        // The seconds hang off to the right, so the name stays centred over the cards
        return Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              foregroundPainter: _PillOutlinePainter(fraction: left, color: color),
              child: child,
            ),
            Positioned(
              right: -32,
              top: 0,
              bottom: 0,
              width: 28,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                '${seconds}s',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The part of a pill's outline still left, starting and ending at the top middle.
class _PillOutlinePainter extends CustomPainter {
  final double fraction;
  final Color color;

  _PillOutlinePainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = math.min(h / 2, w / 2);
    final radius = Radius.circular(r);
    final outline = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w - r, h), radius: radius)
      ..lineTo(r, h)
      ..arcToPoint(Offset(r, 0), radius: radius)
      ..close();
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color.withValues(alpha: 0.18);
    canvas.drawPath(outline, track);
    if (fraction <= 0) return;
    final metric = outline.computeMetrics().first;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawPath(metric.extractPath(0, metric.length * fraction), line);
  }

  @override
  bool shouldRepaint(_PillOutlinePainter old) =>
      old.fraction != fraction || old.color != color;
}

/// One card sliding in as it's dealt.
class _DealIn extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _DealIn({required this.delay, required this.child});

  @override
  State<_DealIn> createState() => _DealInState();
}

class _DealInState extends State<_DealIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
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
      child: widget.child,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, -220 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
