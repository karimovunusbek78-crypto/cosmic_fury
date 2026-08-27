import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart'; // <-- click SFX (matches main_game_page)

// Adjust this import to wherever upgrade_page.dart actually lives in
// your project — mirrors how main_game_page.dart imports
// mode_select_page.dart / skins_page.dart.
import 'package:cosmic_fury/src/pages/upgrade/upgrade_page.dart';

// Pulls in SuperPowerData / kSuperPowers / superPowerFor /
// isSuperPowerOwned / canPurchaseSuperPower / purchaseSuperPower /
// ownedSuperPowerAssetsNotifier — the Ability button/sheet on this
// page now shows the SHIP'S ACTUAL SUPER POWER (the one that fires in
// a level via SuperPowerController — see level_page.dart) instead of
// the old flavor-only abilityName/abilityDescription fields on
// SkinData, so what you see here always matches what the power
// actually does in combat. Adjust this path if ship_super_powers.dart
// lives somewhere else in your project.
import 'package:cosmic_fury/src/pages/main/level_pages/ship_super_powers.dart';

/// ---------------------------------------------------------------------
/// Simple percentage-based responsive sizing helpers, so buttons, icons,
/// and text scale with the actual device screen instead of relying on
/// fixed pixel values that look oversized on small phones and tiny on
/// tablets.
///
/// - `context.wp(percent)` — a width equal to `percent`% of the screen
///   width (e.g. `context.wp(70)` is a box 70% as wide as the screen).
/// - `context.hp(percent)` — same idea, but against screen height.
/// - `context.sp(size)` — scales a "design size" written against a
///   375px-wide reference screen (roughly an iPhone SE/8) up or down to
///   match the current device, clamped so it never gets absurdly small
///   or large on extreme screen sizes. Use this for icon sizes, font
///   sizes, and fixed-looking dimensions like button heights.
/// ---------------------------------------------------------------------
extension ResponsiveSize on BuildContext {
  double get _screenWidth => MediaQuery.of(this).size.width;
  double get _screenHeight => MediaQuery.of(this).size.height;

  double wp(double percent) => _screenWidth * percent / 100;

  double hp(double percent) => _screenHeight * percent / 100;

  double sp(double size) =>
      size * (_screenWidth / 375.0).clamp(0.85, 1.3);
}

/// ---------------------------------------------------------------------
/// Small reusable "counts up/down" number widget — whenever `value`
/// changes, it smoothly animates from whatever it was last showing to
/// the new number instead of snapping straight to it. Used for the
/// gems/coins stat cards, the Health/Energy/Damage stat card, and the
/// Health/Energy current readouts, so switching skins or spending
/// currency feels alive instead of static.
/// ---------------------------------------------------------------------
class AnimatedCounterText extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  final int maxLines;

  const AnimatedCounterText({
    Key? key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 700),
    this.maxLines = 1,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text(
          '${animatedValue.round()}',
          style: style,
          maxLines: maxLines,
        );
      },
    );
  }
}

/// ---------------------------------------------------------------------
/// A single skin entry. Add more entries here later — the carousel
/// already supports any number of skins, wrapping around at both ends.
///
/// `asset` should be the bare filename Flame's image loader expects
/// (e.g. 'ship1.png'), matching how loadSprite() is called elsewhere.
///
/// `price` — how many gems this skin costs to unlock. 0 means it's
/// free from the start (used for the very first ship, the Falcon).
/// Any skin with a non-zero price has to be bought via [purchaseSkin]
/// before it can be equipped.
///
/// `nameColor` — if set, the skin name renders in this solid color
/// instead of the default orange/red gradient (used for the Falcon's
/// blue callsign).
///
/// `flameAccent` — the color the engine trail fades into (core is
/// always white-hot, this is the "cooler" outer color), so each ship
/// can have its own colored exhaust.
///
/// `engineOffsetYFraction` — how far down the sprite (as a fraction of
/// its height, from the center) the engine nozzle actually sits.
/// Sprites often have transparent padding around the art, so this is
/// tunable per-skin to land the flame right at the visible tail
/// instead of floating inside the hull or trailing off below it.
/// Lower value = flame sits higher, closer to the ship's body.
/// Higher value (up to ~0.5, the true bottom edge) = flame sits
/// lower, further from the ship.
///
/// `flameSpread` — how wide the flame jitters side-to-side, in
/// pixels. Small (~4-6) reads as a narrow, tight jet that fits
/// between twin tail fins; larger (~16-20) reads as a wider, fuller
/// exhaust.
///
/// `flameParticleRadius` — base size of each flame particle, in
/// pixels. Pair a small flameSpread with a small radius for a narrow
/// nozzle look.
///
/// `flameLength` — multiplier on how far particles travel down (and
/// how long they live) before fading, controlling the *vertical*
/// length of the trail independently of `flameSpread`'s horizontal
/// width. 1.0 is the default trail length; >1.0 makes it taller
/// without making it wider.
///
/// `bulletColor` — the color this skin's bullets render in on the
/// main game page.
///
/// `bulletFromCenter` — if true, fires a single bolt straight out of
/// the ship's horizontal center. If false, fires the classic twin-gun
/// pair offset left/right of center.
///
/// `bulletSharp` — if true, the bullet renders as a sharp, pointed
/// needle/dart shape (triangular tip + tapered shaft + glowing white
/// core line) instead of the default rounded dot/capsule. Used for
/// skins that should feel like they fire a sharp piercing bolt from
/// dead center (e.g. Nebula).
///
/// `bulletLaser` — if true, each individual bullet renders as a
/// glowing laser-look bolt: a soft blurred outer glow, a saturated
/// colored core, and a bright white hot-core line down the middle —
/// instead of a solid dot/capsule or the sharp needle look. This is
/// still a series of separate, timed shots (like `bulletSharp`), just
/// with a laser-y look per shot (e.g. Shadow Reaper). Takes priority
/// over `bulletSharp` if both are somehow set. See `bulletBeam` below
/// for an actual unbroken continuous beam instead of discrete shots.
///
/// `bulletBeam` — if true, this skin doesn't fire discrete bullets at
/// all. Instead a single continuous laser beam streams out of the
/// ship's muzzle and stretches all the way off the top of the screen,
/// every frame, for as long as the skin is equipped (e.g. Frostbyte).
/// When this is true, `bulletFromCenter` / `bulletSharp` /
/// `bulletLaser` / `bulletHeight` are ignored for firing purposes —
/// only `bulletColor` and `bulletWidth` (the beam's thickness) still
/// apply, along with `bulletOffsetYFraction` for where the beam
/// originates on the ship.
///
/// `bulletWidth` / `bulletHeight` — bullet size in px. Equal
/// width/height reads as a round dot; a taller height than width
/// reads as an elongated bolt/capsule (or, with `bulletSharp`, a
/// pointed dart, or with `bulletLaser`, a glowing beam).
///
/// `bulletOffsetYFraction` — how far above the ship's center (as a
/// fraction of its height) bullets spawn from, i.e. where the "nose"
/// / muzzle sits. Negative moves the spawn point up toward the tip
/// of the ship; less negative (closer to 0) spawns closer to the
/// ship's center. Sprites often have transparent padding, so this is
/// tunable per-skin to land bullets right at the visible nose instead
/// of floating below or above it.
///
/// `maxHealth` / `maxEnergy` / `damage` — BASE flavor stats. These are
/// the level-0 numbers shown before any upgrades are bought on the
/// Upgrade page. Use [effectiveStatValue] (below) anywhere you need
/// the ship's CURRENT stat (base + whatever's been upgraded) rather
/// than reading these fields directly.
///
/// `description` — a line or two of flavor text shown in the Info
/// sheet on the Skins page.
///
/// `abilityName` / `abilityDescription` / `abilityIcon` — NO LONGER
/// shown anywhere in the UI. The Ability button/sheet now reads the
/// ship's real super power straight from [superPowerFor] (see
/// ship_super_powers.dart) so what's displayed always matches what
/// actually happens in a level. These three fields are kept only so
/// existing SkinData literals below don't need to be rewritten; feel
/// free to delete them later.
class SkinData {
  final String name;
  final String asset;
  final int price;
  final Color? nameColor;
  final Color flameAccent;
  final double engineOffsetYFraction;
  final double flameSpread;
  final double flameParticleRadius;
  final double flameLength;
  final Color bulletColor;
  final bool bulletFromCenter;
  final bool bulletSharp;
  final bool bulletLaser;
  final bool bulletBeam;
  final double bulletWidth;
  final double bulletHeight;
  final double bulletOffsetYFraction;
  final int maxHealth;
  final int maxEnergy;
  final int damage;
  final String description;
  final String abilityName;
  final String abilityDescription;
  final IconData abilityIcon;

