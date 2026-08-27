// spells_animations.dart
//
// Everything about "how the spells work" lives here now, pulled out
// of level_page.dart:
//   - SpellCastController: owns all spell state (timers, shield
//     charges, damage/health buffs) and the actual cast_* logic for
//     every spell. level_page.dart just constructs one and forwards
//     SpellsDetector's onCast to controller.castSpell.
//   - every spell's Flame visual-effect component (barrier, particle
//     bursts, homing missile, black hole, gravity well, etc).
//
// NOTE: these are Flame game components (PositionComponent /
// ParticleSystemComponent), not Flutter widgets — they get added
// straight into the game via `game.add(...)`, they don't build a
// Scaffold or anything else UI-tree-based.
import 'dart:async';
import 'dart:math' as math;

import 'package:cosmic_fury/src/pages/main/level_pages/enemy.dart';
import 'package:cosmic_fury/src/pages/main/main_game_page.dart';
// ^ pulls in MyFlameGame, EnergySystem, ExplosionEffect.
import 'package:cosmic_fury/src/pages/spells/spells_page.dart';
// ^ pulls in SpellData and ownedSpellCountsNotifier (needed for the
//   once-per-level refund on Overdrive Core).
// hide Timer: flame/components.dart exports its own Timer class
// (component-based, different API) which otherwise collides with
// dart:async's Timer used throughout this file for the spell
// duration/tick timers.
import 'package:flame/components.dart' hide Timer;
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

/// ------------------------------------------------------------
/// SPELL CAST CONTROLLER
///
/// Owns every bit of state a spell needs across its lifetime (active
/// flags, charges, timers, permanent buffs) and the cast_* logic
/// itself. Doesn't know about BuildContext/setState directly — it's
/// handed small callbacks for the couple of things that legitimately
/// need the widget layer (triggering a rebuild, showing a snackbar),
/// so it can be unit-tested / reused without a State around it.
///
/// Usage from _LevelPageState:
///   _spellController = SpellCastController(
///     getGame: () => _game,
///     energySystem: _energySystem,
///     playerHealthNotifier: _playerHealthNotifier,
///     effectiveMaxHealth: _effectiveMaxHealth,
///     onStateChanged: () { if (mounted) setState(() {}); },
///     onSnack: _showLevelSnack,
///   );
///   ...
///   SpellsDetector(onCast: _spellController.castSpell)
///   ...
///   dispose() { _spellController.dispose(); ... }
/// ------------------------------------------------------------
class SpellCastController {
  SpellCastController({
    required this.getGame,
    required this.energySystem,
    required this.playerHealthNotifier,
    required this.effectiveMaxHealth,
    required this.onStateChanged,
    this.onSnack,
  });

  /// Lazily resolves the running game. A closure rather than a plain
  /// reference so this controller can be constructed before the
  /// game instance itself exists (the game's constructor needs
  /// [shouldBlockDamage] / [onDamageBlocked] / [shieldRadiusIfActive]
  /// / [totalDamageBonus] from this controller, so the controller
  /// has to exist first) — by the time any cast method actually
  /// calls getGame(), the caller will have finished assigning it.
  final MyFlameGame Function() getGame;

  final EnergySystem energySystem;
  final ValueNotifier<double> playerHealthNotifier;

  /// Ship's current max health (post-upgrade base + Overdrive Core's
  /// permanent bonus). Supplied by the caller since it depends on
  /// the equipped skin, which lives outside this controller.
  final double Function() effectiveMaxHealth;

  /// Called after any cast that changes something the UI reads
  /// directly (Overcharge's damage bonus, Overdrive Core's permanent
  /// buffs) so the widget tree can rebuild.
  final VoidCallback onStateChanged;

  /// Optional — shows a small message (e.g. Overdrive Core's
  /// once-per-level refund notice). Left null-safe so this
  /// controller works fine without a snackbar host too.
  final void Function(String message)? onSnack;

  // ---- Spell-cast state ----

  // Spark Shot's fire-rate buff. For its 5s window the ship simply
  // fires faster (via EnergySystem.setShootInterval) while
  // EnergySystem.setFreeFire(true) is active, which makes
  // registerShot() a complete no-op — energy is never read or spent
  // at all during the window, so there's nothing to force/re-pin and
  // nothing that can trip a depletion. Once the timer fires,
  // free-fire is turned back off and the normal interval is
  // restored, and energy trading resumes exactly where it left off.
  Timer? _sparkShotTimer;

  // Scrap Magnet's health/energy drip.
  Timer? _scrapMagnetTimer;

  // Shield Burst: blocks the next N hits outright (checked/consumed
  // via WaveManager's shouldBlockDamage/onDamageBlocked hooks for
  // ram damage, and via shieldRadiusIfActive below for enemy bullets
  // — both wired in through _LevelFlameGame in level_page.dart) and
  // shows a visible barrier component around the ship for the
  // duration. Whichever runs out first — charges or the 10s timer —
  // ends the shield.
  bool _shieldActive = false;
  int _shieldCharges = 0;
  Timer? _shieldTimer;
  ShieldBarrierComponent? _shieldBarrier;

  // Overcharge: flat bonus added to every player bullet's damage for
  // 10s. Read live by WaveManager (via damageBonusGetter, wired
  // through _LevelFlameGame) at the exact moment a player bullet
  // hits an enemy — see enemy.dart's _handleCollisions.
  double _damageBonus = 0;
  Timer? _overchargeTimer;

  // Overdrive Core (was Phoenix Rebirth): a permanent stat buff
  // rather than a timed one, so it's tracked as plain fields instead
  // of a Timer. Combined with _damageBonus (Overcharge) inside
  // [totalDamageBonus], and combined with the equipped skin's
  // EFFECTIVE (post-upgrade) max health via [effectiveMaxHealth].
  // Once-per-level, gated by _overdriveCoreUsed.
  bool _overdriveCoreUsed = false;
  double _permanentDamageBonus = 0;
  double _permanentMaxHealthBonus = 0;

