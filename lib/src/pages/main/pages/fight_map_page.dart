import 'dart:math';

import 'package:cosmic_fury/src/pages/main/level_pages/level_page.dart';
import 'package:flutter/material.dart';
import 'package:flame_audio/flame_audio.dart';

class FightMapPage extends StatefulWidget {
  const FightMapPage({Key? key}) : super(key: key);

  @override
  State<FightMapPage> createState() => _FightMapPageState();
}

// ============================================================================
// THEMES
// ============================================================================

enum _ParticleKind {
  fire,
  ice,
  voidSpace,
}

class _PlaceTheme {
  final String name;
  final String subtitle;
  final IconData icon;

  final Color accent;
  final Color accentDim;

  final List<Color> nodeGradient;
  final List<Color> bossGradient;

  final List<Color> skyTop;
  final List<Color> skyBottom;

  final _ParticleKind particleKind;

  const _PlaceTheme({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.accentDim,
    required this.nodeGradient,
    required this.bossGradient,
    required this.skyTop,
    required this.skyBottom,
    required this.particleKind,
  });
}

const _emberTheme = _PlaceTheme(
  name: 'COSMIC FRONTIER',
  subtitle: 'THE BURNING EDGE',
  icon: Icons.local_fire_department_rounded,
  accent: Color(0xFFFF563D),
  accentDim: Color(0xFF67150F),
  nodeGradient: [
    Color(0xFFFFA05E),
    Color(0xFFB51D20),
  ],
  bossGradient: [
    Color(0xFFFFD36A),
    Color(0xFFFF6037),
    Color(0xFF86100E),
  ],
  skyTop: [
    Color(0xFF250609),
    Color(0xFF100204),
  ],
  skyBottom: [
    Color(0xFF030102),
    Color(0xFF000000),
  ],
  particleKind: _ParticleKind.fire,
);

const _frostTheme = _PlaceTheme(
  name: 'NEBULA REACH',
  subtitle: 'THE FROZEN FRONTIER',
  icon: Icons.ac_unit_rounded,
  accent: Color(0xFF61E9FF),
  accentDim: Color(0xFF103C52),
  nodeGradient: [
    Color(0xFFD5FFFF),
    Color(0xFF2279C8),
  ],
  bossGradient: [
    Color(0xFFE4FFFF),
    Color(0xFF62DFFF),
    Color(0xFF124FA0),
  ],
  skyTop: [
    Color(0xFF05283D),
    Color(0xFF02121F),
  ],
  skyBottom: [
    Color(0xFF01080F),
    Color(0xFF000000),
  ],
  particleKind: _ParticleKind.ice,
);

const _voidTheme = _PlaceTheme(
  name: 'VOID EXPANSE',
  subtitle: 'BEYOND REALITY',
  icon: Icons.blur_on_rounded,
  accent: Color(0xFFD96BFF),
  accentDim: Color(0xFF49105D),
  nodeGradient: [
    Color(0xFFF1B8FF),
    Color(0xFF7624C8),
  ],
  bossGradient: [
    Color(0xFFFFD4FC),
    Color(0xFFE14CFF),
    Color(0xFF570B8E),
  ],
  skyTop: [
    Color(0xFF280731),
    Color(0xFF100218),
  ],
  skyBottom: [
    Color(0xFF040108),
    Color(0xFF000000),
  ],
  particleKind: _ParticleKind.voidSpace,
);

class _PlaceData {
  final _PlaceTheme theme;
  final int totalLevels;
  int unlockedLevel;

  _PlaceData({
    required this.theme,
    this.totalLevels = 100,
    this.unlockedLevel = 1,
  });

  bool get isPlaceLocked => unlockedLevel <= 0;

  int get completedLevels => max(0, unlockedLevel - 1);

  double get progress {
    if (isPlaceLocked) return 0;
    return completedLevels / totalLevels;
  }
}

// ============================================================================
// PAGE
// ============================================================================

