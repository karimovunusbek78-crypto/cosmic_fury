import 'dart:math';

import 'package:cosmic_fury/src/pages/main/level_pages/ship_super_powers.dart';
import 'package:cosmic_fury/src/pages/main/pages/mode_select_page.dart';
import 'package:cosmic_fury/src/pages/shop/shop_page.dart';
import 'package:cosmic_fury/src/pages/skins/skins_page.dart';
import 'package:cosmic_fury/src/pages/upgrade/upgrade_page.dart';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/parallax.dart';
import 'package:flame_audio/flame_audio.dart'; // <-- background music + click SFX

// Pulls in SkinData / kSkins / equippedSkin so this page can build the
// ship the player currently has equipped. Also pulls in gemsNotifier /
// coinsNotifier, the shared currency state used by the stat cards
// below, and effectiveStatValue — the ship's CURRENT (post-upgrade)
// stat, folding in whatever's been bought on the Upgrade page — used
// by Ship.update() below so fired bullets actually deal upgraded
// damage instead of always using the skin's raw base `damage` field.
// Adjust the path to wherever skins_page.dart actually lives in your
// project.

// Pulls in SuperPowerController — the runtime state machine for each
// ship's unique super power (see ship_super_powers.dart). MyFlameGame
// and Ship both hold an optional reference to one, supplied by the
// level (the main-menu preview ship never gets one, same pattern as
// EnergySystem below).

/// ------------------------------------------------------------
/// RENDER ORDER — every visual layer in this game is given an
/// explicit, fixed `priority` (higher = drawn on top). This matters
/// because several layers are added to the game asynchronously
/// (background parallax load, ship sprite load) and Flame's default
/// behavior for equal-priority components is "whoever gets added
/// first renders first (i.e. underneath)". Without explicit
/// priorities, the background and the ship were racing each other:
/// most of the time the ship's single sprite loaded faster than the
/// parallax background and ended up on top like normal, but
/// sometimes the background finished loading/adding AFTER the ship
/// and painted right over it — while bullets (always added well
/// after both, once you actually start shooting) kept rendering
/// fine. That's exactly the "ship invisible, bullets still show up"
/// bug. Fixed priorities make draw order deterministic no matter
/// which async load wins the race.
/// ------------------------------------------------------------
class RenderPriority {
  static const int background = -100;
  static const int starField = -50;
  static const int engineFlame = 5;
  static const int laserBeam = 8;
  static const int ship = 10;
  static const int bullet = 20;
}

/// ------------------------------------------------------------
/// ENERGY SYSTEM — governs how much the player can shoot before
/// the guns need to recharge. Lives here (rather than in
/// level_pages.dart) because [Ship] — the thing that actually
/// fires bullets — needs a direct reference to it, and Ship lives
/// in this file.
///
/// Rules:
/// - capacity = the equipped skin's maxEnergy stat (see [baseMaxEnergy]
///   / [maxEnergy] below — the Falcon's Overcharge Core super power can
///   raise the LIVE cap above the base one for the rest of a level)
/// - BULLET ships: every 3rd bullet fired costs 1 energy (Ship.update()
///   calls registerShot() once per bullet actually spawned)
/// - BEAM ships (skin.bulletBeam == true, e.g. Frostbyte): there are
///   no discrete bullets to hook a per-shot cost into, so instead
///   energy drains continuously at [EnergySystem.continuousDrainPerSecond]
///   per second of active beam time — see [LaserBeam.update], which
///   calls [registerContinuousFire] every frame it's actually on.
/// - hitting 0 locks firing (`canFire == false`) and starts an
///   auto-recharge of 10 energy every 5 seconds (2/sec) until full
/// - the player can ALSO lock firing manually via [stopFiring] —
///   e.g. to bank remaining energy and let it recharge on purpose,
///   without having to burn the guns dry first. This uses the exact
///   same recharge cycle as running out naturally.
/// - once there's at least [reactivateThreshold] energy banked
///   (not necessarily a full bar), `readyNotifier` flips true and
///   the player can tap the FIRE pill in the HUD to re-arm the guns
///   early. It still doesn't resume firing on its own.
/// - fire cadence (seconds between shots) is tunable at runtime via
///   [setShootInterval] / [shootIntervalNotifier], driven by the
///   RATE pill in the HUD. This only applies to bullet ships — beam
///   ships have no cadence to tune (see level_page.dart, which hides
///   the RATE pill entirely for bulletBeam skins).
/// - a spell (Spark Shot, see level_page.dart) can put this system
///   into [setFreeFire] mode: while active, [registerShot] AND
///   [registerContinuousFire] are both complete no-ops — no energy
///   is read, spent, or re-pinned, and the gun/beam simply cannot
///   lock up. This is intentionally the ONLY mechanism a spell needs
///   to grant "free" firing; there is no per-frame forcing/pinning
///   of the energy value anywhere.
/// - separately, the Falcon's OVERCHARGE CORE super power (see
///   ship_super_powers.dart) can call [applyCapMultiplier] to raise
///   [maxEnergy] above [baseMaxEnergy] for the rest of a level (and
///   tops the bar off as an immediate bonus when it kicks in) — e.g.
///   20 base energy becomes 40, refilled instantly, for the whole
///   level. This is completely independent of free-fire — energy is
///   still spent normally, there's just more of it to spend.
/// ------------------------------------------------------------
class EnergySystem {
  /// The ship's un-modified max energy — whatever effectiveStatValue
  /// reported for the Energy stat when the level started. Never
  /// changes after construction; [maxEnergy] is what everything else
  /// should actually read/clamp against, since it reflects any
  /// super-power multiplier currently in effect.
  final double baseMaxEnergy;

  /// The ship's CURRENT max energy — starts equal to [baseMaxEnergy],
  /// and can be raised (never lowered) for the rest of a level by
  /// [applyCapMultiplier] (Falcon's Overcharge Core).
  double maxEnergy;

  double _energy;
  bool _depleted = false;
  bool _manuallyStopped = false;
  int _bulletsSinceUse = 0;
  double _rechargeTimer = 0;

  static const double rechargeAmount = 10;
  static const double rechargeSeconds = 5;

  /// Once at least this much energy is banked, the FIRE pill becomes
  /// tappable — the player doesn't have to wait for a full recharge,
  /// just enough energy to actually fire again.
  static const double reactivateThreshold = 1.0;

  /// Continuous per-second energy drain used by BEAM-type ships
  /// (bulletBeam skins, e.g. Frostbyte) — see [registerContinuousFire].
  static const double continuousDrainPerSecond = 2.0;

  final ValueNotifier<double> energyNotifier;
  final ValueNotifier<bool> depletedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> readyNotifier = ValueNotifier<bool>(false);

  /// Seconds between each bullet the ship fires. Mutable at runtime
  /// — the RATE pill in the HUD cycles this through presets (e.g.
  /// 1s, 0.5s, 0.25s, 0.1s) so the player can tune fire cadence live.
  /// Meaningless for beam ships (no discrete shots), so the HUD hides
  /// the RATE pill for those skins.
  final ValueNotifier<double> shootIntervalNotifier;

  /// While true, [registerShot] and [registerContinuousFire] both do
  /// absolutely nothing — energy is never read, never spent, the gun
  /// can never lock up, and nothing about the displayed energy value
  /// is touched either. Set/cleared exclusively via [setFreeFire].
  /// This is what backs the Spark Shot spell: for its duration the
  /// ship just shoots (or beams), full stop, with energy completely
  /// out of the picture.
  bool _freeFireActive = false;

  EnergySystem({
    required this.baseMaxEnergy,
    double initialShootInterval = 0.35,
  })  : maxEnergy = baseMaxEnergy,
        _energy = baseMaxEnergy,
        energyNotifier = ValueNotifier<double>(baseMaxEnergy),
        shootIntervalNotifier = ValueNotifier<double>(initialShootInterval);

  /// Whether the game/shooting code should currently allow bullets
  /// (or, for beam ships, whether the beam should currently be
  /// on/dealing damage). Free-fire always allows firing, regardless
  /// of the underlying depleted state.
  bool get canFire => _freeFireActive || !_depleted;

