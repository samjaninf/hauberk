import 'package:piecemeal/piecemeal.dart';

import '../../engine.dart';
import '../action/polymorph.dart';

/// Splits a part of a monster off into a new monster.
///
/// For example, a skeleton can amputate into a decapitated skeleton and a
/// skull.
class AmputateMove extends Move {
  @override
  num get experience => _body.breed.maxHealth * 0.5;

  /// The breed the remaining body turns into.
  final BreedRef _body;

  /// The spawned monster representing the body part.
  final BreedRef _part;

  final String _message;

  AmputateMove(this._body, this._part, this._message) : super(1.0);

  /// Doesn't spontaneously amputate.
  @override
  bool shouldUse(Game game, Monster monster) => false;

  @override
  bool shouldUseOnDamage(Monster monster, int damage) {
    // Doing more damage increases the odds.
    var odds = damage / monster.maxHealth;
    if (rng.float(2.0) <= odds) return true;

    // Getting closer to death increases the odds.
    odds = monster.health / monster.maxHealth;
    if (rng.float(2.0) <= odds) return true;

    return false;
  }

  @override
  Action onGetAction(Game game, Monster monster) =>
      AmputateAction(_body.breed, _part.breed, _message);

  @override
  String toString() => "Amputate ${_body.breed.name} + ${_part.breed.name}";
}