  // ---- Public read-only state (level_page.dart's HUD/ship-stats
  // sheet reads these) ----

  double get permanentDamageBonus => _permanentDamageBonus;
  double get permanentMaxHealthBonus => _permanentMaxHealthBonus;

  /// Overcharge's timed bonus + Overdrive Core's permanent bonus,
  /// combined live at the moment of impact. This is what
  /// _LevelFlameGame's damageBonusGetter should point at.
  double get totalDamageBonus => _damageBonus + _permanentDamageBonus;

  // ---- Shield hooks — forward these three straight into
  // _LevelFlameGame's constructor in level_page.dart ----

  bool shouldBlockDamage() => _shieldActive && _shieldCharges > 0;

  void onDamageBlocked() {
    _shieldCharges -= 1;
    if (_shieldCharges <= 0) {
      _deactivateShield();
    }
  }

  /// Bullet-vs-shield interception: returns the shield's current
  /// blocking radius while Shield Burst is active and still has
  /// charges left, or null when there's no shield up. WaveManager
  /// uses this to stop enemy bullets the instant they reach the
  /// visible barrier ring around the ship, rather than letting them
  /// travel all the way in to the ship's own hitbox first.
  double? shieldRadiusIfActive() =>
      (_shieldActive && _shieldCharges > 0) ? ShieldBarrierComponent.baseRadius : null;

  void dispose() {
    _sparkShotTimer?.cancel();
    _scrapMagnetTimer?.cancel();
    _shieldTimer?.cancel();
    _overchargeTimer?.cancel();
  }

  // ------------------------------------------------------------
  // SPELL CASTING
  // ------------------------------------------------------------

  void castSpell(SpellData spell) {
    switch (spell.id) {
      case 'spark_shot':
        _castSparkShot();
        break;
      case 'shield_burst':
        _castShieldBurst();
        break;
      case 'nano_repair':
        _castNanoRepair();
        break;
      case 'ice_nova':
        _castIceNova();
        break;
      case 'scrap_magnet':
        _castScrapMagnet();
        break;
      case 'homing_missiles':
        _castHomingMissiles();
        break;
      case 'emp_pulse':
        _castEmpPulse();
        break;
      case 'overcharge':
        _castOvercharge();
        break;
      case 'chain_lightning':
        _castChainLightning();
        break;
      case 'time_warp':
        _castTimeWarp();
        break;
      case 'black_hole':
        _castBlackHole();
        break;
      case 'phoenix_rebirth':
        _castOverdriveCore();
        break;
      case 'solar_flare':
        _castSolarFlare();
        break;
      case 'gravity_well':
        _castGravityWell();
        break;
      case 'singularity_bomb':
        _castSingularityBomb();
        break;
      default:
        // Unknown spell id — no-op.
        break;
    }
  }

  // Fires at a fast 0.10s cadence for 5 seconds. For the whole
  // window the guns simply do not use energy at all: setFreeFire(true)
  // makes EnergySystem.registerShot() a no-op, so nothing is ever
  // read, spent, or force-corrected. When the 5s timer fires,
  // free-fire turns back off and the previous fire interval is
  // restored, and energy trading resumes normally from wherever it
  // already was.
  void _castSparkShot() {
    final previousInterval = energySystem.shootIntervalNotifier.value;

    _sparkShotTimer?.cancel();

    energySystem.setShootInterval(0.10);
    energySystem.setFreeFire(true);

    _sparkShotTimer = Timer(const Duration(seconds: 5), () {
      energySystem.setFreeFire(false);
      energySystem.setShootInterval(previousInterval);
    });
  }

  // Blocks the next 13 hits outright, capped at 10 seconds —
  // whichever runs out first. Ram damage is intercepted in
  // WaveManager._damagePlayer via shouldBlockDamage/onDamageBlocked
  // above; enemy bullets are intercepted even earlier, right at the
  // visible barrier radius, via shieldRadiusIfActive above (see
  // WaveManager._handleCollisions in enemy.dart) — so a bullet
  // visibly stops on the shield itself instead of flying through to
  // the ship and disappearing there. Either kind of blocked hit burns
  // one of the same 13 charges. A pulsing blue barrier component is
  // attached to the game around the ship for the duration.
  void _castShieldBurst() {
    _shieldTimer?.cancel();

    _shieldCharges = 13;
    _shieldActive = true;

    _shieldBarrier?.removeFromParent();
    _shieldBarrier = ShieldBarrierComponent();
    getGame().add(_shieldBarrier!);

    _shieldTimer = Timer(const Duration(seconds: 10), _deactivateShield);
  }

  void _deactivateShield() {
    _shieldTimer?.cancel();
    _shieldActive = false;
    _shieldCharges = 0;
    _shieldBarrier?.removeFromParent();
    _shieldBarrier = null;
  }

  // Heals a flat 60% of this ship's max health (folding in Overdrive
  // Core's permanent bonus if it's active), with a burst of green
  // particles that converge onto the ship as visual feedback.
  void _castNanoRepair() {
    final maxHealth = effectiveMaxHealth();
    final healed = maxHealth * 0.60;
    playerHealthNotifier.value =
        (playerHealthNotifier.value + healed).clamp(0.0, maxHealth);

    getGame().add(NanoRepairEffect(shipPosition: getGame().ship.position.clone()));
  }

  // Freezes up to 7 of the nearest enemies for 4 seconds.
  void _castIceNova() {
    final game = getGame();
    final enemies = game.children.whereType<Enemy>().toList();
    final shipPos = game.ship.position;
    enemies.sort((a, b) => (a.position - shipPos)
        .length2
        .compareTo((b.position - shipPos).length2));
    for (final enemy in enemies.take(7)) {
      enemy.freeze(const Duration(seconds: 4));
    }
  }

