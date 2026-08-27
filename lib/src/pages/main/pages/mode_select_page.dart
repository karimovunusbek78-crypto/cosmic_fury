import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame_audio/flame_audio.dart';
import 'fight_map_page.dart';

/// Mode select screen — shown after tapping PLAY.
/// Two big cards:
/// Campaign (story missions) and Survival (endless waves).
class ModeSelectPage extends StatefulWidget {
  const ModeSelectPage({Key? key}) : super(key: key);

  @override
  _ModeSelectPageState createState() => _ModeSelectPageState();
}

class _ModeSelectPageState extends State<ModeSelectPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();

    // Preload click sound so the first tap doesn't have a delay.
    FlameAudio.audioCache.load('click.mp3');
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Plays the same click sound used throughout the main game.
  void _playClickSound() {
    FlameAudio.play(
      'click.mp3',
      volume: 0.6,
    );
  }

  void _selectCampaign() {
    _playClickSound();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FightMapPage(),
      ),
    );
  }

  void _selectSurvival() {
    _playClickSound();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _ModePlaceholderPage(
          title: 'Survival',
        ),
      ),
    );
  }

  void _goBack() {
    _playClickSound();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // -------------------------------------------------------------
          // STARFIELD
          // -------------------------------------------------------------
          Positioned.fill(
            child: CustomPaint(
              painter: _StarfieldPainter(),
            ),
          ),

          // -------------------------------------------------------------
          // AMBIENT ORANGE GLOW
          // -------------------------------------------------------------
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.4),
                  radius: 1.2,
                  colors: [
                    Colors.deepOrange.withOpacity(0.16),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------
          // MAIN CONTENT
          // -------------------------------------------------------------
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      24,
                    ),
                    child: Column(
                      children: [
                        // -------------------------------------------------
                        // CAMPAIGN
                        // -------------------------------------------------
                        Expanded(
                          child: _AnimatedEntrance(
                            controller: _entrance,
                            delay: 0.0,
                            child: _ModeCard(
                              title: 'CAMPAIGN',
                              subtitle:
                                  'Fight through story missions and\nface off against evolving bosses.',
                              icon: Icons.rocket_launch_rounded,
                              backgroundAsset:
                                  'assets/images/campaignbackground.png',
                              gradientColors: const [
                                Color(0xFFFFC371),
                                Color(0xFFFF5F3D),
                              ],
                              glowColor: Colors.orange,
                              badge: '100 LEVELS',
                              onTap: _selectCampaign,
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // -------------------------------------------------
                        // SURVIVAL
                        // -------------------------------------------------
                        Expanded(
                          child: _AnimatedEntrance(
                            controller: _entrance,
                            delay: 0.15,
                            child: _ModeCard(
                              title: 'SURVIVAL',
                              subtitle:
                                  'Endless waves, rising difficulty.\nHow long can you last?',
                              icon: Icons.whatshot_rounded,
                              backgroundAsset:
                                  'assets/images/survivalbackground.png',
                              gradientColors: const [
                                Color(0xFFFF5F6D),
                                Color(0xFF8E1F1F),
                              ],
                              glowColor: Colors.redAccent,
                              badge: 'ENDLESS',
                              onTap: _selectSurvival,
                            ),
                          ),
                        ),
                      ],
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
  // HEADER
  // ------------------------------------------------------------------

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        8,
        12,
        20,
        4,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _goBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),

          const SizedBox(width: 4),

          const Text(
            'CHOOSE YOUR MISSION',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// ANIMATED ENTRANCE
// =====================================================================

class _AnimatedEntrance extends StatelessWidget {
  final AnimationController controller;
  final double delay;
  final Widget child;

  const _AnimatedEntrance({
    required this.controller,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(
        delay,
        (delay + 0.7).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(
              0,
              (1 - curved.value) * 30,
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// =====================================================================
// MODE CARD
// =====================================================================

class _ModeCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String backgroundAsset;
  final List<Color> gradientColors;
  final Color glowColor;
  final String badge;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.backgroundAsset,
    required this.gradientColors,
    required this.glowColor,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _pressed = true;
        });
      },

      onTapCancel: () {
        setState(() {
          _pressed = false;
        });
      },

      onTapUp: (_) {
        setState(() {
          _pressed = false;
        });
      },

      onTap: widget.onTap,

      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,

        child: Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.black,

            border: Border.all(
              color: widget.gradientColors.first.withOpacity(0.5),
              width: 1.4,
            ),

            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(0.35),
                blurRadius: 24,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
            ],
          ),

          child: Stack(
            fit: StackFit.expand,
            children: [
              // ---------------------------------------------------------
              // BACKGROUND IMAGE
              // ---------------------------------------------------------

              Image.asset(
                widget.backgroundAsset,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),

              // ---------------------------------------------------------
              // LEFT DARK GRADIENT
              // ---------------------------------------------------------

              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withOpacity(0.92),
                      Colors.black.withOpacity(0.75),
                      Colors.black.withOpacity(0.15),
                    ],
                    stops: const [
                      0.0,
                      0.45,
                      1.0,
                    ],
                  ),
                ),
              ),

              // ---------------------------------------------------------
              // BOTTOM DARK GRADIENT
              // ---------------------------------------------------------

              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.black.withOpacity(0.0),
                    ],
                    stops: const [
                      0.0,
                      0.6,
                    ],
                  ),
                ),
              ),

              // ---------------------------------------------------------
              // TOP ACCENT LINE
              // ---------------------------------------------------------

              Positioned(
                top: 0,
                left: 24,
                right: 24,

                child: Container(
                  height: 3,

                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),

                    gradient: LinearGradient(
                      colors: widget.gradientColors,
                    ),

                    boxShadow: [
                      BoxShadow(
                        color: widget.glowColor.withOpacity(0.8),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),

              // ---------------------------------------------------------
              // CARD CONTENT
              // ---------------------------------------------------------

              Padding(
                padding: const EdgeInsets.all(20),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [
                    Row(
                      children: [
                        // ICON
                        Container(
                          padding: const EdgeInsets.all(10),

                          decoration: BoxDecoration(
                            shape: BoxShape.circle,

                            gradient: LinearGradient(
                              colors: widget.gradientColors,
                            ),

                            boxShadow: [
                              BoxShadow(
                                color:
                                    widget.glowColor.withOpacity(0.6),
                                blurRadius: 12,
                              ),
                            ],
                          ),

                          child: Icon(
                            widget.icon,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),

                        const Spacer(),

                        // BADGE
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),

                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white.withOpacity(0.08),

                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),

                          child: Text(
                            widget.badge,

                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // TITLE
                    Text(
                      widget.title,

                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,

                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),

                    // SUBTITLE
                    Text(
                      widget.subtitle,

                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 12.5,
                        height: 1.35,

                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // TAP TO START
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),

                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),

                        border: Border.all(
                          color: widget.gradientColors.first
                              .withOpacity(0.8),
                        ),

                        color: Colors.black.withOpacity(0.35),
                      ),

                      child: Row(
                        mainAxisSize: MainAxisSize.min,

                        children: [
                          Text(
                            'TAP TO START',

                            style: TextStyle(
                              color: widget.gradientColors.first,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),

                          const SizedBox(width: 4),

                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: widget.gradientColors.first,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// STARFIELD
// =====================================================================

class _StarfieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(7);

    final paint = Paint()
      ..color = Colors.white;

    for (int i = 0; i < 60; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;

      final r = rng.nextDouble() * 1.2 + 0.3;

      paint.color = Colors.white.withOpacity(
        rng.nextDouble() * 0.5 + 0.2,
      );

      canvas.drawCircle(
        Offset(dx, dy),
        r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

// =====================================================================
// PLACEHOLDER PAGE
// =====================================================================

class _ModePlaceholderPage extends StatelessWidget {
  final String title;

  const _ModePlaceholderPage({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(title),
      ),

      body: Center(
        child: Text(
          '$title mode goes here',

          style: const TextStyle(
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}