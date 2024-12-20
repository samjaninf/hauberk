import 'dart:math' as math;

import 'package:malison/malison.dart';
import 'package:malison/malison_web.dart';

import '../../engine.dart';
import '../../hues.dart';
import '../draw.dart';
import '../game_screen.dart';
import '../input.dart';
import 'item_renderer.dart';
import 'put_dialog.dart';
import 'sell_dialog.dart';

// TODO: Home screen is confusing when empty.
// TODO: The home (get) and shop (buy) screens handle selecting a count
// completely differently from the ItemDialogs (put, sell, etc.). Different
// code and different user interface. Unify those.

/// A screen for a place in the town where the hero can interact with items:
/// a shop, their home, or the crucible.
abstract class TownScreen extends Screen<Input> {
  final GameScreen _gameScreen;

  // TODO: Move this and _transfer() to an intermediate class instead of making
  // this nullable?
  /// The place items are being transferred to or `null` if this is just a
  /// view.
  ItemCollection? get _destination => null;

  /// Whether the shift key is currently pressed.
  bool _shiftDown = false;

  /// Whether this screen is on top.
  // TODO: Maintaining this manually is hacky. Maybe have malison expose it?
  bool _isActive = true;

  /// The item currently being inspected or `null` if none.
  Item? _inspected;

  String? _error;

  ItemCollection get _items;

  HeroSave get _save => _gameScreen.game.hero.save;

  String get _headerText;

  Map<String, String> get _helpKeys;

  TownScreen._(this._gameScreen);

  @override
  bool get isTransparent => true;

  factory TownScreen.home(GameScreen gameScreen) => _HomeScreen(gameScreen);

  factory TownScreen.shop(GameScreen gameScreen, Inventory shop) =>
      _ShopScreen(gameScreen, shop);

  factory TownScreen.crucible(GameScreen gameScreen) =>
      _CrucibleScreen(gameScreen);

  bool get _canSelectAny => false;
  bool get _showPrices => false;

  bool _canSelect(Item item) {
    if (_shiftDown) return true;

    return canSelect(item);
  }

  bool canSelect(Item item) => true;

  @override
  bool handleInput(Input input) {
    _error = null;

    if (input == Input.cancel) {
      ui.pop();
      return true;
    }

    return false;
  }

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    _error = null;

    if (keyCode == KeyCode.shift) {
      _shiftDown = true;
      dirty();
      return true;
    }

    if (alt) return false;

    if (_shiftDown && keyCode == KeyCode.escape) {
      _inspected = null;
      dirty();
      return true;
    }

    if (keyCode >= KeyCode.a && keyCode <= KeyCode.z) {
      var index = keyCode - KeyCode.a;
      if (index >= _items.slots.length) return false;
      var item = _items.slots.elementAt(index);
      if (item == null) return false;

      if (_shiftDown) {
        _inspected = item;
        dirty();
      } else {
        if (!_canSelectAny || !canSelect(item)) return false;

        // Prompt the user for a count if the item is a stack.
        if (item.count > 1) {
          _isActive = false;
          ui.push(_CountScreen(_gameScreen, this as _ItemVerbScreen, item));
          return true;
        }

        if (_transfer(item, 1)) {
          ui.pop();
          return true;
        }
      }
    }