  /// Sets how often (in seconds) the ship fires. Clamped so it can
  /// never be 0/negative (instant-fire) or absurdly slow. No-op in
  /// practice for beam ships since they never read shootIntervalNotifier.
  void setShootInterval(double seconds) {
    shootIntervalNotifier.value = seconds.clamp(0.05, 5.0);
  }

  /// Turns free-fire mode on/off.
  ///
  /// Turning it ON immediately un-jams the guns if they happened to
  /// be depleted/manually-stopped — the player never has to sit
  /// through a "still recharging" gap right as the spell starts.
  /// Nothing else about the current energy value is changed: it
  /// simply stops being consulted at all while active.
  ///
  /// Turning it OFF hands control straight back to the normal
  /// depleted/recharge state exactly as it was before the spell
  /// touched anything (registerShot/registerContinuousFire resume
  /// spending energy as usual on the very next qualifying
  /// shot/frame).
  void setFreeFire(bool active) {
    _freeFireActive = active;
    if (active) {
      _manuallyStopped = false;
      _depleted = false;
      depletedNotifier.value = false;
      readyNotifier.value = false;
      _bulletsSinceUse = 0;
    }
  }

  /// Applied by Falcon's "Overcharge Core" super power — multiplies
  /// [baseMaxEnergy] (2.0 = double capacity) and stores the result in
  /// [maxEnergy] for the rest of the level, refilling to that new max
  /// immediately as a bonus. See SuperPowerController in
  /// ship_super_powers.dart, which calls this exactly once, through
  /// the small EnergySystemCapHook adapter LevelPage builds.
  void applyCapMultiplier(double multiplier) {
    maxEnergy = baseMaxEnergy * multiplier;
    _energy = maxEnergy;
    energyNotifier.value = _energy;
  }

  /// Call this once for every bullet the player actually fires.
  /// Hooked into [Ship.update] wherever a Bullet is actually spawned
  /// from player input. Only used by BULLET ships — beam ships use
  /// [registerContinuousFire] instead, since they never spawn
  /// discrete Bullets to call this from.
  void registerShot() {
    // Free-fire: completely bypassed. No energy read, no energy
    // spent, no notifier touched — the spell's bullets truly cost
    // nothing while this is active.
    if (_freeFireActive) return;

    if (_depleted) return;

    _bulletsSinceUse++;
    if (_bulletsSinceUse < 3) return;
    _bulletsSinceUse = 0;

    _energy = (_energy - 1).clamp(0, maxEnergy);
    energyNotifier.value = _energy;

    if (_energy <= 0 && !_depleted) {
      _depleted = true;
      depletedNotifier.value = true;
      readyNotifier.value = false;
      _rechargeTimer = 0;
    }
  }

  /// Continuous per-second energy drain used by BEAM-type ships
  /// (bulletBeam skins, e.g. Frostbyte) instead of [registerShot]'s
  /// per-bullet accounting — a beam never fires discrete "shots" to
  /// hook a per-bullet cost into, it just streams continuously, so
  /// it costs energy continuously instead: [continuousDrainPerSecond]
  /// energy per second of active beam time. Call this once per frame
  /// (with that frame's dt) for as long as the beam is actually
  /// meant to be on/dealing damage — see [LaserBeam.update].
  ///
  /// Mirrors [registerShot]'s free-fire/depleted short-circuits so
  /// Spark Shot and the depleted-lockout behave identically for beam
  /// ships as they do for bullet ships.
  void registerContinuousFire(double dt) {
    if (_freeFireActive) return;
    if (_depleted) return;

    _energy = (_energy - continuousDrainPerSecond * dt).clamp(0, maxEnergy);
    energyNotifier.value = _energy;

    if (_energy <= 0 && !_depleted) {
      _depleted = true;
      depletedNotifier.value = true;
      readyNotifier.value = false;
      _rechargeTimer = 0;
    }
  }

  /// Player-triggered stop (the STOP pill in the HUD) — cuts firing
  /// off immediately, however much energy is left, and kicks off the
  /// same recharge cycle a natural 0-energy depletion would. Lets the
  /// player bank energy on purpose instead of only recovering after
  /// running the guns dry. No-op while free-fire is active (there's
  /// nothing to stop/bank).
  void stopFiring() {
    if (_freeFireActive) return;
    if (_depleted) return;
    _manuallyStopped = true;
    _depleted = true;
    depletedNotifier.value = true;
    // If there's already enough energy banked, FIRE can be tapped
    // again immediately instead of waiting a frame for update() to
    // notice.
    readyNotifier.value = _energy >= reactivateThreshold;
    _rechargeTimer = 0;
    _bulletsSinceUse = 0;
  }

  /// Call every frame — wired into _LevelFlameGame.update(). Recharge
  /// still runs normally even during free-fire (nothing above stops
  /// it), it just won't matter to firing until free-fire ends.
  void update(double dt) {
    if (!_depleted) return;

    _rechargeTimer += dt;
    final gainPerSecond = rechargeAmount / rechargeSeconds;
    _energy = (_energy + gainPerSecond * dt).clamp(0, maxEnergy);
    energyNotifier.value = _energy;

    // FIRE becomes tappable as soon as enough energy is banked to
    // actually fire again — not only once the bar is completely full.
    if (_energy >= reactivateThreshold && !readyNotifier.value) {
      readyNotifier.value = true;
    }
  }

  /// Player tapped the FIRE pill after enough energy is banked (full
  /// recharge no longer required) — re-arms the guns. No-op if
  /// there isn't at least [reactivateThreshold] energy yet.
  void reactivate() {
    if (!readyNotifier.value) return;
    _depleted = false;
    _manuallyStopped = false;
    depletedNotifier.value = false;
    readyNotifier.value = false;
    _bulletsSinceUse = 0;
  }

  void dispose() {
    energyNotifier.dispose();
    depletedNotifier.dispose();
    readyNotifier.dispose();
    shootIntervalNotifier.dispose();
  }
}

/// ---------------------------------------------------------------------
/// Flame game instance. This is the actual "game world" rendered by
/// Flame. Keep your game logic / components / sprites here. The Flutter
/// UI (profile header, budget & coins panels) is drawn as a normal
/// Flutter overlay on TOP of the GameWidget, which is the standard
/// pattern when you want a Flame canvas + native Flutter HUD.
/// ---------------------------------------------------------------------
class MyFlameGame extends FlameGame {
  /// Defaults preserve MainGamePage exactly. LevelPage supplies different
  /// values without duplicating ship, bullet, beam, or flame code.
  final double shipScale;
  final double flameScale;
  final double projectileScale;
  final bool autoPatrol;
  final double dragTopLimitFraction;
  final bool stopMusicOnRemove;

  /// If true (the main menu default), onLoad() loads + plays
  /// `main.mp3` as this game's own background track. LevelPage sets
  /// this to false, because LevelPage already starts/stops
  /// `battle.mp3` itself at the Flutter widget layer — without this
  /// flag, MyFlameGame.onLoad() was ALSO loading and playing
  /// main.mp3 on top of it, which (a) silently swapped the level's
  /// battle music back to menu music the instant onLoad finished,
  /// and (b) wasted real load time decoding an audio file the level
  /// never wanted, which is exactly what showed up as a 1-2s stall
  /// before waves started spawning (WaveManager isn't added until
  /// this onLoad fully resolves).
  final bool playDefaultMusic;

  /// Optional energy gate for the player's guns. Null on the main
  /// menu ship (unlimited fire); set by _LevelFlameGame for actual
  /// levels. Mutable (not final) so a subclass can assign it in its
  /// own constructor body before onLoad ever runs.
  EnergySystem? energySystem;

  /// Optional super-power state machine for the equipped ship. Null
  /// on the main-menu preview ship (no super powers there); set by
  /// _LevelFlameGame for actual levels. Same mutability pattern as
  /// [energySystem] above. Ship reads this to know whether to spawn
  /// Twin Fang's homing bolts; EnergySystem is reached separately via
  /// the EnergySystemCapHook adapter LevelPage builds (Falcon's
  /// Overcharge Core), not through this field.
  SuperPowerController? superPowerController;

