import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';

enum CardState { faceDown, faceUp, peeked, selected, empty }

class CardWidget extends StatefulWidget {
  final Map<String, dynamic>? cardJson; // null = empty slot
  final CardState cardState;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final bool showPeekFlash; // briefly shows card then flips

  const CardWidget({
    super.key,
    this.cardJson,
    this.cardState = CardState.faceDown,
    this.onTap,
    this.width = 70,
    this.height = 100,
    this.showPeekFlash = false,
  });

  @override
  State<CardWidget> createState() => _CardWidgetState();
}

class _CardWidgetState extends State<CardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _flip;
  bool _showFront = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flip = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _updateState();
  }

  @override
  void didUpdateWidget(CardWidget old) {
    super.didUpdateWidget(old);
    if (old.cardState != widget.cardState ||
        old.showPeekFlash != widget.showPeekFlash) {
      _updateState();
    }
  }

  void _updateState() {
    if (widget.showPeekFlash) {
      _doFlash();
      return;
    }
    final shouldShowFront = widget.cardState == CardState.faceUp ||
        widget.cardState == CardState.peeked;
    if (shouldShowFront && !_showFront) {
      _showFront = true;
      _ctrl.forward();
    } else if (!shouldShowFront && _showFront) {
      _showFront = false;
      _ctrl.reverse();
    }
  }

  Future<void> _doFlash() async {
    _showFront = true;
    await _ctrl.forward();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      _showFront = false;
      await _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cardState == CardState.empty) {
      return _EmptySlot(width: widget.width, height: widget.height);
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (_, __) {
          final angle = _flip.value * 3.14159;
          final isFront = _flip.value > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            // When face-up: counter-rotate the front face by π so it reads normally
            // after the outer π rotation. Back face needs no extra rotation.
            child: isFront
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(3.14159),
                  child: _FrontFace(
                    cardJson: widget.cardJson,
                    width: widget.width,
                    height: widget.height,
                    isSelected: widget.cardState == CardState.selected,
                  ),
                )
              : _BackFace(
                  width: widget.width,
                  height: widget.height,
                  isSelected: widget.cardState == CardState.selected,
                ),
          );
        },
      ),
    );
  }
}

// ─── Front face ───────────────────────────────────────────────────────────────

class _FrontFace extends StatelessWidget {
  final Map<String, dynamic>? cardJson;
  final double width;
  final double height;
  final bool isSelected;

  const _FrontFace({
    this.cardJson,
    required this.width,
    required this.height,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final suit = cardJson?['suit'] as String? ?? '';
    final rank = cardJson?['rank'] as String? ?? '';
    final isRed = suit == 'hearts' || suit == 'diamonds';
    final color = isRed ? AppColors.red : AppColors.black;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.cardFront,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? AppColors.highlight : Colors.transparent,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
          if (isSelected)
            BoxShadow(
              color: AppColors.highlight.withValues(alpha: 0.5),
              blurRadius: 12,
            ),
        ],
      ),
      child: Stack(
        children: [
          // Top-left corner
          Positioned(
            top: 4,
            left: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _rankLabel(rank),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
                Text(
                  _suitSymbol(suit),
                  style: TextStyle(fontSize: 12, color: color, height: 1.1),
                ),
              ],
            ),
          ),
          // Centre suit symbol
          Center(
            child: Text(
              _suitSymbol(suit),
              style: TextStyle(fontSize: 28, color: color),
            ),
          ),
          // Bottom-right corner (rotated 180°)
          Positioned(
            bottom: 4,
            right: 5,
            child: RotatedBox(
              quarterTurns: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _rankLabel(rank),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                    ),
                  ),
                  Text(
                    _suitSymbol(suit),
                    style: TextStyle(fontSize: 12, color: color, height: 1.1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _rankLabel(String rank) {
    const map = {
      'ace': 'A', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
      'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
      'jack': 'J', 'queen': 'Q', 'king': 'K',
    };
    return map[rank] ?? rank.toUpperCase();
  }

  String _suitSymbol(String suit) {
    const map = {
      'hearts': '♥', 'diamonds': '♦', 'spades': '♠', 'clubs': '♣',
    };
    return map[suit] ?? suit;
  }
}

// ─── Back face ────────────────────────────────────────────────────────────────

class _BackFace extends StatelessWidget {
  final double width;
  final double height;
  final bool isSelected;

  const _BackFace({required this.width, required this.height, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.cardBack,
        borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border.all(color: AppColors.highlight, width: 2.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
          if (isSelected)
            BoxShadow(
              color: AppColors.highlight.withValues(alpha: 0.5),
              blurRadius: 12,
            ),
        ],
      ),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBackPattern, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Center(
            child: Text(
              'C',
              style: TextStyle(
                color: AppColors.cardBackPattern,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty slot ───────────────────────────────────────────────────────────────

class _EmptySlot extends StatelessWidget {
  final double width;
  final double height;

  const _EmptySlot({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
    );
  }
}
