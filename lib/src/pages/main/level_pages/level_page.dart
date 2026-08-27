// level_page.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cosmic_fury/src/pages/main/level_pages/enemy.dart';
import 'package:cosmic_fury/src/pages/main/level_pages/level_config.dart';
import 'package:cosmic_fury/src/pages/main/level_pages/levels_waves_1world.dart';
import 'package:cosmic_fury/src/pages/main/level_pages/ship_super_powers.dart';
// ^ SuperPowerController owns ALL super-power state/timers for
//   whichever ship is equipped (Overcharge Core, Twin Fang, Aegis
//   Barrier, Absolute Zero, Void Collapse) — see ship_super_powers.dart.
//   This file builds one instance per level, wires it into the
//   EnergySystem / Ship / WaveManager, and drives the HUD button that
//   triggers it. Adjust this path if ship_super_powers.dart lives
//   somewhere else in your project.
import 'package:cosmic_fury/src/pages/main/level_pages/spells_animations.dart';
// ^ SpellCastController now owns ALL spell state (timers, shield
//   charges, damage/health buffs) and every cast_* implementation,
//   plus every spell's Flame visual-effect component. This file just
//   builds one and forwards SpellsDetector's onCast to it — see
//   _spellController below. Adjust this path if spells_animations.dart
//   lives somewhere else in your project.
import 'package:cosmic_fury/src/pages/main/level_pages/spells_detector.dart';
import 'package:cosmic_fury/src/pages/main/main_game_page.dart';
import 'package:cosmic_fury/src/pages/skins/skins_page.dart';

// ^ pulls in SpellData, kAllSpells, equippedSpellIdsNotifier,
//   ownedSpellCountsNotifier — casting a spell is what actually
//   applies its gameplay effect, now handled inside SpellCastController.
// ^ adjust these two paths if spells_page.dart / spells_detector.dart
//   live somewhere else in your project.
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';

/// Player-only campaign level UI.
///
/// Uses the existing [MyFlameGame] implementation, plus a
/// [WaveManager] (see enemy.dart) that spawns the waves defined for
/// this level, moves/fires the enemies, resolves all collisions, and
/// tracks player HP as they get hit.
///
/// Level-specific behavior:
/// - Smaller ship
/// - Smaller projectiles
/// - No auto patrol
/// - Player movement limited to the bottom 40% of the screen
/// - Waves come from level_waves_1world.dart, keyed by level number
/// - A new wave never starts until every enemy from the current one
///   is dead
/// - An [EnergySystem] gates how often the player can shoot — every
///   3rd bullet costs 1 energy, and once it hits 0 (or the player
///   manually taps STOP) the guns lock until enough energy recharges
///   and the player taps FIRE
/// - `battle.mp3` plays as looping background music for the whole
///   level, pausing/resuming alongside the pause menu
/// - All spell state and cast logic lives in [SpellCastController]
///   (spells_animations.dart) — this file just owns one instance and
///   wires it into the game / HUD.
/// - The equipped ship's SUPER POWER (if bought — see
///   ship_super_powers.dart and the new purchase section on
///   SkinsPage) lives in [SuperPowerController], built fresh every
///   time a level starts so its uses always refill. This file owns
///   one instance, ticks it every frame, wires it into EnergySystem
///   (Falcon's Overcharge Core), the Ship (Interceptor's Twin Fang,
///   already read directly off MyFlameGame.superPowerController in
///   main_game_page.dart), WaveManager (Aegis Barrier / Absolute Zero
///   / Void Collapse), and drives the round activation button next to
///   the spells row.
///
/// NOTE: [EnergySystem] is defined ONCE, in main_game_page.dart, and
/// imported from there. Do NOT redeclare an `EnergySystem` class in
/// this file — having the same class name both imported and declared
/// locally is a compile error ("The name 'EnergySystem' is defined in
/// the libraries ... and ..."), which is exactly what was breaking
/// `final EnergySystem energySystem;` below.
///
/// STATS NOTE: every stat read from the equipped skin in this file —
/// starting health, starting energy, and the damage shown in the
/// ship-stats sheet — goes through [effectiveStatValue] (from
/// skins_page.dart) rather than the skin's raw `maxHealth` /
/// `maxEnergy` / `damage` fields, so any levels bought on the Upgrade
/// page actually apply here instead of the level always starting the
/// ship back at its base stats. The ship's actual fired bullet
/// damage is likewise upgraded — see Ship.update() in
/// main_game_page.dart, which also reads effectiveStatValue instead
/// of skin.damage.
class LevelPage extends StatefulWidget {
  final int level;

  const LevelPage({Key? key, this.level = 1}) : super(key: key);

  @override
  State<LevelPage> createState() => _LevelPageState();
}

/// Tiny adapter so ship_super_powers.dart never has to import
/// EnergySystem directly (that would create a needless coupling
/// between "what powers exist" and the gameplay engine file). This
/// just forwards Falcon's Overcharge Core multiplier straight into
/// the level's real EnergySystem.
class _EnergySystemCapHookAdapter implements EnergySystemCapHook {
  final EnergySystem energySystem;
  _EnergySystemCapHookAdapter(this.energySystem);

  @override
  void applyMultiplier(double multiplier) {
    // e.g. 20 energy * 2.0 -> 40 energy, refilled immediately, for
    // the rest of the level (see EnergySystem.applyCapMultiplier).
    energySystem.applyCapMultiplier(multiplier);
  }
}

class _LevelPageState extends State<LevelPage> {
  late final LevelConfig _levelConfig;
  late final _LevelFlameGame _game;

  final ValueNotifier<int> _waveNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _enemiesLeftNotifier = ValueNotifier<int>(0);
  late final ValueNotifier<double> _playerHealthNotifier;
  late final EnergySystem _energySystem;