    return false;
  }

  @override
  bool keyUp(int keyCode, {required bool shift, required bool alt}) {
    if (keyCode == KeyCode.shift) {
      _shiftDown = false;
      dirty();
      return true;
    }

    return false;
  }

  @override
  void activate(Screen<Input> popped, Object? result) {
    _isActive = true;
    _inspected = null;

    if (popped is _CountScreen && result != null) {
      if (_transfer(popped._item, result as int)) {
        ui.pop();
      }
    }
  }

  @override
  void render(Terminal terminal) {
    // Don't show the help if another dialog (like buy or sell) is on top with
    // its own help.
    if (_isActive) {
      if (_shiftDown) {
        Draw.helpKeys(
            terminal,
            {
              "A-Z": "Inspect item",
              if (_inspected != null) "`": "Hide inspector"
            },
            "Inspect which item?");
      } else {
        Draw.helpKeys(terminal, _helpKeys, _headerText);
      }
    }

    renderItems(terminal, _items,
        left: _gameScreen.stagePanel.bounds.x,
        top: _gameScreen.stagePanel.bounds.y,
        width: math.min(
            preferredItemListWidth, _gameScreen.stagePanel.bounds.width),
        itemSlotCount: _items.length,
        save: _gameScreen.game.hero.save,
        capitalize: _shiftDown,
        showPrices: _showPrices,
        inspectedItem: _isActive ? _inspected : null,
        inspectorOnRight: true,
        canSelectAny: _shiftDown || _canSelectAny,
        canSelect: _canSelect,
        getPrice: _itemPrice);

    if (_error != null) {
      terminal.writeAt(0, 32, _error!, red);
    }
  }

  /// The default count to move when transferring a stack from [_items].
  int _initialCount(Item item) => item.count;

  /// The maximum number of items in the stack of [item] that can be
  /// transferred from [_items].
  int _maxCount(Item item) => item.count;

  /// By default, don't show the price.
  int? _itemPrice(Item item) => null;

  bool _transfer(Item item, int count) {
    var destination = _destination!;
    if (!destination.canAdd(item)) {
      _error = "Not enough room for ${item.clone(count)}.";
      dirty();
      return false;
    }

    if (count == item.count) {
      // Moving the entire stack.
      destination.tryAdd(item);
      _items.remove(item);
    } else {
      // Splitting the stack.
      destination.tryAdd(item.splitStack(count));
      _items.countChanged();
    }

    _afterTransfer(item, count);

    return true;
  }

  /// Called after [count] of [item] has been transferred out of [_items].
  void _afterTransfer(Item item, int count) {}
}

/// Base class for town screens where the player is performing an action.
abstract class _ItemVerbScreen extends TownScreen {
  String get _verb;

  _ItemVerbScreen(super.gameScreen) : super._();
}

class _HomeScreen extends TownScreen {
  @override
  ItemCollection get _items => _save.home;

  @override
  String get _headerText => "Welcome home!";

  @override
  Map<String, String> get _helpKeys => {
        "G": "Get item",
        "P": "Put item",
        "Shift": "Inspect item",
        "Tab": "Use crucible",
        "`": "Leave"
      };

  _HomeScreen(super.gameScreen) : super._();

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    if (super.keyDown(keyCode, shift: shift, alt: alt)) return true;

    if (shift || alt) return false;

    switch (keyCode) {
      case KeyCode.g:
        var screen = _GetFromHomeScreen(_gameScreen);
        screen._inspected = _inspected;
        _isActive = false;
        ui.push(screen);
        return true;

      case KeyCode.p:
        _isActive = false;
        ui.push(PutHomeDialog(_gameScreen));
        return true;

      case KeyCode.tab:
        ui.goTo(TownScreen.crucible(_gameScreen));
        return true;
    }

    return false;
  }
}

/// Screen to get items from the hero's home or crucible.
abstract class _GetScreen extends _ItemVerbScreen {
  @override
  String get _headerText => "Get which item?";

  @override
  String get _verb => "Get";

  @override
  Map<String, String> get _helpKeys =>
      {"A-Z": "Select item", "Shift": "Inspect item", "`": "Cancel"};

  @override
  ItemCollection get _destination => _gameScreen.game.hero.inventory;

  _GetScreen(super.gameScreen);

  @override
  bool get _canSelectAny => true;

  @override
  bool canSelect(Item item) => true;

  @override
  void _afterTransfer(Item item, int count) {
    _gameScreen.game.hero.pickUp(_gameScreen.game, item);
  }
}

/// Screen to get items from the hero's home.
class _GetFromHomeScreen extends _GetScreen {
  @override
  ItemCollection get _items => _gameScreen.game.hero.save.home;

  _GetFromHomeScreen(super.gameScreen);

  @override
  void _afterTransfer(Item item, int count) {
    _gameScreen.game.log
        .message("You take ${item.clone(count)} from your home.");
    super._afterTransfer(item, count);
  }
}