  MyFlameGame({
    this.shipScale = 1.0,
    this.flameScale = 1.0,
    this.projectileScale = 1.0,
    this.autoPatrol = true,
    this.dragTopLimitFraction = 0.0,
    this.stopMusicOnRemove = true,
    this.playDefaultMusic = true,
    this.energySystem,
    this.superPowerController,
  });

  // Not `final` anymore — both get reassigned whenever the equipped
  // skin changes (see _spawnShipForEquippedSkin / _onEquippedSkinChanged).
  late Ship ship;
  late EngineFlame _engineFlame;
  LaserBeam? _laserBeam; // only present for skins with bulletBeam: true

  /// Public accessor for [_laserBeam] — WaveManager (enemy.dart, a
  /// different library) needs to read its hit box / active state /
  /// per-second damage rate every frame to actually apply beam
  /// damage to enemies. _laserBeam itself stays private since
  /// nothing outside this file needs to construct or replace it
  /// directly.
  LaserBeam? get laserBeam => _laserBeam;

  /// Overridable hook: returns the position of the nearest active
  /// enemy to [from], or null if there are none. The base
  /// implementation (used by the main-menu preview, which has no
  /// enemies) always returns null. _LevelFlameGame overrides this to
  /// query WaveManager's active enemy list — kept here as a virtual
  /// method instead of a hard Enemy-typed field so THIS file never
  /// needs to import enemy.dart (which already imports this file,
  /// and Dart would rather not need the cycle).
  Vector2? findNearestEnemyPosition(Vector2 from) => null;

  /// Overridable hook: applies [damage] directly to whichever enemy
  /// is at (or very near) [position] — used by [HomingBullet], which
  /// "never misses": rather than resolving a hitbox overlap, it
  /// simply strikes whatever [findNearestEnemyPosition] steered it
  /// toward. No-op by default; _LevelFlameGame overrides it to reach
  /// WaveManager.
  void damageEnemyAt(Vector2 position, double damage) {}

  /// Overridable hook: applies [damage] to EVERY currently-active
  /// enemy on screen at once — used by Shadow Reaper's Void Collapse
  /// super power (see ship_super_powers.dart / level_page.dart),
  /// which detonates an instant shockwave the moment it's triggered.
  /// No-op by default; _LevelFlameGame overrides it to reach
  /// WaveManager.
  void damageAllEnemies(double damage) {}

  /// Overridable hook: applies [damage] to EVERY currently-active
  /// enemy whose hit box overlaps [rect], skipping any enemy already
  /// present in [excludeHandles] (opaque per-enemy identity tokens —
  /// in practice the WaveManager-side [Enemy] objects themselves —
  /// previously returned by an earlier call to this same method for
  /// the same bullet). This is what lets [HomingBullet] (Interceptor's
  /// Twin Fang) pierce clean through an entire line of enemies —
  /// damaging every single one its own hit box touches while it
  /// flies, not just whichever enemy it happened to be steering
  /// toward — without re-damaging the same enemy on every frame it's
  /// still overlapping it. Returns the enemies that were actually hit
  /// THIS call, so the caller can fold them into its running exclude
  /// set for next frame. Empty by default; _LevelFlameGame overrides
  /// it to reach WaveManager.
  List<Object> damageEnemiesInRect(
    Rect rect,
    double damage,
    Set<Object> excludeHandles,
  ) =>
      const [];

  @override
  Future<void> onLoad() async {
    super.onLoad();

    // -------------------------------------------------------------
    // Everything below used to be a chain of sequential `await`s —
    // audio, THEN background, THEN ship — which meant nothing was
    // visible/playable until all three had finished one after
    // another. They don't depend on each other, so they now run
    // concurrently via Future.wait, and WaveManager (added right
    // after this onLoad resolves, in _LevelFlameGame) starts as
    // soon as the slowest of the three finishes instead of the sum
    // of all three.
    //
    // IMPORTANT: because these run concurrently, the ORDER in which
    // they finish and get add()-ed is not guaranteed. Every layer
    // below is therefore given an explicit `priority` (see
    // RenderPriority) so draw order stays correct regardless of
    // which async task wins the race — this is what previously
    // caused the ship to sometimes render underneath (i.e.
    // invisible behind) the background.
    // -------------------------------------------------------------

    // click.mp3 is always needed (button SFX everywhere). main.mp3
    // is ONLY needed/loaded for the main menu — see playDefaultMusic
    // doc comment above.
    final audioFuture = playDefaultMusic
        ? FlameAudio.audioCache.loadAll(['main.mp3', 'click.mp3']).then((_) {
            FlameAudio.bgm.play('main.mp3', volume: 0.5);
          })
        : FlameAudio.audioCache.load('click.mp3');

    // -------------------------------------------------------------
    // Scrolling space background — background.png tiles and scrolls
    // continuously downward to create the illusion of drifting
    // through space. fill: LayerFill.width makes sure it always
    // covers the full screen no matter the device size, and repeat
    // makes it loop seamlessly instead of running out.
    //
    // NOTE ON DIRECTION: baseVelocity's y is the direction the
    // IMAGE CONTENT shifts. Negative y here makes it read as
    // scrolling downward on screen (confirmed fix from previous
    // build where it looked like it scrolled up).
    //
    // Explicit low priority so this always renders BEHIND every
    // other layer no matter when its (async) load finishes.
    // -------------------------------------------------------------
    final parallaxFuture = loadParallaxComponent(
      [ParallaxImageData('background.png')],
      baseVelocity: Vector2(0, -40), // negative = scrolls down on screen
      repeat: ImageRepeat.repeat,
      fill: LayerFill.width,
    ).then((bg) {
      bg.priority = RenderPriority.background;
      add(bg);
    });

    // -------------------------------------------------------------
    // Tiny moving "stars" layered on top of the background — small
    // white dots that drift and add depth/parallax motion, like
    // debris/stars streaking past as you travel through space.
    // Cheap/sync — no need to wait on anything for this one. Sits
    // just above the background, still well below the ship.
    // -------------------------------------------------------------
    add(StarField()..priority = RenderPriority.starField);

    // -------------------------------------------------------------
    // Player ship — loads whichever skin is currently equipped.
    // -------------------------------------------------------------
    final shipFuture = _spawnShipForEquippedSkin();

    await Future.wait([audioFuture, parallaxFuture, shipFuture]);

    // Listen for skin changes made on the Skins page WHILE this game
    // is already running (e.g. you pop back to an existing
    // MainGamePage instance instead of it being rebuilt from scratch)
    // and swap the ship live the instant SELECT is tapped, instead of
    // only picking up the new skin next time onLoad() happens to run.
    equippedSkinNotifier.addListener(_onEquippedSkinChanged);
  }

  /// Builds the ship + its engine flame from whatever `equippedSkin`
  /// currently is, and adds them to the game. Ship stays centered
  /// vertically and automatically patrols left/right on its own.
  /// Dragging with a finger is an ADDITIONAL option layered on top —
  /// while dragging, auto-patrol pauses, then resumes smoothly once
  /// you let go.
  Future<void> _spawnShipForEquippedSkin() async {
    final skin = equippedSkin;
    final shipSprite = await loadSprite(skin.asset);
    ship = Ship(
      sprite: shipSprite,
      skin: skin,
      shipScale: shipScale,
      projectileScale: projectileScale,
      autoPatrol: autoPatrol,
      dragTopLimitFraction: dragTopLimitFraction,
      energySystem: energySystem,
      superPowerController: superPowerController,
    )
      ..setHome(Vector2(size.x / 2, size.y / 2 + 120)) // a bit lower than center
      ..priority = RenderPriority.ship;
    add(ship);

    // Engine flame is a SIBLING of the ship (not a child) that tracks
    // ship.position every frame in absolute/game coordinates — this is
    // the same coordinate space bullets already use, which is why the
    // bullets land correctly and a child-based flame wouldn't. Reads
    // its color/spread/offset straight from the equipped skin so it
    // matches whatever you saw in the skin preview. Priority keeps it
    // just behind the ship sprite so it reads as coming out of the
    // tail rather than floating on top of the hull.
    _engineFlame = EngineFlame(
      ship: ship,
      accentColor: skin.flameAccent,
      engineOffsetYFraction: skin.engineOffsetYFraction,
      spread: skin.flameSpread * flameScale,
      particleRadius: skin.flameParticleRadius * flameScale,
      length: skin.flameLength * flameScale,
    )..priority = RenderPriority.engineFlame;
    add(_engineFlame);

    // Skins with bulletBeam (e.g. Frostbyte) don't fire discrete
    // bullets at all — instead a single continuous beam streams from
    // the muzzle straight off the top of the screen, every frame.
    //
    // `damageGetter` reads the ship's CURRENT (post-upgrade) damage
    // stat live, every time it's called — same effectiveStatValue()
    // call Ship.update() makes for regular bullets — so upgrading
    // Damage on the Upgrade page raises the beam's damage rate too,
    // without needing to rebuild the beam.
    //
    // `energySystem` is forwarded straight through so the beam can
    // drain energy continuously (2/sec, see EnergySystem.
    // registerContinuousFire) and shut itself off the instant the
    // guns are depleted — Ship never gets a chance to do this for
    // beam skins since it deliberately skips them in its own firing
    // branch below.
    if (skin.bulletBeam) {
      _laserBeam = LaserBeam(
        ship: ship,
        color: skin.bulletColor,
        width: skin.bulletWidth * projectileScale,
        offsetYFraction: skin.bulletOffsetYFraction,
        damageGetter: () => effectiveStatValue(skin, 2).toDouble(), // 2 = Damage
        energySystem: energySystem,
      )..priority = RenderPriority.laserBeam;
      add(_laserBeam!);
    }
  }