  const SkinData({
    required this.name,
    required this.asset,
    this.price = 0,
    this.nameColor,
    this.flameAccent = Colors.blueAccent,
    this.engineOffsetYFraction = 0.38,
    this.flameSpread = 18,
    this.flameParticleRadius = 6,
    this.flameLength = 1.0,
    this.bulletColor = Colors.cyanAccent,
    this.bulletFromCenter = false,
    this.bulletSharp = false,
    this.bulletLaser = false,
    this.bulletBeam = false,
    this.bulletWidth = 10,
    this.bulletHeight = 10,
    this.bulletOffsetYFraction = -0.20,
    this.maxHealth = 1000,
    this.maxEnergy = 300,
    this.damage = 60,
    this.description = 'A dependable ship, ready for combat.',
    this.abilityName = 'Boost',
    this.abilityDescription = 'A short burst of extra speed.',
    this.abilityIcon = Icons.bolt,
  });
}

/// ---------------------------------------------------------------------
/// Top-level roster + currently equipped skin, defined OUTSIDE the
/// State class so other pages (like the main game page) can read which
/// skin is equipped without needing SkinsPage's widget state at all.
///
/// `equippedSkin` is what MainGamePage reads when it builds the ship —
/// update it (e.g. from _selectCurrent below) and the change is picked
/// up next time the game page loads.
///
/// NOTE: this is plain in-memory state, so it resets to the Falcon on
/// app restart. Wire up persistence (e.g. shared_preferences) here if
/// you want the equipped skin / gems / coins / owned ships / upgrade
/// levels to survive closing the app.
/// ---------------------------------------------------------------------
const List<SkinData> kSkins = [
  SkinData(
    name: 'Falcon Mk.I',
    asset: 'ship1.png',
    price: 0, // the very first ship — free from the start
    nameColor: Colors.lightBlueAccent, // blue callsign
    flameAccent: Colors.blueAccent, // blue engine trail
    engineOffsetYFraction: 0.30, // moved up a bit more
    flameSpread: 18, // full, wide exhaust
    flameParticleRadius: 6,
    flameLength: 1.0, // default trail length
    bulletColor: Colors.cyanAccent,
    bulletFromCenter: false, // classic twin guns
    bulletWidth: 10,
    bulletHeight: 10, // round dot, same as the original bullet
    bulletOffsetYFraction: -0.20, // unchanged from before
    maxHealth: 100,
    maxEnergy: 20,
    damage: 15,
    description:
        "The Falcon Mk.I — your first ship, reliable and easy to fly. Balanced stats make it a safe pick while you're learning the ropes.",
  ),
  SkinData(
    name: 'Interceptor',
    asset: 'ship2.png',
    price: 250, // costs gems to unlock
    flameAccent: Colors.deepOrangeAccent, // fiery, different trail
    engineOffsetYFraction: 0.24, // moved up further to match the tail
    flameSpread: 4, // narrow, fits between the twin tail fins
    flameParticleRadius: 3.5,
    flameLength: 1.7, // taller trail, still narrow horizontally
    bulletColor: Colors.redAccent,
    bulletFromCenter: true, // single shot from dead center
    bulletWidth: 7,
    bulletHeight: 30, // taller bolt, not a dot
    bulletOffsetYFraction: -0.34, // sits right at this ship's nose tip
    maxHealth: 300,
    maxEnergy: 30,
    damage: 60,
    description:
        'The Interceptor trades a little durability for a sharp, focused single-bolt attack straight out of dead center.',
  ),
  SkinData(
    name: 'Nebula',
    asset: 'ship3.png',
    price: 700, // costs more than the Interceptor — third unlock
    nameColor: const Color(0xFFB39DFF), // blue-leaning purple callsign
    flameAccent: const Color(0xFF8A5CFF), // blue-purple engine trail
    engineOffsetYFraction: 0.32,
    flameSpread: 9, // tighter, swirlier jet — its own distinct look
    flameParticleRadius: 4,
    flameLength: 1.5, // longer, wispier trail
    bulletColor: const Color(0xFFB39DFF),
    bulletFromCenter: true, // single sharp bolt straight from center
    bulletSharp: true, // sharp tip — needle/dart shape, not a dot
    bulletWidth: 10,
    bulletHeight: 30, // long enough for the sharp taper to read well
    bulletOffsetYFraction: -0.35, // nudged a little bit higher again (was -0.32) — sits right at the nose tip
    maxHealth: 700,
    maxEnergy: 40,
    damage: 100,
    description:
        'Nebula wraps its hull in a swirling purple haze and fires a needle-sharp bolt that pierces cleanly through anything in its path.',
  ),
  SkinData(
    name: 'Frostbyte',
    asset: 'ship4.png',
    price: 1500, // blue hull with white stripes
    nameColor: Colors.lightBlueAccent, // blue callsign, matches white stripes
    flameAccent: Colors.white, // white-blue engine trail to match the stripes
    engineOffsetYFraction: 0.34,
    flameSpread: 22, // wide, full icy exhaust — its own distinct look
    flameParticleRadius: 7,
    flameLength: 0.85, // shorter, punchier burst instead of a long tail
    bulletColor: Colors.lightBlueAccent,
    bulletFromCenter: true, // still center-aligned, unused once bulletBeam fires though
    bulletBeam: true, // one unbroken beam streaming off the top of the screen, not separate shots
    bulletWidth: 10, // beam thickness
    bulletOffsetYFraction: -0.30, // where the beam originates on the ship
    maxHealth: 1000,
    maxEnergy: 50,
    damage: 12,
    description:
        'Frostbyte channels its reactor into one unbroken beam instead of separate shots — hold the line and it never stops firing.',
  ),
  SkinData(
    name: 'Shadow Reaper',
    asset: 'ship5.png',
    price: 2769, // priciest — the black ship
    nameColor: Colors.black, // pure black callsign to match the hull
    flameAccent: const Color(0xFF1A0630), // near-black violet trail, dark and sinister
    engineOffsetYFraction: 0.40, // sits a bit lower than the others
    flameSpread: 6, // razor-thin jet, its own distinct look
    flameParticleRadius: 5.5,
    flameLength: 1.6, // long, trailing smoke-like tail
    bulletColor: const Color(0xFF6E0EFF),
    bulletFromCenter: true,
    bulletLaser: true, // glowing laser-look bolt, same style Frostbyte used to fire
    bulletWidth: 8, // a touch wider than before, gives the glow room to read
    bulletHeight: 32, // long bolt
    bulletOffsetYFraction: -0.32,
    maxHealth: 1500,
    maxEnergy: 60,
    damage: 170,
    description:
        'The priciest ship in the fleet. Shadow Reaper is built for players who want the strongest stats and the most menacing silhouette in the fleet.',
  ),
];

