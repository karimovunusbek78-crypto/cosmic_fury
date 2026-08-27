import 'package:flutter/material.dart';

// Pulls in SkinData / kSkins / skinIndexOf / isSkinOwned / coinsNotifier —
// super powers are keyed 1:1 to a skin (same index as kSkins/kStatCaps),
// bought with COINS (not gems, unlike the skins themselves), and can only
// be bought once the ship itself is owned.
// Adjust this import if skins_page.dart lives somewhere else in your
// project.
import 'package:cosmic_fury/src/pages/skins/skins_page.dart';

/// ---------------------------------------------------------------------
/// Static definition of one ship's super power — the flavor/price/UI
/// side. The actual gameplay MECHANICS for each power are implemented
/// in [SuperPowerController] below (and consumed from main_game_page.dart
/// / level_page.dart / enemy.dart) — this class only carries what the
/// Skins page needs to sell it and what the level HUD needs to display
/// it.
///
/// `activeDuration` — how long the power stays active once triggered.
/// `null` is special-cased to mean "lasts the rest of the level" (used
/// only by the Falcon's Overcharge Core).
///
/// `usesPerLevel` — how many times this power can be triggered in a
/// single level. Every power currently defined here is a single-use
/// (1) per level, refilling automatically the next time a level starts.
/// ---------------------------------------------------------------------
class SuperPowerData {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final int price;
  final Duration? activeDuration;
  final int usesPerLevel;

  const SuperPowerData({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.price,
    this.activeDuration,
    this.usesPerLevel = 1,
  });
}

/// One entry per ship, in the exact same order as [kSkins] /
/// [kStatCaps] — index 0 is the Falcon, index 4 is Shadow Reaper.
const List<SuperPowerData> kSuperPowers = [
  // ---- Falcon Mk.I: Overcharge Core ----------------------------------
  // Doubles the ship's max energy capacity for the ENTIRE level (not a
  // short timed burst like the others) — e.g. 20 energy becomes 40.
  // Triggered once, it simply stays on until the level ends.
  SuperPowerData(
    name: 'Overcharge Core',
    description:
        "Overloads the Falcon's reactor, doubling its maximum energy "
        "capacity for the rest of the level — twice the shots before "
        "the guns ever need to recharge.",
    icon: Icons.battery_charging_full_rounded,
    color: Colors.lightBlueAccent,
    price: 4000,
    activeDuration: null, // whole level
    usesPerLevel: 1,
  ),

  // ---- Interceptor: Twin Fang -----------------------------------------
  // For 50 seconds, every 3rd shot cycle also launches an extra, bigger
  // bolt that homes in on the nearest enemy, deals double damage, and
  // can't miss (it re-aims every frame and applies damage directly the
  // instant it closes in, so it's guaranteed to reach its target).
  SuperPowerData(
    name: 'Twin Fang',
    description:
        'For 50 seconds, every third shot is followed by a larger, '
        'homing bolt that locks onto the nearest enemy, chases it down, '
        'deals double damage, and never misses.',
    icon: Icons.gps_fixed_rounded,
    color: Colors.deepOrangeAccent,
    price: 7000,
    activeDuration: Duration(seconds: 50),
    usesPerLevel: 1,
  ),

  // ---- Nebula: Aegis Barrier -------------------------------------------
  // A barrier across the vertical center of the screen for 50 seconds.
  // Any enemy fire that reaches the player while it's up is halved.
  SuperPowerData(
    name: 'Aegis Barrier',
    description:
        'Raises a shimmering barrier across the center of the screen for '
        '50 seconds. Any enemy fire that gets through it deals half '
        'damage.',
    icon: Icons.shield_rounded,
    color: Color(0xFFB39DFF),
    price: 11000,
    activeDuration: Duration(seconds: 50),
    usesPerLevel: 1,
  ),

  // ---- Frostbyte: Absolute Zero -----------------------------------------
  // Slows every enemy on screen to a third speed for 30 seconds, AND
  // slows the player's own outgoing bullets to a third speed too (see
  // SuperPowerController.playerBulletSpeedMultiplier, read by Ship when
  // it spawns a Bullet).
  SuperPowerData(
    name: 'Absolute Zero',
    description:
        'Chills the battlefield for 30 seconds, slowing every enemy '
        'currently on screen (and any that arrive while it\'s active) — '
        'and even your own shots — to a third of their normal speed.',
    icon: Icons.ac_unit_rounded,
    color: Colors.lightBlueAccent,
    price: 16000,
    activeDuration: Duration(seconds: 30),
    usesPerLevel: 1,
  ),

  // ---- Shadow Reaper: Void Collapse --------------------------------------
  // Instant heavy AOE damage to every enemy on screen, then 5 seconds of
  // total invulnerability while the ship "vanishes" into the void.
  SuperPowerData(
    name: 'Void Collapse',
    description:
        'Detonates an instant shockwave that slams every enemy on screen '
        'for 500 damage, then cloaks the ship in an untouchable void — '
        'immune to all damage — for 5 seconds.',
    icon: Icons.brightness_3_rounded,
    color: Color(0xFF8A5CFF),
    price: 24000,
    activeDuration: Duration(seconds: 5),
    usesPerLevel: 1,
  ),
];

