import 'package:hauberk/src/content.dart';

/// Shows how proficiency affects skills for the various classes.
void main(List<String> arguments) {
  var content = createContent();

  for (var heroClass in content.classes) {
    print(heroClass.name);
    for (var skill in content.skills) {
      var line = "";
      if (skill is Discipline) {
        var buffer = StringBuffer();
        for (var level = 1; level <= skill.maxLevel; level++) {
          var training = skill.trainingNeeded(heroClass, level);
          buffer.write(training.toString().padLeft(6));
          line = buffer.toString();
        }
      } else if (skill is Spell) {
        if (heroClass.proficiency(skill) != 0.0) {
          var complexity = skill.complexity(heroClass);
          line = complexity.toString();
        } else {
          line = "N/A";
        }
      }

      print("  ${skill.name.padRight(20)} $line");
    }
  }
}