/// The skin currently equipped on the main game page, as a
/// ValueNotifier so anything already running (like MyFlameGame on the
/// main page) can react LIVE the instant the player hits SELECT,
/// instead of only picking it up next time that widget's initState
/// happens to run. This matters because navigating back to
/// MainGamePage often doesn't recreate its State (e.g. a simple pop,
/// or a bottom-nav IndexedStack keeping it alive) — so a plain
/// variable read once in onLoad() would silently go stale.
final ValueNotifier<SkinData> equippedSkinNotifier =
    ValueNotifier<SkinData>(kSkins[0]);

/// Convenience getter/setter so existing code that reads/writes
/// `equippedSkin` directly (like below) keeps working unchanged,
/// while MyFlameGame listens to `equippedSkinNotifier` for live
/// updates.
SkinData get equippedSkin => equippedSkinNotifier.value;
set equippedSkin(SkinData skin) => equippedSkinNotifier.value = skin;

/// ---------------------------------------------------------------------
/// Currency + ownership state — real, shared, and readable from any
/// page (SkinsPage, UpgradePage, and MainGamePage all bind to these
/// directly).
/// ---------------------------------------------------------------------

/// Gems — the premium currency spent on unlocking new ships. Bumped
/// up to a big testing pile so every skin (including the 2769-gem
/// Shadow Reaper) is affordable right away.
final ValueNotifier<int> gemsNotifier = ValueNotifier<int>(1000000);

/// Coins — the secondary currency, spent on stat upgrades AND on
/// buying each ship's super power (see ship_super_powers.dart).
/// Tracked as real state (not a hardcoded string) so it updates
/// consistently everywhere it's shown. Bumped up to a big testing
/// pile so every stat/power can be bought without running dry.
final ValueNotifier<int> coinsNotifier = ValueNotifier<int>(1000000000);

/// Which skins are owned, tracked by asset filename. The Falcon is
/// free, so it's owned from the start; anything else has to be
/// bought with gems via [purchaseSkin].
final ValueNotifier<Set<String>> ownedSkinAssetsNotifier =
    ValueNotifier<Set<String>>({kSkins[0].asset});

/// ---------------------------------------------------------------------
/// Hull integrity — real, shared, per-ship state (0-100), tracked by
/// asset filename just like ownership. Every ship starts at 100 (fully
/// repaired). Nothing lowers it yet (no combat/damage system wired
/// up), but this is genuinely live state now, not a hardcoded
/// constant: call [setHull] from wherever damage/repair happens later
/// (or from a debug button while testing) and the badge on the Skins
/// page will animate to the new value immediately, on any ship, from
/// any page — the same pattern as gems/coins/ownership above.
/// ---------------------------------------------------------------------
final ValueNotifier<Map<String, int>> hullByAssetNotifier =
    ValueNotifier<Map<String, int>>({
  for (final s in kSkins) s.asset: 100,
});

/// Current hull integrity (0-100) for [skin]. Defaults to 100 for any
/// ship not yet present in the map.
int hullFor(SkinData skin) => hullByAssetNotifier.value[skin.asset] ?? 100;

/// Sets hull integrity for [skin], clamped to 0-100, and notifies
/// every listener (e.g. the badge on the Skins page) immediately.
void setHull(SkinData skin, int value) {
  final clamped = value.clamp(0, 100);
  hullByAssetNotifier.value = {
    ...hullByAssetNotifier.value,
    skin.asset: clamped,
  };
}

/// Whether [skin] can currently be equipped — either it's free, or
/// it's already been purchased.
bool isSkinOwned(SkinData skin) =>
    skin.price == 0 || ownedSkinAssetsNotifier.value.contains(skin.asset);

/// Attempts to buy [skin] with gems. Returns true if the skin is
/// owned afterward (it already was, or the purchase just succeeded),
/// false if there weren't enough gems to cover it.
bool purchaseSkin(SkinData skin) {
  if (isSkinOwned(skin)) return true;
  if (gemsNotifier.value < skin.price) return false;
  gemsNotifier.value -= skin.price;
  ownedSkinAssetsNotifier.value = {
    ...ownedSkinAssetsNotifier.value,
    skin.asset,
  };
  return true;
}

/// ---------------------------------------------------------------------
/// STAT UPGRADE SYSTEM
/// ---------------------------------------------------------------------
/// Each ship has 3 upgradeable stats — Health (index 0), Energy
/// (index 1), and Damage (index 2) — each with 15 upgrade levels,
/// stepping evenly from the ship's BASE stat (SkinData.maxHealth /
/// maxEnergy / damage, i.e. level 0) up to a per-ship, per-stat CAP
/// defined in [kStatCaps] below (level 15).
///
/// [kStatCaps] is indexed the same way as [kSkins] (ship 0 = Falcon,
/// ship 1 = Interceptor, ... ship 4 = Shadow Reaper), and each entry
/// is `[healthCap, energyCap, damageCap]`:
///
///   Falcon Mk.I    -> health 320,  energy 35, damage 70
///   Interceptor    -> health 750,  energy 45, damage 100
///   Nebula         -> health 1000, energy 53, damage 140
///   Frostbyte      -> health 1450, energy 78, damage 30
///   Shadow Reaper  -> health 2100, energy 80, damage 230
///
/// Upgrades are bought with coins via [purchaseUpgrade]; cost rises
/// both per level (later levels of the same stat cost more) and per
/// ship (pricier/later ships cost more per level, mirroring their gem
/// price tier).
/// ---------------------------------------------------------------------

/// Number of upgrade levels available per stat, per ship.
const int kMaxUpgradeLevel = 15;

/// `[healthCap, energyCap, damageCap]` per ship, in the same order as
/// [kSkins].
const List<List<int>> kStatCaps = [
  [320, 35, 70], // Falcon Mk.I
  [750, 45, 100], // Interceptor
  [1000, 53, 140], // Nebula
  [1450, 78, 30], // Frostbyte
  [2100, 80, 230], // Shadow Reaper
];

/// Current upgrade level (0-15) per stat, per ship, tracked by asset
/// filename just like ownership/hull. `[healthLevel, energyLevel,
/// damageLevel]`, all starting at 0 (i.e. base stats, no upgrades
/// bought yet).
final ValueNotifier<Map<String, List<int>>> upgradeLevelsNotifier =
    ValueNotifier<Map<String, List<int>>>({
  for (final s in kSkins) s.asset: [0, 0, 0],
});

/// Index of [skin] within [kSkins] — used to look up its row in
/// [kStatCaps] AND its entry in [kSuperPowers] (see
/// ship_super_powers.dart).
int skinIndexOf(SkinData skin) => kSkins.indexOf(skin);