  /// Fired by equippedSkinNotifier whenever a new skin is selected.
  /// Removes the current ship + flame and spawns fresh ones for the
  /// newly equipped skin, so the change shows up immediately even if
  /// this game instance has been running the whole time.
  void _onEquippedSkinChanged() {
    ship.removeFromParent();
    _engineFlame.removeFromParent();
    _laserBeam?.removeFromParent();
    _laserBeam = null;
    _spawnShipForEquippedSkin();
  }

  @override
  void onRemove() {
    if (stopMusicOnRemove) {
      FlameAudio.bgm.stop();
    }
    equippedSkinNotifier.removeListener(_onEquippedSkinChanged);
    super.onRemove();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      ship.setHome(Vector2(size.x / 2, size.y / 2 + 120));
    }
  }
}

/// The player's ship. Auto-patrols left/right around a fixed home
/// center (sine wave), can additionally be dragged with a finger
/// (which pauses the patrol until released), and fires a bullet
/// automatically at a fixed interval regardless of movement mode.
///
/// Firing pattern and bullet look come from `skin`: skins with
/// `bulletFromCenter == true` fire a single bolt straight out of the
/// ship's horizontal center (e.g. the Interceptor's red bolt, or
/// Nebula's sharp needle bolt); others fire the classic twin-gun pair
/// offset left/right of center (e.g. the Falcon's cyan dots). Skins
/// with `bulletBeam == true` (e.g. Frostbyte) don't go through this
/// bullet-spawning path at all — see [LaserBeam], added as a sibling
/// component in MyFlameGame instead.
///
/// Every bullet's damage comes from `effectiveStatValue(skin, 2)` —
/// the ship's CURRENT (post-upgrade) damage stat, from skins_page.dart
/// — rather than `skin.damage` directly, so any levels bought on the
/// Upgrade page actually deal more damage in combat instead of only
/// showing a bigger number on the stats screen.
///
/// If [energySystem] is supplied (levels do this; the main menu ship
/// does not), firing is gated behind `energySystem.canFire` and every
/// bullet actually spawned reports itself via `registerShot()`. The
/// fire cadence itself also comes from `energySystem` when present
/// (`energySystem.shootIntervalNotifier`, tunable live via the RATE
/// pill in the HUD) — falling back to the fixed [shootInterval]
/// constant only when there's no energy system (the main menu ship).
///
/// If [superPowerController] is supplied AND its owner is the
/// Interceptor with Twin Fang active, every 3rd shot cycle this ship
/// fires also spawns a [HomingBullet] alongside its normal bullet(s)
/// — see ship_super_powers.dart for the full mechanic. If its owner
/// is Frostbyte with Absolute Zero active, every bullet this ship
/// spawns is also slowed to 1/3 speed via
/// `superPowerController.playerBulletSpeedMultiplier`.
class Ship extends SpriteComponent
    with DragCallbacks, HasGameRef<MyFlameGame> {
  final SkinData skin;
  final double shipScale;
  final double projectileScale;
  final bool autoPatrol;
  final double dragTopLimitFraction;
  final EnergySystem? energySystem;
  final SuperPowerController? superPowerController;

  double _shootTimer = 0;
  static const double shootInterval = 0.35; // fallback when no energySystem

  // Auto-patrol (left/right, sine-based so it eases at the edges).
  Vector2 _homeCenter = Vector2.zero();
  double _time = 0;
  bool _isDragging = false;
  static const double patrolAmplitude = 35; // px left/right — short sweep
  static const double patrolSpeed = 3.2; // higher = faster side-to-side

  Ship({
    required Sprite sprite,
    required this.skin,
    this.shipScale = 1.0,
    this.projectileScale = 1.0,
    this.autoPatrol = true,
    this.dragTopLimitFraction = 0.0,
    this.energySystem,
    this.superPowerController,
  })
      : super(
          sprite: sprite,
          size: Vector2.all(320 * shipScale),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Engine flame is added by MyFlameGame as a sibling that tracks
    // this ship's position directly — see EngineFlame below.
  }

  /// Sets the ship's home (patrol center) and snaps it there.
  void setHome(Vector2 center) {
    _homeCenter = center.clone();
    if (!_isDragging) {
      position = center.clone();
    }
  }

  /// Hit box used for collision checks (enemy bullets / ramming vs
  /// the player) — a bit tighter than the full sprite bounds so it
  /// feels fair, matching how Enemy.hitRect is scaled down too.
  Rect hitRect() => Rect.fromCenter(
        center: position.toOffset(),
        width: size.x * 0.35,
        height: size.y * 0.35,
      );

  @override
  void update(double dt) {
    super.update(dt);

    _shootTimer += dt;
    // energySystem == null (main menu ship) always allows firing;
    // when it IS set (in-level ship), firing locks out entirely
    // while the guns are depleted/recharging/manually stopped
    // (unless free-fire is active — see EnergySystem.canFire).
    final canFire = energySystem?.canFire ?? true;

    // Fire cadence comes from the energy system's live-tunable
    // interval (RATE pill) when one is present; otherwise falls back
    // to the fixed constant (main menu ship has no energy system).
    final effectiveShootInterval =
        energySystem?.shootIntervalNotifier.value ?? shootInterval;

    // Frostbyte's Absolute Zero — read once per shot cycle and
    // applied to every Bullet spawned below. 1.0 whenever Absolute
    // Zero isn't active/owned (or this ship has no super power at
    // all), so nothing changes for any other ship.
    final double bulletSpeedMultiplier =
        superPowerController?.playerBulletSpeedMultiplier ?? 1.0;

    // Beam skins (skin.bulletBeam) never enter this branch at all —
    // they're driven entirely by LaserBeam instead, including their
    // own energy draining (see EnergySystem.registerContinuousFire).
    if (_shootTimer >= effectiveShootInterval && !skin.bulletBeam && canFire) {
      _shootTimer = 0;
      final gunOffsetY = size.y * skin.bulletOffsetYFraction;

      // Current (post-upgrade) damage for this shot — reads whatever
      // level has been bought for this ship's Damage stat on the
      // Upgrade page, falling back to the skin's base damage at
      // level 0. Computed once per shot rather than per bullet so
      // both bullets in a twin-gun burst always deal identical
      // damage.
      final currentDamage = effectiveStatValue(skin, 2).toDouble(); // 2 = Damage

      if (skin.bulletFromCenter) {
        // Single bolt, straight out of the ship's horizontal center.
        // If the skin is marked `bulletSharp` (e.g. Nebula), this
        // renders as a pointed needle/dart instead of a round dot. If
        // it's marked `bulletLaser` (e.g. Frostbyte), it renders as a
        // glowing laser beam instead (takes priority over `sharp`).
        gameRef.add(Bullet(
          startPosition: position.clone() + Vector2(0, gunOffsetY),
          color: skin.bulletColor,
          bulletWidth: skin.bulletWidth * projectileScale,
          bulletHeight: skin.bulletHeight * projectileScale,
          sharp: skin.bulletSharp,
          laser: skin.bulletLaser,
          damage: currentDamage,
          speedMultiplier: bulletSpeedMultiplier,
        ));
        energySystem?.registerShot();
      } else {
        // Classic twin guns — keeping the original horizontal offset
        // (close to center), only nudged a little further up.
        final gunOffsetX = size.x * 0.14;
        gameRef.add(Bullet(
          startPosition: position.clone() + Vector2(-gunOffsetX, gunOffsetY),
          color: skin.bulletColor,
          bulletWidth: skin.bulletWidth * projectileScale,
          bulletHeight: skin.bulletHeight * projectileScale,
          sharp: skin.bulletSharp,
          laser: skin.bulletLaser,
          damage: currentDamage,
          speedMultiplier: bulletSpeedMultiplier,
        ));
        energySystem?.registerShot();
        gameRef.add(Bullet(
          startPosition: position.clone() + Vector2(gunOffsetX, gunOffsetY),
          color: skin.bulletColor,
          bulletWidth: skin.bulletWidth * projectileScale,
          bulletHeight: skin.bulletHeight * projectileScale,
          sharp: skin.bulletSharp,
          laser: skin.bulletLaser,
          damage: currentDamage,
          speedMultiplier: bulletSpeedMultiplier,
        ));
        energySystem?.registerShot();
      }

      // Twin Fang (Interceptor's super power) — every 3rd shot cycle
      // this ship fires, ALSO launch a bigger, guaranteed-hit homing
      // bolt for double damage, on top of whatever it normally fires.
      // registerBulletForHoming() is a no-op returning false for any
      // ship/state other than "Interceptor with Twin Fang active",
      // so this is silently inert for every other ship. The bolt
      // itself now pierces through every enemy it touches (see
      // HomingBullet below) rather than stopping at the first one.
      if (superPowerController?.registerBulletForHoming() ?? false) {
        gameRef.add(HomingBullet(
          startPosition: position.clone() + Vector2(0, gunOffsetY),
          color: skin.bulletColor,
          damage: currentDamage * 2,
        ));
      }
    }

    if (!_isDragging && autoPatrol) {
      _time += dt;
      final offsetX = sin(_time * patrolSpeed) * patrolAmplitude;
      position.x = _homeCenter.x + offsetX;
      position.y = _homeCenter.y;
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _isDragging = true;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    position += event.localDelta;

    // Keep the ship fully on screen while dragging.
    position.x = position.x.clamp(size.x / 2, gameRef.size.x - size.x / 2);
    final topLimit = gameRef.size.y * dragTopLimitFraction + size.y / 2;
    position.y = position.y.clamp(
      topLimit,
      gameRef.size.y - size.y / 2,
    );
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (autoPatrol) {
      _resumePatrolFromCurrentPosition();
    } else {
      _isDragging = false;
    }
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (autoPatrol) {
      _resumePatrolFromCurrentPosition();
    } else {
      _isDragging = false;
    }
  }

  /// Re-syncs the sine wave's phase to wherever the finger left the
  /// ship, so the auto-patrol resumes smoothly instead of jumping.
  void _resumePatrolFromCurrentPosition() {
    _isDragging = false;
    final clampedOffset =
        (position.x - _homeCenter.x).clamp(-patrolAmplitude, patrolAmplitude);
    _time = asin((clampedOffset / patrolAmplitude).clamp(-1.0, 1.0)) /
        patrolSpeed;
  }
}

/// A continuous flame effect that streams out from the ship's engine,
/// centered at the tail (bottom-center, between the two rear fins).
/// Tracks `ship.position` every frame in the SAME absolute coordinate
/// space the game/bullets use, so it stays glued to the ship
/// regardless of patrol movement or dragging.
///
/// Color, offset, spread, particle size, and trail length are all
/// passed in from the equipped skin (see MyFlameGame.onLoad), so the
/// trail on the main game page matches what you see in the skin
/// preview carousel.
class EngineFlame extends Component {
  final Ship ship;
  final Color accentColor;
  final double engineOffsetYFraction;
  final double spread;
  final double particleRadius;
  final double length;
  final List<_FlameParticle> _particles = [];
  final Random _rng = Random();
  double _spawnTimer = 0;
  static const double spawnInterval = 0.02; // higher rate = denser flame

  EngineFlame({
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

    final enginePos = ship.position +
        Vector2(0, ship.size.y * engineOffsetYFraction);

    _spawnTimer += dt;
    if (_spawnTimer >= spawnInterval) {
      _spawnTimer = 0;
      final life = (0.24 + _rng.nextDouble() * 0.14) * length;
      _particles.add(_FlameParticle(
        position: enginePos + Vector2((_rng.nextDouble() - 0.5) * spread, 0),
        velocity: Vector2(
          (_rng.nextDouble() - 0.5) * (spread * 0.6),
          (_rng.nextDouble() * 90 + 90) * length, // shoots downward, out the tail
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
      final color = Color.lerp(
            Colors.white,
            accentColor,
            t.clamp(0.0, 1.0),
          ) ??
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

/// A single, unbroken laser beam that streams out of the ship's
/// muzzle and stretches all the way past the top of the screen, every
/// frame, for as long as the skin is equipped AND the ship's energy
/// gate currently allows firing — used by skins with `bulletBeam:
/// true` (e.g. Frostbyte) instead of firing separate, timed [Bullet]s.
/// Tracks `ship.position` every frame in the same absolute
/// coordinate space bullets use, so it stays glued to the ship
/// through patrol movement and dragging, exactly like [EngineFlame].
/// Draws the same glow → saturated core → white hot-line look as a
/// laser [Bullet], just stretched into one continuous strip instead
/// of a series of discrete shots, with a gentle brightness pulse so
/// it doesn't read as a flat, static sprite.
///
/// ENERGY: unlike a bullet ship — which spends energy per-shot via
/// [EnergySystem.registerShot] — a beam has no discrete "shots" to
/// hook a cost into. Instead, every frame the beam is [isActive] it
/// calls [EnergySystem.registerContinuousFire], draining
/// [EnergySystem.continuousDrainPerSecond] (2/sec) of energy. The
/// instant the energy system reports `canFire == false` (guns
/// depleted, same as a bullet ship locking up), [isActive] flips
/// false too: the beam stops drawing AND stops dealing damage, and
/// stays off until the player taps the FIRE pill to reactivate —
/// exactly the same STOP/FIRE/recharge cycle bullet ships already
/// use, just applied continuously instead of per-shot. If
/// [energySystem] is null (the main-menu preview ship has none), the
/// beam is always active.
///
/// DAMAGE: there is NO discrete tick timer — the beam simply exposes
/// [damagePerSecond] (from [damageGetter]) and [hitRect], and
/// [WaveManager] (see enemy.dart) applies `damagePerSecond * dt` to
/// every enemy currently overlapping the beam, every single frame,
/// for as long as [isActive] is true. A skin with (post-upgrade)
/// damage stat D deals `D * 10` damage per second (i.e. what used to
/// take a full 2 seconds now lands in 1 second) — e.g. 12 base ->
/// 120/sec, or 30 fully upgraded -> 300/sec — spread smoothly across
/// every frame instead of landing in chunks, and it stops the instant
/// the beam goes inactive (energy runs out) rather than waiting on a
/// tick boundary.
class LaserBeam extends Component with HasGameRef<MyFlameGame> {
  final Ship ship;
  final Color color;
  final double width;
  final double offsetYFraction;

  /// Optional energy gate — mirrors what [Ship] takes. Null on the
  /// main-menu preview (unlimited beam); set by the level for actual
  /// gameplay so the beam actually costs energy and can lock up.
  final EnergySystem? energySystem;

  /// Returns the CURRENT (post-upgrade) damage this beam deals. Read
  /// fresh every time [damagePerSecond] is read (i.e. every frame),
  /// so buying a Damage upgrade mid-level raises the beam's damage
  /// immediately without needing to rebuild it.
  final double Function() damageGetter;

  double _time = 0;

  // How far past the top of the visible screen the beam extends, in
  // px. Large enough that it always reads as "infinite" regardless of
  // device height, without needing to know the actual screen size.
  static const double _overshoot = 1200;

  /// Continuous damage rate (per second) this beam deals to whatever
  /// it's touching. No discrete tick timer — [WaveManager] just
  /// applies `damagePerSecond * dt` every frame. The *10 means a
  /// full "burst" of damage now lands in 1 second instead of 2 (the
  /// ship was feeling too weak for a 1500-gem skin at the old rate)
  /// — a base 12-damage skin deals 120 damage/sec; a fully upgraded
  /// 30-damage skin deals 300 damage/sec.
  double get damagePerSecond => damageGetter() * 10;

  /// Whether the beam is currently allowed to be on — i.e. whether it
  /// should render and deal damage this frame. Mirrors the same gate
  /// [Ship] uses for bullets: no energy system at all (main-menu
  /// preview) means always active; otherwise it follows
  /// [EnergySystem.canFire] exactly, so a depleted/manually-stopped
  /// beam ship shuts its beam off just like a depleted bullet ship
  /// stops spawning bullets.
  bool get isActive => energySystem?.canFire ?? true;

  LaserBeam({
    required this.ship,
    required this.color,
    required this.width,
    required this.offsetYFraction,
    required this.damageGetter,
    this.energySystem,
  });

  /// The beam's current hit box in the same absolute game-world
  /// coordinates [Bullet]/[EnemyBullet] use — a vertical strip from
  /// the muzzle up past the top of the screen. Recomputed every call
  /// so it always matches wherever the ship currently is (patrol,
  /// drag, etc.), exactly like [render] below.
  Rect hitRect() {
    final muzzle = ship.position + Vector2(0, ship.size.y * offsetYFraction);
    final topY = muzzle.y - _overshoot;
    final h = muzzle.y - topY;
    return Rect.fromLTWH(muzzle.x - width / 2, topY, width, h);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    // Energy gate: while the beam isn't allowed to fire (depleted,
    // manually stopped, and not in free-fire), it does nothing this
    // frame at all — no energy drained (none left to drain anyway),
    // no damage dealt, nothing to render. It comes back the instant
    // [isActive] flips true again (recharge threshold reached +
    // player taps FIRE, or free-fire kicks in).
    if (!isActive) {
      return;
    }

    // Beam-type ships don't fire discrete bullets for registerShot()
    // to hook into, so energy drains continuously instead, at a flat
    // rate per second of active beam time. No-op if energySystem is
    // null (main-menu preview).
    energySystem?.registerContinuousFire(dt);

    // No tick timer to advance anymore — damage is applied directly
    // by WaveManager every frame via damagePerSecond * dt, for as
    // long as this beam stays active and overlapping an enemy.
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Beam is powered down (out of energy, waiting on the player to
    // tap FIRE) — draw nothing, same as a bullet ship simply not
    // spawning bullets while depleted.
    if (!isActive) return;

    final muzzle = ship.position + Vector2(0, ship.size.y * offsetYFraction);
    final topY = muzzle.y - _overshoot;
    final h = muzzle.y - topY;
    if (h <= 0) return;

    final w = width;
    final cx = muzzle.x;

    // Slow, gentle brightness pulse so the beam feels alive rather
    // than a flat static bar.
    final pulse = 0.85 + 0.15 * sin(_time * 6);

    final beamRect = Rect.fromLTWH(cx - w / 2, topY, w, h);
    final beamRRect =
        RRect.fromRectAndRadius(beamRect, Radius.circular(w / 2));

    // Wide, soft outer glow.
    final outerGlowPaint = Paint()
      ..color = color.withOpacity(0.28 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawRRect(beamRRect, outerGlowPaint);

    final innerGlowPaint = Paint()
      ..color = color.withOpacity(0.5 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(beamRRect, innerGlowPaint);

    // Saturated colored core, narrower than the glow.
    final coreRect = Rect.fromLTWH(cx - w * 0.3, topY, w * 0.6, h);
    final coreRRect =
        RRect.fromRectAndRadius(coreRect, Radius.circular(w * 0.3));
    final corePaint = Paint()..color = color.withOpacity(0.92 * pulse);
    canvas.drawRRect(coreRRect, corePaint);

    // Bright white hot-core line straight down the middle.
    final hotPaint = Paint()
      ..color = Colors.white.withOpacity(0.92 * pulse)
      ..strokeWidth = (w * 0.2).clamp(1.5, 4.5)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, topY), Offset(cx, muzzle.y), hotPaint);
  }
}

/// A single auto-fired bullet that travels straight up from wherever
/// it was spawned and removes itself once off-screen. Shape/size/color
/// are driven per-skin: equal width/height reads as a round dot (the
/// Falcon's classic look), a taller height than width reads as an
/// elongated bolt/capsule (the Interceptor's look), `sharp: true`
/// (e.g. Nebula) draws a pointed needle/dart shape — острый кончик — with a
/// triangular tip, tapered body, and a glowing white core line down
/// the middle, and `laser: true` (e.g. Frostbyte) draws an actual
/// glowing energy beam — a soft blurred outer glow, a saturated
/// colored core, and a bright white hot-core line down the middle —
/// instead of any of the rounded/sharp shapes. `laser` takes
/// priority over `sharp` if both are somehow set.
///
/// `damage` is passed in per-instance by Ship.update() (see above),
/// already resolved to the ship's current (post-upgrade) damage stat
/// at the moment of firing — Bullet itself doesn't know or care about
/// skins/upgrades, it just carries whatever number it was given.
///
/// `speedMultiplier` is likewise passed in per-instance by
/// Ship.update() — normally 1.0, but scaled to 1/3 while Frostbyte's
/// Absolute Zero super power is active (see
/// SuperPowerController.playerBulletSpeedMultiplier), so the player's
/// own shots crawl out slowly right alongside the slowed enemies.
///
/// Fixed `priority: RenderPriority.bullet` (see the `super(...)` call
/// below) so bullets always render above the ship/background/flame
/// regardless of add order.
class Bullet extends PositionComponent with HasGameRef<MyFlameGame> {
  /// Base travel speed before any super-power multiplier is applied.
  static const double baseSpeed = 460;

  /// Per-instance speed scale — 1.0 normally, 1/3 while Absolute Zero
  /// is active on the ship that fired this bullet.
  final double speedMultiplier;

  final Paint _paint;
  final Color _color;
  final bool sharp;
  final bool laser;

  /// Damage this bullet deals on hit — read by WaveManager when it
  /// resolves player-bullet-vs-enemy collisions.
  final double damage;

  Bullet({
    required Vector2 startPosition,
    required Color color,
    double bulletWidth = 10,
    double bulletHeight = 10,
    this.sharp = false,
    this.laser = false,
    this.damage = 20,
    this.speedMultiplier = 1.0,
  })  : _paint = Paint()..color = color,
        _color = color,
        super(
          position: startPosition,
          size: Vector2(bulletWidth, bulletHeight),
          anchor: Anchor.center,
          priority: RenderPriority.bullet,
        );

  @override
  void update(double dt) {
    super.update(dt);
    position.y -= baseSpeed * speedMultiplier * dt;
    if (position.y < -40) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (laser) {
      final w = size.x;
      final h = size.y;
      final cx = w / 2;
      final capRadius = w / 2;

      // Wide, soft outer glow — blurred so it bleeds out past the
      // beam's own width, giving it that "energy" haze instead of a
      // hard-edged shape.
      final glowRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(capRadius),
      );
      final outerGlowPaint = Paint()
        ..color = _color.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawRRect(glowRect, outerGlowPaint);

      final innerGlowPaint = Paint()
        ..color = _color.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(glowRect, innerGlowPaint);

      // Saturated colored core beam, narrower than the glow so the
      // glow reads as a halo around it.
      final coreRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.20, 0, w * 0.60, h),
        Radius.circular(w * 0.30),
      );
      final corePaint = Paint()..color = _color.withOpacity(0.95);
      canvas.drawRRect(coreRect, corePaint);

      // Bright white hot-core line straight down the middle — the
      // actual "beam" the eye locks onto.
      final hotPaint = Paint()
        ..color = Colors.white.withOpacity(0.95)
        ..strokeWidth = (w * 0.20).clamp(1.5, 4.5)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(cx, h * 0.05),
        Offset(cx, h * 0.95),
        hotPaint,
      );
      return;
    }

    if (sharp) {
      final w = size.x;
      final h = size.y;

      // Needle/dart silhouette: a sharp triangular tip at the top
      // that tapers into a thin shaft, with a small flared base at
      // the bottom — reads as a piercing bolt rather than a dot.
      final path = Path()
        ..moveTo(w / 2, 0) // sharp tip
        ..lineTo(w * 0.78, h * 0.22)
        ..lineTo(w * 0.62, h * 0.85)
        ..lineTo(w * 0.62, h)
        ..lineTo(w * 0.38, h)
        ..lineTo(w * 0.38, h * 0.85)
        ..lineTo(w * 0.22, h * 0.22)
        ..close();
      canvas.drawPath(path, _paint);

      // Thin bright core line down the middle for a laser-like glow,
      // reinforcing the sharp/piercing look.
      final corePaint = Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = (w * 0.14).clamp(1.0, 4.0)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(w / 2, h * 0.06),
        Offset(w / 2, h * 0.88),
        corePaint,
      );
      return;
    }

    // Rounded rect with radius = half the width: when width == height
    // this renders as a circle (matches the original round bullet);
    // when height > width it renders as a tall capsule/bolt shape.
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Radius.circular(size.x / 2),
    );
    canvas.drawRRect(rrect, _paint);
  }
}

/// A special, larger bullet fired by ships whose Twin Fang super
/// power (Interceptor — see ship_super_powers.dart) is currently
/// active. Every frame it re-aims itself at whatever the CURRENT
/// nearest enemy is (via MyFlameGame.findNearestEnemyPosition,
/// overridden by the level's game instance to actually query
/// WaveManager) so it visually "chases" a target instead of flying in
/// a fixed straight line.
///
/// UNLIKE a normal [Bullet] (which stops dead the instant it touches
/// its first enemy), this bolt PIERCES straight through: every frame,
/// it checks its own hit box against every currently-active enemy via
/// [MyFlameGame.damageEnemiesInRect] and damages every single one it's
/// touching, then keeps flying — so a line of enemies caught in its
/// path all take damage, not just whichever one it happened to be
/// steering toward. [_hitEnemies] tracks which enemies this specific
/// bolt has already damaged so a slow pass over one enemy for a
/// couple of frames doesn't melt it instantly; once hit, an enemy is
/// excluded for the rest of THIS bolt's flight, while anything else
/// it touches (including new enemies further along its path) still
/// takes damage normally. It only disappears once its lifetime runs
/// out or it leaves the screen — never on "first hit".
///
/// Fixed `priority: RenderPriority.bullet` (same as [Bullet]) so it
/// always renders above the ship/background regardless of add order.
class HomingBullet extends PositionComponent with HasGameRef<MyFlameGame> {
  final Color color;
  final double damage;
  final Paint _paint;

  static const double _speed = 520;
  static const double _turnRate = 7.0; // higher = sharper mid-flight turns

  /// Half-extent (in px) of the square hit box used for piercing
  /// damage detection each frame — deliberately larger than the
  /// visible sprite, same generous size the old single-target
  /// "can't miss" radius used, so this still reads as a guaranteed
  /// hit rather than needing a pixel-perfect graze.
  static const double _hitRadius = 26;

  static const double _maxLifetime = 3.5;

  Vector2 _velocity;
  double _age = 0;

  /// Enemies this specific bolt has already damaged — excluded from
  /// further hits for the rest of its flight so it doesn't re-damage
  /// the same enemy every single frame while still overlapping it.
  /// Populated with the opaque handles (the WaveManager-side [Enemy]
  /// objects themselves) returned by
  /// [MyFlameGame.damageEnemiesInRect].
  final Set<Object> _hitEnemies = {};

  HomingBullet({
    required Vector2 startPosition,
    required this.color,
    required this.damage,
    double width = 16,
    double height = 26,
  })  : _paint = Paint()..color = color,
        _velocity = Vector2(0, -_speed),
        super(
          position: startPosition,
          size: Vector2(width, height),
          anchor: Anchor.center,
          priority: RenderPriority.bullet,
        );

  /// Hit box used for piercing damage detection — see class doc
  /// comment above.
  Rect hitRect() => Rect.fromCenter(
        center: position.toOffset(),
        width: _hitRadius * 2,
        height: _hitRadius * 2,
      );

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;

    // Steering only — decides which way the bolt curves toward, it
    // no longer decides whether/who gets damaged. Damage is resolved
    // separately below via a hit-box overlap check against EVERY
    // active enemy, so the bolt can pierce through enemies it passes
    // that aren't even its current steering target.
    final targetPos = gameRef.findNearestEnemyPosition(position);
    if (targetPos != null) {
      final toTarget = targetPos - position;
      final distance = toTarget.length;

      if (distance > 1) {
        final desiredDirection = toTarget.normalized();
        final currentDirection = _velocity.length > 0
            ? _velocity.normalized()
            : desiredDirection;
        final turn = (_turnRate * dt).clamp(0.0, 1.0);
        final blended =
            currentDirection + (desiredDirection - currentDirection) * turn;
        _velocity = (blended.length > 0 ? blended.normalized() : desiredDirection) *
            _speed;
      }
    }

    position += _velocity * dt;
    angle = atan2(_velocity.x, -_velocity.y);

    // Piercing hit detection — damage every enemy currently
    // overlapping this bolt's hit box that it hasn't already hit.
    // Freshly-hit enemies get folded into _hitEnemies so they're
    // excluded on every subsequent frame this bolt is still alive.
    final justHit =
        gameRef.damageEnemiesInRect(hitRect(), damage, _hitEnemies);
    if (justHit.isNotEmpty) {
      _hitEnemies.addAll(justHit);
    }

    if (_age >= _maxLifetime ||
        position.y < -80 ||
        position.y > gameRef.size.y + 80 ||
        position.x < -80 ||
        position.x > gameRef.size.x + 80) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final w = size.x;
    final h = size.y;

    // Same needle/glow language as a sharp bullet, just bigger and
    // brighter, so it reads as an upgraded shot rather than a
    // completely different weapon.
    final outerGlowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.7, outerGlowPaint);

    final path = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w * 0.85, h * 0.28)
      ..lineTo(w * 0.65, h)
      ..lineTo(w * 0.35, h)
      ..lineTo(w * 0.15, h * 0.28)
      ..close();
    canvas.drawPath(path, _paint);

    final hotPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w / 2, h * 0.1), Offset(w / 2, h * 0.85), hotPaint);
  }
}

