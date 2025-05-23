import 'dart:collection';

import 'package:hauberk/src/content.dart';
import 'package:hauberk/src/content/item/drops.dart';
import 'package:hauberk/src/content/item/items.dart';
import 'package:hauberk/src/engine.dart';

/// This script is for tuning and balancing the way stats and equipment affect
/// melee combat.
///
/// Given a hero -- its stats and equipment -- it runs a number of simulated
/// fights against monsters with varying starting health. Over time, it
/// estimates the strongest monster that that hero has a 50% chance of
/// defeating. By comparing that monster's health against the results from
/// different configurations of heroes, you can get an approximate sense of how
/// different configurations compare.
const simulationRounds = 20;

final content = createContent();
final actions = Queue<Action>();
final breeds = <int, Breed>{};

void main(List<String> arguments) {
  for (var strength = 10; strength <= 60; strength += 5) {
    var results = <String, int>{};

    for (var armor in Items.types.all) {
      if (armor.armor == 0) continue;

      for (var weapon in Items.types.all) {
        if (weapon.attack == null || weapon.attack!.range > 0) continue;

        runTrial(strength, 20, 20, [weapon, armor], results);
      }
    }

    print("--- $strength ---");
    var sorted = results.keys.toList();
    sorted.sort((a, b) => results[b]!.compareTo(results[a]!));
    for (var line in sorted.take(5)) {
      print("${results[line].toString().padLeft(4, '0')} = $line");
    }
  }

//  const totalPoints = 80;
//  for (var s = 0; s <= 50; s += 5) {
//    for (var a = 0; a <= 50; a += 5) {
//      var f = totalPoints - s - a;
//      if (f > 50) continue;
//      if (f < 0) continue;
//      if (s + a + f > totalPoints) continue;
//
//      var strength = 10 + s;
//      var agility = 10 + a;
//      var fortitude = 10 + f;
//      runTrial(strength, agility, fortitude, "Scimitar");
//    }
//  }
}

void runTrial(int strength, int agility, int fortitude, List<ItemType> gear,
    [Map<String, int>? results]) {
  var save = content.createHero("blah");
  var game = Game(content, 1, save);

//  save.attributes[Attribute.strength] = strength;
//  save.attributes[Attribute.agility] = agility;
//  save.attributes[Attribute.fortitude] = fortitude;
//  save.attributes[Attribute.intellect] = 20;
//  save.attributes[Attribute.will] = 20;

  for (var item in gear) {
    save.equipment.tryAdd(Item(item, 1));
  }

  var match = findMatch(game, save);

  var stuff = gear.map((type) => type.name).join(" ");
  var line = "str:$strength agi:$agility for:$fortitude $stuff";
  if (results != null) {
    results[line] = match;
  } else {
    print("${match.toString().padLeft(4, '0')} = $line");
  }
}

int findMatch(Game game, HeroSave save) {
  var min = 1;
  var max = 2000;

  while (min < max) {
    var middle = (min + max) ~/ 2;
    var result = runMatch(game, save, middle);
    if (result == 0) {
      return middle;
    } else if (result < 0) {
      max = middle - 1;
    } else {
      min = middle + 1;
    }
  }

  return min;
}

int runMatch(Game game, HeroSave save, int monsterHealth) {
//  print("match $monsterHealth");
  var rounds = 0;
  var wins = 0;
  var losses = 0;

  while (true) {
    rounds++;
    if (fight(game, save, monsterHealth)) {
      wins++;
    } else {
      losses++;
    }

    // TODO: There's certainly a smarter way to estimate how many rounds are
    // needed to know when we can stop based on the previous results.
    var winRate = wins / rounds;
    if (rounds > 10 && winRate > 0.7) {
      return 1;
    } else if (rounds > 10 && winRate < 0.3) {
      return -1;
    } else if (rounds > 400 && winRate > 0.6) {
      return 1;
    } else if (rounds > 400 && winRate < 0.4) {
      return -1;
    } else if (rounds > 800 && winRate > 0.55) {
      return 1;
    } else if (rounds > 800 && winRate < 0.45) {
      return -1;
    } else if (rounds > 2000) {
      return wins - losses;
    }
  }
}

bool fight(Game game, HeroSave save, int monsterHealth) {
  var breed = breeds.putIfAbsent(
      monsterHealth,
      () => Breed("meat", Pronoun.it, "", [Attack(null, "hits", 20)], [],
          dropAllOf([]), SpawnLocation.anywhere, Motility.walk,
          depth: 1,
          meander: 0,
          maxHealth: monsterHealth,
          tracking: 10,
          flags: BreedFlags.fromSet({})));

  var monster = Monster(breed, 0, 0, 1);

  while (true) {
    var action = AttackAction(monster);
    action.bind(game, game.hero);
    action.perform();

    if (monster.health <= 0) {
//      print("versus $monsterHealth -> win");
      return true;
    }

    action = AttackAction(game.hero);
    action.bind(game, monster);
    action.perform();

    if (game.hero.health <= 0) {
//      print("versus $monsterHealth -> lose");
      return false;
    }
  }
}
