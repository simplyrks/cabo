import 'package:cabo_server/game_engine.dart';
import 'package:cabo_shared/models/card_model.dart';
import 'package:test/test.dart';

void main() {
  /// Two players with set hands; empty spots are null.
  GameEngine table(List<List<CaboCard?>> ravi, List<List<CaboCard?>> cutu) {
    final engine = GameEngine();
    final r = engine.addPlayer('ravi', 'Ravi');
    final c = engine.addPlayer('cutu', 'cutu');
    r.hand
      ..clear()
      ..addAll(ravi);
    c.hand
      ..clear()
      ..addAll(cutu);
    return engine;
  }

  const three = CaboCard(suit: Suit.spades, rank: Rank.three);
  const ace = CaboCard(suit: Suit.hearts, rank: Rank.ace);
  const blackKing = CaboCard(suit: Suit.clubs, rank: Rank.king);
  const two = CaboCard(suit: Suit.clubs, rank: Rank.two);

  test('lowest points wins even with more cards', () {
    // The round from the screenshot: Ravi 1 card / 3 pts, cutu 2 cards / 1 pt
    final engine = table(
      [[null, null], [three, null]],
      [[null, ace], [null, blackKing]],
    );
    final winner = engine.computeScores().singleWhere((s) => s.isWinner);
    expect(winner.playerId, 'cutu');
  });

  test('tied points: fewer cards wins', () {
    final engine = table(
      [[null, null], [two, null]],
      [[null, ace], [ace, null]],
    );
    final winner = engine.computeScores().singleWhere((s) => s.isWinner);
    expect(winner.playerId, 'ravi');
  });

  test('eliminated players finish last whatever their points', () {
    final engine = table(
      [[null, null], [blackKing, null]],
      [[three, three], [three, three]],
    );
    engine.state.getPlayer('ravi')!.isEliminated = true;
    final scores = engine.computeScores();
    expect(scores.first.playerId, 'cutu');
    expect(scores.last.playerId, 'ravi');
  });
}