/// The super power that belongs to [skin] — same index as kSkins.
SuperPowerData superPowerFor(SkinData skin) => kSuperPowers[skinIndexOf(skin)];

/// ---------------------------------------------------------------------
/// Ownership + purchasing — mirrors the shape of ownedSkinAssetsNotifier
/// / purchaseSkin in skins_page.dart, but keyed to the SUPER POWER (not
/// the skin itself), spent in COINS (not gems), and gated behind the
/// ship already being owned: you can't buy a ship's super power before
/// you've bought the ship.
/// ---------------------------------------------------------------------
final ValueNotifier<Set<String>> ownedSuperPowerAssetsNotifier =
    ValueNotifier<Set<String>>({});

/// Whether [skin]'s super power has been bought.
bool isSuperPowerOwned(SkinData skin) =>
    ownedSuperPowerAssetsNotifier.value.contains(skin.asset);

/// Whether [skin]'s super power is currently purchasable — the ship
/// itself has to be unlocked first, and it can't already be owned.
bool canPurchaseSuperPower(SkinData skin) =>
    isSkinOwned(skin) && !isSuperPowerOwned(skin);

/// Attempts to buy [skin]'s super power with coins. Returns true if it
/// ends up owned (already was, or the purchase just succeeded); false
/// if the ship itself isn't unlocked yet, or there aren't enough coins.
bool purchaseSuperPower(SkinData skin) {
  if (!isSkinOwned(skin)) return false; // ship must be unlocked first
  if (isSuperPowerOwned(skin)) return true;

  final power = superPowerFor(skin);
  if (coinsNotifier.value < power.price) return false;

  coinsNotifier.value -= power.price;
  ownedSuperPowerAssetsNotifier.value = {
    ...ownedSuperPowerAssetsNotifier.value,
    skin.asset,
  };
  return true;
}

/// ---------------------------------------------------------------------
/// Small hook interface so this file (and SuperPowerController below)
/// never needs to import main_game_page.dart's EnergySystem directly —
/// that would create a needless coupling between the "what powers
/// exist" file and the gameplay engine file. LevelPage wires the real
/// implementation in via a tiny adapter that just calls
/// EnergySystem.applyCapMultiplier under the hood.
/// ---------------------------------------------------------------------
abstract class EnergySystemCapHook {
  void applyMultiplier(double multiplier);
}

/// ---------------------------------------------------------------------
/// Runtime controller for a single level's super power usage — one
/// instance per LevelPage, built fresh every time a level starts (so
/// uses always refill). Mirrors the shape of SpellCastController
/// (spells_animations.dart): it owns the timers/state and exposes
/// everything the HUD button and the actual gameplay hooks (Ship,
/// EnergySystem, WaveManager) need to query every frame.
///
/// Which power applies is derived entirely from [skin] (whichever ship
/// was equipped when the level started) via [superPowerFor] — there is
/// only ever one power "live" per level, matching the one super power a
/// player actually flies with.
/// ---------------------------------------------------------------------
class SuperPowerController {
  final SkinData skin;
  final ValueChanged<String>? onSnack;
  final VoidCallback? onStateChanged;

  /// Lets Falcon's Overcharge Core reach into the level's EnergySystem
  /// and actually double its cap. Null for any other ship (never used).
  final EnergySystemCapHook? energyCapHook;

  /// Called exactly once, synchronously, the instant Shadow Reaper's
  /// Void Collapse triggers — the level page implements this by dealing
  /// its nova damage to every enemy currently on screen.
  final VoidCallback? onVoidNova;

  late final SuperPowerData data;
  late final int skinIndex;

  final ValueNotifier<int> usesRemainingNotifier;
  final ValueNotifier<bool> activeNotifier = ValueNotifier<bool>(false);

  /// Seconds left on the current activation. -1 is a special value
  /// meaning "active for the rest of the level" (Falcon), which the HUD
  /// should render as e.g. "ACTIVE" instead of a countdown.
  final ValueNotifier<double> remainingSecondsNotifier =
      ValueNotifier<double>(0);

  double _timer = 0;
  bool _wholeLevelActive = false; // Falcon only

  // Interceptor's Twin Fang — counts normal shot cycles fired while
  // active; every 3rd one also spawns a homing bolt.
  int _shotsSinceHoming = 0;

  SuperPowerController({
    required this.skin,
    this.onSnack,
    this.onStateChanged,
    this.energyCapHook,
    this.onVoidNova,
  }) : usesRemainingNotifier = ValueNotifier<int>(
          isSuperPowerOwned(skin) ? superPowerFor(skin).usesPerLevel : 0,
        ) {
    data = superPowerFor(skin);
    skinIndex = skinIndexOf(skin);
  }

  bool get isOwned => isSuperPowerOwned(skin);

