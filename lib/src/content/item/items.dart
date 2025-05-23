import '../../engine.dart';
import 'armor.dart';
import 'builder.dart';
import 'magic.dart';
import 'other.dart';
import 'weapons.dart';

/// Static class containing all of the [ItemType]s.
class Items {
  static final types = ResourceSet<ItemType>();

  static void initialize() {
    types.defineTags("item");

    litter();
    treasure();
    gems();
    pelts();
    food();
    lightSources();
    potions();
    scrolls();
    spellBooks();
    rings();
    // TODO: Amulets.
    // TODO: Wands.
    weapons();
    helms();
    bodyArmor();
    cloaks();
    gloves();
    shields();
    boots();

    // CharCode.latinSmallLetterIWithDiaeresis // ring
    // CharCode.latinSmallLetterIWithCircumflex // wand

    finishItem();
  }
}