/// Screen to get items from the hero's crucible.
class _GetFromCrucibleScreen extends _GetScreen {
  final void Function() _onTransfer;

  @override
  ItemCollection get _items => _gameScreen.game.hero.save.crucible;

  _GetFromCrucibleScreen(super.gameScreen, this._onTransfer);

  @override
  void _afterTransfer(Item item, int count) {
    _gameScreen.game.log
        .message("You remove ${item.clone(count)} from the crucible.");
    super._afterTransfer(item, count);

    _onTransfer();
  }
}

class _CrucibleScreen extends TownScreen {
  /// If the crucible contains a complete recipe, this will be it. Otherwise,
  /// this will be `null`.
  Recipe? _completeRecipe;

  @override
  ItemCollection get _items => _save.crucible;

  @override
  String get _headerText => _completeRecipe != null
      ? "Ready to forge item!"
      : "Place items to complete a recipe.";

  @override
  Map<String, String> get _helpKeys => {
        "G": "Get item",
        "P": "Put item",
        "Shift": "Inspect item",
        if (_completeRecipe != null) "Space": "Forge item",
        "Tab": "Back to home",
        "`": "Leave"
      };

  _CrucibleScreen(super.gameScreen) : super._() {
    _refreshRecipe();
  }

  @override
  void render(Terminal terminal) {
    super.render(terminal);

    // TODO: This UI isn't great.
    var width =
        math.min(preferredItemListWidth, _gameScreen.stagePanel.bounds.width);
    terminal = terminal.rect(_gameScreen.stagePanel.bounds.x + 4,
        _gameScreen.stagePanel.bounds.y + _items.length + 1, width - 8, 3);

    Draw.box(terminal, 0, 0, terminal.width, terminal.height);
    terminal.writeAt(0, 0, "┬", darkCoolGray);
    terminal.writeAt(terminal.width - 1, 0, "┬", darkCoolGray);

    if (_completeRecipe case var recipe?) {
      terminal.writeAt(1, 1, "Forge a ${recipe.produces}", UIHue.primary);
    } else if (_items.isEmpty) {
      terminal.writeAt(1, 1, "Add ingredients to crucible", UIHue.disabled);
    } else {
      terminal.writeAt(1, 1, "Not a complete recipe", UIHue.disabled);
    }
  }

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    if (super.keyDown(keyCode, shift: shift, alt: alt)) return true;

    if (shift || alt) return false;

    switch (keyCode) {
      case KeyCode.g:
        var screen = _GetFromCrucibleScreen(_gameScreen, _refreshRecipe);
        screen._inspected = _inspected;
        _isActive = false;
        ui.push(screen);
        return true;

      case KeyCode.p:
        _isActive = false;
        ui.push(PutCrucibleDialog(_gameScreen, _refreshRecipe));
        return true;

      case KeyCode.space when _completeRecipe != null:
        _save.crucible.clear();
        _completeRecipe!.result.dropItem(_save.lore, 1, _save.crucible.tryAdd);
        _refreshRecipe();
        dirty();
        return true;

      case KeyCode.tab:
        ui.goTo(TownScreen.home(_gameScreen));
        return true;
    }

    return false;
  }

  @override
  void _afterTransfer(Item item, int count) {
    _refreshRecipe();
  }

  void _refreshRecipe() {
    _completeRecipe = null;

    // TODO: Would be good to show partially matching recipes somehow.

    for (var recipe in _gameScreen.game.content.recipes) {
      if (recipe.isComplete(_save.crucible)) {
        _completeRecipe = recipe;
        return;
      }
    }
  }
}

/// Views the contents of a shop and lets the player choose to buy or sell.
class _ShopScreen extends TownScreen {
  final Inventory _shop;

  @override
  ItemCollection get _items => _shop;

  @override
  String get _headerText => "What can I interest you in?";
  @override
  bool get _showPrices => true;

  @override
  Map<String, String> get _helpKeys => {
        "B": "Buy item",
        "S": "Sell item",
        "Shift": "Inspect item",
        "`": "Cancel"
      };