/// Purely visual band across the vertical center of the screen for
/// Nebula's "Aegis Barrier" super power — rendered only while
/// [activeGetter] returns true. The actual damage-halving mechanic
/// lives in WaveManager (enemy.dart), which checks the same
/// SuperPowerController state directly; this component never touches
/// gameplay, it just draws the barrier so the player can see it.
class BarrierVisual extends Component with HasGameRef<MyFlameGame> {
  final bool Function() activeGetter;
  double _time = 0;

  static const double bandHeight = 46;
  static const Color barrierColor = Color(0xFFB39DFF);

  BarrierVisual({required this.activeGetter});

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!activeGetter()) return;

    final w = gameRef.size.x;
    final centerY = gameRef.size.y * 0.5;
    final pulse = 0.7 + 0.3 * sin(_time * 3);

    final rect = Rect.fromLTWH(0, centerY - bandHeight / 2, w, bandHeight);

    final glowPaint = Paint()
      ..color = barrierColor.withOpacity(0.18 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawRect(rect, glowPaint);

    final linePaint = Paint()
      ..color = barrierColor.withOpacity(0.75 * pulse)
      ..strokeWidth = 2.2;
    canvas.drawLine(
      Offset(0, centerY - bandHeight / 2),
      Offset(w, centerY - bandHeight / 2),
      linePaint,
    );
    canvas.drawLine(
      Offset(0, centerY + bandHeight / 2),
      Offset(w, centerY + bandHeight / 2),
      linePaint,
    );

    // A few faint vertical "energy" ticks along the band for texture.
    final tickPaint = Paint()..color = Colors.white.withOpacity(0.25 * pulse);
    for (double x = 0; x < w; x += 34) {
      canvas.drawLine(
        Offset(x, centerY - bandHeight / 2 + 4),
        Offset(x, centerY + bandHeight / 2 - 4),
        tickPaint,
      );
    }
  }
}

