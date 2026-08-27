import 'dart:math';

import 'package:cosmic_fury/src/pages/main/level_pages/level_config.dart';
import 'package:cosmic_fury/src/pages/main/main_game_page.dart';
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

/// A single enemy ship. Drops in from above the screen down to an
/// initial holding line, then WANDERS to random points anywhere
/// within the top [Enemy._wanderAreaBottomFraction] (60%) of the
/// screen — never chasing or converging on the player's X position,
/// so a wave spreads out and drifts on its own instead of stacking
/// up wherever the player happens to be. Still dodges incoming
/// player bullets when it can, and fires bursts at the player at a
/// fixed interval. Dies (and reports itself via [onDefeated]) once
/// its health hits zero.
class Enemy extends SpriteComponent with HasGameRef<MyFlameGame> {
  final double maxHealth;
  double health;

  /// Damage dealt to the player on contact (kamikaze/ram collision).
  final double ramDamage;

  final int bulletsPerBurst;
  final double fireInterval;
  final double bulletSpeed;
  final double bulletDamage;
  final Color bulletColor;

  final double trackSpeed;
  final double descendSpeed;

  /// Vestigial — no longer used to steer movement (enemies wander
  /// randomly now instead of tracking the player's X + a formation
  /// slot). Kept only so WaveManager's existing formation-grid setup
  /// doesn't need to change; safe to ignore/remove entirely later.
  final double formationOffsetX;

  /// Called once, right before this enemy removes itself, so
  /// [WaveManager] can update its counts.
  final void Function(Enemy enemy) onDefeated;

  /// Frostbyte's Absolute Zero super power (see ship_super_powers.dart
  /// / level_page.dart) reaches every enemy — including ones that
  /// spawn WHILE it's active — through this live getter, supplied by
  /// WaveManager. Returns 1.0 normally, or the slow multiplier
  /// (1/3) while the power is active. Multiplies the entrance drop
  /// speed, the wander/dodge speed, AND (see [_fireBurst]) the speed
  /// of this enemy's own outgoing bullets, every frame. Null on
  /// ships with no super power owned (WaveManager just doesn't pass
  /// one, since there's nothing to slow with).
  final double Function()? externalSpeedMultiplierGetter;

  double _fireTimer = 0;
  double _ramCooldown = 0;
  bool _reachedHoldLine = false;
  double _holdY = 0;
  final double _holdYFraction;
  bool _defeated = false;

  /// Latest value read from [externalSpeedMultiplierGetter] this
  /// frame — cached as a field (rather than only a local in update())
  /// so [_fireBurst] can also read it when a burst actually fires,
  /// without needing to call the getter a second time.
  double _externalSpeedMultiplier = 1.0;

  // ------------------------------------------------------------
  // FREEZE — used by the Ice Nova spell (see level_page.dart).
  // While frozen, this enemy skips movement AND firing entirely
  // (its wander/dodge timers just don't advance), but it can still
  // be hit and killed normally. A light blue overlay renders on top
  // of the sprite for the duration so it's obvious at a glance.
  // ------------------------------------------------------------
  bool _frozen = false;
  double _freezeTimer = 0;

  /// Freezes this enemy for [duration] — pauses its movement and
  /// firing, but it can still take damage/die while frozen. Calling
  /// this again while already frozen just refreshes the timer to the
  /// new duration rather than stacking.
  void freeze(Duration duration) {
    if (_defeated) return;
    _frozen = true;
    _freezeTimer = duration.inMilliseconds / 1000.0;
  }

  // ------------------------------------------------------------
  // EMP PULSE — used by the EMP Pulse spell (see level_page.dart).
  // Disables firing ONLY — movement, dodging, wandering, and ramming
  // all keep working exactly as normal, the enemy just can't shoot
  // for the duration. A light purple border overlay renders on top
  // of the sprite so it's obvious at a glance which enemies are
  // silenced.
  // ------------------------------------------------------------
  bool _bulletsDisabled = false;
  double _disableFireTimer = 0;

  /// Disables this enemy's firing for [duration]. Calling this again
  /// while already disabled just refreshes the timer rather than
  /// stacking.
  void disableFiring(Duration duration) {
    if (_defeated) return;
    _bulletsDisabled = true;
    _disableFireTimer = duration.inMilliseconds / 1000.0;
  }

  // ------------------------------------------------------------
  // TIME WARP — used by the Time Warp spell (see level_page.dart).
  // Slows both wander/dodge movement AND outgoing bullet speed to
  // 1/3 for the duration. fireInterval itself (how OFTEN it shoots)
  // is untouched — only how fast it moves and how fast its bullets
  // travel once fired. A light lavender border overlay renders on
  // top of the sprite for the duration.
  // ------------------------------------------------------------
  double _slowMultiplier = 1.0;
  double _slowTimer = 0;