class _FightMapPageState extends State<FightMapPage>
    with TickerProviderStateMixin {
  static const double _itemHeight = 142;
  static const double _topPadding = 80;
  static const double _bottomPadding = 190;

  late final List<_PlaceData> _places = [
    _PlaceData(
      theme: _emberTheme,
      unlockedLevel: 1,
    ),
    _PlaceData(
      theme: _frostTheme,
      unlockedLevel: 0,
    ),
    _PlaceData(
      theme: _voidTheme,
      unlockedLevel: 0,
    ),
  ];

  late final PageController _placeController = PageController();

  late final List<ScrollController> _mapControllers = List.generate(
    3,
    (_) => ScrollController(),
  );

  late final AnimationController _backgroundController =
      AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  late final AnimationController _floatingController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat(reverse: true);

  int _currentPlace = 0;

  @override
  void initState() {
    super.initState();

    FlameAudio.audioCache.load('click.mp3');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToUnlocked(0);
    });
  }

  @override
  void dispose() {
    _placeController.dispose();

    for (final controller in _mapControllers) {
      controller.dispose();
    }

    _backgroundController.dispose();
    _pulseController.dispose();
    _floatingController.dispose();

    super.dispose();
  }

  void _playClickSound() {
    FlameAudio.play(
      'click.mp3',
      volume: 0.55,
    );
  }

  bool _isBoss(int level) => level % 10 == 0;

  void _goBack() {
    _playClickSound();
    Navigator.of(context).pop();
  }

  void _scrollToUnlocked(int placeIndex) {
    final controller = _mapControllers[placeIndex];

    if (!controller.hasClients) return;

    final level = max(1, _places[placeIndex].unlockedLevel);

    final target =
        _topPadding + (level - 1) * _itemHeight;

    final viewport = controller.position.viewportDimension;

    final maxScroll = controller.position.maxScrollExtent;

    controller.jumpTo(
      (target - viewport * 0.45)
          .clamp(0.0, maxScroll),
    );
  }

  void _goToPlace(int index) {
    _playClickSound();

    _placeController.animateToPage(
      index,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _onLevelTap(
    int placeIndex,
    int level,
  ) {
    final place = _places[placeIndex];

    if (place.isPlaceLocked ||
        level > place.unlockedLevel) {
      _playClickSound();
      return;
    }

    _playClickSound();

    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (_) => const LevelPage(),
      ),
    )
        .then((cleared) {
      if (cleared != true || !mounted) return;

      setState(() {
        if (level == place.unlockedLevel &&
            level < place.totalLevels) {
          place.unlockedLevel = level + 1;
        } else if (
            level == place.totalLevels &&
            placeIndex + 1 < _places.length &&
            _places[placeIndex + 1].isPlaceLocked) {
          _places[placeIndex + 1].unlockedLevel = 1;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToUnlocked(placeIndex),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = _places[_currentPlace].theme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _backgroundController,
                builder: (_, __) {
                  return CustomPaint(
                    painter: _CosmicBackgroundPainter(
                      theme: theme,
                      progress: _backgroundController.value,
                    ),
                  );
                },
              ),
            ),

            Column(
              children: [
                _buildTopHud(),
                _buildWorldSelector(),

                Expanded(
                  child: PageView.builder(
                    controller: _placeController,
                    itemCount: _places.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPlace = index;
                      });

                      WidgetsBinding.instance
                          .addPostFrameCallback(
                        (_) => _scrollToUnlocked(index),
                      );
                    },
                    itemBuilder: (_, index) {
                      return _buildWorld(index);
                    },
                  ),
                ),
              ],
            ),

            // Soft scrim so the HUD stays legible over the animated sky.
            IgnorePointer(
              child: Container(
                height: 190,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.black.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            _buildBottomProgress(),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // TOP HUD
  // ==========================================================================

  Widget _buildTopHud() {
    final place = _places[_currentPlace];
    final theme = place.theme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          _hudCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: _goBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.34),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.accent.withOpacity(0.13),
                      border: Border.all(
                        color: theme.accent.withOpacity(0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.accent.withOpacity(0.18),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                    child: Icon(
                      theme.icon,
                      color: theme.accent,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CAMPAIGN SECTOR',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          theme.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!place.isPlaceLocked) ...[
                    const SizedBox(width: 8),
                    _sectorBadge(theme: theme, place: place),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.12),
              Colors.white.withOpacity(0.035),
            ],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.30),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }

  Widget _sectorBadge({
    required _PlaceTheme theme,
    required _PlaceData place,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.48),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.accent.withOpacity(0.24),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.flag_rounded,
            size: 13,
            color: theme.accent,
          ),
          const SizedBox(width: 6),
          Text(
            '${place.completedLevels}/${place.totalLevels}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // WORLD SELECTOR
  // ==========================================================================

  Widget _buildWorldSelector() {
    return SizedBox(
      height: 104,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        itemCount: _places.length,
        itemBuilder: (_, index) {
          final place = _places[index];
          final selected = index == _currentPlace;
          final accent = place.isPlaceLocked
              ? Colors.white
              : place.theme.accent;

          return GestureDetector(
            onTap: () => _goToPlace(index),
            child: AnimatedScale(
              scale: selected ? 1.0 : 0.95,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 158,
                margin: EdgeInsets.only(
                  right: index == _places.length - 1 ? 0 : 10,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: place.isPlaceLocked
                        ? [
                            Colors.white.withOpacity(0.045),
                            Colors.white.withOpacity(0.018),
                          ]
                        : [
                            accent.withOpacity(selected ? 0.19 : 0.08),
                            Colors.black.withOpacity(0.30),
                          ],
                  ),
                  border: Border.all(
                    color: selected
                        ? accent.withOpacity(place.isPlaceLocked ? 0.22 : 0.70)
                        : Colors.white.withOpacity(0.08),
                    width: selected ? 1.4 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: accent.withOpacity(
                              place.isPlaceLocked ? 0.03 : 0.15,
                            ),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withOpacity(
                              place.isPlaceLocked ? 0.05 : 0.13,
                            ),
                            border: Border.all(
                              color: accent.withOpacity(
                                place.isPlaceLocked ? 0.08 : 0.25,
                              ),
                            ),
                          ),
                          child: Icon(
                            place.isPlaceLocked
                                ? Icons.lock_rounded
                                : place.theme.icon,
                            size: 14,
                            color: place.isPlaceLocked
                                ? Colors.white30
                                : accent,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '0${index + 1}',
                            style: TextStyle(
                              color: place.isPlaceLocked
                                  ? Colors.white24
                                  : accent.withOpacity(0.75),
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      place.isPlaceLocked ? 'LOCKED SECTOR' : place.theme.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: place.isPlaceLocked ? Colors.white38 : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: place.isPlaceLocked ? 0 : place.progress,
                        minHeight: 4,
                        backgroundColor: Colors.white.withOpacity(0.07),
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================================================
  // WORLD
  // ==========================================================================

  Widget _buildWorld(int placeIndex) {
    final place = _places[placeIndex];

    return AnimatedBuilder(
      animation: Listenable.merge([
        _backgroundController,
        _pulseController,
      ]),
      builder: (_, __) {
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ParticlePainter(
                  theme: place.theme,
                  progress:
                      _backgroundController.value,
                ),
              ),
            ),

            if (place.isPlaceLocked)
              Positioned.fill(
                child: Container(
                  color:
                      Colors.black.withOpacity(0.30),
                ),
              ),

            ListView(
              controller:
                  _mapControllers[placeIndex],
              physics:
                  const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: _topPadding +
                      (place.totalLevels - 1) *
                          _itemHeight +
                      _bottomPadding,
                  child: LayoutBuilder(
                    builder:
                        (context, constraints) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter:
                                  _CampaignPathPainter(
                                totalLevels:
                                    place.totalLevels,
                                theme:
                                    place.theme,
                                unlockedLevel:
                                    place
                                        .unlockedLevel,
                              ),
                            ),
                          ),

                          for (int level = 1;
                              level <=
                                  place.totalLevels;
                              level++)
                            _buildLevel(
                              placeIndex:
                                  placeIndex,
                              level: level,
                              width:
                                  constraints.maxWidth,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),

            if (place.isPlaceLocked)
              _buildLockedWorld(place),
          ],
        );
      },
    );
  }

  Widget _buildLockedWorld(
    _PlaceData place,
  ) {
    return Center(
      child: Container(
        margin:
            const EdgeInsets.symmetric(
          horizontal: 40,
        ),
        padding:
            const EdgeInsets.fromLTRB(
          24,
          25,
          24,
          22,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF08090D)
              .withOpacity(0.92),
          borderRadius:
              BorderRadius.circular(24),
          border: Border.all(
            color:
                Colors.white.withOpacity(0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withOpacity(0.55),
              blurRadius: 30,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white
                    .withOpacity(0.035),
                border: Border.all(
                  color: Colors.white
                      .withOpacity(0.12),
                ),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white54,
                size: 26,
              ),
            ),

            const SizedBox(height: 15),

            const Text(
              'WORLD LOCKED',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              'Complete the previous world\nto unlock this sector.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    Colors.white.withOpacity(0.48),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // LEVEL
  // ==========================================================================

  Widget _buildLevel({
    required int placeIndex,
    required int level,
    required double width,
  }) {
    final place = _places[placeIndex];

    final boss = _isBoss(level);

    final locked =
        place.isPlaceLocked ||
            level > place.unlockedLevel;

    final current =
        !place.isPlaceLocked &&
            level == place.unlockedLevel;

    final cleared =
        !place.isPlaceLocked &&
            level < place.unlockedLevel;

    final x = _pathX(level, width);

    final y =
        _topPadding +
            (level - 1) * _itemHeight;

    final size = boss ? 124.0 : 92.0;

    return Positioned(
      left: x - size / 2,
      top: y - size / 2,
      width: size,
      height: size,
      child: boss
          ? _BossNode(
              level: level,
              theme: place.theme,
              locked: locked,
              current: current,
              cleared: cleared,
              pulse:
                  _pulseController.value,
              onTap: () => _onLevelTap(
                placeIndex,
                level,
              ),
            )
          : _LevelNode(
              level: level,
              theme: place.theme,
              locked: locked,
              current: current,
              cleared: cleared,
              pulse:
                  _pulseController.value,
              onTap: () => _onLevelTap(
                placeIndex,
                level,
              ),
            ),
    );
  }

  double _pathX(
    int level,
    double width,
  ) {
    const side = 48.0;

    final usable =
        max(30.0, width - side * 2);

    final wave =
        sin((level - 1) * 0.88);

    final second =
        sin((level - 1) * 0.31 + 0.7);

    final normalized =
        0.5 +
            wave * 0.30 +
            second * 0.08;

    return side +
        usable *
            normalized.clamp(0.10, 0.90);
  }

  // ==========================================================================
  // BOTTOM PROGRESS
  // ==========================================================================

  Widget _buildBottomProgress() {
    final place = _places[_currentPlace];
    final theme = place.theme;

    if (place.isPlaceLocked) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 14,
      right: 14,
      bottom: 14,
      child: AnimatedBuilder(
        animation: _floatingController,
        builder: (_, __) {
          final offset =
              sin(_floatingController.value *
                      pi) *
                  2;

          return Transform.translate(
            offset: Offset(0, offset),
            child: Container(
              padding:
                  const EdgeInsets.fromLTRB(
                15,
                12,
                15,
                12,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF07090D)
                    .withOpacity(0.94),
                borderRadius:
                    BorderRadius.circular(18),
                border: Border.all(
                  color: theme.accent
                      .withOpacity(0.20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(0.45),
                    blurRadius: 22,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.accent
                          .withOpacity(0.10),
                    ),
                    child: Icon(
                      theme.icon,
                      color: theme.accent,
                      size: 18,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              theme.subtitle,
                              style: const TextStyle(
                                color:
                                    Colors.white54,
                                fontSize: 8,
                                fontWeight:
                                    FontWeight.w900,
                                letterSpacing:
                                    1.3,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${place.completedLevels}/${place.totalLevels}',
                              style: TextStyle(
                                color: theme.accent,
                                fontSize: 9,
                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(
                            5,
                          ),
                          child:
                              LinearProgressIndicator(
                            value:
                                place.progress,
                            minHeight: 5,
                            backgroundColor:
                                Colors.white
                                    .withOpacity(
                                        0.07),
                            valueColor:
                                AlwaysStoppedAnimation(
                              theme.accent,
                            ),
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
      ),
    );
  }
}

// ============================================================================
// NORMAL NODE
// ============================================================================

class _LevelNode extends StatelessWidget {
  final int level;
  final _PlaceTheme theme;

  final bool locked;
  final bool current;
  final bool cleared;

  final double pulse;

  final VoidCallback onTap;

  const _LevelNode({
    required this.level,
    required this.theme,
    required this.locked,
    required this.current,
    required this.cleared,
    required this.pulse,
    required this.onTap,
  });

  List<Color> get _clearedGradient => [
        Color.lerp(theme.nodeGradient[0], Colors.black, 0.30)!,
        Color.lerp(theme.nodeGradient[1], Colors.black, 0.30)!,
      ];

  @override
  Widget build(BuildContext context) {
    final glow =
        current
            ? 0.25 + pulse * 0.30
            : 0.10;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (current)
            Container(
              width: 76 + pulse * 9,
              height: 76 + pulse * 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.accent
                        .withOpacity(glow),
                    blurRadius:
                        24 + pulse * 12,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),

          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF080A0F),
              border: Border.all(
                color: locked
                    ? Colors.white
                        .withOpacity(0.12)
                    : theme.accent
                        .withOpacity(
                        current ? 0.95 : 0.48,
                      ),
                width: current ? 2.3 : 1.3,
              ),
            ),
          ),

          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: locked
                  ? const LinearGradient(
                      colors: [
                        Color(0xFF35373C),
                        Color(0xFF111216),
                      ],
                    )
                  : LinearGradient(
                      begin:
                          Alignment.topLeft,
                      end:
                          Alignment.bottomRight,
                      colors: cleared
                          ? _clearedGradient
                          : theme.nodeGradient,
                    ),
              boxShadow: [
                BoxShadow(
                  color: locked
                      ? Colors.black
                          .withOpacity(0.4)
                      : theme.accent
                          .withOpacity(
                        current ? 0.22 : 0.10,
                      ),
                  blurRadius: current ? 14 : 10,
                ),
              ],
            ),
            child: Center(
              child: locked
                  ? const Icon(
                      Icons.lock_rounded,
                      color: Colors.white38,
                      size: 19,
                    )
                  : cleared
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 27,
                        )
                      : Text(
                          '$level',
                          style:
                              const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
            ),
          ),

          if (current)
            Positioned(
              bottom: -5,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF08090D,
                  ),
                  borderRadius:
                      BorderRadius.circular(9),
                  border: Border.all(
                    color: theme.accent
                        .withOpacity(0.7),
                  ),
                ),
                child: Text(
                  'PLAY',
                  style: TextStyle(
                    color: theme.accent,
                    fontSize: 8,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// BOSS NODE
// ============================================================================

class _BossNode extends StatelessWidget {
  final int level;
  final _PlaceTheme theme;

  final bool locked;
  final bool current;
  final bool cleared;

  final double pulse;

  final VoidCallback onTap;

  const _BossNode({
    required this.level,
    required this.theme,
    required this.locked,
    required this.current,
    required this.cleared,
    required this.pulse,
    required this.onTap,
  });

  List<Color> get _clearedGradient => [
        Color.lerp(theme.bossGradient[0], Colors.black, 0.30)!,
        Color.lerp(theme.bossGradient[1], Colors.black, 0.30)!,
        Color.lerp(theme.bossGradient[2], Colors.black, 0.30)!,
      ];

  @override
  Widget build(BuildContext context) {
    final accent =
        locked ? Colors.white38 : theme.accent;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (!locked)
            Container(
              width: 96 + pulse * 8,
              height: 96 + pulse * 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.accent
                        .withOpacity(
                      current
                          ? 0.42 +
                              pulse * 0.25
                          : 0.15,
                    ),
                    blurRadius:
                        30 + pulse * 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),

          CustomPaint(
            size: const Size(112, 112),
            painter: _BossPainter(
              theme: theme,
              locked: locked,
              current: current,
              progress: pulse,
            ),
          ),

          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: locked
                  ? const LinearGradient(
                      colors: [
                        Color(0xFF404248),
                        Color(0xFF15161A),
                      ],
                    )
                  : LinearGradient(
                      begin:
                          Alignment.topLeft,
                      end:
                          Alignment.bottomRight,
                      colors: cleared
                          ? _clearedGradient
                          : theme.bossGradient,
                    ),
              border: Border.all(
                color: Colors.white
                    .withOpacity(
                  locked ? 0.12 : 0.75,
                ),
                width: 1.4,
              ),
            ),
            child: Center(
              child: locked
                  ? const Icon(
                      Icons.lock_rounded,
                      color: Colors.white38,
                      size: 20,
                    )
                  : cleared
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 28,
                        )
                      : Text(
                          '$level',
                          style:
                              const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
            ),
          ),

          Positioned(
            top: -14,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color:
                    const Color(0xFF08090D),
                borderRadius:
                    BorderRadius.circular(10),
                border: Border.all(
                  color: accent
                      .withOpacity(0.65),
                ),
              ),
              child: Row(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Icon(
                    Icons
                        .workspace_premium_rounded,
                    size: 11,
                    color: accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    cleared
                        ? 'DEFEATED'
                        : 'BOSS',
                    style: TextStyle(
                      color: locked
                          ? Colors.white38
                          : Colors.white,
                      fontSize: 8,
                      fontWeight:
                          FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (current)
            Positioned(
              bottom: -14,
              child: Text(
                'BOSS BATTLE',
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 8,
                  fontWeight:
                      FontWeight.w900,
                  letterSpacing: 1.1,
                  shadows: const [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// BOSS PAINTER
// ============================================================================

class _BossPainter extends CustomPainter {
  final _PlaceTheme theme;
  final bool locked;
  final bool current;
  final double progress;

  const _BossPainter({
    required this.theme,
    required this.locked,
    required this.current,
    required this.progress,
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

    final accent =
        locked ? Colors.white : theme.accent;

    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          current ? 2.5 : 1.7
      ..color = accent.withOpacity(
        locked ? 0.22 : 0.72,
      );

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withOpacity(
        locked ? 0.12 : 0.38,
      );

    canvas.drawCircle(
      center,
      44,
      outer,
    );

    canvas.drawCircle(
      center,
      34,
      inner,
    );

    final rotation =
        progress * pi * 2;

    final orbitPaint = Paint()
      ..color = accent.withOpacity(
        locked ? 0.18 : 0.9,
      );

    for (int i = 0; i < 4; i++) {
      final angle =
          rotation +
              i * (pi / 2);

      final point = Offset(
        center.dx +
            cos(angle) * 44,
        center.dy +
            sin(angle) * 44,
      );

      canvas.drawCircle(
        point,
        current ? 4 : 3,
        orbitPaint,
      );
    }

    final diamond = Path()
      ..moveTo(
        center.dx,
        center.dy - 49,
      )
      ..lineTo(
        center.dx + 7,
        center.dy - 40,
      )
      ..lineTo(
        center.dx,
        center.dy - 32,
      )
      ..lineTo(
        center.dx - 7,
        center.dy - 40,
      )
      ..close();

    canvas.drawPath(
      diamond,
      Paint()
        ..color = accent.withOpacity(
          locked ? 0.18 : 0.75,
        ),
    );
  }

  @override
  bool shouldRepaint(
    covariant _BossPainter oldDelegate,
  ) {
    return oldDelegate.progress != progress ||
        oldDelegate.locked != locked ||
        oldDelegate.current != current;
  }
}

// ============================================================================
// CAMPAIGN PATH
// ============================================================================

class _CampaignPathPainter
    extends CustomPainter {
  final int totalLevels;
  final _PlaceTheme theme;
  final int unlockedLevel;

  const _CampaignPathPainter({
    required this.totalLevels,
    required this.theme,
    required this.unlockedLevel,
  });

  double _xFor(int level, double width) {
    const side = 48.0;
    final usable = max(30.0, width - side * 2);
    final wave = sin((level - 1) * 0.88);
    final secondary = sin((level - 1) * 0.31 + 0.7);
    final normalized = 0.5 + wave * 0.30 + secondary * 0.08;
    return side + usable * normalized.clamp(0.10, 0.90);
  }

  Path _buildPath(int from, int to, double width) {
    const top = 80.0;
    const height = 142.0;

    final path = Path();

    for (int level = from; level <= to; level++) {
      final current = Offset(
        _xFor(level, width),
        top + (level - 1) * height,
      );

      if (level == from) {
        path.moveTo(current.dx, current.dy);
      } else {
        final previous = Offset(
          _xFor(level - 1, width),
          top + (level - 2) * height,
        );

        final mid = (previous.dy + current.dy) / 2;

        path.cubicTo(
          previous.dx,
          mid,
          current.dx,
          mid,
          current.dx,
          current.dy,
        );
      }
    }

    return path;
  }

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final doneEnd = unlockedLevel.clamp(1, totalLevels);

    final donePath = _buildPath(1, doneEnd, size.width);

    final remainPath = doneEnd < totalLevels
        ? _buildPath(doneEnd, totalLevels, size.width)
        : null;

    // Remaining (locked) section — dim, no glow.
    if (remainPath != null) {
      canvas.drawPath(
        remainPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.10),
      );

      canvas.drawPath(
        remainPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withOpacity(0.05),
      );
    }

    // Completed / active section — bright with glow.
    canvas.drawPath(
      donePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = theme.accent.withOpacity(0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawPath(
      donePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = theme.accent.withOpacity(0.45),
    );

    canvas.drawPath(
      donePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withOpacity(0.22),
    );
  }

  @override
  bool shouldRepaint(
    covariant _CampaignPathPainter oldDelegate,
  ) {
    return oldDelegate.theme != theme ||
        oldDelegate.totalLevels !=
            totalLevels ||
        oldDelegate.unlockedLevel !=
            unlockedLevel;
  }
}

// ============================================================================
// COSMIC BACKGROUND
// ============================================================================

class _CosmicBackgroundPainter
    extends CustomPainter {
  final _PlaceTheme theme;
  final double progress;

  const _CosmicBackgroundPainter({
    required this.theme,
    required this.progress,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ...theme.skyTop,
          ...theme.skyBottom,
        ],
      ).createShader(
        Offset.zero & size,
      );

    canvas.drawRect(
      Offset.zero & size,
      background,
    );

    final drift =
        sin(progress * pi * 2) * 22;

    final nebula = Paint()
      ..shader = RadialGradient(
        colors: [
          theme.accent
              .withOpacity(0.16),
          theme.accentDim
              .withOpacity(0.08),
          Colors.transparent,
        ],
        stops: const [
          0,
          0.42,
          1,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(
            size.width * 0.72,
            size.height * 0.25 +
                drift,
          ),
          radius:
              size.width * 0.70,
        ),
      );

    canvas.drawCircle(
      Offset(
        size.width * 0.72,
        size.height * 0.25 +
            drift,
      ),
      size.width * 0.70,
      nebula,
    );

    final random =
        Random(theme.name.hashCode);

    for (int i = 0; i < 100; i++) {
      final x =
          random.nextDouble() *
              size.width;

      final y =
          random.nextDouble() *
              size.height;

      final radius =
          random.nextDouble() *
                  1.1 +
              0.2;

      final alpha =
          random.nextDouble() *
                  0.35 +
              0.08;

      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white
              .withOpacity(alpha),
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _CosmicBackgroundPainter
        oldDelegate,
  ) {
    return oldDelegate.progress !=
            progress ||
        oldDelegate.theme != theme;
  }
}

// ============================================================================
// PARTICLES
// ============================================================================

class _ParticlePainter
    extends CustomPainter {
  final _PlaceTheme theme;
  final double progress;

  const _ParticlePainter({
    required this.theme,
    required this.progress,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final random =
        Random(theme.name.hashCode + 91);

    for (int i = 0; i < 36; i++) {
      final baseX =
          random.nextDouble() *
              size.width;

      final baseY =
          random.nextDouble() *
              size.height;

      final speed =
          0.25 +
              random.nextDouble() *
                  0.75;

      final phase =
          random.nextDouble();

      final t =
          (progress * speed +
                  phase) %
              1.0;

      double x = baseX;
      double y = baseY;

      double radius =
          1.2 +
              random.nextDouble() *
                  2;

      Color color =
          theme.accent.withOpacity(
        0.25,
      );

      switch (theme.particleKind) {
        case _ParticleKind.fire:
          y = (baseY - t * 160) %
              size.height;

          x = baseX +
              sin(
                    t * pi * 3 +
                        phase * 8,
                  ) *
                  8;

          color =
              (i.isEven
                      ? Colors.orangeAccent
                      : theme.accent)
                  .withOpacity(
            0.12 + t * 0.24,
          );

          break;

        case _ParticleKind.ice:
          y = (baseY + t * 120) %
              size.height;

          x = baseX +
              sin(
                    t * pi * 2 +
                        phase * 9,
                  ) *
                  6;

          radius =
              0.8 +
                  random.nextDouble() *
                      1.6;

          color = Colors.cyanAccent
              .withOpacity(
            0.12 + t * 0.22,
          );

          break;

        case _ParticleKind.voidSpace:
          x = (baseX + t * 100) %
              size.width;

          y = baseY +
              sin(
                    t * pi * 2 +
                        phase * 12,
                  ) *
                  13;

          color =
              theme.accent.withOpacity(
            0.10 + t * 0.24,
          );

          break;
      }

      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _ParticlePainter
        oldDelegate,
  ) {
    return oldDelegate.progress !=
            progress ||
        oldDelegate.theme != theme;
  }
}