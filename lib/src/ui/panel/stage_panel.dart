import 'dart:math' as math;

import 'package:malison/malison.dart';
import 'package:piecemeal/piecemeal.dart';

// TODO: Directly importing this is a little hacky. Put "appearance" on Element?
import '../../content/elements.dart';
import '../../debug.dart';
import '../../engine.dart';
import '../../hues.dart';
import '../effect.dart';
import '../game_screen.dart';
import 'panel.dart';

/// The main gameplay area of the screen.
class StagePanel extends Panel {
  static const _dazzleColors = [
    darkCoolGray,
    coolGray,
    lightCoolGray,
    ash,
    sandal,
    tan,
    persimmon,
    brown,
    buttermilk,
    gold,
    carrot,
    mint,
    olive,
    lima,
    peaGreen,
    sherwood,
    pink,
    red,
    maroon,
    lilac,
    purple,
    violet,
    lightAqua,
    lightBlue,
    blue,
    darkBlue,
  ];

  static const _fireChars = [CharCode.blackUpPointingTriangle, CharCode.caret];
  static const _fireColors = [
    [gold, persimmon],
    [buttermilk, carrot],
    [tan, red],
    [red, brown]
  ];

  final GameScreen _gameScreen;

  final _effects = <Effect>[];

  final List<Monster> visibleMonsters = [];

  bool _hasAnimatedTile = false;

  int _frame = 0;

  /// The portion of the [Stage] currently in view on screen.
  Rect get cameraBounds => _cameraBounds;

  /// This will get initialized by [_positionCamera] before it gets used.
  Rect _cameraBounds = Rect.empty;

  /// The amount to offset the rendered stage from the top left corner of the
  /// screen.
  ///
  /// This will be zero unless the stage is smaller than the view.
  Vec _renderOffset = Vec.zero;

  StagePanel(this._gameScreen);

  /// Draws [Glyph] at [x], [y] in [Stage] coordinates onto the current view.
  void drawStageGlyph(Terminal terminal, int x, int y, Glyph glyph) {
    _drawStageGlyph(terminal, x + bounds.x, y + bounds.y, glyph);
  }

  void _drawStageGlyph(Terminal terminal, int x, int y, Glyph glyph) {
    terminal.drawGlyph(x - _cameraBounds.x + _renderOffset.x,
        y - _cameraBounds.y + _renderOffset.y, glyph);
  }

  bool update(Iterable<Event> events) {
    _frame++;

    for (var event in events) {
      addEffects(_effects, event);
    }

    var hadEffects = _effects.isNotEmpty;
    _effects.removeWhere((effect) => !effect.update(_gameScreen.game));

    // TODO: Re-rendering the entire screen when only animated tiles have
    // changed is pretty rough on CPU usage. Maybe optimize to only redraw the
    // animated tiles if that's all that happened in a turn?
    return _hasAnimatedTile ||
        hadEffects ||
        _effects.isNotEmpty ||
        _gameScreen.game.hero.dazzle.isActive;
  }