  /// Slows this enemy's movement + bullet speed to 1/3 for
  /// [duration]. Calling this again while already slowed just
  /// refreshes the timer rather than stacking.
  void applyTimeWarp(Duration duration) {
    if (_defeated) return;
    _slowMultiplier = 1 / 3;
    _slowTimer = duration.inMilliseconds / 1000.0;
  }

  // ------------------------------------------------------------
  // RANDOM WANDER — replaces the old player-tracking + formation
  // logic. Once an enemy reaches its initial holding line, it picks
  // a random point anywhere within the top [_wanderAreaBottomFraction]
  // of the screen, drifts toward it, then — once it arrives (or a
  // randomized timer runs out first) — picks a fresh random point
  // and repeats. This is what keeps a wave spread out and roaming
  // instead of converging on/stacking near the player.
  // ------------------------------------------------------------

  /// How far down the screen (as a fraction of screen height) an
  /// enemy is allowed to wander. 0.6 = enemies roam anywhere in the
  /// top 60% of the screen, never drifting into the player's zone.
  static const double _wanderAreaBottomFraction = 0.60;

  static const double _wanderMinIntervalSeconds = 1.8;
  static const double _wanderMaxIntervalSeconds = 3.6;

  /// Distance from the target at which it's considered "arrived" and
  /// a new random target gets picked early (before the timer runs out).
  static const double _wanderArriveDistance = 14;

  Vector2 _wanderTarget = Vector2.zero();
  double _wanderTimer = 0;
  double _wanderInterval = 0;

  /// Per-enemy speed personality so a whole wave doesn't drift in
  /// lockstep — each enemy wanders a little faster or slower.
  late final double _wanderSpeedMultiplier;

  /// Smoothed dodge offset — eased toward a freshly-computed target
  /// each frame instead of snapping, so avoidance reads as a swerve
  /// rather than a twitch.
  double _dodgeOffset = 0;

  /// How far below the enemy (in px) a player bullet has to be to
  /// register as "approaching" and worth dodging.
  static const double _dodgeDetectionRange = 240;

  /// How close in X a bullet needs to be to actually trigger a dodge.
  static const double _dodgeXThreshold = 46;

  /// Max lateral distance a dodge can push the enemy from its
  /// current wander target.
  static const double _maxDodgeOffset = 90;

  final Random _rng = Random();

  Enemy({
    required Sprite sprite,
    required Vector2 startPosition,
    required double enemySize,
    required this.maxHealth,
    required this.ramDamage,
    required this.bulletsPerBurst,
    required this.fireInterval,
    required this.bulletSpeed,
    required this.bulletDamage,
    required this.bulletColor,
    required this.trackSpeed,
    required this.descendSpeed,
    required this.onDefeated,
    bool flipVertically = false,
    double holdYFraction = 0.28,
    this.formationOffsetX = 0,
    this.externalSpeedMultiplierGetter,
  })  : health = maxHealth,
        _holdYFraction = holdYFraction,
        super(
          sprite: sprite,
          position: startPosition,
          size: Vector2.all(enemySize),
          anchor: Anchor.center,
        ) {
    // Sprite art points "up" by default (same convention as the
    // player ship); rotate 180° so it visually faces the player
    // instead of flying backwards.
    if (flipVertically) {
      angle = pi;
    }

    // ~0.65–1.15x trackSpeed, randomized per enemy.
    _wanderSpeedMultiplier = 0.65 + _rng.nextDouble() * 0.5;
  }