  // Drips in a flat 100 health and 15 energy over 10 seconds (not a
  // percentage), in small ticks so it reads as a gradual pull rather
  // than an instant top-up. A continuous stream of small particles
  // (see ScrapMagnetEffect) spawns near active enemies — or, if
  // there are none, near random points around the top of the screen
  // — and streaks in toward the ship for the same 10 seconds: green
  // for the health being pulled, blue for the energy. The green
  // stream isn't just for show — each one actually damages the
  // enemy it came from, so Scrap Magnet is genuinely draining nearby
  // enemies, on top of always healing the player the same flat
  // amount regardless of whether any enemy was around to pull from.
  void _castScrapMagnet() {
    _scrapMagnetTimer?.cancel();

    const totalTicks = 20; // 20 * 500ms = 10s
    const healthPerTick = 100 / totalTicks;
    const energyPerTick = 15 / totalTicks;
    var ticksDone = 0;

    // Visual-only pulling effect, runs for the same 10s window.
    getGame().add(ScrapMagnetEffect());

    _scrapMagnetTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) {
        ticksDone++;
        final maxHealth = effectiveMaxHealth();
        playerHealthNotifier.value =
            (playerHealthNotifier.value + healthPerTick).clamp(0.0, maxHealth);
        energySystem.energyNotifier.value =
            (energySystem.energyNotifier.value + energyPerTick)
                .clamp(0.0, energySystem.maxEnergy);
        if (ticksDone >= totalTicks) timer.cancel();
      },
    );
  }

  // Fires 4 heat-seeking missiles at up to 4 different enemies
  // (closest first). Each missile tracks its own target's live
  // position every frame — "no miss" means it always converges on
  // wherever the target currently is rather than a fixed point. If
  // the target already died from something else before the missile
  // arrives, it just fizzles quietly instead of retargeting.
  void _castHomingMissiles() {
    final game = getGame();
    final enemies = game.children.whereType<Enemy>().toList();
    if (enemies.isEmpty) return;

    final shipPos = game.ship.position;
    enemies.sort((a, b) => (a.position - shipPos)
        .length2
        .compareTo((b.position - shipPos).length2));

    for (final target in enemies.take(4)) {
      game.add(HomingMissile(
        startPosition: game.ship.position.clone(),
        target: target,
        damage: 350,
      ));
    }
  }

  // Disables firing on every enemy currently on screen for 10s —
  // they keep moving/dodging/ramming, they just can't shoot.
  void _castEmpPulse() {
    final game = getGame();
    final enemies = game.children.whereType<Enemy>().toList();
    for (final enemy in enemies) {
      enemy.disableFiring(const Duration(seconds: 10));
    }
    game.add(EmpPulseEffect(shipPosition: game.ship.position.clone()));
  }

  // +70 flat damage on every player bullet for 10s. Read live by
  // WaveManager via damageBonusGetter at the moment of impact — see
  // enemy.dart's _handleCollisions.
  void _castOvercharge() {
    _overchargeTimer?.cancel();
    _damageBonus = 70;
    onStateChanged();
    _overchargeTimer = Timer(const Duration(seconds: 10), () {
      _damageBonus = 0;
      onStateChanged();
    });
  }

  // 4 bolts, 150 damage each, chained round-robin across whatever
  // enemies are on screen: 4+ enemies -> one bolt each; 3 enemies ->
  // the 4th bolt loops back to the first (300 dmg to that one); 2
  // enemies -> 2 bolts each; 1 enemy -> all 4 bolts hit it (600 dmg
  // total). Each bolt is drawn as a jagged lightning segment chained
  // from the previous hit point (starting at the ship).
  void _castChainLightning() {
    final game = getGame();
    final enemies = game.children.whereType<Enemy>().toList();
    if (enemies.isEmpty) return;

    const totalBolts = 4;
    const damagePerBolt = 150.0;
    var previousPoint = game.ship.position.clone();

    for (int i = 0; i < totalBolts; i++) {
      final enemy = enemies[i % enemies.length];
      if (enemy.parent == null) continue; // died mid-chain

      final targetPoint = enemy.position.clone();
      game.add(LightningBoltEffect(from: previousPoint, to: targetPoint));
      enemy.takeDamage(damagePerBolt);
      previousPoint = targetPoint;
    }
  }

  // Slows every enemy currently on screen to 1/3 movement speed and
  // 1/3 bullet speed for 7 seconds.
  void _castTimeWarp() {
    final game = getGame();
    final enemies = game.children.whereType<Enemy>().toList();
    for (final enemy in enemies) {
      enemy.applyTimeWarp(const Duration(seconds: 7));
    }
    game.add(TimeWarpEffect(shipPosition: game.ship.position.clone()));
  }

  // Opens a singularity at the center of the screen. See
  // BlackHoleComponent for the full pull/crush/release logic — it
  // manages its own lifetime (closes after processing 5 enemies or
  // after 10 seconds) entirely on its own once added to the game.
  void _castBlackHole() {
    final game = getGame();
    final center = Vector2(game.size.x / 2, game.size.y / 2);
    game.add(BlackHoleComponent(center: center));
  }

  // Permanently adds +300 max health (healing the same amount right
  // away) and +50 flat bullet damage for the rest of the level.
  // Once-per-level: if it's already been triggered, the cast is
  // refunded (the spent copy is handed straight back to the player)
  // and nothing else happens.
  void _castOverdriveCore() {
    if (_overdriveCoreUsed) {
      final current = ownedSpellCountsNotifier.value;
      ownedSpellCountsNotifier.value = {
        ...current,
        'phoenix_rebirth': (current['phoenix_rebirth'] ?? 0) + 1,
      };
      onSnack?.call('Overdrive Core already active this level.');
      return;
    }

    _overdriveCoreUsed = true;
    _permanentMaxHealthBonus += 300;
    _permanentDamageBonus += 50;
    playerHealthNotifier.value =
        (playerHealthNotifier.value + 300).clamp(0.0, effectiveMaxHealth());
    onStateChanged();

    getGame().add(OverdriveCoreEffect(shipPosition: getGame().ship.position.clone()));
  }

  // Deals a flat 500 damage to every enemy currently on screen the
  // instant it's cast — a single screen-wide flash, no tracking of
  // enemies that spawn afterward.
  void _castSolarFlare() {
    final game = getGame();
    final enemies = game.children.whereType<Enemy>().toList();
    for (final enemy in enemies) {
      if (enemy.parent != null) enemy.takeDamage(500);
    }
    game.add(SolarFlareEffect(screenSize: game.size.clone()));
  }

  // Traps every enemy currently on screen for 6 seconds (frozen in
  // place, no movement or firing) while ticking 30 damage into each
  // of them every half-second. See GravityWellComponent.
  void _castGravityWell() {
    final enemies = getGame()
        .children
        .whereType<Enemy>()
        .where((e) => e.parent != null)
        .toList();
    if (enemies.isEmpty) return;
    getGame().add(GravityWellComponent(trapped: enemies));
  }

  // Sends a bomb from the ship to the center of the screen. On
  // arrival it blasts everything nearby for 1000 damage, then sprays
  // 10 fragments outward in a full circle, each dealing 150 damage
  // to the first enemy it touches. See SingularityBombComponent.
  void _castSingularityBomb() {
    final game = getGame();
    final target = Vector2(game.size.x / 2, game.size.y / 2);
    game.add(SingularityBombComponent(
      start: game.ship.position.clone(),
      target: target,
    ));
  }
}

