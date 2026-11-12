import 'package:flutter/material.dart';
import 'package:cabo/core/theme/app_theme.dart';

/// Opens the rules over whatever screen is showing.
Future<void> showRules(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) => const _RulesDialog(),
  );
}

/// A small "?" button that opens the rules.
class RulesButton extends StatelessWidget {
  /// Matches the small buttons in the game's status bar.
  final bool compact;

  const RulesButton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: 'How to play',
        child: GestureDetector(
          onTap: () => showRules(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.help_outline,
                size: 14, color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: 'How to play',
      onPressed: () => showRules(context),
      icon: const Icon(Icons.help_outline, color: AppColors.textSecondary),
    );
  }
}

/// Puts the rules button in the top-right corner of a screen.
class WithRulesButton extends StatelessWidget {
  final Widget child;

  const WithRulesButton({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(top: 4, right: 4, child: RulesButton()),
      ],
    );
  }
}

class _RulesDialog extends StatelessWidget {
  const _RulesDialog();

  static const _tabs = ['Basics', 'Powers', 'Slapping', 'Winning'];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: 520, maxHeight: size.height * 0.85),
        child: DefaultTabController(
          length: _tabs.length,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book,
                        color: AppColors.gold, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'How to play',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: false,
                labelColor: AppColors.gold,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.gold,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                dividerColor: Colors.white.withValues(alpha: 0.08),
                tabs: [for (final t in _tabs) Tab(text: t, height: 38)],
              ),
              const Flexible(
                child: TabBarView(
                  children: [
                    _BasicsTab(),
                    _PowersTab(),
                    _SlappingTab(),
                    _WinningTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tabs ─────────────────────────────────────────────────────────────────────

class _BasicsTab extends StatelessWidget {
  const _BasicsTab();

  @override
  Widget build(BuildContext context) {
    return const _TabBody(children: [
      _Lead('Finish the round with the lowest total points in your hand. '
          'Memory and quick hands win.'),
      _Heading('Setting up'),
      _Bullet('Everyone gets 4 cards face down, in two rows of two.'),
      _Bullet(
          'At the start you see your bottom two cards once. Remember them — '
          'after that, your cards stay face down.'),
      _Heading('Card values'),
      _CardValues(),
      _Heading('Your turn'),
      _Step(
          1,
          'Draw a card from the deck. Only you can see it. Everyone else sees '
          'a glowing card next to the deck.'),
      _Step(2, 'Then choose one:'),
      _Bullet(
          'Swap — tap one of your cards. It goes face up onto the discard pile and '
          'the drawn card takes its place. Everyone sees which spot you swapped.',
          indent: true),
      _Bullet(
          'Discard — put the drawn card on the discard pile. If it has a power '
          '(7 to King), you can use it now or skip it.',
          indent: true),
      _Bullet(
          'Or, instead of drawing, call CABO at the start of your turn (see Winning).'),
      _Heading('Turn timer'),
      _Bullet(
          'The line around the name of the player whose turn it is shrinks as '
          'their time runs out.'),
      _Bullet(
          'You have 10 seconds to draw. If time runs out, your turn is skipped.'),
      _Bullet(
          'You then have 15 seconds to swap or discard. If time runs out, the card '
          'is discarded for you, and you can still use its power.'),
      _Bullet(
          'Using a power gets another 15 seconds, or 30 for a Queen or King swap. '
          'If time runs out, the power is skipped.'),
      _Heading('Good to know'),
      _Bullet(
          'When the deck runs out, the discard pile is shuffled into a new deck.'),
      _Bullet(
          'Tap the clock button at the top of the game to see everything that has '
          'happened so far.'),
    ]);
  }
}

class _PowersTab extends StatelessWidget {
  const _PowersTab();

  @override
  Widget build(BuildContext context) {
    return const _TabBody(children: [
      _Lead(
          'A power works only when you draw the card from the deck and discard it. '
          'Cards you swap out of your hand never use their power.'),
      _Power(
          '7  8',
          'Peek at your own card',
          'Look at one of your face-down cards. The game holds for 4 seconds, and '
              'everyone sees which card you\'re looking at — but not what it is.'),
      _Power(
          '9  10',
          'Peek at an opponent\'s card',
          'Look at one card in someone else\'s hand. Everyone sees which card, '
              'and only you see its value.'),
      _Power('J', 'Skip', 'The next player loses their turn.'),
      _Power(
          'Q',
          'Blind swap',
          'Pick one of your cards and one of an opponent\'s, and swap them without '
              'looking at either.'),
      _Power(
          'K ♥♦',
          'Look, then swap',
          'Red King: look at an opponent\'s card first, then decide whether to swap '
              'it with one of yours.'),
      _Power('K ♠♣', 'No power',
          'The Black King has no power, but it\'s worth 0 — the best card to keep.'),
      _Heading('Everyone sees the positions'),
      _Bullet(
          'For every peek and swap, all players see which positions were picked, '
          'so you can tell when a card you remember has moved.'),
    ]);
  }
}

class _SlappingTab extends StatelessWidget {
  const _SlappingTab();

  @override
  Widget build(BuildContext context) {
    return const _TabBody(children: [
      _Lead(
          'When a card lands on the discard pile, anyone can slap a card that has the '
          'same rank — a 5 on a 5, a Queen on a Queen. It\'s not your turn? '
          'You can still slap.'),
      _Heading('How it works'),
      _Bullet(
          'Tap any face-down card — yours or an opponent\'s — that you think matches '
          'the top of the discard pile.'),
      _Bullet(
          'Each player gets one try per card. The fastest correct slap wins; '
          'the order is decided by when your finger touched the screen.'),
      _Bullet('A green dot on the discard pile means slapping is open.'),
      _Heading('What happens'),
      _Outcome(Icons.check_circle, AppColors.highlight, 'Right, your own card',
          'It leaves your hand for the discard pile. One card fewer!'),
      _Outcome(
          Icons.check_circle,
          AppColors.highlight,
          'Right, an opponent\'s card',
          'It leaves their hand, and then you give them one of your cards — you pick which.'),
      _Outcome(Icons.cancel, AppColors.danger, 'Wrong',
          'Everyone sees the card, it goes back, and you take a penalty card from the deck.'),
      _Outcome(Icons.remove_circle_outline, AppColors.textSecondary,
          'Empty spot', 'Nothing happens, and no penalty.'),
      _Heading('Slapping on your own turn'),
      _Bullet(
          'While you hold a drawn card, tapping your card swaps it. To slap instead, '
          'flip the SWAP | SLAP switch to SLAP — everyone is told.'),
      _Bullet(
          'If slapping isn\'t open, a 3-2-1 countdown plays on every screen and '
          'then slapping opens for everyone.'),
      _Bullet(
          'After one slap the switch goes back to SWAP, and you finish your turn.'),
      _Heading('Too many penalties'),
      _Bullet(
          'You can hold up to 8 cards. A wrong slap when you already have 8 '
          'eliminates you from the round.'),
    ]);
  }
}

class _WinningTab extends StatelessWidget {
  const _WinningTab();

  @override
  Widget build(BuildContext context) {
    return const _TabBody(children: [
      _Heading('Calling CABO'),
      _Bullet(
          'At the start of your turn, before drawing, you can call CABO if you '
          'think you\'re winning.'),
      _Bullet('The round ends right away and every card is turned face up.'),
      _Heading('Other ways the round ends'),
      _Bullet(
          'Only one player is left because everyone else has been eliminated.'),
      _Heading('Who wins'),
      _Step(1, 'The player with the lowest total points wins.'),
      _Step(2, 'If points are tied, the player with fewer cards wins.'),
      _Step(3, 'Eliminated players always finish last.'),
      _Heading('Tips'),
      _Bullet('Low cards to keep: Black Kings (0), Aces (1), 2s.'),
      _Bullet(
          'Get rid of Red Kings (13), Queens (12) and Jacks (11) when you can.'),
      _Bullet(
          'Watch the glowing spots — a swapped card you remembered isn\'t the same card any more.'),
      _Bullet(
          'Slapping gets rid of a card and all its points, but a wrong guess adds a card.'),
    ]);
  }
}

// ─── Building blocks ──────────────────────────────────────────────────────────

class _TabBody extends StatelessWidget {
  final List<Widget> children;

  const _TabBody({required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: children,
    );
  }
}

class _Lead extends StatelessWidget {
  final String text;

  const _Lead(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 13.5, height: 1.4, color: AppColors.textPrimary),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppColors.gold,
        ),
      ),
    );
  }
}