  /// Hit box for collisions vs player bullets / the player ship —
  /// tighter than the full sprite bounds, matching Ship.hitRect.
  Rect hitRect() => Rect.fromCenter(
        center: position.toOffset(),
        width: size.x * 0.5,
        height: size.y * 0.5,
      );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Random-ish holding line so a wave doesn't all stack on one row.
    final jitter = _rng.nextDouble() * 60 - 30;
    _holdY = gameRef.size.y * _holdYFraction + jitter;
  }

  /// Applies damage; removes and reports itself once health hits 0.
  void takeDamage(double amount) {
    if (_defeated) return;
    health -= amount;
    if (health <= 0) {
      _defeated = true;
      onDefeated(this);
      // Explosion burst at the enemy's last position, scaled to its
      // sprite size so bigger enemies get a bigger blast.
      gameRef.add(ExplosionEffect(
        position: position.clone(),
        scale: size.x / 45,
      ));
      removeFromParent();
    }
  }

  /// Ram damage has a short cooldown so standing in an enemy doesn't
  /// delete the player's HP in a single frame — returns true if this
  /// call should actually apply damage.
  bool tryRam() {
    if (_ramCooldown <= 0) {
      _ramCooldown = 1.0;
      return true;
    }
    return false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_defeated) return;

    // Frostbyte's Absolute Zero (or any future external slow) — read
    // once per frame, cached to a field so _fireBurst can reuse it
    // without calling the getter again, and applied to the entrance
    // drop speed, the wander/dodge speed below, AND this enemy's own
    // outgoing bullet speed (see _fireBurst). 1.0 when no super
    // power is active/owned.
    _externalSpeedMultiplier = externalSpeedMultiplierGetter?.call() ?? 1.0;
    final double externalSpeedMultiplier = _externalSpeedMultiplier;

    // Frozen: ram cooldown still ticks down (so a frozen enemy
    // doesn't instantly ram the moment it thaws if the player is
    // already touching it) but movement, dodging, wandering, and
    // firing are all skipped entirely.
    if (_frozen) {
      if (_ramCooldown > 0) {
        _ramCooldown -= dt;
      }
      _freezeTimer -= dt;
      if (_freezeTimer <= 0) {
        _frozen = false;
      } else {
        return;
      }
    }

    // EMP Pulse — ticks down independently of movement/frozen state.
    if (_bulletsDisabled) {
      _disableFireTimer -= dt;
      if (_disableFireTimer <= 0) {
        _bulletsDisabled = false;
      }
    }

    // Time Warp — ticks down independently too.
    if (_slowMultiplier != 1.0) {
      _slowTimer -= dt;
      if (_slowTimer <= 0) {
        _slowMultiplier = 1.0;
      }
    }

    if (_ramCooldown > 0) {
      _ramCooldown -= dt;
    }

    if (!_reachedHoldLine) {
      // Entrance drop — unchanged, still allowed to come in from
      // above the visible screen. Slowed by Absolute Zero just like
      // wandering enemies are.
      position.y += descendSpeed * externalSpeedMultiplier * dt;
      if (position.y >= _holdY) {
        position.y = _holdY;
        _reachedHoldLine = true;
        // Kick off wandering immediately with a fresh random target
        // instead of sitting still on the holding line.
        _pickNewWanderTarget();
      }
    } else {
      _wanderTimer += dt;

      final distToTarget = (position - _wanderTarget).length;
      if (_wanderTimer >= _wanderInterval ||
          distToTarget <= _wanderArriveDistance) {
        _pickNewWanderTarget();
      }

      // Steer away from any player bullet on a likely collision
      // course, eased toward the freshly computed dodge each frame.
      final desiredDodge = _computeDodgeOffset();
      _dodgeOffset += (desiredDodge - _dodgeOffset) * min(1.0, dt * 6);

      final target = _wanderTarget + Vector2(_dodgeOffset, 0);
      final delta = target - position;
      final deltaLength = delta.length;
      if (deltaLength > 1) {
        // Dodging feels snappier than the base wander speed; casual
        // wandering stays at the randomized personality pace. Time
        // Warp (_slowMultiplier) and Absolute Zero
        // (externalSpeedMultiplier) both scale the whole thing down
        // when active — they can stack (e.g. Time Warp cast while
        // Absolute Zero is running).
        final urgency = _dodgeOffset.abs() > 8 ? 1.6 : 1.0;
        final moveDist = min(
          deltaLength,
          trackSpeed *
              _wanderSpeedMultiplier *
              urgency *
              _slowMultiplier *
              externalSpeedMultiplier *
              dt,
        );
        position += delta.normalized() * moveDist;
      }
    }

    // Hard clamp so an enemy can never drift off past the visible
    // play area, regardless of wander/dodge math.
    final halfW = size.x * 0.5;
    position.x = position.x.clamp(halfW, gameRef.size.x - halfW);

    if (_reachedHoldLine) {
      // Keep wandering enemies within a sane vertical band — never
      // above the very top edge, never drifting down toward the
      // player's movement zone.
      final minY = size.y * 0.5;
      final maxY = gameRef.size.y * _wanderAreaBottomFraction;
      position.y = position.y.clamp(minY, maxY);
    }

    _fireTimer += dt;
    if (_fireTimer >= fireInterval) {
      _fireTimer = 0;
      _fireBurst();
    }
  }

  /// Picks a fresh random destination anywhere within the top
  /// [_wanderAreaBottomFraction] of the screen (respecting the
  /// enemy's own half-size so it doesn't clip past the edges), and a
  /// randomized dwell interval before the next pick.
  void _pickNewWanderTarget() {
    final s = gameRef.size;
    final halfW = size.x * 0.5;
    final minX = halfW;
    final maxX = max(minX, s.x - halfW);

    final minY = size.y * 0.5;
    final maxY = max(minY, s.y * _wanderAreaBottomFraction);

    final targetX = minX + _rng.nextDouble() * (maxX - minX);
    final targetY = minY + _rng.nextDouble() * (maxY - minY);

    _wanderTarget = Vector2(targetX, targetY);
    _wanderInterval = _wanderMinIntervalSeconds +
        _rng.nextDouble() *
            (_wanderMaxIntervalSeconds - _wanderMinIntervalSeconds);
    _wanderTimer = 0;
  }

  /// Looks at active player bullets and returns a lateral offset
  /// (added to the enemy's wander target) that steers away from any
  /// bullet that's below this enemy, close enough in X, and close
  /// enough in Y to count as "incoming". Returns 0 when nothing
  /// nearby needs dodging.
  double _computeDodgeOffset() {
    double totalPush = 0;
    int contributingBullets = 0;

    for (final bullet in gameRef.children.whereType<Bullet>()) {
      final bx = bullet.position.x;
      final by = bullet.position.y;

      // Player bullets travel upward (toward smaller Y) — only
      // bullets still below this enemy are actually approaching it.
      final verticalGap = by - position.y;
      if (verticalGap <= 0 || verticalGap > _dodgeDetectionRange) continue;

      final horizontalGap = bx - position.x;
      if (horizontalGap.abs() > _dodgeXThreshold) continue;

      // Closer bullets (smaller verticalGap) push harder.
      final urgency = 1.0 - (verticalGap / _dodgeDetectionRange);
      final pushDirection = horizontalGap <= 0 ? 1.0 : -1.0; // move away
      totalPush += pushDirection * urgency;
      contributingBullets++;
    }

    if (contributingBullets == 0) return 0;

    final averaged = (totalPush / contributingBullets) * _maxDodgeOffset;
    return averaged.clamp(-_maxDodgeOffset, _maxDodgeOffset);
  }

  void _fireBurst() {
    // EMP Pulse — guns are offline, skip the burst entirely.
    if (_bulletsDisabled) return;

    final origin = position + Vector2(0, size.y * 0.4);
    final target = gameRef.ship.position;
    final toPlayer = target - origin;
    final direction =
        toPlayer.length > 0 ? toPlayer.normalized() : Vector2(0, 1);

    // Combined bullet-speed multiplier: Time Warp (_slowMultiplier)
    // and Frostbyte's Absolute Zero (_externalSpeedMultiplier) both
    // scale outgoing bullet speed down when active, and stack if
    // both happen to be active at once (e.g. Time Warp cast on an
    // enemy while Absolute Zero is already running) — same pattern
    // already used for movement above.
    final double bulletSpeedMultiplier =
        _slowMultiplier * _externalSpeedMultiplier;

    for (int i = 0; i < bulletsPerBurst; i++) {
      gameRef.add(EnemyBullet(
        startPosition: origin.clone(),
        velocity: direction * bulletSpeed * bulletSpeedMultiplier,
        color: bulletColor,
        damage: bulletDamage,
      ));
    }
  }

  // ------------------------------------------------------------
  // Enemy HP bar, drawn just above the sprite. Flame renders
  // SpriteComponent in local space where (0,0) is the box's top-left
  // and (size.x, size.y) is its bottom-right regardless of anchor,
  // so a negative Y here reliably sits just above the visible ship.
  // ------------------------------------------------------------
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_defeated) return;
    if (_frozen) {
      _renderFrozenOverlay(canvas);
    }
    if (_bulletsDisabled) {
      _renderEmpOverlay(canvas);
    }
    if (_slowMultiplier != 1.0) {
      _renderSlowOverlay(canvas);
    }
    _renderHealthBar(canvas);
  }

  /// A light, icy tint drawn over the sprite's own bounds (plus a
  /// couple of little "crystal" flecks) so a frozen enemy reads as
  /// frozen at a glance, without needing a second sprite asset.
  void _renderFrozenOverlay(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final tintPaint = Paint()..color = const Color(0xFF9BE7FF).withOpacity(0.38);
    canvas.drawRect(rect, tintPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFFE0F7FF).withOpacity(0.85);
    canvas.drawRect(rect, borderPaint);

    final flickPaint = Paint()..color = Colors.white.withOpacity(0.8);
    canvas.drawCircle(Offset(size.x * 0.28, size.y * 0.32), 1.6, flickPaint);
    canvas.drawCircle(Offset(size.x * 0.68, size.y * 0.58), 1.3, flickPaint);
    canvas.drawCircle(Offset(size.x * 0.5, size.y * 0.78), 1.5, flickPaint);
  }

  /// Purple border so a firing-disabled (EMP Pulse) enemy is obvious
  /// at a glance without needing a second sprite asset.
  void _renderEmpOverlay(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFB68CFF).withOpacity(0.8);
    canvas.drawRect(rect, borderPaint);
  }

  /// Faint lavender border so a slowed (Time Warp) enemy is obvious
  /// at a glance without needing a second sprite asset.
  void _renderSlowOverlay(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFFC9A6FF).withOpacity(0.55);
    canvas.drawRect(rect, borderPaint);
  }

  void _renderHealthBar(Canvas canvas) {
    const barHeight = 5.0;
    const barGap = 9.0; // distance above the sprite's top edge
    final barWidth = size.x * 0.82;
    final barX = (size.x - barWidth) / 2;
    final barY = -barGap - barHeight;

    final rect = Rect.fromLTWH(barX, barY, barWidth, barHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    final bgPaint = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawRRect(rrect, bgPaint);

    final frac = (health / maxHealth).clamp(0.0, 1.0);
    if (frac > 0) {
      final fillRect = Rect.fromLTWH(barX, barY, barWidth * frac, barHeight);
      final fillRRect =
          RRect.fromRectAndRadius(fillRect, const Radius.circular(3));
      final fillColor =
          Color.lerp(const Color(0xFFFF4655), const Color(0xFF45E879), frac)!;
      canvas.drawRRect(fillRRect, Paint()..color = fillColor);
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.35);
    canvas.drawRRect(rrect, borderPaint);
  }
}