/// ------------------------------------------------------------
/// SHIELD BARRIER — pulsing blue energy ring drawn around the ship
/// while Shield Burst is active. The radius drawn here
/// ([baseRadius]) is also the exact radius SpellCastController uses
/// (via shieldRadiusIfActive) to tell WaveManager where an enemy
/// bullet gets intercepted, so what you see is what actually blocks
/// bullets — a bullet visibly stops right on this ring instead of
/// flying through to the ship. Ram damage from enemies still goes
/// through shouldBlockDamage / onDamageBlocked.
/// ------------------------------------------------------------

class ShieldBarrierComponent extends PositionComponent
    with HasGameRef<MyFlameGame> {
  double _time = 0;

  // Bumped up from 46 -> 78 so the shield visibly encloses the whole
  // ship with real breathing room, instead of hugging tight around
  // it. Tune further if it still doesn't match your ship's on-screen
  // size. IMPORTANT: this is also the radius used for bullet
  // interception (see SpellCastController.shieldRadiusIfActive) —
  // keep the two in sync, i.e. don't change how far bullets stop
  // without also changing how far the ring is drawn (or vice versa).
  static const double baseRadius = 78;

  ShieldBarrierComponent() : super(anchor: Anchor.center, priority: 5);

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    position = gameRef.ship.position.clone();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final radius = baseRadius + math.sin(_time * 5) * 4;

    final glow = Paint()
      ..color = const Color(0xFF4DA3FF).withOpacity(0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(Offset.zero, radius + 10, glow);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = const Color(0xFF8FCBFF).withOpacity(0.85);
    canvas.drawCircle(Offset.zero, radius, ring);

    final innerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFEAF6FF).withOpacity(0.55);
    canvas.drawCircle(Offset.zero, radius - 8, innerRing);

    final node = Paint()..color = const Color(0xFFCDE9FF).withOpacity(0.9);
    for (int i = 0; i < 6; i++) {
      final angle = (_time * 1.6) + (math.pi * 2 / 6) * i;
      canvas.drawCircle(
        Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        3.0,
        node,
      );
    }
  }
}

/// ------------------------------------------------------------
/// NANO REPAIR EFFECT — little green particles that converge inward
/// onto the ship, spawned once when Nano Repair is cast. Purely
/// visual; the actual 60% heal is applied directly in
/// SpellCastController._castNanoRepair.
/// ------------------------------------------------------------

class NanoRepairEffect extends ParticleSystemComponent {
  NanoRepairEffect({required Vector2 shipPosition})
      : super(
          position: shipPosition,
          anchor: Anchor.center,
          particle: _build(),
        );

  static Particle _build() {
    final rng = math.Random();
    return Particle.generate(
      count: 14,
      lifespan: 0.7,
      generator: (i) {
        final angle = rng.nextDouble() * math.pi * 2;
        final startRadius = 60 + rng.nextDouble() * 40;
        final start =
            Vector2(math.cos(angle), math.sin(angle)) * startRadius;

        return ComputedParticle(
          lifespan: 0.7,
          renderer: (canvas, particle) {
            final t = Curves.easeIn.transform(particle.progress);
            final pos = start * (1 - t); // eases in toward the ship
            final opacity = (1 - particle.progress).clamp(0.0, 1.0);

            canvas.drawCircle(
              pos.toOffset(),
              6,
              Paint()
                ..color = const Color(0xFF45E879).withOpacity(opacity * 0.4)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
            );
            canvas.drawCircle(
              pos.toOffset(),
              3.2,
              Paint()..color = const Color(0xFF6FFF9B).withOpacity(opacity),
            );
          },
        );
      },
    );
  }
}

/// ------------------------------------------------------------
/// SCRAP MAGNET EFFECT — the "pulling" animation for Scrap Magnet.
///
/// Every ~0.18s, for the same 10s duration as the actual drip in
/// SpellCastController._castScrapMagnet, this spawns a single
/// [MagnetParticle] that starts either at a currently-active
/// enemy's position (if there are any on screen) or at a random
/// point near the top of the screen, then streaks in and converges
/// on the ship's live position — green for the health being
/// "pulled", blue for the energy.
///
/// The green (health) stream is no longer just an illusion: each
/// time one spawns from an actual enemy, that enemy is dealt real
/// damage right then via [Enemy.takeDamage] — the same call a player
/// bullet uses — so Scrap Magnet is genuinely tearing health off of
/// nearby enemies, and a weak enemy can be finished off by it. The
/// blue (energy) stream stays purely visual, since enemies don't
/// have an energy stat of their own to drain. If there are no
/// enemies on screen when a health particle would spawn, it just
/// starts from a random point instead — no damage happens on those.
/// ------------------------------------------------------------