  @override
  void renderPanel(Terminal terminal) {
    _positionCamera(terminal.size);

    visibleMonsters.clear();
    _hasAnimatedTile = false;

    var game = _gameScreen.game;
    var hero = game.hero;

    // Draw the tiles and items.
    for (var pos in _cameraBounds) {
      int? char;
      var fore = Color.black;
      var back = Color.black;

      // Show tiles containing interesting things more brightly.
      var lightFore = false;
      var lightBack = false;

      // Even if not currently visible, if explored we can see the tile itself.
      var tile = game.stage[pos];
      if (tile.isExplored) {
        var tileGlyph = _tileGlyph(pos, tile);
        char = tileGlyph.char;
        fore = tileGlyph.fore;
        back = tileGlyph.back;
        lightFore = true;
        lightBack = true;

        // Show the item if the tile has been explored, even if not currently
        // visible.
        // TODO: Should this show what the player last saw when the tile was
        // visible?
        var items = game.stage.itemsAt(pos);
        if (items.isNotEmpty) {
          var itemGlyph = items.first.appearance as Glyph;
          char = itemGlyph.char;
          fore = itemGlyph.fore;
          lightFore = false;
        }
      }

      // If the tile is currently visible, show any actor on it.
      if (tile.isVisible) {
        if (tile.substance != 0) {
          if (tile.element == Elements.fire) {
            char = rng.item(_fireChars);
            var color = rng.item(_fireColors);
            fore = color[0];
            back = color[1];

            _hasAnimatedTile = true;
          } else if (tile.element == Elements.poison) {
            var amount = 0.1 + (tile.substance / 255) * 0.9;
            back = back.blend(lima, amount);
          }
        }
      }

      var actor = game.stage.actorAt(pos);
      var showActor = tile.isVisible ||
          pos == game.hero.pos ||
          Debug.showAllMonsters ||
          actor != null && game.heroCanPerceive(actor);

      if (showActor && actor != null) {
        var actorGlyph = actor.appearance;
        if (actorGlyph is Glyph) {
          char = actorGlyph.char;
          fore = actorGlyph.fore;
        } else {
          // Hero.
          char = CharCode.at;
          fore = _gameScreen.heroColor;
        }
        lightFore = false;

        // If the actor is being targeted, invert its colors.
        if (_gameScreen.currentTargetActor == actor) {
          back = fore;
          fore = darkerCoolGray;
          lightBack = false;
        }

        if (actor is Monster) visibleMonsters.add(actor);
      }

      if (hero.dazzle.isActive) {
        var chance = math.min(90, hero.dazzle.duration * 8);
        if (rng.percent(chance)) {
          char = rng.percent(chance) ? char : CharCode.asterisk;
          fore = rng.item(_dazzleColors);
        }

        lightFore = false;
        lightBack = false;
      }

      Color multiply(Color a, Color b) {
        return Color(a.r * b.r ~/ 255, a.g * b.g ~/ 255, a.b * b.b ~/ 255);
      }

      // TODO: This could be cached if needed.
      var foreShadow = multiply(fore, const Color(80, 80, 95));
      var backShadow = multiply(back, const Color(40, 40, 55));

      // Apply lighting and visibility to the tile.
      if (tile.isVisible && (lightFore || lightBack)) {
        Color applyLighting(Color color, Color shadow) {
          // Apply a slight brightness curve to either end of the range of
          // floor illumination. We keep most of the middle of the range flat
          // so that there is still a visible ramp down at the dark end and
          // just a small bloom around lights at the bright end.
          var visibility = tile.floorIllumination - tile.fallOff;
          if (visibility < 64) {
            // Only blend up to 50% of the shadow color so that there is a
            // clear line between hidden and visible tiles.
            color =
                color.blend(shadow, lerpDouble(visibility, 0, 64, 0.5, 0.0));
          } else if (visibility > 128) {
            color = color.add(ash, lerpDouble(visibility, 128, 255, 0.0, 0.2));
          }

          if (tile.actorIllumination > 0) {
            const glow = Color(200, 130, 0);
            color = color.add(
                glow, lerpDouble(tile.actorIllumination, 0, 255, 0.05, 0.1));
          }

          return color;
        }

        if (lightFore) fore = applyLighting(fore, foreShadow);
        if (lightBack) back = applyLighting(back, backShadow);
      } else {
        if (lightFore) fore = foreShadow;
        if (lightBack) back = backShadow;
      }

      if (Debug.showHeroVolume) {
        var volume = game.stage.heroVolume(pos);
        if (volume > 0.0) back = back.blend(peaGreen, volume);
      }

      if (Debug.showMonsterAlertness && actor is Monster) {
        back = Color.blue.blend(Color.red, actor.alertness);
      }

      if (char != null) {
        var glyph = Glyph.fromCharCode(char, fore, back);
        _drawStageGlyph(terminal, pos.x, pos.y, glyph);
      }
    }

    // Draw the effects.
    for (var effect in _effects) {
      // TODO: Allow effects to preserve the tile's existing background color.
      effect.render(game, (x, y, glyph) {
        _drawStageGlyph(terminal, x, y, glyph);
      });
    }
  }