/// A short-lived explosion burst spawned wherever an [Enemy] dies.
/// Built entirely from Flame's [Particle] system: an expanding/fading
/// shockwave ring, a quick bright core flash, and a spray of
/// radiating spark/debris particles. Purely visual — it removes
/// itself automatically once its particles finish, via
/// [ParticleSystemComponent]'s built-in lifecycle, so callers never
/// need to clean it up manually.
class ExplosionEffect extends ParticleSystemComponent {
  ExplosionEffect({
    required Vector2 position,
    double scale = 1.0,
  }) : super(
          position: position,
          anchor: Anchor.center,
          particle: _build(scale.clamp(0.4, 3.0)),
        );

  static Particle _build(double scale) {
    final rng = Random();

    // Expanding, fading shockwave ring.
    final shockwave = ComputedParticle(
      lifespan: 0.35,
      renderer: (canvas, particle) {
        final progress = particle.progress;
        final radius = 6 + progress * 46 * scale;
        final opacity = (1 - progress).clamp(0.0, 1.0);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - progress) + 1
          ..color = const Color(0xFFFFD54F).withOpacity(opacity * 0.8);
        canvas.drawCircle(Offset.zero, radius, paint);
      },
    );

    // Bright core flash that pops then fades quickly.
    final flash = ComputedParticle(
      lifespan: 0.18,
      renderer: (canvas, particle) {
        final progress = particle.progress;
        final radius = 14 * scale * (1 - progress);
        final paint = Paint()
          ..color = Colors.white.withOpacity((1 - progress).clamp(0.0, 1.0));
        canvas.drawCircle(Offset.zero, radius, paint);
      },
    );