class ScrapMagnetEffect extends Component with HasGameRef<MyFlameGame> {
  double _elapsed = 0;
  double _spawnTimer = 0;

  static const double _duration = 10.0;
  static const double _spawnInterval = 0.18;

  /// How much real HP is torn off the sampled enemy every time a
  /// health (green) particle spawns from one. Tuned so a handful of
  /// pulls can meaningfully chip — or finish off — a weak enemy over
  /// the spell's 10s window, without being an instant free kill on
  /// anything durable.
  static const double _healthDrainPerParticle = 8.0;

  final math.Random _rng = math.Random();

  @override
  void update(double dt) {
    super.update(dt);

    _elapsed += dt;

    if (_elapsed < _duration) {
      _spawnTimer += dt;
      if (_spawnTimer >= _spawnInterval) {
        _spawnTimer = 0;
        _spawnParticle();
      }
    } else if (children.isEmpty) {
      // Stop ticking once the window is over and every in-flight
      // particle has finished converging.
      removeFromParent();
    }
  }

  void _spawnParticle() {
    final enemies = gameRef.children.whereType<Enemy>().toList();

    // Alternate roughly evenly between the health (green) and energy
    // (blue) streams so both read clearly instead of one dominating.
    final isHealth = _rng.nextDouble() < 0.6; // slight bias, matches
    // the fact that health is being pulled in a bigger flat amount
    // (100) than energy (15) over the same window.

    Vector2 source;
    Enemy? sourceEnemy;

    if (enemies.isNotEmpty) {
      sourceEnemy = enemies[_rng.nextInt(enemies.length)];
      source = sourceEnemy.position.clone();
    } else {
      source = Vector2(
        _rng.nextDouble() * gameRef.size.x,
        _rng.nextDouble() * gameRef.size.y * 0.5,
      );
    }

    // Actually rip the health off the enemy this particle is
    // streaking away from — real damage, applied immediately, using
    // the same takeDamage path a player bullet uses (handles death,
    // the explosion effect, and WaveManager's counts on its own).
    if (isHealth && sourceEnemy != null) {
      sourceEnemy.takeDamage(_healthDrainPerParticle);
    }

    add(MagnetParticle(
      source: source,
      color: isHealth ? const Color(0xFF6FFF9B) : const Color(0xFF8FCBFF),
    ));
  }
}

/// A single streak that eases from [source] toward wherever the ship
/// currently is (re-sampled every frame, so it still converges
/// correctly even while the ship is moving), then removes itself.
class MagnetParticle extends PositionComponent with HasGameRef<MyFlameGame> {
  final Vector2 source;
  final Color color;

  double _age = 0;
  static const double _life = 0.55;

  MagnetParticle({required this.source, required this.color})
      : super(position: source.clone(), anchor: Anchor.center, priority: 6);

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _life) {
      removeFromParent();
      return;
    }

    final t = Curves.easeIn.transform((_age / _life).clamp(0.0, 1.0));
    final target = gameRef.ship.position;
    position
      ..x = source.x + (target.x - source.x) * t
      ..y = source.y + (target.y - source.y) * t;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final opacity = (1 - (_age / _life)).clamp(0.0, 1.0);

    final glowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset.zero, 5.5, glowPaint);

    final corePaint = Paint()..color = color.withOpacity(opacity);
    canvas.drawCircle(Offset.zero, 2.8, corePaint);
  }
}

/// ------------------------------------------------------------
/// HOMING MISSILE — Tier 2 Homing Missiles. Steers directly at its
/// assigned enemy's live position every frame, so it can't actually
/// miss unless the target dies first (in which case it fizzles
/// quietly instead of retargeting).
/// ------------------------------------------------------------

class HomingMissile extends PositionComponent with HasGameRef<MyFlameGame> {
  final Enemy target;
  final double damage;

  static const double _speed = 620;
  static const double _hitDistance = 22;

  HomingMissile({
    required Vector2 startPosition,
    required this.target,
    required this.damage,
  }) : super(
          position: startPosition,
          size: Vector2(10, 18),
          anchor: Anchor.center,
          priority: 6,
        );

  @override
  void update(double dt) {
    super.update(dt);

    if (target.parent == null) {
      // Target already died from something else — fizzle out.
      removeFromParent();
      return;
    }

    final toTarget = target.position - position;
    final dist = toTarget.length;
    angle = math.atan2(toTarget.y, toTarget.x) + math.pi / 2;

    if (dist <= _hitDistance) {
      target.takeDamage(damage);
      removeFromParent();
      return;
    }

    position += toTarget.normalized() * _speed * dt;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final trailPaint = Paint()
      ..color = const Color(0xFFFF8A5C).withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(Offset(size.x / 2, size.y * 0.8), 7, trailPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFFFD3B8),
    );
  }
}

/// ------------------------------------------------------------
/// EMP PULSE EFFECT — expanding purple ring, purely visual. The
/// actual firing-disable is applied directly in
/// SpellCastController._castEmpPulse via Enemy.disableFiring.
/// ------------------------------------------------------------

class EmpPulseEffect extends ParticleSystemComponent {
  EmpPulseEffect({required Vector2 shipPosition})
      : super(
          position: shipPosition,
          anchor: Anchor.center,
          particle: _build(),
        );

  static Particle _build() {
    return ComputedParticle(
      lifespan: 0.6,
      renderer: (canvas, particle) {
        final progress = particle.progress;
        final radius = 30 + progress * 260;
        final opacity = (1 - progress).clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset.zero,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * (1 - progress) + 1
            ..color = const Color(0xFFB68CFF).withOpacity(opacity * 0.85),
        );
      },
    );
  }
}