  bool get canActivate =>
      isOwned && usesRemainingNotifier.value > 0 && !activeNotifier.value;

  /// Triggers this level's super power for the equipped ship. Returns
  /// true if it actually activated.
  bool activate() {
    if (!canActivate) return false;

    usesRemainingNotifier.value -= 1;
    activeNotifier.value = true;
    _timer = 0;

    switch (skinIndex) {
      case 0: // Falcon — Overcharge Core: doubles max energy, whole level.
        _wholeLevelActive = true;
        energyCapHook?.applyMultiplier(2.0);
        remainingSecondsNotifier.value = -1; // "rest of the level"
        onSnack?.call(
            'Overcharge Core online — energy capacity doubled for the level!');
        break;

      case 1: // Interceptor — Twin Fang, 50s.
        _shotsSinceHoming = 0;
        remainingSecondsNotifier.value =
            data.activeDuration!.inSeconds.toDouble();
        onSnack?.call('Twin Fang engaged — every third shot now hunts!');
        break;

      case 2: // Nebula — Aegis Barrier, 50s.
        remainingSecondsNotifier.value =
            data.activeDuration!.inSeconds.toDouble();
        onSnack?.call('Aegis Barrier raised — incoming fire is halved!');
        break;

      case 3: // Frostbyte — Absolute Zero, 30s.
        remainingSecondsNotifier.value =
            data.activeDuration!.inSeconds.toDouble();
        onSnack?.call('Absolute Zero unleashed — the enemy fleet is chilled!');
        break;

      case 4: // Shadow Reaper — Void Collapse: instant nova + 5s invuln.
        remainingSecondsNotifier.value =
            data.activeDuration!.inSeconds.toDouble();
        onVoidNova?.call();
        onSnack?.call('Void Collapse! The ship slips into the void...');
        break;
    }

    onStateChanged?.call();
    return true;
  }

  /// Call every frame from the level's game loop (see
  /// _LevelFlameGame.update in level_page.dart).
  void update(double dt) {
    if (!activeNotifier.value) return;

    // Falcon's power has no timer — it simply lasts until the level
    // ends, so there's nothing to tick down here. LevelPage never
    // calls _deactivate for it; it just stays true and the level
    // itself gets torn down when the level ends.
    if (_wholeLevelActive) return;

    _timer += dt;
    final total = data.activeDuration!.inSeconds.toDouble();
    final remaining = (total - _timer).clamp(0.0, total);
    remainingSecondsNotifier.value = remaining;

    if (_timer >= total) {
      _deactivate();
    }
  }

  void _deactivate() {
    activeNotifier.value = false;
    remainingSecondsNotifier.value = 0;
    onStateChanged?.call();
  }

  // ---- Interceptor: Twin Fang -----------------------------------------
  bool get twinFangActive => skinIndex == 1 && activeNotifier.value;

  /// Call once per shot CYCLE (not per individual bullet — a twin-gun
  /// ship firing two bullets at once still counts as one cycle) from
  /// Ship.update(). Returns true on every 3rd cycle while Twin Fang is
  /// active, telling the caller to also spawn a homing bolt. The
  /// homing bolt itself (HomingBullet, main_game_page.dart) re-aims at
  /// the nearest enemy every frame and applies its damage directly the
  /// instant it closes to hit range — so once this returns true, that
  /// shot is a guaranteed, 100%-chasing hit.
  bool registerBulletForHoming() {
    if (!twinFangActive) return false;
    _shotsSinceHoming++;
    if (_shotsSinceHoming >= 3) {
      _shotsSinceHoming = 0;
      return true;
    }
    return false;
  }

  // ---- Nebula: Aegis Barrier -------------------------------------------
  bool get barrierActive => skinIndex == 2 && activeNotifier.value;
  static const double barrierDamageMultiplier = 0.5;

  // ---- Frostbyte: Absolute Zero -----------------------------------------
  bool get enemySlowActive => skinIndex == 3 && activeNotifier.value;
  static const double enemySlowMultiplier = 1 / 3;

  /// Same 1/3 multiplier, exposed for the PLAYER'S OWN bullets — Ship
  /// reads this every time it spawns a Bullet (see main_game_page.dart)
  /// so Absolute Zero slows the player's outgoing fire too, not just
  /// enemy movement/dodging. 1.0 (no change) whenever Absolute Zero
  /// isn't active/owned.
  double get playerBulletSpeedMultiplier =>
      enemySlowActive ? enemySlowMultiplier : 1.0;

  // ---- Shadow Reaper: Void Collapse --------------------------------------
  bool get isInvulnerable => skinIndex == 4 && activeNotifier.value;

  /// Flat damage dealt to every enemy on screen the instant Void
  /// Collapse triggers (see onVoidNova / WaveManager.dealDamageToAllEnemies).
  static const double voidNovaDamage = 500;

  void dispose() {
    usesRemainingNotifier.dispose();
    activeNotifier.dispose();
    remainingSecondsNotifier.dispose();
  }
}