    // Radiating spark/debris particles that fly outward and decelerate.
    final sparks = Particle.generate(
      count: 16,
      lifespan: 0.55,
      generator: (i) {
        final angle = rng.nextDouble() * pi * 2;
        final speed = (70 + rng.nextDouble() * 130) * scale;
        final velocity = Vector2(cos(angle), sin(angle)) * speed;
        final color = Color.lerp(
          const Color(0xFFFFD54F),
          const Color(0xFFFF4655),
          rng.nextDouble(),
        )!;

        return AcceleratedParticle(
          speed: velocity,
          acceleration: velocity * -1.4,
          child: CircleParticle(
            radius: (1.8 + rng.nextDouble() * 2.6) * scale,
            paint: Paint()..color = color,
          ),
        );
      },
    );

    return ComposedParticle(children: [shockwave, sparks, flash]);
  }
}

/// A bullet fired by an [Enemy], aimed at wherever the player was the
/// instant it was fired. Travels in a straight line and removes
/// itself once it drifts off screen.
class EnemyBullet extends PositionComponent with HasGameRef<MyFlameGame> {
  final Vector2 velocity;
  final Color color;
  final double damage;
  final Paint _paint;

  EnemyBullet({
    required Vector2 startPosition,
    required this.velocity,
    required this.color,
    required this.damage,
    double bulletSize = 11,
  })  : _paint = Paint()..color = color,
        super(
          position: startPosition,
          size: Vector2.all(bulletSize),
          anchor: Anchor.center,
        );

  Rect hitRect() => Rect.fromCenter(
        center: position.toOffset(),
        width: size.x,
        height: size.y,
      );

  @override
  void update(double dt) {
    super.update(dt);
    position += velocity * dt;

    final s = gameRef.size;
    if (position.y < -60 ||
        position.y > s.y + 60 ||
        position.x < -60 ||
        position.x > s.x + 60) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final center = Offset(size.x / 2, size.y / 2);

    final glowPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, size.x / 2 + 3, glowPaint);