/// ------------------------------------------------------------
/// LIGHTNING BOLT EFFECT — a single jagged bolt segment for Chain
/// Lightning, drawn from [from] to [to] and gone in a flash. One of
/// these is spawned per bolt in
/// SpellCastController._castChainLightning, chained from the
/// previous hit point (starting at the ship).
/// ------------------------------------------------------------

class LightningBoltEffect extends PositionComponent
    with HasGameRef<MyFlameGame> {
  final Vector2 from;
  final Vector2 to;

  double _age = 0;
  static const double _life = 0.22;
  late final List<Offset> _jaggedPoints;

  LightningBoltEffect({required this.from, required this.to})
      : super(priority: 7) {
    final rng = math.Random();
    const segments = 6;
    _jaggedPoints = List.generate(segments + 1, (i) {
      final t = i / segments;
      final base = Offset(
        from.x + (to.x - from.x) * t,
        from.y + (to.y - from.y) * t,
      );
      if (i == 0 || i == segments) return base;
      final perp = (rng.nextDouble() - 0.5) * 18;
      return base + Offset(perp, perp);
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final opacity = (1 - (_age / _life)).clamp(0.0, 1.0);
    final path = Path()
      ..moveTo(_jaggedPoints.first.dx, _jaggedPoints.first.dy);
    for (final p in _jaggedPoints.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = const Color(0xFF6FE3FF).withOpacity(opacity * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = Colors.white.withOpacity(opacity),
    );
  }
}

/// ------------------------------------------------------------
/// TIME WARP EFFECT — expanding lavender ring, purely visual. The
/// actual slow is applied directly in
/// SpellCastController._castTimeWarp via Enemy.applyTimeWarp.
/// ------------------------------------------------------------

class TimeWarpEffect extends ParticleSystemComponent {
  TimeWarpEffect({required Vector2 shipPosition})
      : super(
          position: shipPosition,
          anchor: Anchor.center,
          particle: _build(),
        );

  static Particle _build() {
    return ComputedParticle(
      lifespan: 0.7,
      renderer: (canvas, particle) {
        final progress = particle.progress;
        final radius = 20 + progress * 300;
        final opacity = (1 - progress).clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset.zero,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFFC9A6FF).withOpacity(opacity * 0.7),
        );
      },
    );
  }
}

/// ------------------------------------------------------------
/// BLACK HOLE — Tier 3 Black Hole. Spawns at the center of the
/// screen, hunts down the nearest un-processed enemies within its
/// pull radius and drags each one straight toward its center
/// (several can be mid-pull at once — whatever's open of the 5
/// slots). An enemy that arrives at the center with under 400 health
/// is crushed outright; one with 400 or more instead takes a flat
/// 400 damage and is permanently released from this hole, free to
/// act normally again. The hole closes itself the instant it's
/// processed 5 enemies, or after 10 seconds — whichever happens
/// first.
///
/// Enemies being pulled are kept immobile/silent via Enemy.freeze(),
/// refreshed every frame with a short duration — so if this
/// component is ever removed mid-pull, any enemy it was holding
/// self-releases within a fraction of a second instead of staying
/// frozen forever.
/// ------------------------------------------------------------

class BlackHoleComponent extends PositionComponent
    with HasGameRef<MyFlameGame> {
  static const double _duration = 10.0;
  static const int _maxProcessed = 5;
  static const double _pullRadius = 520;
  static const double _pullSpeed = 240;
  static const double _arriveDistance = 16;
  static const double _weakHealthThreshold = 400;
  static const double _toughDamage = 400;

  double _elapsed = 0;
  double _time = 0;
  int _processed = 0;
  final List<Enemy> _pulling = [];
  final Set<Enemy> _released = {};

  BlackHoleComponent({required Vector2 center})
      : super(position: center, anchor: Anchor.center, priority: 8);

  @override
  void update(double dt) {
    super.update(dt);

    if (_processed >= _maxProcessed || _elapsed >= _duration) {
      removeFromParent();
      return;
    }

    _elapsed += dt;
    _time += dt;

    _pulling.removeWhere((e) => e.parent == null);

    var slotsOpen = _maxProcessed - _processed - _pulling.length;
    if (slotsOpen > 0) {
      final candidates = gameRef.children
          .whereType<Enemy>()
          .where((e) =>
              e.parent != null &&
              !_pulling.contains(e) &&
              !_released.contains(e))
          .toList()
        ..sort((a, b) => (a.position - position)
            .length2
            .compareTo((b.position - position).length2));

      for (final enemy in candidates) {
        if (slotsOpen <= 0) break;
        if ((enemy.position - position).length > _pullRadius) continue;
        _pulling.add(enemy);
        slotsOpen--;
      }
    }

    for (final enemy in List<Enemy>.from(_pulling)) {
      if (enemy.parent == null) continue;

      // Refreshed every frame — see class doc above.
      enemy.freeze(const Duration(milliseconds: 250));

      final toCenter = position - enemy.position;
      final dist = toCenter.length;
      if (dist <= _arriveDistance) {
        _resolveEnemy(enemy);
        continue;
      }
      final moveDist = math.min(dist, _pullSpeed * dt);
      enemy.position += toCenter.normalized() * moveDist;
    }
  }

  void _resolveEnemy(Enemy enemy) {
    _pulling.remove(enemy);
    _processed++;
    if (enemy.health < _weakHealthThreshold) {
      enemy.takeDamage(enemy.health + 1);
    } else {
      enemy.takeDamage(_toughDamage);
      _released.add(enemy);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final growth = (_processed / _maxProcessed).clamp(0.0, 1.0);
    final baseRadius = 34.0 + growth * 14;

    canvas.drawCircle(
      Offset.zero,
      baseRadius + 55,
      Paint()
        ..color = const Color(0xFF8B7CFF).withOpacity(0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );

    for (int i = 0; i < 3; i++) {
      final ringRadius = baseRadius + 14 + i * 16.0;
      final angle = _time * (1.2 + i * 0.5) * (i.isEven ? 1 : -1);
      canvas.save();
      canvas.rotate(angle);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: ringRadius),
        0,
        math.pi * 1.4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFFB68CFF).withOpacity(0.55 - i * 0.12),
      );
      canvas.restore();
    }

    canvas.drawCircle(
      Offset.zero,
      baseRadius,
      Paint()..color = const Color(0xFF05030A),
    );
    canvas.drawCircle(
      Offset.zero,
      baseRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFCBB6FF).withOpacity(0.75),
    );
  }
}

