import 'package:flutter/material.dart';

import 'level_config.dart';

/// World 1 wave/level definitions.
///
/// Each level is a fixed, hand-tuned list of [WaveConfig]s. A new wave
/// only starts once every enemy from the previous wave is dead — that
/// logic lives in [WaveManager] (see enemy.dart), this file only
/// describes *what* spawns.
///
/// To add a new level: define a new `kWorld1LevelN` constant below and
/// register it in [_kWorld1Levels]. [getWorld1Level] and [LevelPage]
/// pick it up automatically, nothing else needs to change.

const kWorld1Level1 = LevelConfig(
  world: 1,
  level: 1,
  title: 'First Contact',
  interWaveDelay: 1.8,
  waves: [
    // Wave 1 — 5 enemies.
    WaveConfig(
      enemyCount: 5,
      enemyAsset: 'enemy1.png',
      enemyHealth: 100,
      enemySize: 70,
      bulletsPerBurst: 1,
      fireInterval: 5.0,
      bulletSpeed: 220,
      bulletDamage: 10,
      bulletColor: Color(0xFFFF4655),
      trackSpeed: 30,
      descendSpeed: 65,
      ramDamage: 15,
      spawnStagger: 0.4,
    ),
    // Wave 2 — 7 enemies.
    WaveConfig(
      enemyCount: 7,
      enemyAsset: 'enemy1.png',
      enemyHealth: 100,
      enemySize: 70,
      bulletsPerBurst: 1,
      fireInterval: 5.0,
      bulletSpeed: 230,
      bulletDamage: 10,
      bulletColor: Color(0xFFFF4655),
      trackSpeed: 32,
      descendSpeed: 68,
      ramDamage: 15,
      spawnStagger: 0.35,
    ),
    // Wave 3 — 13 enemies.
    WaveConfig(
      enemyCount: 13,
      enemyAsset: 'enemy1.png',
      enemyHealth: 100,
      enemySize: 70,
      bulletsPerBurst: 1,
      fireInterval: 5.0,
      bulletSpeed: 240,
      bulletDamage: 10,
      bulletColor: Color(0xFFFF4655),
      trackSpeed: 34,
      descendSpeed: 72,
      ramDamage: 15,
      spawnStagger: 0.3,
    ),
  ],
);

/// Every level currently defined for World 1, keyed by level number.
/// Add new levels here as you define them.
final Map<int, LevelConfig> _kWorld1Levels = {
  1: kWorld1Level1,
};

/// Looks up a World 1 level by its number. Returns null if that level
/// hasn't been defined yet — [LevelPage] falls back to
/// [kWorld1Level1] in that case.
LevelConfig? getWorld1Level(int level) => _kWorld1Levels[level];