    canvas.drawCircle(center, size.x / 2, _paint);

    final hotPaint = Paint()..color = Colors.white.withOpacity(0.85);
    canvas.drawCircle(center, size.x / 4, hotPaint);
  }
}

/// Drives an entire [LevelConfig]: spawns waves one at a time (a new
/// wave never starts until every enemy from the previous one is
/// dead), resolves all bullet/ram/beam collisions each frame, and
/// reports player HP changes plus level-complete / player-defeated
/// events.
class WaveManager extends Component with HasGameRef<MyFlameGame> {
  final LevelConfig level;
  final ValueNotifier<int> waveNotifier;
  final ValueNotifier<int> enemiesLeftNotifier;
  final ValueNotifier<double> playerHealthNotifier;
  final VoidCallback? onLevelComplete;
  final VoidCallback? onPlayerDefeated;

  /// Shield Burst hook: called before ram damage is applied to the
  /// player. Return true to block that hit entirely — the player's
  /// health is never touched at all for that hit (not applied then
  /// reverted, just never applied in the first place). Supplied by
  /// the level page. (Enemy *bullets* are no longer routed through
  /// this — see [shieldRadiusGetter] below, which intercepts them
  /// earlier, right at the shield's visible barrier.)
  final bool Function()? shouldBlockDamage;

  /// Called exactly once per hit that got blocked (whether a bullet
  /// stopped at the barrier or a ram that reached the ship), so the
  /// caster can burn a shield charge and deactivate once they run
  /// out.
  final VoidCallback? onDamageBlocked;

  /// Shield Burst hook: returns the shield's current blocking radius
  /// around the ship while it's active and still has charges left,
  /// or null when there's no shield up. Used in [_handleCollisions]
  /// to stop an enemy bullet the instant it's within this radius of
  /// the ship — i.e. right on the visible barrier ring — instead of
  /// letting it travel all the way in to the ship's own hitbox
  /// first. Supplied by the level page.
  final double? Function()? shieldRadiusGetter;

  /// Overcharge hook: flat bonus damage added to every player bullet
  /// at the exact moment it hits an enemy. Returns 0 whenever
  /// Overcharge isn't active. Supplied by the level page.
  final double Function()? damageBonusGetter;

  /// Nebula's Aegis Barrier super power: multiplies any damage that
  /// actually reaches the player (bullets AND rams) — 1.0 normally,
  /// 0.5 while the barrier is active. Supplied by the level page via
  /// SuperPowerController.barrierActive.
  final double Function()? incomingDamageMultiplierGetter;

  /// Frostbyte's Absolute Zero super power: forwarded straight down
  /// into every [Enemy] this WaveManager spawns (including ones
  /// spawned while it's already active) so their movement AND their
  /// own outgoing bullet speed slow live. Supplied by the level page.
  final double Function()? enemySpeedMultiplierGetter;

  /// Shadow Reaper's Void Collapse super power: while true, the
  /// player takes NO damage at all from any source this WaveManager
  /// resolves — checked first in [_damagePlayer], before Shield
  /// Burst or the Aegis Barrier multiplier even run. Supplied by the
  /// level page.
  final bool Function()? playerInvulnerableGetter;

  WaveManager({
    required this.level,
    required this.waveNotifier,
    required this.enemiesLeftNotifier,
    required this.playerHealthNotifier,
    this.onLevelComplete,
    this.onPlayerDefeated,
    this.shouldBlockDamage,
    this.onDamageBlocked,
    this.shieldRadiusGetter,
    this.damageBonusGetter,
    this.incomingDamageMultiplierGetter,
    this.enemySpeedMultiplierGetter,
    this.playerInvulnerableGetter,
  });

  final List<Enemy> _activeEnemies = [];
  int _currentWaveIndex = -1;
  bool _spawningWave = false;
  bool _waitingForNextWave = false;
  double _interWaveTimer = 0;
  bool _levelFinished = false;
  bool _playerDefeated = false;