/// ------------------------------------------------------------
/// OVERDRIVE CORE EFFECT — a triumphant golden burst around the ship
/// (expanding ring + outward sparks) played once when Overdrive Core
/// is cast. Deliberately expands OUTWARD rather than converging
/// inward like Nano Repair's effect, so a permanent buff reads
/// differently at a glance from a heal. Purely visual — the actual
/// permanent +300 health / +50 damage is applied directly in
/// SpellCastController._castOverdriveCore.
/// ------------------------------------------------------------

class OverdriveCoreEffect extends ParticleSystemComponent {
  OverdriveCoreEffect({required Vector2 shipPosition})
      : super(
          position: shipPosition,
          anchor: Anchor.center,
          particle: _build(),
        );

  static Particle _build() {
    final rng = math.Random();

    final ring = ComputedParticle(
      lifespan: 0.9,
      renderer: (canvas, particle) {
        final progress = particle.progress;
        final radius = 20 + progress * 130;
        final opacity = (1 - progress).clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset.zero,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * (1 - progress) + 1
            ..color = const Color(0xFFFFB25C).withOpacity(opacity * 0.85),
        );
      },
    );

    final sparks = Particle.generate(
      count: 20,
      lifespan: 0.75,
      generator: (i) {
        final angle = rng.nextDouble() * math.pi * 2;
        final speed = 90 + rng.nextDouble() * 140;
        final velocity = Vector2(math.cos(angle), math.sin(angle)) * speed;
        return AcceleratedParticle(
          speed: velocity,
          acceleration: velocity * -1.0,
          child: CircleParticle(
            radius: 2.2 + rng.nextDouble() * 2.4,
            paint: Paint()..color = const Color(0xFFFFD9A0),
          ),
        );
      },
    );

    return ComposedParticle(children: [ring, sparks]);
  }
}

/// ------------------------------------------------------------
/// SOLAR FLARE EFFECT — a whole-screen wash plus a bright band that
/// sweeps top -> bottom once, timed to when Solar Flare's flat 500
/// damage is actually applied in
/// SpellCastController._castSolarFlare (which happens instantly,
/// before this even starts playing).
/// ------------------------------------------------------------

class SolarFlareEffect extends PositionComponent {
  final Vector2 screenSize;
  double _age = 0;
  static const double _life = 0.55;

  SolarFlareEffect({required this.screenSize})
      : super(position: Vector2.zero(), priority: 9);

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final t = (_age / _life).clamp(0.0, 1.0);
    final opacity = (1 - t).clamp(0.0, 1.0);

    // Whole-screen flash wash.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, screenSize.x, screenSize.y),
      Paint()..color = const Color(0xFFFFE9A8).withOpacity(opacity * 0.28),
    );

    // A bright sweeping band that travels top -> bottom.
    final bandY = screenSize.y * t;
    final bandRect = Rect.fromLTWH(0, bandY - 40, screenSize.x, 80);
    canvas.drawRect(
      bandRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFFFFD65C).withOpacity(opacity * 0.9),
            Colors.transparent,
          ],
        ).createShader(bandRect),
    );
  }
}

/// ------------------------------------------------------------
/// GRAVITY WELL — Tier 3 Gravity Well. Freezes every enemy that was
/// on screen when it was cast for 6 seconds (no movement, no firing)
/// while ticking 30 damage into each of them every half-second — up
/// to 360 damage total per enemy if the well runs its full course.
/// Purely a debuff/DoT field; unlike Black Hole it doesn't move
/// enemies around, just locks them where they already are.
/// ------------------------------------------------------------

class GravityWellComponent extends PositionComponent {
  static const double _duration = 6.0;
  static const double _tickInterval = 0.5;
  static const double _damagePerTick = 30;

  final List<Enemy> trapped;

  double _elapsed = 0;
  double _tickTimer = 0;
  double _time = 0;

  GravityWellComponent({required this.trapped})
      : super(anchor: Anchor.center, priority: 4);

  @override
  Future<void> onLoad() async {
    super.onLoad();
    position = _averagePosition();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    trapped.removeWhere((e) => e.parent == null);
    if (trapped.isEmpty) {
      removeFromParent();
      return;
    }

    _elapsed += dt;
    if (_elapsed >= _duration) {
      removeFromParent();
      return;
    }

    for (final enemy in trapped) {
      // Refreshed every frame — self-releases quickly once the well
      // ends or this component is removed.
      enemy.freeze(const Duration(milliseconds: 250));
    }

    _tickTimer += dt;
    if (_tickTimer >= _tickInterval) {
      _tickTimer = 0;
      for (final enemy in List<Enemy>.from(trapped)) {
        if (enemy.parent != null) {
          enemy.takeDamage(_damagePerTick);
        }
      }
    }
  }

  Vector2 _averagePosition() {
    var sumX = 0.0;
    var sumY = 0.0;
    for (final e in trapped) {
      sumX += e.position.x;
      sumY += e.position.y;
    }
    final count = trapped.length.toDouble();
    return Vector2(sumX / count, sumY / count);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Faint distortion ring around every still-trapped enemy.
    for (final enemy in trapped) {
      if (enemy.parent == null) continue;
      final rel = (enemy.position - position).toOffset();
      final pulse = 26 + math.sin(_time * 4 + enemy.hashCode) * 4;
      canvas.drawCircle(
        rel,
        pulse,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFF7C8CFF).withOpacity(0.5),
      );
    }

