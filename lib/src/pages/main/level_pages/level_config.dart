import 'package:flutter/material.dart';

/// One wave inside a level: how many enemies, which sprite, how tough
/// they are, and how they shoot. Everything is tunable per wave, so
/// wave 3 of a level can be nastier than wave 1 without new code.
@immutable
class WaveConfig {
  final int enemyCount;

  /// Bare filename Flame's loader expects — assets/images/enemy1.png
  final String enemyAsset;

  /// If your enemy art points UP, set this to true so it faces the
  /// player instead of flying backwards.
  final bool flipVertically;

  final double enemyHealth;
  final double enemySize;

  /// How fast an enemy slides sideways while tracking the player.
  final double trackSpeed;

  /// How fast it drops in from above to its holding line.
  final double descendSpeed;

  /// Shooting: `bulletsPerBurst` shots every `fireInterval` seconds.
  final int bulletsPerBurst;
  final double fireInterval;
  final double bulletSpeed;
  final double bulletDamage;
  final Color bulletColor;

  /// Contact damage if an enemy rams the player.
  final double ramDamage;

  /// Delay between individual spawns so a wave streams in instead of
  /// popping into existence all at once.
  final double spawnStagger;

  const WaveConfig({
    required this.enemyCount,
    this.enemyAsset = 'enemy1.png',
    this.flipVertically = false,
    this.enemyHealth = 100,
    this.enemySize = 76,
    this.trackSpeed = 34,
    this.descendSpeed = 70,
    this.bulletsPerBurst = 1,
    this.fireInterval = 5.0,
    this.bulletSpeed = 240,
    this.bulletDamage = 10,
    this.bulletColor = const Color(0xFFFF4655),
    this.ramDamage = 15,
    this.spawnStagger = 0.35,
  });
}

/// A single campaign level: which world it belongs to, its number, and
/// the ordered list of waves the player has to clear.
@immutable
class LevelConfig {
  final int world;
  final int level;
  final String title;
  final List<WaveConfig> waves;

  /// Pause between clearing a wave and the next one starting.
  final double interWaveDelay;

  const LevelConfig({
    required this.world,
    required this.level,
    required this.title,
    required this.waves,
    this.interWaveDelay = 1.6,
  });

  int get waveCount => waves.length;

  String get label => 'W$world · L$level';
}