  // Replaces reliance on Flame's `isMounted`, which is still false
  // while this component's own onLoad() (and therefore the first
  // wave spawn it kicks off) is still running.
  bool _active = true;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    await _startNextWave();
  }

  Future<void> _startNextWave() async {
    _currentWaveIndex++;

    if (_currentWaveIndex >= level.waves.length) {
      _finishLevel();
      return;
    }

    waveNotifier.value = _currentWaveIndex + 1;
    _spawningWave = true;

    final wave = level.waves[_currentWaveIndex];
    final sprite = await gameRef.loadSprite(wave.enemyAsset);

    // Precompute a formation grid for this wave so enemies spread
    // out into columns/rows instead of all tracking to the exact
    // same X as the player.
    final count = wave.enemyCount;
    final columns = min(count, 5);
    const horizontalSpread = 220.0;

    for (int i = 0; i < count; i++) {
      if (!_active || _playerDefeated || _levelFinished) return;

      final col = i % columns;
      final row = i ~/ columns;

      final colFraction = columns > 1 ? col / (columns - 1) : 0.5;
      final formationOffsetX = (colFraction - 0.5) * horizontalSpread;

      final startX = 40 + Random().nextDouble() * (gameRef.size.x - 80);
      final startY = -80.0 - Random().nextDouble() * 160;

      final enemy = Enemy(
        sprite: sprite,
        startPosition: Vector2(startX, startY),
        enemySize: wave.enemySize,
        maxHealth: wave.enemyHealth,
        ramDamage: wave.ramDamage,
        bulletsPerBurst: wave.bulletsPerBurst,
        fireInterval: wave.fireInterval,
        bulletSpeed: wave.bulletSpeed,
        bulletDamage: wave.bulletDamage,
        bulletColor: wave.bulletColor,
        trackSpeed: wave.trackSpeed,
        descendSpeed: wave.descendSpeed,
        flipVertically: wave.flipVertically,
        onDefeated: _onEnemyDefeated,
        formationOffsetX: formationOffsetX,
        holdYFraction: 0.20 + row * 0.11,
        // Frostbyte's Absolute Zero — forwarded to every enemy this
        // wave spawns so newly-arriving enemies are slowed too, not
        // just whatever was already on screen when it activated.
        externalSpeedMultiplierGetter: enemySpeedMultiplierGetter,
      );

      _activeEnemies.add(enemy);
      gameRef.add(enemy);
      enemiesLeftNotifier.value = _activeEnemies.length;

      await Future.delayed(
        Duration(milliseconds: (wave.spawnStagger * 1000).round()),
      );
    }

    if (!_active || _playerDefeated || _levelFinished) return;

    _spawningWave = false;

    // Covers the edge case where the last enemy of the wave died
    // while later enemies were still being staggered in.
    if (_activeEnemies.isEmpty && !_waitingForNextWave) {
      _waitingForNextWave = true;
      _interWaveTimer = 0;
    }
  }

  void _onEnemyDefeated(Enemy enemy) {
    _activeEnemies.remove(enemy);
    enemiesLeftNotifier.value = _activeEnemies.length;

    if (!_spawningWave && _activeEnemies.isEmpty && !_waitingForNextWave) {
      _waitingForNextWave = true;
      _interWaveTimer = 0;
    }
  }

  void _finishLevel() {
    if (_levelFinished) return;
    _levelFinished = true;
    gameRef.pauseEngine();
    onLevelComplete?.call();
  }

  void _defeatPlayer() {
    if (_playerDefeated) return;
    _playerDefeated = true;
    gameRef.pauseEngine();
    onPlayerDefeated?.call();
  }

  void _damagePlayer(double amount) {
    if (_playerDefeated) return;

    // Shadow Reaper's Void Collapse — total immunity. Checked first
    // and returns immediately: no shield charge is burned, no
    // barrier math runs, nothing is recorded. This is a harder wall
    // than Shield Burst; the ship simply cannot be hit at all for
    // the duration.
    if (playerInvulnerableGetter?.call() ?? false) {
      return;
    }

    // Shield Burst: block this hit entirely before it ever touches
    // health — no damage is applied at all, then a charge is burned.
    // (For enemy bullets this is now a backstop only — they're
    // normally already intercepted earlier in _handleCollisions, at
    // the shield's visible barrier radius, well before they'd ever
    // overlap the ship's own hitbox and get here.)
    if (shouldBlockDamage != null && shouldBlockDamage!()) {
      onDamageBlocked?.call();
      return;
    }

    // Nebula's Aegis Barrier — halves whatever damage actually gets
    // this far (both bullets and rams). 1.0 (no change) whenever the
    // barrier isn't active/owned.
    final multiplier = incomingDamageMultiplierGetter?.call() ?? 1.0;
    final adjustedAmount = amount * multiplier;

    final newHealth =
        (playerHealthNotifier.value - adjustedAmount).clamp(0, double.infinity);
    playerHealthNotifier.value = newHealth.toDouble();
    if (newHealth <= 0) {
      _defeatPlayer();
    }
  }

  /// Shadow Reaper's Void Collapse: deals [damage] to every enemy
  /// currently active on screen at once, the instant the power
  /// triggers. Called by _LevelFlameGame.damageAllEnemies (see
  /// level_page.dart), which is itself called from
  /// SuperPowerController.activate() via the onVoidNova callback.
  void dealDamageToAllEnemies(double damage) {
    for (final enemy in List<Enemy>.from(_activeEnemies)) {
      enemy.takeDamage(damage);
    }
  }

  /// Interceptor's Twin Fang: piercing hit-detection for
  /// [HomingBullet] (see main_game_page.dart). Unlike a normal
  /// player bullet, which stops after its first collision, a Twin
  /// Fang bolt flies straight through a whole line of enemies —
  /// every frame it's alive, this damages every currently-active
  /// enemy whose hit box overlaps [rect] EXCEPT any enemy already
  /// present in [excludeHandles] (the bolt's own running set of
  /// enemies it's already pierced, passed back in from
  /// HomingBullet). This is what stops a slow-moving bolt sitting on
  /// top of one enemy for a couple of frames from re-damaging that
  /// same enemy every single frame — once hit, an enemy is excluded
  /// for the rest of that bolt's flight, but anything else it
  /// touches (including enemies further along its path) still takes
  /// damage normally.
  ///
  /// Returns the enemies actually hit THIS call so HomingBullet can
  /// fold them into its own exclude set for next frame.
  List<Enemy> dealDamageToEnemiesInRect(
    Rect rect,
    double damage,
    Set<Object> excludeHandles,
  ) {
    final hit = <Enemy>[];
    for (final enemy in List<Enemy>.from(_activeEnemies)) {
      if (excludeHandles.contains(enemy)) continue;
      if (enemy.hitRect().overlaps(rect)) {
        enemy.takeDamage(damage);
        hit.add(enemy);
      }
    }
    return hit;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_playerDefeated || _levelFinished) return;

    if (_waitingForNextWave) {
      _interWaveTimer += dt;
      if (_interWaveTimer >= level.interWaveDelay) {
        _waitingForNextWave = false;
        _startNextWave();
      }
      return;
    }

    _handleCollisions(dt);
  }

  void _handleCollisions(double dt) {
    final ship = gameRef.ship;
    final playerRect = ship.hitRect();

    // Player bullets vs enemies. Overcharge's flat bonus (if active)
    // is added right here, at the moment of impact, so it never
    // needs to touch how Ship/Bullet actually get created.
    final playerBullets = gameRef.children.whereType<Bullet>().toList();
    for (final bullet in playerBullets) {
      final bulletRect = Rect.fromCenter(
        center: bullet.position.toOffset(),
        width: bullet.size.x,
        height: bullet.size.y,
      );

      for (final enemy in List<Enemy>.from(_activeEnemies)) {
        if (bulletRect.overlaps(enemy.hitRect())) {
          bullet.removeFromParent();
          final bonus = damageBonusGetter?.call() ?? 0;
          enemy.takeDamage(bullet.damage + bonus);
          break;
        }
      }
    }

    // Player LASER BEAM (bulletBeam skins, e.g. Frostbyte) vs
    // enemies. No discrete tick timer — every single frame the beam
    // is active, whatever's currently overlapping its hit box takes
    // `damagePerSecond * dt` damage, same continuous pattern the
    // energy system itself already uses to drain (see
    // LaserBeam.damagePerSecond's doc comment in main_game_page.dart
    // — full damage now lands in 1 second instead of 2). Stops the
    // instant the beam goes inactive (energy runs out).
    final beam = gameRef.laserBeam;
    if (beam != null && beam.isActive) {
      final beamRect = beam.hitRect();
      final frameDamage = beam.damagePerSecond * dt;
      if (frameDamage > 0) {
        for (final enemy in List<Enemy>.from(_activeEnemies)) {
          if (beamRect.overlaps(enemy.hitRect())) {
            enemy.takeDamage(frameDamage);
          }
        }
      }
    }

    // Enemy bullets vs the player. While Shield Burst is up, a
    // bullet is intercepted the instant it comes within the shield's
    // visible barrier radius of the ship — it's removed right there
    // (so it visually stops on the shield ring) and never gets a
    // chance to overlap the ship's own hitbox at all. Only once the
    // shield is down (or its charges are gone) do bullets fall
    // through to the normal ship-hitbox check below.
    final enemyBullets = gameRef.children.whereType<EnemyBullet>().toList();
    for (final bullet in enemyBullets) {
      final shieldRadius = shieldRadiusGetter?.call();
      if (shieldRadius != null) {
        final distanceToShip = (bullet.position - ship.position).length;
        if (distanceToShip <= shieldRadius) {
          bullet.removeFromParent();
          onDamageBlocked?.call();
          continue;
        }
      }

      if (bullet.hitRect().overlaps(playerRect)) {
        bullet.removeFromParent();
        _damagePlayer(bullet.damage);
      }
    }

    // Enemies ramming the player.
    for (final enemy in List<Enemy>.from(_activeEnemies)) {
      if (enemy.hitRect().overlaps(playerRect) && enemy.tryRam()) {
        _damagePlayer(enemy.ramDamage);
      }
    }
  }

  @override
  void onRemove() {
    _active = false;
    _activeEnemies.clear();
    super.onRemove();
  }
}