/// The BASE (level-0, pre-upgrade) value of stat [statIndex] (0 =
/// Health, 1 = Energy, 2 = Damage) for [skin].
int statBaseValue(SkinData skin, int statIndex) {
  switch (statIndex) {
    case 0:
      return skin.maxHealth;
    case 1:
      return skin.maxEnergy;
    default:
      return skin.damage;
  }
}

/// The level-15 (fully upgraded) value of stat [statIndex] for
/// [skin], from [kStatCaps].
int statCapValue(SkinData skin, int statIndex) =>
    kStatCaps[skinIndexOf(skin)][statIndex];

/// Current upgrade level (0-15) of stat [statIndex] for [skin].
int upgradeLevelFor(SkinData skin, int statIndex) =>
    (upgradeLevelsNotifier.value[skin.asset] ?? const [0, 0, 0])[statIndex];

/// Whether stat [statIndex] on [skin] is already at its cap (level
/// 15) — nothing left to buy.
bool isStatMaxed(SkinData skin, int statIndex) =>
    upgradeLevelFor(skin, statIndex) >= kMaxUpgradeLevel;

/// The ship's CURRENT value for stat [statIndex] — base stat plus
/// whatever's been upgraded so far, stepping evenly from base (level
/// 0) to cap (level 15). This is what UI (and eventually gameplay)
/// should read instead of `skin.maxHealth` / `maxEnergy` / `damage`
/// directly, so upgrades actually show up.
int effectiveStatValue(SkinData skin, int statIndex) {
  final level = upgradeLevelFor(skin, statIndex);
  final base = statBaseValue(skin, statIndex);
  if (level <= 0) return base;
  final cap = statCapValue(skin, statIndex);
  final step = (cap - base) / kMaxUpgradeLevel;
  return (base + step * level).round();
}

/// Coin cost to go from [currentLevel] to `currentLevel + 1` for
/// [skin]'s stat [statIndex]. Scales up with both the level being
/// bought (later levels cost more) and the ship's tier (pricier,
/// later-unlock ships cost more per level, mirroring their gem price
/// tier) — so maxing out the Falcon is a lot cheaper than maxing out
/// the Shadow Reaper.
int upgradeCost(SkinData skin, int statIndex, int currentLevel) {
  final tier = skinIndexOf(skin) + 1; // 1 (Falcon) .. 5 (Shadow Reaper)
  final baseCost = 80 * tier;
  return baseCost * (currentLevel + 1);
}

/// Attempts to spend coins to bump [skin]'s stat [statIndex] up one
/// level. Returns true on success, false if the stat is already
/// maxed or there aren't enough coins.
bool purchaseUpgrade(SkinData skin, int statIndex) {
  final level = upgradeLevelFor(skin, statIndex);
  if (level >= kMaxUpgradeLevel) return false;

  final cost = upgradeCost(skin, statIndex, level);
  if (coinsNotifier.value < cost) return false;

  coinsNotifier.value -= cost;

  final updated = Map<String, List<int>>.from(upgradeLevelsNotifier.value);
  final levels = List<int>.from(updated[skin.asset] ?? const [0, 0, 0]);
  levels[statIndex] = level + 1;
  updated[skin.asset] = levels;
  upgradeLevelsNotifier.value = updated;
  return true;
}

class SkinsPage extends StatefulWidget {
  const SkinsPage({Key? key}) : super(key: key);

  @override
  _SkinsPageState createState() => _SkinsPageState();
}

class _SkinsPageState extends State<SkinsPage> {
  int _currentIndex = 0;
  late int _selectedIndex; // the currently equipped skin

  SkinData get _currentSkin => kSkins[_currentIndex];

  @override
  void initState() {
    super.initState();
    // Start the carousel on whatever is currently equipped, so
    // re-opening this page shows the right ship marked EQUIPPED.
    final idx = kSkins.indexOf(equippedSkin);
    _selectedIndex = idx == -1 ? 0 : idx;
    _currentIndex = _selectedIndex;

    // ---------------------------------------------------------------
    // Click SFX — preloaded here (assets/audio/click.mp3) the exact
    // same way MainGamePage does it, via FlameAudio's shared
    // audioCache, so the very first tap on this page fires instantly
    // instead of stalling while the file decodes. If MainGamePage has
    // already run this session the file is likely cached already, but
    // this covers the case where SkinsPage is opened first.
    // ---------------------------------------------------------------
    FlameAudio.audioCache.load('click.mp3');
  }

  /// Plays the shared button-tap SFX — same call MainGamePage uses
  /// (FlameAudio.play), so both pages share one consistent sound
  /// pipeline instead of two different audio packages.
  void _playClickSound() {
    FlameAudio.play('click.mp3', volume: 0.6);
  }

  void _goToPrevious() {
    setState(() {
      _currentIndex = (_currentIndex - 1 + kSkins.length) % kSkins.length;
    });
  }