  // Owns every bit of spell state (timers, shield charges, damage/
  // health buffs) and the cast_* logic itself — see
  // spells_animations.dart. SpellsDetector's onCast is forwarded
  // straight into _spellController.castSpell in build() below.
  late final SpellCastController _spellController;

  // Owns whichever ONE super power belongs to the currently equipped
  // ship (derived from the skin via superPowerFor in
  // ship_super_powers.dart) — refills its uses every time a fresh
  // level starts. Ticked every frame from _LevelFlameGame.update().
  late final SuperPowerController _superPowerController;

  bool _canLeave = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();

    _levelConfig = getWorld1Level(widget.level) ?? kWorld1Level1;

    // Seed starting health/energy from the ship's EFFECTIVE (i.e.
    // post-upgrade) stats — effectiveStatValue folds in whatever
    // levels have been bought on the Upgrade page on top of the
    // skin's base maxHealth/maxEnergy, so a fully-upgraded Falcon
    // actually starts the level at 320 HP / 35 energy instead of
    // silently resetting to its base 100 HP / 20 energy.
    final equippedSkin = equippedSkinNotifier.value;
    _playerHealthNotifier = ValueNotifier<double>(
      effectiveStatValue(equippedSkin, 0).toDouble(), // 0 = Health
    );

    _energySystem = EnergySystem(
      baseMaxEnergy: effectiveStatValue(equippedSkin, 1).toDouble(), // 1 = Energy
    );

    // Built right after EnergySystem exists, since Falcon's
    // Overcharge Core needs a live hook into it. The nova-damage
    // callback (Shadow Reaper) references `_game` through a closure
    // rather than directly, because `_game` isn't constructed yet at
    // this point — by the time Void Collapse can actually be
    // triggered mid-level, `_game` is already assigned.
    _superPowerController = SuperPowerController(
      skin: equippedSkin,
      onSnack: _showLevelSnack,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      energyCapHook: _EnergySystemCapHookAdapter(_energySystem),
      onVoidNova: () {
        _game.damageAllEnemies(SuperPowerController.voidNovaDamage);
      },
    );

    // getGame is a closure rather than a direct _game reference
    // because _game's own constructor needs three hooks straight off
    // this controller (shouldBlockDamage / onDamageBlocked /
    // shieldRadiusGetter / damageBonusGetter below), so the
    // controller has to exist before _game does. By the time any
    // cast method actually calls getGame(), _game will already be
    // assigned.
    _spellController = SpellCastController(
      getGame: () => _game,
      energySystem: _energySystem,
      playerHealthNotifier: _playerHealthNotifier,
      effectiveMaxHealth: _effectiveMaxHealth,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      onSnack: _showLevelSnack,
    );

    _game = _LevelFlameGame(
      levelConfig: _levelConfig,
      waveNotifier: _waveNotifier,
      enemiesLeftNotifier: _enemiesLeftNotifier,
      playerHealthNotifier: _playerHealthNotifier,
      energySystem: _energySystem,
      superPowerController: _superPowerController,
      shouldBlockDamage: _spellController.shouldBlockDamage,
      onDamageBlocked: _spellController.onDamageBlocked,
      shieldRadiusGetter: _spellController.shieldRadiusIfActive,
      // Overcharge's timed bonus + Overdrive Core's permanent bonus,
      // combined live at the moment of impact.
      damageBonusGetter: () => _spellController.totalDamageBonus,
      onLevelComplete: () {
        // All waves cleared — nothing happens yet.
      },
      onPlayerDefeated: () {
        // Player died — nothing happens yet.
      },
    );