  _ShopScreen(super.gameScreen, this._shop) : super._();

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    if (super.keyDown(keyCode, shift: shift, alt: alt)) return true;

    if (shift || alt) return false;

    switch (keyCode) {
      case KeyCode.b:
        var screen = _ShopBuyScreen(_gameScreen, _shop);
        screen._inspected = _inspected;
        _isActive = false;
        ui.push(screen);

      case KeyCode.s:
        _isActive = false;
        ui.push(SellDialog(_gameScreen, _shop));
        return true;
    }

    return false;
  }

  @override
  int? _itemPrice(Item item) => item.price;
}

/// Screen to buy items from a shop.
class _ShopBuyScreen extends _ItemVerbScreen {
  final Inventory _shop;

  @override
  String get _headerText => "Buy which item?";

  @override
  String get _verb => "Buy";

  @override
  Map<String, String> get _helpKeys =>
      {"A-Z": "Select item", "Shift": "Inspect item", "`": "Cancel"};

  @override
  ItemCollection get _items => _shop;

  @override
  ItemCollection get _destination => _gameScreen.game.hero.save.inventory;

  _ShopBuyScreen(super.gameScreen, this._shop);

  @override
  bool get _canSelectAny => true;
  @override
  bool get _showPrices => true;

  @override
  bool canSelect(Item item) => item.price <= _save.gold;

  @override
  int _initialCount(Item item) => 1;

  /// Don't allow buying more than the hero can afford.
  @override
  int _maxCount(Item item) => math.min(item.count, _save.gold ~/ item.price);

  @override
  int? _itemPrice(Item item) => item.price;

  /// Pay for purchased item.
  @override
  void _afterTransfer(Item item, int count) {
    var price = item.price * count;
    _gameScreen.game.log
        .message("You buy ${item.clone(count)} for $price gold.");
    _save.gold -= price;

    // Acquiring an item may unlock skills.
    // TODO: Would be nice if hero handled this more automatically. Maybe make
    // Inventory and Equipment manage this?
    _gameScreen.game.hero.pickUp(_gameScreen.game, item);
  }
}

/// Screen to let the player choose a count for a selected item.
class _CountScreen extends TownScreen {
  /// The [_ItemVerbScreen] that pushed this.
  final _ItemVerbScreen _parent;
  final Item _item;
  int _count;

  @override
  ItemCollection get _items => _parent._items;

  @override
  String get _headerText {
    var itemText = _item.clone(_count).toString();
    var price = _parent._itemPrice(_item);
    if (price != null) {
      var priceString = formatMoney(price * _count);
      return "${_parent._verb} $itemText for $priceString gold?";
    } else {
      return "${_parent._verb} $itemText?";
    }
  }

  @override
  Map<String, String> get _helpKeys =>
      {"OK": _parent._verb, "↕": "Change quantity", "`": "Cancel"};

  _CountScreen(super.gameScreen, this._parent, this._item)
      : _count = _parent._initialCount(_item),
        super._() {
    _inspected = _item;
  }

  @override
  bool get _canSelectAny => true;

  /// Highlight the item the user already selected.
  @override
  bool canSelect(Item item) => item == _item;

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    // Don't allow the shift key to inspect items.
    if (keyCode == KeyCode.shift) return false;

    return super.keyDown(keyCode, shift: shift, alt: alt);
  }

  @override
  bool keyUp(int keyCode, {required bool shift, required bool alt}) {
    // Don't allow the shift key to inspect items.
    return false;
  }

  @override
  bool handleInput(Input input) {
    switch (input) {
      case Input.ok:
        ui.pop(_count);
      case Input.cancel:
        ui.pop();
      case Input.n when _count < _parent._maxCount(_item):
        _count++;
      case Input.s when _count > 1:
        _count--;
      case Input.runN:
        _count = _parent._maxCount(_item);
      case Input.runS:
        _count = 1;

      // TODO: Allow typing in number.

      default:
        return false;
    }

    dirty();
    return true;
  }

  @override
  int? _itemPrice(Item item) => _parent._itemPrice(item);
}