const _bodyStyle =
    TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textPrimary);

class _Bullet extends StatelessWidget {
  final String text;
  final bool indent;

  const _Bullet(this.text, {this.indent = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 28 : 0, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 10),
            child: CircleAvatar(
                radius: 2.5, backgroundColor: AppColors.textSecondary),
          ),
          Expanded(child: Text(text, style: _bodyStyle)),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;

  const _Step(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 8, top: 1),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.gold, shape: BoxShape.circle),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(child: Text(text, style: _bodyStyle)),
        ],
      ),
    );
  }
}

class _Power extends StatelessWidget {
  final String cards;
  final String title;
  final String text;

  const _Power(this.cards, this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.cardFront,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              cards,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: cards.contains('♥') ? AppColors.red : AppColors.black,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  const _Outcome(this.icon, this.color, this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '$title. ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: text),
              ]),
              style: _bodyStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardValues extends StatelessWidget {
  const _CardValues();

  static const _values = [
    ('A', '1', false),
    ('2–10', 'face', false),
    ('J', '11', false),
    ('Q', '12', false),
    ('K ♥♦', '13', true),
    ('K ♠♣', '0', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (card, value, red) in _values)
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardFront,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  card,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: red ? AppColors.red : AppColors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value == 'face' ? 'face value' : '$value pts',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
