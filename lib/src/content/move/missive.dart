import '../../engine.dart';
import '../action/missive.dart';

class MissiveMove extends Move {
  final Missive _missive;

  MissiveMove(this._missive, num rate) : super(rate);

  @override
  num get experience => 0.0;

  @override
  bool shouldUse(Game game, Monster monster) {
    var target = game.hero.pos;
    var distance = (target - monster.pos).kingLength;

    // Don't insult when in melee distance.
    if (distance <= 1) return false;

    // Don't insult someone it can't see.
    return game.stage.canView(monster, target);
  }

  @override
  Action onGetAction(Game game, Monster monster) =>
      MissiveAction(game.hero, _missive);

  @override
  String toString() => "$_missive rate: $rate";
}