  /// Gets the [Glyph] to render for [tile].
  Glyph _tileGlyph(Vec pos, Tile tile) {
    // If the appearance is a single glyph, it's a normal tile.
    var appearance = tile.type.appearance;
    if (appearance is Glyph) return appearance;

    // Otherwise it's an animated tile, like water.
    var glyphs = appearance as List<Glyph>;

    // Ping pong back and forth.
    var period = glyphs.length * 2 - 2;

    // Calculate a "random" but consistent phase for each position.
    var phase = hashPoint(pos.x, pos.y);
    var frame = (_frame ~/ 8 + phase) % period;
    if (frame >= glyphs.length) {
      frame = glyphs.length - (frame - glyphs.length) - 1;
    }

    _hasAnimatedTile = true;
    return glyphs[frame];
  }

  /// Determines which portion of the [Stage] should be in view based on the
  /// position of the [Hero].
  ///
  /// We don't continuously center the hero on every step because the constant
  /// scrolling by one tile at a time makes it hard for the player to keep
  /// track of what's moving during combat. This wouldn't be an issue if the
  /// game had pixel-level scrolling, but scrolling one tile at a time makes it
  /// too jumpy.
  ///
  /// Instead, we only re-center the view when the hero gets close to a screen
  /// edge. Also, we center horizontally and vertically independently of each
  /// other.
  ///
  /// This function also handles the view size being larger than the stage,
  /// which can happen in the town or in small dungeons if the player has a
  /// large screen.
  void _positionCamera(Vec viewSize) {
    var game = _gameScreen.game;

    var cameraX = _cameraBounds.left;
    var offsetX = 0;

    int centerX() => (game.hero.pos.x - viewSize.x ~/ 2)
        .clamp(0, game.stage.width - viewSize.x);

    if (viewSize.x >= game.stage.width) {
      // The view is bigger than the stage, so lock the camera and center the
      // stage inside the view.
      cameraX = 0;
      offsetX = math.max(0, viewSize.x - game.stage.width) ~/ 2;
    } else if (_cameraBounds.width == 0 || _cameraBounds.width != viewSize.x) {
      // We haven't initialized the camera yet, so center it on the hero.
      cameraX = centerX();
    } else {
      var heroViewX = game.hero.pos.x - _cameraBounds.left;
      if (heroViewX < 8 || heroViewX > viewSize.x - 8) {
        // The hero is getting too close to the left or right edge, so
        // re-center.
        cameraX = centerX();
      }
    }

    var cameraY = _cameraBounds.top;
    var offsetY = 0;

    int centerY() => (game.hero.pos.y - viewSize.y ~/ 2)
        .clamp(0, game.stage.height - viewSize.y);

    if (viewSize.y >= game.stage.height) {
      // The view is bigger than the stage, so lock the camera and center the
      // stage inside the view.
      cameraY = 0;
      offsetY = math.max(0, viewSize.y - game.stage.height) ~/ 2;
    } else if (_cameraBounds.height == 0 ||
        _cameraBounds.height != viewSize.y) {
      // We haven't initialized the camera yet, so center it on the hero.
      cameraY = centerY();
    } else {
      var heroViewY = game.hero.pos.y - _cameraBounds.top;
      if (heroViewY < 8 || heroViewY > viewSize.y - 8) {
        // The hero is getting too close to the left or right edge, so
        // re-center.
        cameraY = centerY();
      }
    }

    _cameraBounds = Rect(
        cameraX,
        cameraY,
        math.min(viewSize.x, game.stage.width),
        math.min(viewSize.y, game.stage.height));
    _renderOffset = Vec(offsetX, offsetY);
  }
}