/// A lightweight field of small white dots that continuously drift
/// down the screen and wrap back to the top, giving a subtle sense
/// of movement through space. Cheap to render — plain canvas circles,
/// no sprites needed.
class StarField extends Component with HasGameRef<MyFlameGame> {
  final List<_Star> _stars = [];
  final Random _rng = Random();
  static const int starCount = 70;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    for (int i = 0; i < starCount; i++) {
      _stars.add(_Star(
        position: Vector2(
          _rng.nextDouble() * gameRef.size.x,
          _rng.nextDouble() * gameRef.size.y,
        ),
        radius: _rng.nextDouble() * 1.4 + 0.4, // very small, 0.4–1.8px
        speed: _rng.nextDouble() * 35 + 15, // varied speed = depth
        opacity: _rng.nextDouble() * 0.6 + 0.4,
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (final star in _stars) {
      star.position.y += star.speed * dt;
      if (star.position.y > gameRef.size.y) {
        star.position.y = 0;
        star.position.x = _rng.nextDouble() * gameRef.size.x;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (final star in _stars) {
      final paint = Paint()..color = Colors.white.withOpacity(star.opacity);
      canvas.drawCircle(star.position.toOffset(), star.radius, paint);
    }
  }
}

class _Star {
  Vector2 position;
  final double radius;
  final double speed;
  final double opacity;

  _Star({
    required this.position,
    required this.radius,
    required this.speed,
    required this.opacity,
  });
}

// NOTE: AnimatedTapButton is no longer defined in this file — it's
// imported from skins_page.dart above, since defining it in both
// files caused a duplicate-class compile error.

class MainGamePage extends StatefulWidget {
  const MainGamePage({Key? key}) : super(key: key);

  @override
  _MainGamePageState createState() => _MainGamePageState();
}

class _MainGamePageState extends State<MainGamePage> {
  late final MyFlameGame _game;

  // ---- Fake/placeholder player data, wire this up to your real state ----
  final String playerName = 'Silva Robertin';
  final int level = 12;
  final int currentXp = 3450;
  final int maxXp = 5000;

  // NOTE: budget/coins are no longer hardcoded strings here — the stat
  // cards below read `gemsNotifier` / `coinsNotifier` directly (shared
  // with skins_page.dart), so spending gems on a skin actually updates
  // the number shown on this page too.

  @override
  void initState() {
    super.initState();
    _game = MyFlameGame();

    // Preload click.mp3 up front (assets/audio/click.mp3) so the very
    // first button tap fires instantly instead of stalling while the
    // file decodes. MyFlameGame.onLoad also preloads it, so this is
    // just belt-and-suspenders in case the HUD button is tapped
    // before the Flame game finishes its own onLoad.
    FlameAudio.audioCache.load('click.mp3');
  }

  /// Plays the shared button-tap SFX. Call this at the top of every
  /// button's onTap before running its actual action.
  void _playClickSound() {
    FlameAudio.play('click.mp3', volume: 0.6);
  }

  @override
  Widget build(BuildContext context) {
    final double xpProgress = currentXp / maxXp;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ---------------- Flame game canvas (background) ----------------
          Positioned.fill(
            child: GameWidget(game: _game),
          ),

          // ---------------------- Flutter HUD overlay -----------------------
          SafeArea(
            child: Column(
              children: [
                _buildProfileHeader(xpProgress),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<int>(
                            valueListenable: gemsNotifier,
                            builder: (context, gems, _) => _buildStatCard(
                              iconAsset: 'assets/images/budget.png',
                              value: '$gems',
                              iconSize: 36,
                              showAddButton: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ValueListenableBuilder<int>(
                            valueListenable: coinsNotifier,
                            builder: (context, coins, _) => _buildStatCard(
                              iconAsset: 'assets/images/coin.png',
                              value: '$coins',
                              iconSize: 36,
                              showAddButton: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ---------------------------------------------------------
                // Daily Reward / Achievements — small pill buttons, right
                // under the stat cards. Not wired up to anything yet
                // besides the click SFX.
                // ---------------------------------------------------------
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildPillButton(
                        icon: Icons.card_giftcard,
                        label: 'Daily',
                        onTap: () {
                          _playClickSound();
                        },
                      ),
                      const SizedBox(width: 10),
                      _buildPillButton(
                        icon: Icons.emoji_events,
                        label: 'Achievements',
                        onTap: () {
                          _playClickSound();
                        },
                      ),
                    ],
                  ),
                ),

                const Expanded(child: SizedBox()), // ship sits in here

                // ---------------------------------------------------------
                // Play / Shop / Upgrade — main action row near the bottom,
                // just under where the ship patrols. Play navigates to
                // ModeSelectPage, Shop navigates to the new ShopPage, and
                // Upgrade navigates to UpgradePage pre-selected on
                // whichever ship is currently equipped — all after the
                // click SFX fires.
                // ---------------------------------------------------------
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSecondaryActionButton(
                          icon: Icons.storefront,
                          label: 'Shop',
                          onTap: () {
                            _playClickSound();
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const ShopPage()),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _buildPlayButton(onTap: () {
                          _playClickSound();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ModeSelectPage()),
                          );
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSecondaryActionButton(
                          icon: Icons.upgrade,
                          label: 'Upgrade',
                          onTap: () {
                            _playClickSound();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    UpgradePage(initialSkin: equippedSkin),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Profile header: avatar (profile.png) + name + level badge + XP bar
  // ------------------------------------------------------------------
  Widget _buildProfileHeader(double xpProgress) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          ClipOval(
            child: Image.asset(
              'assets/images/profile.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),

          // Level badge + XP bar (name removed, just the indicator)
          Expanded(
            child: Row(
              children: [
                    // Level badge
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        border: Border.all(color: Colors.orange, width: 2),
                      ),
                      child: Text(
                        '$level',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // XP bar + label
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Level $level',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              children: [
                                Container(
                                  height: 6,
                                  color: Colors.grey.shade800,
                                ),
                                FractionallySizedBox(
                                  widthFactor: xpProgress.clamp(0.0, 1.0),
                                  child: Container(
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.yellow,
                                          Colors.orange,
                                          Colors.red,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$currentXp / $maxXp XP',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Small pill button — used for Daily Reward / Achievements. Icon +
  // label, dark bg, orange border to match the stat cards' style.
  // ------------------------------------------------------------------
  Widget _buildPillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return AnimatedTapButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF3D1707), Color(0xFF140500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.orangeAccent.withOpacity(0.55),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.orangeAccent,
              size: 16,
              shadows: [
                Shadow(color: Colors.orange.withOpacity(0.8), blurRadius: 6),
              ],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
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
  // Main "Play" button — the big, primary CTA in the middle of the
  // bottom action row.
  // ------------------------------------------------------------------
  Widget _buildPlayButton({required VoidCallback onTap}) {
    return AnimatedTapButton(
      onTap: onTap,
      child: Container(
        height: 58,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFC371), Color(0xFFFF5F3D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.deepOrange.withOpacity(0.55),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Subtle glossy shine along the top edge for a "physical
            // button" feel.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.35),
                      Colors.white.withOpacity(0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                SizedBox(width: 6),
                Text(
                  'PLAY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Secondary action button — used for Shop and Upgrade, flanking the
  // Play button. Smaller, matches the dark/orange-bordered look.
  // ------------------------------------------------------------------
  Widget _buildSecondaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return AnimatedTapButton(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
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
            Icon(
              icon,
              color: Colors.orangeAccent,
              size: 22,
              shadows: [
                Shadow(color: Colors.orange.withOpacity(0.8), blurRadius: 8),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Budget / Coins stat card. Just the icon image + a large value —
  // no text label rendered anywhere on the card. The value is wrapped
  // in a FittedBox so big numbers (like 100000+) shrink to fit the
  // card instead of overflowing or getting clipped/ellipsized.
  // ------------------------------------------------------------------
  Widget _buildStatCard({
    required String iconAsset,
    required String value,
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
                value,
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