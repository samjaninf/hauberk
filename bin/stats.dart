import 'package:hauberk/src/engine.dart';

void main() {
  var strength = Strength();
  var agility = Agility();
  var fortitude = Fortitude();
  var intellect = Intellect();
  var will = Will();

  print("     Strength   Agility     Fortitude Intellect           Will");
  print("     ┌───────┐ ┌──────────┐ ┌───────┐ ┌─────────────────┐ ┌───┐");
  print("Lvl  Toss Heft Dodge Strike Health    MaxFocus SpellFocus Focus");

  for (var i = 1; i <= Stat.max; i++) {
    strength.update(i, (_) {});
    agility.update(i, (_) {});
    fortitude.update(i, (_) {});
    intellect.update(i, (_) {});
    will.update(i, (_) {});

    print(" ${i.toString().padLeft(2)}:"
        " ${strength.tossRangeScale.toStringAsFixed(1).padLeft(3)}"
        " ${strength.heftScale(20).toStringAsFixed(2).padLeft(5)}"
        " ${agility.dodgeBonus.toString().padLeft(5)}"
        " ${agility.strikeBonus.toString().padLeft(6)}"
        " ${fortitude.maxHealth.toString().padLeft(6)}"
        " ${intellect.maxFocus.toString().padLeft(11)}"
        " ${intellect.spellFocusScale(10).toStringAsFixed(2).padLeft(10)}"
        " ${will.damageFocusScale.toStringAsFixed(0).padLeft(5)}");
  }
}
