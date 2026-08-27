import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart'; // <-- click SFX, matches skins_page/main_game_page

// Pulls in SkinData / kSkins, the responsive-size extension, the
// coins/upgrade-level state and helpers (effectiveStatValue,
// upgradeCost, purchaseUpgrade, etc.), AnimatedCounterText,
// AnimatedTapButton, and SkinPreviewGame — all shared with the Skins
// page so this screen looks and behaves consistently with it.
// Adjust the path to wherever skins_page.dart actually lives in your
// project.
import 'package:cosmic_fury/src/pages/skins/skins_page.dart';

/// ---------------------------------------------------------------------
/// Upgrade page — lets the player spend coins to push a ship's
/// Health, Energy, and Damage stats up from their base value toward
/// that ship's per-stat cap, in 15 discrete levels per stat:
///
///   Falcon Mk.I    -> health 100  -> 320,  energy 20 -> 35, damage 15  -> 70
///   Interceptor    -> health 300  -> 750,  energy 30 -> 45, damage 60  -> 100
///   Nebula         -> health 700  -> 1000, energy 40 -> 53, damage 100 -> 140
///   Frostbyte      -> health 1000 -> 1450, energy 50 -> 78, damage 12  -> 30
///   Shadow Reaper  -> health 1500 -> 2100, energy 60 -> 80, damage 170 -> 230
///
/// All of the actual math/state (levels, costs, caps) lives in
/// skins_page.dart (kStatCaps, upgradeLevelsNotifier,
/// effectiveStatValue, upgradeCost, purchaseUpgrade) so any other
/// screen can read a ship's current (post-upgrade) stats the same
/// way. This page is just the shop UI on top of that state.
///
/// Pass [initialSkin] to open straight to a specific ship (e.g. from
/// the Skins page's Upgrade button); defaults to the first ship if
/// omitted.
/// ---------------------------------------------------------------------
class UpgradePage extends StatefulWidget {
  final SkinData? initialSkin;

  const UpgradePage({Key? key, this.initialSkin}) : super(key: key);

  @override
  _UpgradePageState createState() => _UpgradePageState();
}

class _UpgradePageState extends State<UpgradePage> {
  late int _currentIndex;

  SkinData get _currentSkin => kSkins[_currentIndex];

  @override
  void initState() {
    super.initState();
    final idx =
        widget.initialSkin == null ? 0 : kSkins.indexOf(widget.initialSkin!);
    _currentIndex = idx == -1 ? 0 : idx;

    // Preload the shared click SFX the same way SkinsPage/MainGamePage
    // do, so the very first tap on this page fires instantly.
    FlameAudio.audioCache.load('click.mp3');
  }

  void _playClickSound() => FlameAudio.play('click.mp3', volume: 0.6);

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