    // Battle music — looping BGM for the whole level, started as
    // soon as the page comes up. FlameAudio's bgm player handles
    // looping + stopping any previously playing track automatically.
    FlameAudio.bgm.play('battle.mp3', volume: 0.55);
  }

  @override
  void dispose() {
    _game.pauseEngine();
    FlameAudio.bgm.stop();
    _waveNotifier.dispose();
    _enemiesLeftNotifier.dispose();
    _spellController.dispose();
    _superPowerController.dispose();
    _playerHealthNotifier.dispose();
    _energySystem.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // Ship's current max health, folding in Overdrive Core's permanent
  // bonus (if it's been cast this level, tracked inside
  // _spellController) on top of the ship's EFFECTIVE (post-upgrade)
  // max health — effectiveStatValue reads whatever's been bought on
  // the Upgrade page, not just the skin's raw base maxHealth. Used
  // everywhere health is clamped or displayed so both the upgrade
  // and the buff are reflected consistently.
  // ------------------------------------------------------------
  double _effectiveMaxHealth() =>
      effectiveStatValue(equippedSkinNotifier.value, 0).toDouble() +
      _spellController.permanentMaxHealthBonus;

  // Small snackbar helper local to this file — spells_page.dart's
  // _showSnack is private to that library and not visible here.
  // Passed into SpellCastController AND SuperPowerController as
  // onSnack.
  void _showLevelSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF2A0F05),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<bool> _blockSystemBack() async => _canLeave;

  void _playClickSound() {
    FlameAudio.play(
      'click.mp3',
      volume: 0.55,
    );
  }

  void _activateSuperPower() {
    if (!_superPowerController.canActivate) return;
    _playClickSound();
    _superPowerController.activate();
  }

  Future<void> _openPauseMenu() async {
    if (_paused) return;

    _playClickSound();

    setState(() {
      _paused = true;
    });

    _game.pauseEngine();
    FlameAudio.bgm.pause();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Pause Menu',
      barrierColor: Colors.black.withOpacity(0.78),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (
        dialogContext,
        animation,
        secondaryAnimation,
      ) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              child: _AnimatedPauseDialog(
                onResume: () {
                  _playClickSound();
                  Navigator.of(dialogContext).pop();
                },
                onHome: () {
                  _playClickSound();

                  Navigator.of(dialogContext).pop();

                  _canLeave = true;

                  FlameAudio.bgm.stop();

                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const MainGamePage(),
                    ),
                    (route) => false,
                  );
                },
                onMap: () {
                  _playClickSound();

                  Navigator.of(dialogContext).pop();

                  _canLeave = true;

                  FlameAudio.bgm.stop();

                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (
        context,
        animation,
        secondaryAnimation,
        child,
      ) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );

        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.72,
              end: 1.0,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (mounted && !_canLeave) {
      _game.resumeEngine();
      FlameAudio.bgm.resume();

      setState(() {
        _paused = false;
      });
    }
  }

  void _showShipStats(SkinData skin) {
    _playClickSound();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF08111D).withOpacity(0.98),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: skin.flameAccent.withOpacity(0.60),
            ),
          ),
          child: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/images/${skin.asset}',
                  width: 60,
                  height: 60,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      skin.name.toUpperCase(),
                      style: TextStyle(
                        color: skin.nameColor ?? Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        decoration: TextDecoration.none,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Health + damage + energy, all reading through
                    // effectiveStatValue so any levels bought on the
                    // Upgrade page show up here — health and damage
                    // additionally fold in Overdrive Core's permanent
                    // bonus (tracked inside _spellController) on top
                    // of that upgraded base.
                    Wrap(
                      spacing: 12,
                      children: [
                        _Stat(
                          icon: Icons.favorite_rounded,
                          value: '${_effectiveMaxHealth().round()}',
                          color: const Color(0xFF45E879),
                        ),
                        _Stat(
                          icon: Icons.gps_fixed_rounded,
                          value:
                              '${(effectiveStatValue(skin, 2) + _spellController.permanentDamageBonus).round()}',
                          color: const Color(0xFFFF4F5B),
                        ),
                        _Stat(
                          icon: Icons.flash_on_rounded,
                          value: '${effectiveStatValue(skin, 1)}',
                          color: const Color(0xFF4DA3FF),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _blockSystemBack,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: GameWidget(
                game: _game,
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  14,
                  18,
                  18,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WaveIndicator(
                          waveNotifier: _waveNotifier,
                          enemiesLeftNotifier: _enemiesLeftNotifier,
                          totalWaves: _levelConfig.waveCount,
                        ),
                        _PauseButton(
                          onTap: _openPauseMenu,
                        ),
                      ],
                    ),

                    const Spacer(),

                    // Spells sit directly above the ship-portrait
                    // circle at the very left, left-aligned to match
                    // it. The ship's super power button (if owned)
                    // now sits on the same row, right-aligned, so
                    // both "active abilities" read together right
                    // above the HUD.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: SpellsDetector(
                              onCast: _spellController.castSpell,
                            ),
                          ),
                          const Spacer(),
                          _SuperPowerButton(
                            controller: _superPowerController,
                            onActivate: _activateSuperPower,
                          ),
                        ],
                      ),
                    ),

                    ValueListenableBuilder<SkinData>(
                      valueListenable: equippedSkinNotifier,
                      builder: (context, skin, _) {
                        return _BottomPlayerHud(
                          skin: skin,
                          maxHealth: _effectiveMaxHealth(),
                          healthNotifier: _playerHealthNotifier,
                          energySystem: _energySystem,
                          onPortraitTap: () {
                            _showShipStats(skin);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// REAL FLAME GAME
/// ------------------------------------------------------------

class _LevelFlameGame extends MyFlameGame {
  final LevelConfig levelConfig;
  final ValueNotifier<int> waveNotifier;
  final ValueNotifier<int> enemiesLeftNotifier;
  final ValueNotifier<double> playerHealthNotifier;

  // No longer redeclared as its own field — this getter just exposes
  // the inherited MyFlameGame.energySystem (set via super below) as
  // a non-nullable EnergySystem, since a level always has one. This
  // keeps every existing `energySystem.xxx` call site in this file
  // working unchanged while guaranteeing Ship actually receives the
  // same instance MyFlameGame.onLoad() uses to build it.
  EnergySystem get energySystem => super.energySystem!;

  final VoidCallback? onLevelComplete;
  final VoidCallback? onPlayerDefeated;

  // Shield Burst hooks, forwarded straight through to WaveManager so
  // damage gets intercepted at the source instead of being reverted
  // after the fact. Sourced from SpellCastController in
  // _LevelPageState.initState.
  final bool Function()? shouldBlockDamage;
  final VoidCallback? onDamageBlocked;

  // Returns the shield's blocking radius while Shield Burst is
  // active (see SpellCastController.shieldRadiusIfActive), or null
  // when no shield is up. Forwarded straight to WaveManager so enemy
  // bullets get stopped right at the visible barrier instead of
  // flying through to the ship's own hitbox.
  final double? Function()? shieldRadiusGetter;

  // Overcharge + Overdrive Core hook: flat bonus damage added to
  // every player bullet at the moment it hits an enemy (see
  // SpellCastController.totalDamageBonus and WaveManager's
  // _handleCollisions in enemy.dart).
  final double Function()? damageBonusGetter;

  // Kept as a direct reference (not just the inherited
  // MyFlameGame.superPowerController field) so this class can add
  // the WaveManager hooks below and expose damageAllEnemies() for
  // Shadow Reaper's Void Collapse.
  final SuperPowerController? _superPower;

  // Reference to the added WaveManager instance, kept so
  // damageAllEnemies() (Void Collapse) and damageEnemiesInRect()
  // (Twin Fang) have something to actually call into. Assigned in
  // onLoad() right after WaveManager is constructed.
  late final WaveManager _waveManager;

  _LevelFlameGame({
    required this.levelConfig,
    required this.waveNotifier,
    required this.enemiesLeftNotifier,
    required this.playerHealthNotifier,
    required EnergySystem energySystem,
    SuperPowerController? superPowerController,
    this.shouldBlockDamage,
    this.onDamageBlocked,
    this.shieldRadiusGetter,
    this.damageBonusGetter,
    this.onLevelComplete,
    this.onPlayerDefeated,
  })  : _superPower = superPowerController,
        super(
          shipScale: 0.4,
          flameScale: 0.5,
          projectileScale: 0.5,
          autoPatrol: false,

          // Bottom 40% movement zone.
          dragTopLimitFraction: 0.6,

          stopMusicOnRemove: false,

          // IMPORTANT: forward it up so MyFlameGame actually knows
          // about it. Without this line, MyFlameGame.energySystem
          // stays null, _spawnShipForEquippedSkin() builds the Ship
          // with a null energy gate, and the in-level ship fires
          // with unlimited energy no matter what the HUD shows.
          energySystem: energySystem,

          // Forwarded up the same way — MyFlameGame passes this
          // straight into Ship, which is what actually makes
          // Interceptor's Twin Fang spawn homing bolts (see
          // Ship.update() in main_game_page.dart). Without this line
          // Ship.superPowerController stays null and
          // registerBulletForHoming() never gets called at all.
          superPowerController: superPowerController,

          // Levels handle their own battle.mp3 at the Flutter widget
          // layer (see _LevelPageState.initState). Without this,
          // MyFlameGame.onLoad() was ALSO loading + playing main.mp3
          // on top of it, silently swapping background music back to
          // menu music once onLoad finished, and adding real load
          // time before WaveManager could even start spawning waves
          // — that was the "level stays, then starts 1-2s later" bug.
          playDefaultMusic: false,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _waveManager = WaveManager(
      level: levelConfig,
      waveNotifier: waveNotifier,
      enemiesLeftNotifier: enemiesLeftNotifier,
      playerHealthNotifier: playerHealthNotifier,
      onLevelComplete: onLevelComplete,
      onPlayerDefeated: onPlayerDefeated,
      shouldBlockDamage: shouldBlockDamage,
      onDamageBlocked: onDamageBlocked,
      shieldRadiusGetter: shieldRadiusGetter,
      damageBonusGetter: damageBonusGetter,

      // ---- NEW: super-power hooks -------------------------------
      // These three are NOT implemented in enemy.dart yet — see the
      // integration note that came with this file. Once WaveManager
      // accepts them, this is all that's needed on the level_page.dart
      // side:
      //
      // Nebula's Aegis Barrier: any enemy fire that actually reaches
      // the player gets multiplied by this before being applied to
      // playerHealthNotifier — 1.0 normally, 0.5 while the barrier is
      // up (so 10 damage becomes 5).
      incomingDamageMultiplierGetter: () =>
          _superPower?.barrierActive == true
              ? SuperPowerController.barrierDamageMultiplier
              : 1.0,

      // Frostbyte's Absolute Zero: every enemy's movement speed gets
      // multiplied by this every frame — 1.0 normally, 1/3 while
      // active, affecting every enemy currently on screen AND any
      // that spawn while it's still running.
      enemySpeedMultiplierGetter: () =>
          _superPower?.enemySlowActive == true
              ? SuperPowerController.enemySlowMultiplier
              : 1.0,

      // Shadow Reaper's Void Collapse: while true, the player takes
      // NO damage at all from any source WaveManager resolves,
      // exactly like an extra permanent shield for its 5-second
      // duration.
      playerInvulnerableGetter: () => _superPower?.isInvulnerable ?? false,
    );
    add(_waveManager);

    // Nebula's Aegis Barrier — purely visual band across the center
    // of the screen; the actual damage-halving happens in
    // WaveManager via incomingDamageMultiplierGetter above.
    // BarrierVisual is defined in main_game_page.dart and only reads
    // activeGetter(), so it's safe to add unconditionally — it just
    // renders nothing while barrierActive is false / no power owned.
    add(BarrierVisual(activeGetter: () => _superPower?.barrierActive ?? false));
  }

  /// Shadow Reaper's Void Collapse: deals [damage] to every enemy
  /// currently on screen at once. Requires WaveManager to expose a
  /// matching `dealDamageToAllEnemies` method — see the integration
  /// note.
  @override
  void damageAllEnemies(double damage) {
    _waveManager.dealDamageToAllEnemies(damage);
  }

  /// Interceptor's Twin Fang: forwards straight to WaveManager so a
  /// homing bolt (see HomingBullet in main_game_page.dart) pierces
  /// through every enemy its own hit box touches while it flies —
  /// not just whichever enemy it happened to be steering toward —
  /// instead of stopping dead at the first one.
  @override
  List<Object> damageEnemiesInRect(
    Rect rect,
    double damage,
    Set<Object> excludeHandles,
  ) {
    return _waveManager.dealDamageToEnemiesInRect(rect, damage, excludeHandles);
  }

  // Keeps the energy recharge timer ticking every frame, synced to
  // the actual game loop instead of a separate Flutter timer. Spark
  // Shot no longer needs anything special here — while its free-fire
  // flag is active, EnergySystem.registerShot()/canFire already
  // short-circuit on their own (see main_game_page.dart), so there's
  // nothing left for this override to force or re-pin.
  //
  // Also ticks the equipped ship's SuperPowerController every frame
  // — this is what counts down Twin Fang / Aegis Barrier / Absolute
  // Zero / Void Collapse's active duration and flips them back off
  // automatically once time runs out. Falcon's Overcharge Core has
  // no timer (see SuperPowerController.update), so this is a no-op
  // for it once activated — it simply stays on for the whole level.
  @override
  void update(double dt) {
    super.update(dt);
    energySystem.update(dt);
    _superPower?.update(dt);
  }
}

/// ------------------------------------------------------------
/// WAVE / ENEMIES-LEFT INDICATOR
/// ------------------------------------------------------------

class _WaveIndicator extends StatelessWidget {
  final ValueNotifier<int> waveNotifier;
  final ValueNotifier<int> enemiesLeftNotifier;
  final int totalWaves;

  const _WaveIndicator({
    required this.waveNotifier,
    required this.enemiesLeftNotifier,
    required this.totalWaves,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([waveNotifier, enemiesLeftNotifier]),
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.48),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WAVE ${waveNotifier.value}/$totalWaves',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ENEMIES: ${enemiesLeftNotifier.value}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ------------------------------------------------------------
/// SUPER POWER BUTTON — sits on the same row as the spells
/// detector, right-aligned. Hidden entirely if the equipped ship's
/// super power hasn't been bought (see the purchase section added to
/// SkinsPage). Otherwise shows the power's icon, glows/becomes
/// tappable once it's ready, and shows a live countdown (or "ACTIVE"
/// for Falcon's whole-level Overcharge Core) while it's running.
/// ------------------------------------------------------------

class _SuperPowerButton extends StatelessWidget {
  final SuperPowerController controller;
  final VoidCallback onActivate;

  const _SuperPowerButton({
    required this.controller,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.isOwned) {
      // Power not bought yet on the Skins page — nothing to show.
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        controller.usesRemainingNotifier,
        controller.activeNotifier,
        controller.remainingSecondsNotifier,
      ]),
      builder: (context, _) {
        final data = controller.data;
        final active = controller.activeNotifier.value;
        final usesLeft = controller.usesRemainingNotifier.value;
        final remaining = controller.remainingSecondsNotifier.value;
        final canTap = controller.canActivate;

        String subtitle;
        if (active) {
          subtitle = remaining < 0 ? 'ACTIVE' : '${remaining.ceil()}s';
        } else if (usesLeft > 0) {
          subtitle = 'READY';
        } else {
          subtitle = 'USED';
        }

        final bool glowing = active || canTap;

        return GestureDetector(
          onTap: canTap ? onActivate : null,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.55),
              border: Border.all(
                color: glowing ? data.color : Colors.white24,
                width: active ? 2.4 : 1.8,
              ),
              boxShadow: glowing
                  ? [
                      BoxShadow(
                        color: data.color.withOpacity(active ? 0.55 : 0.30),
                        blurRadius: active ? 18 : 10,
                        spreadRadius: active ? 1 : 0,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  data.icon,
                  color: glowing ? data.color : Colors.white38,
                  size: 22,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: glowing ? Colors.white : Colors.white38,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ------------------------------------------------------------
/// ANIMATED PAUSE DIALOG
/// ------------------------------------------------------------

class _AnimatedPauseDialog extends StatefulWidget {
  final VoidCallback onResume;
  final VoidCallback onHome;
  final VoidCallback onMap;

  const _AnimatedPauseDialog({
    required this.onResume,
    required this.onHome,
    required this.onMap,
  });

  @override
  State<_AnimatedPauseDialog> createState() =>
      _AnimatedPauseDialogState();
}

class _AnimatedPauseDialogState
    extends State<_AnimatedPauseDialog>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _scanController;
  late final AnimationController _lineController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1500,
      ),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(
        seconds: 10,
      ),
    )..repeat();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 2200,
      ),
    )..repeat();

    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1300,
      ),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _scanController.dispose();
    _lineController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _pulseController,
        _rotateController,
        _scanController,
        _lineController,
      ]),
      builder: (context, child) {
        final pulse =
            0.5 + (_pulseController.value * 0.5);

        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            maxWidth: 390,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF26070B),
                Color(0xFF100307),
                Color(0xFF050507),
              ],
            ),
            border: Border.all(
              color: const Color(0xFFFF3D4F),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2438)
                    .withOpacity(
                  0.16 + pulse * 0.12,
                ),
                blurRadius: 45,
                spreadRadius: 3,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.85),
                blurRadius: 40,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              children: [
                /// RED AMBIENT GLOW
                Positioned(
                  top: -130,
                  right: -100,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF263D)
                              .withOpacity(
                            0.22 * pulse,
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                Positioned(
                  bottom: -140,
                  left: -120,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF9B071B)
                              .withOpacity(
                            0.20 * pulse,
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                /// ROTATING TECH RING
                Positioned(
                  top: 20,
                  right: 18,
                  child: Transform.rotate(
                    angle:
                        _rotateController.value *
                            math.pi *
                            2,
                    child: CustomPaint(
                      size: const Size(65, 65),
                      painter: _TechRingPainter(
                        opacity: 0.28,
                      ),
                    ),
                  ),
                ),

                /// SCANNING RED LIGHT
                Positioned(
                  top: 0,
                  left: 20 +
                      (_scanController.value * 240),
                  child: Container(
                    width: 90,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFFFF4655)
                              .withOpacity(0.85),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xFFFF3044),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),

                /// TOP RED LINE
                Positioned(
                  top: 0,
                  left: 25,
                  right: 25,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFFFF3E50)
                              .withOpacity(
                            0.55 +
                                (_lineController.value *
                                    0.4),
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                /// CONTENT
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    22,
                    27,
                    22,
                    22,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AnimatedPauseCore(
                        pulse: pulse,
                        rotation:
                            _rotateController.value,
                      ),

                      const SizedBox(height: 18),

                      const Text(
                        'SYSTEM PAUSED',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                          decoration: TextDecoration.none,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'MISSION TEMPORARILY SUSPENDED',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFFF6672)
                              .withOpacity(0.75),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.7,
                          decoration: TextDecoration.none,
                        ),
                      ),

                      const SizedBox(height: 22),

                      _StatusPanel(
                        pulse: pulse,
                      ),

                      const SizedBox(height: 18),

                      /// RESUME
                      _AnimatedPauseMenuButton(
                        label: 'RESUME MISSION',
                        subtitle: 'CONTINUE FLIGHT',
                        icon: Icons.play_arrow_rounded,
                        color: const Color(0xFFFF3F50),
                        primary: true,
                        onTap: widget.onResume,
                      ),

                      const SizedBox(height: 10),

                      /// MAP
                      _AnimatedPauseMenuButton(
                        label: 'RETURN TO MAP',
                        subtitle: 'END CURRENT FLIGHT',
                        icon: Icons.map_rounded,
                        color: const Color(0xFFFF6670),
                        onTap: widget.onMap,
                      ),

                      const SizedBox(height: 10),

                      /// HOME
                      _AnimatedPauseMenuButton(
                        label: 'MAIN HANGAR',
                        subtitle: 'RETURN TO MAIN MENU',
                        icon: Icons.home_rounded,
                        color: const Color(0xFFFF4655),
                        onTap: widget.onHome,
                      ),

                      const SizedBox(height: 18),

                      /// FOOTER
                      Text(
                        'COSMIC FURY',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.28),
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ------------------------------------------------------------
/// PAUSE CORE
/// ------------------------------------------------------------

class _AnimatedPauseCore extends StatelessWidget {
  final double pulse;
  final double rotation;

  const _AnimatedPauseCore({
    required this.pulse,
    required this.rotation,
  });

  @override
  Widget build(BuildContext context) {
    final glow = 0.15 + (pulse * 0.28);

    return SizedBox(
      width: 105,
      height: 105,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 105,
            height: 105,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF263D)
                      .withOpacity(glow),
                  blurRadius: 32,
                  spreadRadius: 3,
                ),
              ],
            ),
          ),

          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFF3D50)
                    .withOpacity(0.18),
                width: 1,
              ),
            ),
          ),

          Transform.rotate(
            angle: rotation * math.pi * 2,
            child: CustomPaint(
              size: const Size(88, 88),
              painter: _TechRingPainter(
                opacity: 0.75,
              ),
            ),
          ),

          Container(
            width: 77,
            height: 77,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFF4A59)
                    .withOpacity(0.42),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF273C)
                      .withOpacity(0.16),
                  blurRadius: 20,
                ),
              ],
            ),
          ),

          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFF5360)
                      .withOpacity(0.38),
                  const Color(0xFF3B080E)
                      .withOpacity(0.95),
                ],
              ),
              border: Border.all(
                color: const Color(0xFFFF6672)
                    .withOpacity(0.85),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF293D)
                      .withOpacity(0.40),
                  blurRadius: 25,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.pause_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),

          Positioned(
            top: 0,
            child: Container(
              width: 22,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4655),
                borderRadius:
                    BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFFFF263D),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            child: Container(
              width: 22,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4655),
                borderRadius:
                    BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFFFF263D),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            left: 0,
            child: Container(
              width: 3,
              height: 15,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4655),
                borderRadius:
                    BorderRadius.circular(5),
              ),
            ),
          ),

          Positioned(
            right: 0,
            child: Container(
              width: 3,
              height: 15,
              decoration: BoxDecoration(
                color: const Color(0xFFFF4655),
                borderRadius:
                    BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// STATUS PANEL
/// ------------------------------------------------------------

class _StatusPanel extends StatelessWidget {
  final double pulse;

  const _StatusPanel({
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFF1F34)
            .withOpacity(0.035),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFFF4A59)
              .withOpacity(0.20),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF263D)
                  .withOpacity(0.10),
              border: Border.all(
                color: const Color(0xFFFF4D5D)
                    .withOpacity(0.45),
              ),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Color(0xFFFF6670),
              size: 15,
            ),
          ),

          const SizedBox(width: 10),

          Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'SHIP STATUS',
                style: TextStyle(
                  color:
                      Colors.white.withOpacity(0.45),
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'SYSTEM SECURE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),

          const Spacer(),

          AnimatedContainer(
            duration: const Duration(
              milliseconds: 300,
            ),
            width: 8 + (pulse * 2),
            height: 8 + (pulse * 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF4655),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF263D)
                      .withOpacity(0.55),
                  blurRadius: 10 + pulse * 5,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          const Text(
            'SAFE',
            style: TextStyle(
              color: Color(0xFFFF6670),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------------
/// ANIMATED MENU BUTTON
/// ------------------------------------------------------------

class _AnimatedPauseMenuButton extends StatefulWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  const _AnimatedPauseMenuButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.primary = false,
  });

  @override
  State<_AnimatedPauseMenuButton> createState() =>
      _AnimatedPauseMenuButtonState();
}

class _AnimatedPauseMenuButtonState
    extends State<_AnimatedPauseMenuButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool _pressed = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 850,
      ),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() {
      _pressed = true;
    });
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() {
      _pressed = false;
    });

    widget.onTap();
  }

  void _handleTapCancel() {
    setState(() {
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = _controller.value;

        return AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(
            milliseconds: 100,
          ),
          child: GestureDetector(
            onTapDown: _handleTapDown,
            onTapUp: _handleTapUp,
            onTapCancel: _handleTapCancel,
            child: Container(
              width: double.infinity,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    widget.color.withOpacity(
                      widget.primary
                          ? 0.18 + glow * 0.06
                          : 0.075,
                    ),
                    widget.color.withOpacity(
                      widget.primary
                          ? 0.055
                          : 0.025,
                    ),
                  ],
                ),
                borderRadius:
                    BorderRadius.circular(16),
                border: Border.all(
                  color: widget.color.withOpacity(
                    widget.primary
                        ? 0.78 + glow * 0.17
                        : 0.42,
                  ),
                  width:
                      widget.primary ? 1.3 : 1,
                ),
                boxShadow: widget.primary
                    ? [
                        BoxShadow(
                          color: widget.color
                              .withOpacity(
                            0.10 + glow * 0.10,
                          ),
                          blurRadius:
                              15 + glow * 10,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 13),

                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color
                          .withOpacity(0.10),
                      border: Border.all(
                        color: widget.color
                            .withOpacity(0.55),
                      ),
                      boxShadow:
                          widget.primary
                              ? [
                                  BoxShadow(
                                    color: widget.color
                                        .withOpacity(
                                      0.16 +
                                          glow * 0.15,
                                    ),
                                    blurRadius: 12,
                                  ),
                                ]
                              : null,
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.color,
                      size: 20,
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w900,
                            letterSpacing: 1.05,
                            decoration: TextDecoration.none,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            color: Colors.white
                                .withOpacity(0.35),
                            fontSize: 7,
                            fontWeight:
                                FontWeight.w700,
                            letterSpacing: 0.8,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Icon(
                    Icons.chevron_right_rounded,
                    color: widget.color
                        .withOpacity(
                      0.55 + glow * 0.25,
                    ),
                    size: 22,
                  ),

                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ------------------------------------------------------------
/// TECH RING PAINTER
/// ------------------------------------------------------------

class _TechRingPainter extends CustomPainter {
  final double opacity;

  _TechRingPainter({
    required this.opacity,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        math.min(size.width, size.height) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFFFF3E50)
          .withOpacity(opacity);

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      0,
      math.pi * 0.55,
      false,
      paint,
    );

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      math.pi * 0.8,
      math.pi * 0.35,
      false,
      paint,
    );

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      math.pi * 1.55,
      math.pi * 0.3,
      false,
      paint,
    );

    final markerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFF4B5B)
          .withOpacity(opacity);

    for (int i = 0; i < 8; i++) {
      final angle =
          (math.pi * 2 / 8) * i;

      final x =
          center.dx +
          math.cos(angle) * radius;

      final y =
          center.dy +
          math.sin(angle) * radius;

      canvas.drawCircle(
        Offset(x, y),
        1.5,
        markerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _TechRingPainter oldDelegate,
  ) {
    return oldDelegate.opacity != opacity;
  }
}

/// ------------------------------------------------------------
/// PAUSE BUTTON
/// ------------------------------------------------------------

class _PauseButton extends StatefulWidget {
  final VoidCallback onTap;

  const _PauseButton({
    required this.onTap,
  });

  @override
  State<_PauseButton> createState() =>
      _PauseButtonState();
}

class _PauseButtonState
    extends State<_PauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool _pressed = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1200,
      ),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = _controller.value;

        return GestureDetector(
          onTapDown: (_) {
            setState(() {
              _pressed = true;
            });
          },
          onTapUp: (_) {
            setState(() {
              _pressed = false;
            });

            widget.onTap();
          },
          onTapCancel: () {
            setState(() {
              _pressed = false;
            });
          },
          child: AnimatedScale(
            scale: _pressed ? 0.91 : 1.0,
            duration: const Duration(
              milliseconds: 100,
            ),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF5B0A13),
                    Color(0xFF1B0307),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Color(0xFFFF4655),
                  width: 2.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF263D)
                        .withOpacity(
                      0.30 + pulse * 0.20,
                    ),
                    blurRadius:
                        15 + pulse * 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 5,
                    child: Container(
                      width: 38,
                      height: 16,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                        gradient:
                            LinearGradient(
                          colors: [
                            Colors.white
                                .withOpacity(0.20),
                            Colors.white
                                .withOpacity(0.0),
                          ],
                          begin:
                              Alignment.topCenter,
                          end:
                              Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),

                  const Icon(
                    Icons.pause_rounded,
                    color: Colors.white,
                    size: 31,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ------------------------------------------------------------
/// PLAYER HUD — rate/energy row on top, HP bar directly below it,
/// live-updating from playerHealthNotifier / energySystem / maxHealth
/// (the last one folds in Overdrive Core's permanent bonus, passed
/// down from _LevelPageState._effectiveMaxHealth()).
/// ------------------------------------------------------------

class _BottomPlayerHud extends StatelessWidget {
  final SkinData skin;
  final double maxHealth;
  final ValueNotifier<double> healthNotifier;
  final EnergySystem energySystem;
  final VoidCallback onPortraitTap;

  const _BottomPlayerHud({
    required this.skin,
    required this.maxHealth,
    required this.healthNotifier,
    required this.energySystem,
    required this.onPortraitTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: onPortraitTap,
          child: Container(
            width: 55,
            height: 55,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  Colors.black.withOpacity(0.48),
              border: Border.all(
                color: const Color(0xFFFF4655),
                width: 1.7,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF263D)
                      .withOpacity(0.28),
                  blurRadius: 17,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/${skin.asset}',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),

        const SizedBox(width: 9),

        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.only(bottom: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                // ENERGY — sits directly above the HP bar. Half the
                // length of the HP bar, plus the STOP/FIRE/RATE
                // control pills.
                _EnergyRow(energySystem: energySystem),

                const SizedBox(height: 8),

                // HEALTH
                ValueListenableBuilder<double>(
                  valueListenable: healthNotifier,
                  builder: (context, health, _) {
                    final frac = maxHealth > 0
                        ? (health / maxHealth).clamp(0.0, 1.0)
                        : 0.0;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Container(
                                height: 15,
                                decoration:
                                    BoxDecoration(
                                  color: Colors.black
                                      .withOpacity(0.63),
                                  borderRadius:
                                      BorderRadius.circular(
                                    14,
                                  ),
                                  border: Border.all(
                                    color:
                                        const Color(
                                      0xFF45E879,
                                    ).withOpacity(0.78),
                                  ),
                                ),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(
                                    1.5,
                                  ),
                                  child: FractionallySizedBox(
                                    alignment:
                                        Alignment.centerLeft,
                                    widthFactor: frac,
                                    child: Container(
                                      decoration:
                                          BoxDecoration(
                                        borderRadius:
                                            BorderRadius
                                                .circular(14),
                                        gradient:
                                            const LinearGradient(
                                          colors: [
                                            Color(0xFF6FFF9B),
                                            Color(0xFF16C957),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                const Color(
                                              0xFF22E65D,
                                            ).withOpacity(0.65),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 5),

                            /// GREEN HP INDICATOR
                            Container(
                              width: 15,
                              height: 15,
                              decoration:
                                  BoxDecoration(
                                shape: BoxShape.circle,
                                gradient:
                                    const LinearGradient(
                                  colors: [
                                    Color(0xFF6FFF9B),
                                    Color(0xFF16C957),
                                  ],
                                ),
                                border: Border.all(
                                  color:
                                      const Color(
                                    0xFF83FFA7,
                                  ).withOpacity(0.85),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        const Color(
                                      0xFF22E65D,
                                    ).withOpacity(0.65),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        Text(
                          '${health.clamp(0, maxHealth).round()} / ${maxHealth.round()} HP',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w900,
                            letterSpacing: 0.35,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ------------------------------------------------------------
/// ENERGY BAR — sits directly above the HP bar, same full width,
/// blue instead of green. Fills from 0 -> maxEnergy as
/// EnergySystem.energyNotifier reports it. Alongside it:
///
/// - STOP pill (red) — shown while firing is currently allowed.
///   Tapping it manually cuts off firing right away (regardless of
///   how much energy is left) and kicks off the same recharge cycle
///   a natural 0-energy depletion would, so the player can bank
///   energy on purpose.
/// - FIRE pill (blue) — shown once EnergySystem.readyNotifier flips
///   true, which now happens as soon as there's at least
///   EnergySystem.reactivateThreshold energy banked, not only once
///   the bar is completely full. Tapping it re-arms the guns
///   (EnergySystem.reactivate).
/// - RATE pill (grey) — always visible. Cycles through a small set
///   of fire-cadence presets (seconds between shots) each tap, via
///   EnergySystem.setShootInterval, and shows the current value.
///
/// All three pills (STOP/FIRE/RATE) use an enlarged tap target
/// (min 34px tall, generous horizontal padding) and bigger label
/// text (12px vs the old 8px) so they're actually easy to hit and
/// read mid-fight instead of being tiny sliver-buttons.
/// ------------------------------------------------------------

class _EnergyRow extends StatelessWidget {
  final EnergySystem energySystem;

  const _EnergyRow({required this.energySystem});

  // Presets for the RATE pill — seconds between shots. Tapping the
  // pill cycles to the next value in this list, wrapping around.
  static const List<double> _intervalPresets = [1.0, 0.5, 0.35, 0.25, 0.1];

  void _cycleInterval() {
    final current = energySystem.shootIntervalNotifier.value;
    final idx = _intervalPresets.indexWhere(
      (v) => (v - current).abs() < 0.001,
    );
    final nextIdx = (idx + 1) % _intervalPresets.length;
    energySystem.setShootInterval(_intervalPresets[nextIdx]);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        energySystem.energyNotifier,
        energySystem.depletedNotifier,
        energySystem.readyNotifier,
        energySystem.shootIntervalNotifier,
      ]),
      builder: (context, _) {
        final energy = energySystem.energyNotifier.value;
        final maxEnergy = energySystem.maxEnergy;
        final depleted = energySystem.depletedNotifier.value;
        final ready = energySystem.readyNotifier.value;
        final interval = energySystem.shootIntervalNotifier.value;
        final frac =
            maxEnergy > 0 ? (energy / maxEnergy).clamp(0.0, 1.0) : 0.0;

        // Full width — same width as the HP bar directly below it,
        // so the two stack flush on top of each other instead of the
        // energy bar looking like a stub.
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                // Bumped from 11 -> 15 so it stays visually
                // proportionate to the larger control pills beside it.
                height: 15,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.63),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF4DA3FF).withOpacity(0.78),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: frac,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF8FCBFF),
                            Color(0xFF2D8CFF),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2D8CFF)
                                .withOpacity(0.65),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // STOP pill — only while firing is currently allowed
            // (i.e. not already depleted/manually stopped). Lets the
            // player cut firing off on purpose to bank energy.
            if (!depleted) ...[
              const SizedBox(width: 8),
              _EnergyPillButton(
                label: 'STOP',
                onTap: energySystem.stopFiring,
                gradientColors: const [
                  Color(0xFFFF8F8F),
                  Color(0xFFFF3D3D),
                ],
                glowColor: const Color(0xFFFF3D3D),
              ),
            ],

            // FIRE pill — appears as soon as EnergySystem.readyNotifier
            // flips true, which now happens once there's at least
            // enough energy banked to fire again (not only once the
            // bar is completely full).
            if (depleted && ready) ...[
              const SizedBox(width: 8),
              _EnergyPillButton(
                label: 'FIRE',
                onTap: energySystem.reactivate,
                gradientColors: const [
                  Color(0xFF8FCBFF),
                  Color(0xFF2D8CFF),
                ],
                glowColor: const Color(0xFF2D8CFF),
              ),
            ],

            // RATE pill — always visible. Tap to cycle the fire
            // cadence through the preset list and shows the current
            // seconds-between-shots value.
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _cycleInterval,
              child: Container(
                constraints:
                    const BoxConstraints(minWidth: 56, minHeight: 34),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black.withOpacity(0.55),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  '${interval.toStringAsFixed(2)}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shared pill button for STOP/FIRE — pulled out so both get the
/// same bigger, easier-to-tap treatment (min 34px tall touch target,
/// bigger label, opaque hit test over the padding) without
/// duplicating the same decoration/text style twice.
class _EnergyPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final List<Color> gradientColors;
  final Color glowColor;

  const _EnergyPillButton({
    required this.label,
    required this.onTap,
    required this.gradientColors,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 64, minHeight: 34),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(colors: gradientColors),
          boxShadow: [
            BoxShadow(
              color: glowColor.withOpacity(0.6),
              blurRadius: 10,
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// MENU BUTTON
/// ------------------------------------------------------------

class _MenuButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius:
              BorderRadius.circular(14),
          border: Border.all(
            color: color.withOpacity(0.75),
          ),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 19,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight:
                    FontWeight.w900,
                letterSpacing: 0.9,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// STAT
/// ------------------------------------------------------------

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _Stat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(
            color:
                Colors.white.withOpacity(0.80),
            fontSize: 11,
            fontWeight:
                FontWeight.w800,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}