    // Central swirling gravity core at the trap's centroid.
    const coreRadius = 22.0;
    canvas.drawCircle(
      Offset.zero,
      coreRadius + 40,
      Paint()
        ..color = const Color(0xFF4B3FCF).withOpacity(0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    for (int i = 0; i < 3; i++) {
      final angle = _time * (1.0 + i * 0.4) * (i.isEven ? 1 : -1);
      canvas.save();
      canvas.rotate(angle);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: coreRadius + i * 10),
        0,
        math.pi * 1.1,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = const Color(0xFF9B8CFF).withOpacity(0.6 - i * 0.15),
      );
      canvas.restore();
    }
  }
}

/// ------------------------------------------------------------
/// SINGULARITY BOMB — Tier 3 Singularity Bomb. Lobs a bomb from the
/// ship to the center of the screen; on arrival it detonates for
/// 1000 damage to anything caught in the blast radius, then sprays
/// 10 fragments outward in a full circle, each dealing 150 damage to
/// the first enemy it touches.
///
/// Sizing note: the blast radius, the explosion visual, the bomb's
/// in-flight appearance, and the fragments were all scaled up
/// together (blast radius/explosion effect ~3x; bomb + fragments
/// visually bigger; fragments travel much farther before fizzling)
/// so the whole spell reads as a genuinely huge detonation instead
/// of a small local burst.
/// ------------------------------------------------------------

class SingularityBombComponent extends PositionComponent
    with HasGameRef<MyFlameGame> {
  final Vector2 start;
  final Vector2 target;

  static const double _travelTime = 0.8;

  // Blast radius tripled (150 -> 450) so the detonation itself
  // covers a much bigger area of the screen.
  static const double _blastRadius = 450;
  static const double _blastDamage = 1000;
  static const int _fragmentCount = 10;

  double _age = 0;
  bool _detonated = false;

  SingularityBombComponent({required this.start, required this.target})
      : super(position: start.clone(), anchor: Anchor.center, priority: 8);

  @override
  void update(double dt) {
    super.update(dt);
    if (_detonated) return;

    _age += dt;
    final t = Curves.easeIn.transform((_age / _travelTime).clamp(0.0, 1.0));
    position
      ..x = start.x + (target.x - start.x) * t
      ..y = start.y + (target.y - start.y) * t;

    if (_age >= _travelTime) {
      _detonate();
    }
  }

  void _detonate() {
    _detonated = true;

    for (final enemy in gameRef.children.whereType<Enemy>().toList()) {
      if (enemy.parent == null) continue;
      if ((enemy.position - target).length <= _blastRadius) {
        enemy.takeDamage(_blastDamage);
      }
    }

    // Explosion visual tripled (3.2 -> 9.6) to match the tripled
    // blast radius, so the huge flash on screen lines up with what
    // actually gets hit.
    gameRef.add(ExplosionEffect(position: target.clone(), scale: 9.6));

    for (int i = 0; i < _fragmentCount; i++) {
      final angle = (math.pi * 2 / _fragmentCount) * i;
      final direction = Vector2(math.cos(angle), math.sin(angle));
      gameRef.add(BombFragment(
        startPosition: target.clone(),
        direction: direction,
      ));
    }

    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_detonated) return;

    // Bomb's in-flight visual bumped up (glow 16 -> 34, core 9 -> 18)
    // so it reads as a much heavier, bigger payload while it travels
    // toward the target, matching the bigger detonation to come.
    final glow = Paint()
      ..color = const Color(0xFFFF4D4D).withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(Offset.zero, 34, glow);

    canvas.drawCircle(Offset.zero, 18, Paint()..color = const Color(0xFF2A0A0A));
    canvas.drawCircle(
      Offset.zero,
      18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = const Color(0xFFFF8A5C).withOpacity(0.85),
    );
  }
}

/// A single circular-burst fragment from Singularity Bomb's
/// detonation — travels outward in a straight line from [direction]
/// and disappears the instant it touches an enemy (dealing 150
/// damage) or after its lifespan/off-screen check runs out.
///
/// Fragments now fly noticeably farther (faster + longer-lived) and
/// are visually bigger, to match the bomb's bigger blast.
class BombFragment extends PositionComponent with HasGameRef<MyFlameGame> {
  final Vector2 direction;

  // Speed and lifespan both increased so fragments cover roughly 3x
  // the distance they used to before fizzling out (was
  // ~460 * 0.7 ≈ 322px max travel; now ~700 * 1.3 ≈ 910px).
  static const double _speed = 700;
  static const double _damage = 150;
  static const double _hitDistance = 32;
  static const double _life = 1.3;

  double _age = 0;

  BombFragment({required Vector2 startPosition, required this.direction})
      : super(
          position: startPosition,
          // Fragment size doubled (9 -> 18) to match the bigger bomb
          // and blast.
          size: Vector2.all(18),
          anchor: Anchor.center,
          priority: 7,
        );

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_age >= _life) {
      removeFromParent();
      return;
    }

    position += direction * _speed * dt;

    for (final enemy in gameRef.children.whereType<Enemy>().toList()) {
      if (enemy.parent == null) continue;
      if ((enemy.position - position).length <= _hitDistance) {
        enemy.takeDamage(_damage);
        removeFromParent();
        return;
      }
    }

    final s = gameRef.size;
    if (position.x < -40 ||
        position.x > s.x + 40 ||
        position.y < -40 ||
        position.y > s.y + 40) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final opacity = (1 - (_age / _life)).clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..color = const Color(0xFFFF4D4D).withOpacity(opacity * 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), size.x, glowPaint);
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      size.x / 2,
      Paint()..color = const Color(0xFFFFB25C).withOpacity(opacity),
    );
  }
}