  /// Attempts to buy the next level of stat [statIndex] for the ship
  /// currently shown. Refuses outright if the ship hasn't been
  /// unlocked yet (bought with gems on the Skins page) — you can look
  /// at a locked ship's upgrade cards here, but not actually spend
  /// coins on them. Shows a snackbar instead of silently doing
  /// nothing if there aren't enough coins either.
  void _tryUpgrade(int statIndex) {
    final skin = _currentSkin;
    if (isStatMaxed(skin, statIndex)) return;

    if (!isSkinOwned(skin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unlock ${skin.name} on the Skins page first.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final level = upgradeLevelFor(skin, statIndex);
    final cost = upgradeCost(skin, statIndex, level);

    if (coinsNotifier.value < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Not enough coins — this upgrade costs $cost.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    purchaseUpgrade(skin, statIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ---- Static background image, full-bleed — same asset the
          //      Skins page uses, so this reads as part of the same
          //      screen family. ----
          Positioned.fill(
            child: Image.asset(
              'assets/images/skinbackground.png',
              fit: BoxFit.cover,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(),

                Padding(
                  padding: EdgeInsets.fromLTRB(
                      context.wp(5), context.hp(1.2), context.wp(5), 0),
                  child: ValueListenableBuilder<int>(
                    valueListenable: coinsNotifier,
                    builder: (context, coins, _) => _buildCoinsCard(coins),
                  ),
                ),

                SizedBox(height: context.hp(1.0)),

                // ---- Ship name + carousel (arrows + live preview) ----
                _buildSkinName(),
                SizedBox(height: context.hp(0.6)),
                _buildShipSelector(),

                SizedBox(height: context.hp(1.2)),

                // ---- Scrollable stat-upgrade cards ----
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        context.wp(5), 0, context.wp(5), context.hp(2)),
                    child: ValueListenableBuilder<Map<String, List<int>>>(
                      valueListenable: upgradeLevelsNotifier,
                      builder: (context, levels, _) {
                        return Column(
                          children: [
                            _buildStatUpgradeCard(
                              statIndex: 0,
                              icon: Icons.favorite,
                              color: Colors.redAccent,
                              label: 'HEALTH',
                            ),
                            SizedBox(height: context.hp(1.4)),
                            _buildStatUpgradeCard(
                              statIndex: 1,
                              icon: Icons.flash_on,
                              color: Colors.lightBlueAccent,
                              label: 'ENERGY',
                            ),
                            SizedBox(height: context.hp(1.4)),
                            _buildStatUpgradeCard(
                              statIndex: 2,
                              icon: Icons.gpp_maybe,
                              color: Colors.orangeAccent,
                              label: 'DAMAGE',
                            ),
                          ],
                        );
                      },
                    ),
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
  // Header — back button + "Upgrade" title. Gesture/system back also
  // works via Navigator regardless, this is just an explicit tap
  // target matching the rest of the app's button style.
  // ------------------------------------------------------------------
  Widget _buildHeader() {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(context.wp(3), context.hp(1.6), context.wp(5), 0),
      child: Row(
        children: [
          AnimatedTapButton(
            onTap: () {
              _playClickSound();
              Navigator.of(context).pop();
            },
            child: Container(
              width: context.sp(38),
              height: context.sp(38),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.45),
                border: Border.all(
                  color: Colors.deepOrange.shade400.withOpacity(0.8),
                  width: 1.2,
                ),
              ),
              child: Icon(Icons.arrow_back_ios_new,
                  color: Colors.orangeAccent, size: context.sp(16)),
            ),
          ),
          SizedBox(width: context.wp(3)),
          Text(
            'Upgrade',
            style: TextStyle(
              color: Colors.white,
              fontSize: context.sp(20),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Coins card — same visual language as the Skins/Home page currency
  // cards, but full-width and coins-only (this screen never spends
  // gems).
  // ------------------------------------------------------------------
  Widget _buildCoinsCard(int coins) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepOrange.shade900, width: 1),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/coin.png', width: 26, height: 26),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedCounterText(
              value: coins,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            'COINS',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: context.sp(10),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Ship name above the carousel — same solid/gradient treatment
  // SkinsPage uses so it reads as the same family of screen.
  // ------------------------------------------------------------------
  Widget _buildSkinName() {
    final skin = _currentSkin;

    if (skin.nameColor != null) {
      return Text(
        skin.name,
        style: TextStyle(
          color: skin.nameColor,
          fontSize: context.sp(20),
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
        style: TextStyle(
          color: Colors.white,
          fontSize: context.sp(20),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Ship selector — left/right arrows around a live Flame-rendered
  // ship preview (same SkinPreviewGame widget the Skins page uses),
  // so switching ships here looks exactly like switching them there.
  // ------------------------------------------------------------------
  Widget _buildShipSelector() {
    final skin = _currentSkin;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildArrowButton(
          icon: Icons.chevron_left_rounded,
          onTap: kSkins.length > 1 ? _goToPrevious : null,
        ),
        SizedBox(
          width: context.wp(60),
          height: context.hp(20),
          // Blurred + locked, same treatment SkinsPage uses, so it's
          // obvious at a glance that this ship needs to be bought
          // (with gems, on the Skins page) before its stats can be
          // upgraded with coins here.
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: ownedSkinAssetsNotifier,
            builder: (context, owned, _) {
              final bool locked = !isSkinOwned(skin);
              return Stack(
                alignment: Alignment.center,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: locked ? 6 : 0,
                      sigmaY: locked ? 6 : 0,
                    ),
                    child: GameWidget(
                      key: ValueKey('upgrade_${skin.asset}'),
                      game: SkinPreviewGame(
                        shipAsset: skin.asset,
                        flameAccent: skin.flameAccent,
                        engineOffsetYFraction: skin.engineOffsetYFraction,
                        flameSpread: skin.flameSpread,
                        flameParticleRadius: skin.flameParticleRadius,
                        flameLength: skin.flameLength,
                      ),
                    ),
                  ),
                  if (locked)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.black.withOpacity(0.6),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.7),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock,
                              color: Colors.white, size: context.sp(18)),
                          SizedBox(width: context.wp(1.5)),
                          Text(
                            'Locked',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: context.sp(12),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        _buildArrowButton(
          icon: Icons.chevron_right_rounded,
          onTap: kSkins.length > 1 ? _goToNext : null,
        ),
      ],
    );
  }

  Widget _buildArrowButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;
    final circle = Container(
      width: context.sp(40),
      height: context.sp(40),
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
          width: 1.2,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Colors.deepOrange.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Icon(
        icon,
        color: enabled ? Colors.orangeAccent : Colors.grey.shade700,
        size: context.sp(22),
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
  // One stat's upgrade card — icon/label header with the current
  // level, a 15-segment level track, current -> next value preview,
  // and the buy button (or a MAXED badge once level 15 is reached).
  // ------------------------------------------------------------------
  Widget _buildStatUpgradeCard({
    required int statIndex,
    required IconData icon,
    required Color color,
    required String label,
  }) {
    final skin = _currentSkin;
    final level = upgradeLevelFor(skin, statIndex);
    final maxed = level >= kMaxUpgradeLevel;
    final locked = !isSkinOwned(skin);

    final base = statBaseValue(skin, statIndex);
    final cap = statCapValue(skin, statIndex);
    final currentValue = effectiveStatValue(skin, statIndex);
    final step = (cap - base) / kMaxUpgradeLevel;
    final nextValue =
        maxed ? currentValue : (base + step * (level + 1)).round();
    final cost = maxed ? 0 : upgradeCost(skin, statIndex, level);

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.wp(4), vertical: context.hp(1.4)),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepOrange.shade900, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: context.sp(16)),
              SizedBox(width: context.wp(2)),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: context.sp(12),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                'Lv $level/$kMaxUpgradeLevel',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: context.sp(11),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          SizedBox(height: context.hp(0.9)),

          // ---- 15-segment level track ----
          Row(
            children: List.generate(kMaxUpgradeLevel, (i) {
              final filled = i < level;
              return Expanded(
                child: Container(
                  height: context.sp(6),
                  margin: EdgeInsets.symmetric(horizontal: context.wp(0.3)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: filled ? color : Colors.white12,
                  ),
                ),
              );
            }),
          ),

          SizedBox(height: context.hp(1.1)),

          Row(
            children: [
              AnimatedCounterText(
                value: currentValue,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: context.sp(16),
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!maxed) ...[
                SizedBox(width: context.wp(2)),
                Icon(Icons.arrow_forward,
                    color: Colors.white38, size: context.sp(13)),
                SizedBox(width: context.wp(2)),
                Text(
                  '$nextValue',
                  style: TextStyle(
                    color: color,
                    fontSize: context.sp(14),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const Spacer(),
              _buildUpgradeActionButton(
                statIndex: statIndex,
                maxed: maxed,
                locked: locked,
                cost: cost,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Buy button for a single stat — shows the coin cost, greys out
  // (but stays tappable, to surface the "not enough coins" snackbar)
  // when unaffordable, and swaps to a green MAXED pill at level 15.
  // ------------------------------------------------------------------
  Widget _buildUpgradeActionButton({
    required int statIndex,
    required bool maxed,
    required bool locked,
    required int cost,
  }) {
    if (locked) {
      // Ship hasn't been bought yet — tapping still surfaces a
      // snackbar via _tryUpgrade (which re-checks ownership), but the
      // button itself reads as disabled: grey, lock icon, no price.
      return AnimatedTapButton(
        onTap: () {
          _playClickSound();
          _tryUpgrade(statIndex);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.wp(4), vertical: context.hp(0.9)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey.shade900,
            border: Border.all(color: Colors.grey.shade700, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, color: Colors.grey.shade400, size: 13),
              const SizedBox(width: 5),
              Text(
                'LOCKED',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (maxed) {
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: context.wp(4), vertical: context.hp(0.9)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.green.withOpacity(0.15),
          border: Border.all(color: Colors.greenAccent, width: 1),
        ),
        child: const Text(
          'MAXED',
          style: TextStyle(
            color: Colors.greenAccent,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: coinsNotifier,
      builder: (context, coins, _) {
        final bool canAfford = coins >= cost;
        return AnimatedTapButton(
          onTap: () {
            _playClickSound();
            _tryUpgrade(statIndex);
          },
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: context.wp(3.5), vertical: context.hp(0.9)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: canAfford
                    ? [Colors.lightBlueAccent.shade700, Colors.blue.shade900]
                    : [Colors.grey.shade700, Colors.grey.shade900],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
              boxShadow: canAfford
                  ? [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/coin.png',
                    width: context.sp(14), height: context.sp(14)),
                SizedBox(width: context.wp(1.2)),
                Text(
                  '$cost',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.sp(11),
                    fontWeight: FontWeight.w800,
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