  void _goToNext() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % kSkins.length;
    });
  }

  void _selectCurrent() {
    setState(() {
      _selectedIndex = _currentIndex;
      equippedSkin = kSkins[_currentIndex];
    });
  }

  /// Shows a confirmation dialog before spending gems on [skin]. Only
  /// calls [_purchaseCurrent] if the player confirms — tapping BUY no
  /// longer spends gems immediately.
  void _confirmPurchase(SkinData skin) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF160600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.deepOrange.shade400, width: 1),
        ),
        title: Row(
          children: [
            Image.asset('assets/images/budget.png', width: 20, height: 20),
            const SizedBox(width: 8),
            const Text(
              'Confirm Purchase',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Buy ${skin.name} for ${skin.price} gems?',
          style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _playClickSound();
              Navigator.of(context).pop();
            },
            child: Text('CANCEL', style: TextStyle(color: Colors.grey.shade400)),
          ),
          TextButton(
            onPressed: () {
              _playClickSound();
              Navigator.of(context).pop();
              _purchaseCurrent(skin);
            },
            child: const Text('BUY', style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
    );
  }

  /// Attempts to buy the given (currently unowned) skin. On success,
  /// equips it immediately. On failure (not enough gems), lets the
  /// player know instead of silently doing nothing.
  void _purchaseCurrent(SkinData skin) {
    final bought = purchaseSkin(skin);
    if (!bought) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Not enough gems — ${skin.name} costs ${skin.price}.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _selectedIndex = _currentIndex;
      equippedSkin = skin;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ---- Static background image, full-bleed ----
          Positioned.fill(
            child: Image.asset(
              'assets/images/skinbackground.png',
              fit: BoxFit.cover,
            ),
          ),

          // ---- Foreground UI ----
          // No scroll wrapper — the content below is compact enough
          // now (smaller stats card, no separate upgrade row) to fit
          // without scrolling.
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: context.hp(0.8)),
              child: Column(
                children: [
                  _buildHeader(),

                  // ---- Stat cards row — same look as the home page ----
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        context.wp(5), context.hp(1.4), context.wp(5), 0),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ValueListenableBuilder<int>(
                              valueListenable: gemsNotifier,
                              builder: (context, gems, _) => _buildStatCard(
                                iconAsset: 'assets/images/budget.png',
                                value: gems,
                                iconSize: context.sp(36),
                                showAddButton: true,
                              ),
                            ),
                          ),
                          SizedBox(width: context.wp(3)),
                          Expanded(
                            child: ValueListenableBuilder<int>(
                              valueListenable: coinsNotifier,
                              builder: (context, coins, _) => _buildStatCard(
                                iconAsset: 'assets/images/coin.png',
                                value: coins,
                                iconSize: context.sp(36),
                                showAddButton: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ---- Info button, below the currency cards ----
                  _buildInfoRow(),

                  SizedBox(height: context.hp(0.6)),

                  // ---- Skin name, floating above the ship ----
                  _buildSkinName(),

                  _buildBadge(),

                  // Hull bar now sits above the ship itself (see
                  // _buildSkinCarousel) — a bit more gap here so it
                  // doesn't crowd right up against the badge above it.
                  SizedBox(height: context.hp(1.0)),

                  // ---- Ship carousel — the ship itself, rendered by
                  //      Flame with a live engine-flame trail, the
                  //      hull indicator above it, the page dots
                  //      anchored under the ship, and the super power
                  //      button sitting next to the dots.
                  _buildSkinCarousel(),

                  SizedBox(height: context.hp(0.8)),

                  // ---- Stats card (Health/Energy/Damage as plain
                  //      numbers, reflecting any upgrades bought on
                  //      the Upgrade page) with the Upgrade/Select
                  //      buttons as their own row underneath it, not
                  //      inside the card. Last thing in the column —
                  //      nothing pushes it down further.
                  _buildStatsSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Header — just the page title now. The back arrow was removed (the
  // system/gesture back still works via Navigator), and the Info
  // button moved down below the currency cards — see _buildInfoRow.
  // ------------------------------------------------------------------
  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          context.wp(5), context.hp(1.6), context.wp(5), 0),
      child: Text(
        'Skins',
        style: TextStyle(
          color: Colors.white,
          fontSize: context.sp(20),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Info button — a small pill sitting under the gems/coins cards
  // (right-aligned), separate from the currency row so it doesn't
  // read as part of it. Opens the same Info sheet as before.
  // ------------------------------------------------------------------
  Widget _buildInfoRow() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          context.wp(5), context.hp(0.6), context.wp(5), 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AnimatedTapButton(
            onTap: () {
              _playClickSound();
              _showInfoSheet();
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: context.wp(3), vertical: context.hp(0.7)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.black.withOpacity(0.45),
                border: Border.all(
                  color: Colors.deepOrange.shade400.withOpacity(0.8),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.orangeAccent, size: context.sp(14)),
                  SizedBox(width: context.wp(1.2)),
                  Text(
                    'Info',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: context.sp(11),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Skin name — solid `nameColor` when the skin defines one (e.g. the
  // Falcon's blue callsign), otherwise the default orange/red gradient.
  // ------------------------------------------------------------------
  Widget _buildSkinName() {
    final skin = _currentSkin;

    if (skin.nameColor != null) {
      return Text(
        skin.name,
        style: TextStyle(
          color: skin.nameColor,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          shadows: [
            Shadow(color: skin.nameColor!.withOpacity(0.7), blurRadius: 14),
          ],
        ),
      );
    }

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFFFFC107), Color(0xFFB71C1C)],
      ).createShader(bounds),
      child: Text(
        skin.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Small pill under the skin name — "EQUIPPED" if this is the active
  // ship, or the gem price if it hasn't been bought yet. Nothing shows
  // if it's owned but simply not equipped right now.
  //
  // FIX: previously the "owned but not equipped" case returned
  // `SizedBox.shrink()` — a literal 0-height widget — while the other
  // two cases returned a ~26px-tall Padding+Container. Since this
  // widget sits directly in a Column with no fixed-height wrapper,
  // that 0px-vs-26px difference made everything below it (hull bar,
  // ship carousel, stats card) visibly jump up/down as you swiped
  // between owned-not-equipped skins and equipped/locked skins.
  //
  // The fix: always return a Padding+Container of the SAME fixed
  // size, and just make it invisible (Opacity 0, non-interactive)
  // when there's nothing to show. Same layout footprint in all three
  // states, so nothing else in the Column shifts.
  // ------------------------------------------------------------------
  Widget _buildBadge() {
    final bool isEquipped = _currentIndex == _selectedIndex;

    if (isEquipped) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.green.withOpacity(0.15),
            border: Border.all(color: Colors.greenAccent, width: 1),
          ),
          child: const Text(
            'EQUIPPED',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: ownedSkinAssetsNotifier,
      builder: (context, owned, _) {
        final skin = _currentSkin;
        final bool ownedNotEquipped = isSkinOwned(skin);

        // Same-shaped badge widget either way — only its visibility
        // (and interactivity) changes, never its size.
        final badge = Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.lightBlueAccent.withOpacity(0.15),
              border: Border.all(color: Colors.lightBlueAccent, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/budget.png', width: 14, height: 14),
                const SizedBox(width: 4),
                Text(
                  '${skin.price}',
                  style: const TextStyle(
                    color: Colors.lightBlueAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        );

        if (ownedNotEquipped) {
          // Owned but not the active skin: reserve the same space,
          // just show nothing there.
          return Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: badge,
          );
        }

        // Locked (not owned): show the real price badge.
        return badge;
      },
    );
  }

  // ------------------------------------------------------------------
  // Carousel — left arrow / big Flame-rendered ship / right arrow,
  // all centered as one row. The ship itself has no background card;
  // it floats over the background image with a live engine-flame
  // trail. The hull indicator floats above the ship (small circular
  // ring badge, top-left). The page dots sit centered under the ship,
  // and the super power button now sits at that same bottom row, on
  // the right side, bigger than it used to be — so it reads together
  // with the carousel indicator instead of floating up near the hull
  // ring. Rebuilding the GameWidget with a fresh key per skin gives
  // each ship its own clean sprite + particle instance (and its own
  // flame color / width / engine offset) when you switch.
  // ------------------------------------------------------------------
  Widget _buildSkinCarousel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildArrowButton(
          icon: Icons.chevron_left_rounded,
          onTap: kSkins.length > 1 ? _goToPrevious : null,
        ),
        SizedBox(
          width: context.wp(70),
          height: context.hp(38),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Ship preview — blurred with a lock icon over it when
              // the skin hasn't been bought yet, so it's obvious at a
              // glance that it needs to be purchased first.
              ValueListenableBuilder<Set<String>>(
                valueListenable: ownedSkinAssetsNotifier,
                builder: (context, owned, _) {
                  final bool locked = !isSkinOwned(_currentSkin);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: locked ? 6 : 0,
                          sigmaY: locked ? 6 : 0,
                        ),
                        child: GameWidget(
                          key: ValueKey(_currentSkin.asset),
                          game: SkinPreviewGame(
                            shipAsset: _currentSkin.asset,
                            flameAccent: _currentSkin.flameAccent,
                            engineOffsetYFraction:
                                _currentSkin.engineOffsetYFraction,
                            flameSpread: _currentSkin.flameSpread,
                            flameParticleRadius:
                                _currentSkin.flameParticleRadius,
                            flameLength: _currentSkin.flameLength,
                          ),
                        ),
                      ),
                      if (locked)
                        Container(
                          width: context.sp(64),
                          height: context.sp(64),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.55),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.7),
                              width: 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.lock,
                            color: Colors.white,
                            size: context.sp(30),
                          ),
                        ),
                    ],
                  );
                },
              ),
              // Hull bar — top-center of the ship. This is the
              // "car dashboard" style condition gauge: a bar that
              // shrinks and shifts color (green → amber → red) as
              // hull drops, so it reads as "does this need repair?"
              // at a glance. Tapping it tells you directly.
              Positioned(
                top: -context.hp(0.6),
                left: 0,
                right: 0,
                child: Center(child: _buildHullBadge()),
              ),
              // Page dots — centered under the ship, nudged down a
              // touch closer to the bottom edge.
              Positioned(
                bottom: context.hp(0.1),
                left: 0,
                right: 0,
                child: Center(child: _buildDots()),
              ),
              // Super power — sits on the same bottom row as the
              // dots, on the RIGHT side, nudged down a touch as well.
              Positioned(
                bottom: -context.hp(0.2),
                right: context.wp(1),
                child: _buildSuperPowerCircleButton(),
              ),
            ],
          ),
        ),
        _buildArrowButton(
          icon: Icons.chevron_right_rounded,
          onTap: kSkins.length > 1 ? _goToNext : null,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Round arrow buttons — filled gradient circle with glow, bigger
  // and punchier than a plain outlined ring.
  // ------------------------------------------------------------------
  Widget _buildArrowButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;

    final circle = Container(
      width: context.sp(46),
      height: context.sp(46),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: enabled
            ? const LinearGradient(
                colors: [Color(0xFF4A1D0D), Color(0xFF160600)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: enabled ? null : Colors.grey.shade900,
        border: Border.all(
          color: enabled
              ? Colors.deepOrange.shade400.withOpacity(0.8)
              : Colors.grey.shade800,
          width: 1.4,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Colors.deepOrange.withOpacity(0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Icon(
        icon,
        color: enabled ? Colors.orangeAccent : Colors.grey.shade700,
        size: context.sp(24),
      ),
    );

    if (!enabled) return circle;

    return AnimatedTapButton(
      onTap: () {
        _playClickSound();
        onTap();
      },
      child: circle,
    );
  }

  // ------------------------------------------------------------------
  // SUPER POWER BUTTON — sits on the same bottom row as the page dots
  // (see _buildSkinCarousel), on the RIGHT side. Icon + glow color now
  // come straight from the ship's REAL super power (superPowerFor,
  // see ship_super_powers.dart) instead of the old flavor
  // abilityIcon, so this always matches what actually happens in a
  // level. A small lock badge appears in the corner while the power
  // hasn't been bought yet. Tapping it opens the purchase/detail
  // sheet — see _showSuperPowerSheet.
  // ------------------------------------------------------------------
  Widget _buildSuperPowerCircleButton() {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: ownedSuperPowerAssetsNotifier,
      builder: (context, ownedPowers, _) {
        final skin = _currentSkin;
        final power = superPowerFor(skin);
        final owned = isSuperPowerOwned(skin);

        return AnimatedTapButton(
          onTap: () {
            _playClickSound();
            _showSuperPowerSheet();
          },
          child: Container(
            width: context.sp(58),
            height: context.sp(58),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.55),
              border: Border.all(
                color: power.color.withOpacity(owned ? 0.9 : 0.5),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: power.color.withOpacity(owned ? 0.35 : 0.15),
                  blurRadius: 14,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  power.icon,
                  color: owned ? power.color : power.color.withOpacity(0.45),
                  size: context.sp(28),
                ),
                if (!owned)
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black87,
                      ),
                      child: Icon(
                        Icons.lock,
                        color: Colors.white70,
                        size: context.sp(10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Page indicator dots — centered under the ship. Every dot is a
  // plain circle, same shape for active and inactive — active just
  // gets a gold tint, a touch bigger, and a soft glow, instead of the
  // old elongated pill shape. Sits on a small dark backdrop so it
  // stays readable over any ship or background color.
  // ------------------------------------------------------------------
  Widget _buildDots() {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.wp(1.8), vertical: context.hp(0.5)),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(kSkins.length, (i) {
          final bool active = i == _currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 8 : 6,
            height: active ? 8 : 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active
                  ? const LinearGradient(
                      colors: [Color(0xFFFFC107), Color(0xFFB71C1C)],
                    )
                  : null,
              color: active ? null : Colors.grey.shade600,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.6),
                        blurRadius: 5,
                      ),
                    ]
                  : [],
            ),
          );
        }),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Stats card — ONLY the Health / Energy / Damage numbers now, no
  // buttons inside it. Values now reflect any upgrades bought on the
  // Upgrade page (via effectiveStatValue), rebuilding live off
  // upgradeLevelsNotifier. Upgrade and Buy/Select live in their own
  // row right underneath (see below), each bigger than they used to
  // be.
  // ------------------------------------------------------------------
  Widget _buildStatsSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.wp(5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: context.wp(4), vertical: context.hp(1.1)),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.deepOrange.shade900, width: 1),
            ),
            child: ValueListenableBuilder<Map<String, List<int>>>(
              valueListenable: upgradeLevelsNotifier,
              builder: (context, levels, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatBar(
                      icon: Icons.favorite,
                      color: Colors.redAccent,
                      label: 'HEALTH',
                      value: effectiveStatValue(_currentSkin, 0),
                    ),
                    SizedBox(height: context.hp(0.6)),
                    _buildStatBar(
                      icon: Icons.flash_on,
                      color: Colors.lightBlueAccent,
                      label: 'ENERGY',
                      value: effectiveStatValue(_currentSkin, 1),
                    ),
                    SizedBox(height: context.hp(0.6)),
                    _buildStatBar(
                      icon: Icons.gpp_maybe,
                      color: Colors.orangeAccent,
                      label: 'DAMAGE',
                      value: effectiveStatValue(_currentSkin, 2),
                    ),
                  ],
                );
              },
            ),
          ),

          SizedBox(height: context.hp(0.8)),

          // ---- Upgrade + Buy/Select — their own row, separate from
          //      the stats card, back to their original compact size
          //      (the bigger version overflowed the screen).
          Row(
            children: [
              Expanded(child: _buildUpgradeButton()),
              SizedBox(width: context.wp(3)),
              Expanded(child: _buildCompactSelectButton()),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // A single stat row — icon, label, and the actual number (e.g.
  // "HEALTH  800"), animated so it counts up/down when you switch
  // ships (or buy an upgrade). No bar/track anymore — this is a
  // readout, not a gauge (that visual style is reserved for the hull
  // ring above the ship).
  // ------------------------------------------------------------------
  Widget _buildStatBar({
    required IconData icon,
    required Color color,
    required String label,
    required int value,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: context.sp(13)),
        SizedBox(width: context.wp(1.5)),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: context.sp(9),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        AnimatedCounterText(
          value: value,
          style: TextStyle(
            color: Colors.white,
            fontSize: context.sp(11),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Upgrade button — lives in its own row below the stats card (not
  // inside it), sized back to its original compact look, and fills
  // half the row width via Expanded from _buildStatsSection. Now
  // navigates to the real UpgradePage (for the ship currently shown
  // in the carousel) instead of opening a placeholder dialog.
  // ------------------------------------------------------------------
  Widget _buildUpgradeButton() {
    return AnimatedTapButton(
      onTap: () {
        _playClickSound();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UpgradePage(initialSkin: _currentSkin),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.hp(0.8)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF4A1D0D), Color(0xFF160600)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.deepOrange.shade400.withOpacity(0.7),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.deepOrange.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upgrade, color: Colors.orangeAccent, size: context.sp(17)),
            SizedBox(height: context.hp(0.3)),
            Text(
              'Upgrade',
              style: TextStyle(
                color: Colors.white,
                fontSize: context.sp(8),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Buy / Select / Equipped button — same three states as before:
  // green check when equipped (not tappable), plain orange "SELECT"
  // when owned but not equipped, or the gem price in blue (grey if
  // unaffordable) when it still needs to be bought. Now lives in its
  // own row below the stats card instead of inside it.
  // ------------------------------------------------------------------
  Widget _buildCompactSelectButton() {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: ownedSkinAssetsNotifier,
      builder: (context, owned, _) {
        return ValueListenableBuilder<int>(
          valueListenable: gemsNotifier,
          builder: (context, gems, __) {
            final skin = _currentSkin;
            final bool isEquipped = _currentIndex == _selectedIndex;
            final bool isOwned = isSkinOwned(skin);

            if (isEquipped) {
              return _buildSquareActionButton(
                label: 'EQUIPPED',
                icon: Icons.check_circle,
                gradientColors: [Colors.green.shade600, Colors.green.shade900],
                onTap: null,
              );
            }

            if (isOwned) {
              return _buildSquareActionButton(
                label: 'SELECT',
                icon: Icons.touch_app,
                gradientColors: const [Color(0xFFFFC371), Color(0xFFFF5F3D)],
                onTap: _selectCurrent,
              );
            }

            final bool canAfford = gems >= skin.price;
            return _buildSquareActionButton(
              label: 'BUY • ${skin.price}',
              iconWidget: Image.asset(
                'assets/images/budget.png',
                width: context.sp(16),
                height: context.sp(16),
              ),
              gradientColors: canAfford
                  ? [Colors.lightBlueAccent.shade700, Colors.blue.shade900]
                  : [Colors.grey.shade700, Colors.grey.shade900],
              onTap: () => _confirmPurchase(skin),
            );
          },
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Shared action-button shell used by the Buy/Select/Equipped button
  // above (Upgrade has its own fixed look since it never changes
  // state). No fixed width anymore — both buttons fill their half of
  // the row (via Expanded in _buildStatsSection), sized back to their
  // original compact look.
  // ------------------------------------------------------------------
  Widget _buildSquareActionButton({
    required String label,
    IconData? icon,
    Widget? iconWidget,
    required List<Color> gradientColors,
    VoidCallback? onTap,
  }) {
    return AnimatedTapButton(
      onTap: onTap == null
          ? () {}
          : () {
              _playClickSound();
              onTap();
            },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.hp(0.8)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2),
          boxShadow: onTap == null
              ? []
              : [
                  BoxShadow(
                    color: gradientColors.last.withOpacity(0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (iconWidget != null)
              iconWidget
            else if (icon != null)
              Icon(icon, color: Colors.white, size: context.sp(16)),
            SizedBox(height: context.hp(0.3)),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontSize: context.sp(7.5),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Hull indicator — a plain BAR now, no icon: just a thin fill track
  // that grows/shrinks with [hull] (full bar = fully repaired, a
  // short bar = needs repair), wider than before so it reads clearly
  // at top-center. No number/percentage text. It listens to
  // [hullByAssetNotifier], so it reflects each ship's actual hull
  // value (defaults to 100, but updates instantly the moment anything
  // calls setHull() from a combat/repair system later), animating
  // smoothly between values. Color shifts through three real
  // thresholds — green, amber, red — and a small pulsing corner dot
  // marks it as a live reading. Tapping it tells you directly whether
  // the ship needs repair.
  // ------------------------------------------------------------------
  Widget _buildHullBadge() {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: hullByAssetNotifier,
      builder: (context, hullMap, _) {
        final skin = _currentSkin;
        final int hull = hullMap[skin.asset] ?? 100;

        final Color color;
        final String message;
        if (hull >= 70) {
          color = Colors.greenAccent;
          message = 'No repair needed right now.';
        } else if (hull >= 35) {
          color = Colors.orangeAccent;
          message = 'Hull is holding up, but repairs would help soon.';
        } else {
          color = Colors.redAccent;
          message = 'This ship needs repair!';
        }

        final double barWidth = context.wp(38);
        final double barHeight = context.sp(8);

        return AnimatedTapButton(
          onTap: () {
            _playClickSound();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: context.wp(2.5), vertical: context.hp(0.7)),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: color.withOpacity(0.85), width: 1.2),
                ),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: hull / 100),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedFraction, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: barWidth,
                        height: barHeight,
                        color: color.withOpacity(0.18),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: animatedFraction.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [color.withOpacity(0.7), color],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: -2,
                right: -2,
                child: _LiveDot(color: color),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Info sheet — flavor description for the ship currently shown in
  // the carousel.
  // ------------------------------------------------------------------
  void _showInfoSheet() {
    final skin = _currentSkin;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildDetailSheet(
        icon: Icons.info_outline,
        iconColor: Colors.orangeAccent,
        title: skin.name,
        body: skin.description,
      ),
    );
  }

  // ------------------------------------------------------------------
  // SUPER POWER sheet — replaces the old "Ability" sheet. Shows the
  // ship's REAL super power (name/description/duration/uses/price)
  // straight from ship_super_powers.dart, with a working Buy button
  // that spends coins via purchaseSuperPower. Rebuilds live off both
  // ownedSuperPowerAssetsNotifier and coinsNotifier so the sheet
  // updates immediately after a successful purchase without needing
  // to reopen it.
  // ------------------------------------------------------------------
  void _showSuperPowerSheet() {
    final skin = _currentSkin;
    final power = superPowerFor(skin);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ValueListenableBuilder<Set<String>>(
          valueListenable: ownedSuperPowerAssetsNotifier,
          builder: (context, ownedPowers, _) {
            return ValueListenableBuilder<int>(
              valueListenable: coinsNotifier,
              builder: (context, coins, __) {
                final owned = isSuperPowerOwned(skin);
                final shipOwned = isSkinOwned(skin);
                final canAfford = coins >= power.price;

                return _buildSuperPowerSheetContent(
                  power: power,
                  owned: owned,
                  shipOwned: shipOwned,
                  canAfford: canAfford,
                  onBuy: () {
                    _playClickSound();
                    final bought = purchaseSuperPower(skin);
                    if (!bought) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            !shipOwned
                                ? 'Unlock ${skin.name} first.'
                                : 'Not enough coins — ${power.name} costs ${power.price}.',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Content of the super power sheet — icon/name/description straight
  // from SuperPowerData, plus duration/uses-per-level readouts and an
  // OWNED badge or a BUY button depending on state.
  // ------------------------------------------------------------------
  Widget _buildSuperPowerSheetContent({
    required SuperPowerData power,
    required bool owned,
    required bool shipOwned,
    required bool canAfford,
    required VoidCallback onBuy,
  }) {
    final String durationLabel = power.activeDuration == null
        ? 'Rest of the level'
        : '${power.activeDuration!.inSeconds}s';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF160600),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: power.color.withOpacity(0.55), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: power.color.withOpacity(0.15),
                  border: Border.all(color: power.color.withOpacity(0.75)),
                ),
                child: Icon(power.icon, color: power.color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      power.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'SUPER POWER',
                      style: TextStyle(
                        color: power.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            power.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.timer_outlined, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Text(
                durationLabel,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.replay, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Text(
                '${power.usesPerLevel}x per level',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (owned)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.greenAccent, width: 1),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'OWNED',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: onBuy,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: (shipOwned && canAfford)
                        ? [power.color.withOpacity(0.9), power.color.withOpacity(0.55)]
                        : [Colors.grey.shade700, Colors.grey.shade900],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.25),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (shipOwned)
                      Image.asset(
                        'assets/images/coin.png',
                        width: 18,
                        height: 18,
                      )
                    else
                      const Icon(Icons.lock, color: Colors.white70, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      !shipOwned ? 'UNLOCK SHIP FIRST' : 'BUY • ${power.price}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Shared bottom-sheet shell used by the Info button — dark rounded
  // card, icon + title header, body text below.
  // ------------------------------------------------------------------
  Widget _buildDetailSheet({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF160600),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: Colors.deepOrange.shade900, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Budget / Coins stat card — copied to match the home page exactly.
  // Slightly darker/opaque now that it sits over the background image.
  // ------------------------------------------------------------------
  Widget _buildStatCard({
    required String iconAsset,
    required int value,
    bool showAddButton = false,
    double iconSize = 28,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepOrange.shade900, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            iconAsset,
            width: iconSize,
            height: iconSize,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
              ),
            ),
          ),
          if (showAddButton)
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange, width: 1.5),
              ),
              child: const Icon(Icons.add, color: Colors.orange, size: 16),
            ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// A tiny Flame game whose only job is to show one ship, big and
/// centered, with a live engine-flame trail — the same particle
/// effect used in the main game, just without patrol/drag/shooting.
/// A short, small vertical bob keeps it feeling alive without being
/// distracting. Transparent background so the background image shows
/// through underneath it.
///
/// Reused by both SkinsPage (in the skin carousel) and UpgradePage
/// (in the ship selector), so both screens render the same live
/// ship+flame preview.
/// ---------------------------------------------------------------------
class SkinPreviewGame extends FlameGame {
  final String shipAsset;
  final Color flameAccent;
  final double engineOffsetYFraction;
  final double flameSpread;
  final double flameParticleRadius;
  final double flameLength;
  late PreviewShip ship;

  SkinPreviewGame({
    required this.shipAsset,
    required this.flameAccent,
    required this.engineOffsetYFraction,
    required this.flameSpread,
    required this.flameParticleRadius,
    required this.flameLength,
  });

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final sprite = await loadSprite(shipAsset);
    ship = PreviewShip(sprite: sprite)
      ..anchor = Anchor.center
      ..setHome(Vector2(size.x / 2, size.y / 2 - 10));
    add(ship);
    add(PreviewEngineFlame(
      ship: ship,
      accentColor: flameAccent,
      engineOffsetYFraction: engineOffsetYFraction,
      spread: flameSpread,
      particleRadius: flameParticleRadius,
      length: flameLength,
    ));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      ship.setHome(Vector2(size.x / 2, size.y / 2 - 10));
    }
  }
}

/// Big, centered ship sprite with a short, small idle bob — moves a
/// few pixels up and down only, no scaling, so it reads as a calm
/// hover instead of a pulsing/breathing effect.
class PreviewShip extends SpriteComponent {
  Vector2 _home = Vector2.zero();
  double _time = 0;

  static const double bobAmplitude = 5; // short travel, top to bottom
  static const double bobSpeed = 1.8;

  PreviewShip({required Sprite sprite})
      : super(
          sprite: sprite,
          size: Vector2(240, 240), // big, centerpiece of the screen
          anchor: Anchor.center,
        );

  void setHome(Vector2 center) {
    _home = center.clone();
    position = center.clone();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    position.x = _home.x;
    position.y = _home.y + sin(_time * bobSpeed) * bobAmplitude;
  }
}

/// Engine-flame particle stream, generalized to track any ship-like
/// component so this preview doesn't need to depend on the gameplay
/// Ship class.
///
/// - `engineOffsetYFraction`: how far below the ship's center (as a
///   fraction of its height) the nozzle sits, so the flame lands
///   exactly at the visible tail instead of floating inside the hull.
/// - `spread`: how far particles jitter side-to-side. Small values
///   (~4) keep the flame narrow enough to fit in the gap between twin
///   tail fins; larger values (~18) read as a fuller, wider exhaust.
/// - `particleRadius`: base particle size, smaller for a tighter jet.
/// - `length`: scales particle lifetime and downward speed together,
///   so the trail reads as taller/longer without touching `spread`
///   (which only affects horizontal width).
class PreviewEngineFlame extends Component {
  final PreviewShip ship;
  final Color accentColor;
  final double engineOffsetYFraction;
  final double spread;
  final double particleRadius;
  final double length;
  final List<_FlameParticle> _particles = [];
  final Random _rng = Random();
  double _spawnTimer = 0;
  static const double spawnInterval = 0.02;

  PreviewEngineFlame({
    required this.ship,
    required this.accentColor,
    required this.engineOffsetYFraction,
    required this.spread,
    required this.particleRadius,
    this.length = 1.0,
  });

  @override
  void update(double dt) {
    super.update(dt);

    // Tracks ship.position every frame (including its idle bob), so
    // the flame stays glued exactly to the tail as the ship moves.
    final enginePos =
        ship.position + Vector2(0, ship.size.y * engineOffsetYFraction);

    _spawnTimer += dt;
    if (_spawnTimer >= spawnInterval) {
      _spawnTimer = 0;
      final life = (0.24 + _rng.nextDouble() * 0.14) * length;
      _particles.add(_FlameParticle(
        position: enginePos + Vector2((_rng.nextDouble() - 0.5) * spread, 0),
        velocity: Vector2(
          (_rng.nextDouble() - 0.5) * (spread * 0.6),
          (_rng.nextDouble() * 90 + 90) * length,
        ),
        life: life,
        radius: _rng.nextDouble() * (particleRadius * 0.6) + particleRadius,
      ));
    }

    for (final p in _particles) {
      p.position += p.velocity * dt;
      p.age += dt;
    }
    _particles.removeWhere((p) => p.age >= p.life);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (final p in _particles) {
      final t = (p.age / p.life).clamp(0.0, 1.0);
      final color = Color.lerp(Colors.white, accentColor, t.clamp(0.0, 1.0)) ??
          accentColor;
      final paint = Paint()..color = color.withOpacity((1 - t) * 0.85);
      canvas.drawCircle(
        p.position.toOffset(),
        p.radius * (1 - t * 0.7),
        paint,
      );
    }
  }
}

class _FlameParticle {
  Vector2 position;
  final Vector2 velocity;
  double age = 0;
  final double life;
  final double radius;

  _FlameParticle({
    required this.position,
    required this.velocity,
    required this.life,
    required this.radius,
  });
}

/// ---------------------------------------------------------------------
/// Small pulsing dot used by the hull badge to signal "this is a live
/// reading", not a static label — a slow, continuous opacity breathe,
/// tinted to match whatever status color the badge is currently
/// showing (green/orange/red).
/// ---------------------------------------------------------------------
class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({Key? key, required this.color}) : super(key: key);

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.8),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// Same springy tap-scale wrapper used on the home page's buttons —
/// duplicated here so this file is self-contained. If you already
/// export it from a shared widgets file, delete this copy and import
/// that one instead to avoid two definitions in your project.
/// ---------------------------------------------------------------------
class AnimatedTapButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const AnimatedTapButton({
    Key? key,
    required this.child,
    required this.onTap,
  }) : super(key: key);

  @override
  State<AnimatedTapButton> createState() => _AnimatedTapButtonState();
}

class _AnimatedTapButtonState extends State<AnimatedTapButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}