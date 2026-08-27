import 'package:cosmic_fury/src/nav_bar/main_shell.dart';
import 'package:flutter/material.dart';

class IntroPage extends StatefulWidget {
  const IntroPage({ Key? key }) : super(key: key);

  @override
  _IntroPageState createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progress;

  late AnimationController _flickerController;
  late Animation<double> _flicker;

  @override
  void initState() {
    super.initState();

    // Loading progress (0 -> 100% over 5 seconds)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _progress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    )..addListener(() {
        setState(() {});
      });

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    });

    // Subtle flicker loop (glow pulsing)
    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _flicker = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _flickerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _flickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress.value * 100).toInt();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // -----------------------------------------------------------
          // Full-screen intro image — fills the ENTIRE screen edge to
          // edge (ignores SafeArea on purpose so it goes under the
          // notch/status bar too), instead of being boxed into the top
          // portion above the loading bar.
          // -----------------------------------------------------------
          Positioned.fill(
            child: Image.asset(
              'assets/images/intro.png',
              fit: BoxFit.cover,
            ),
          ),

          // -----------------------------------------------------------
          // Loading bar overlay — pinned near the bottom of the screen,
          // on top of the full-screen image. Wrapped in its own
          // SafeArea so the bar itself doesn't sit under system UI,
          // while the background image still goes full-bleed.
          // -----------------------------------------------------------
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_controller, _flickerController]),
                    builder: (context, child) {
                      return Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final barWidth = constraints.maxWidth;
                              const shipSize = 60.0;
                              const barHeight = 18.0;
                              const stackHeight = 60.0; // room for bigger ship

                              // Ship center follows the fill exactly, from
                              // the very start to the very end of the bar.
                              final shipCenterX =
                                  barWidth * _progress.value.clamp(0.0, 1.0);
                              final shipLeft =
                                  (shipCenterX - shipSize / 2).clamp(
                                -shipSize / 2,
                                barWidth - shipSize / 2,
                              );

                              return SizedBox(
                                height: stackHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Outer glow behind the whole bar
                                    Positioned(
                                      top: (stackHeight - barHeight) / 2 - 4,
                                      left: -4,
                                      right: -4,
                                      child: Container(
                                        height: barHeight + 8,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFF1744)
                                                  .withOpacity(
                                                      0.35 * _flicker.value),
                                              blurRadius: 20 * _flicker.value,
                                              spreadRadius: 2 * _flicker.value,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Base track — glass capsule with gradient border
                                    Positioned(
                                      top: (stackHeight - barHeight) / 2,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: barHeight,
                                        padding: const EdgeInsets.all(1.6),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          gradient: LinearGradient(
                                            colors: [
                                              const Color(0xFFFF5252)
                                                  .withOpacity(0.9),
                                              const Color(0xFF7A0C0C)
                                                  .withOpacity(0.9),
                                            ],
                                          ),
                                        ),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(19),
                                            color: const Color(0xFF150505),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black,
                                                blurRadius: 6,
                                                spreadRadius: -2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Fill with shimmer highlight
                                    Positioned(
                                      top: (stackHeight - barHeight) / 2 + 2.5,
                                      left: 2.5,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          height: barHeight - 5,
                                          width: (barWidth - 5) *
                                              _progress.value.clamp(0.0, 1.0),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFFFFC107), // amber
                                                Color(0xFFFF3D00), // red-orange
                                                Color(0xFFB71C1C), // deep red
                                              ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFD50000)
                                                    .withOpacity(
                                                        0.7 * _flicker.value),
                                                blurRadius: 16 * _flicker.value,
                                                spreadRadius:
                                                    1.5 * _flicker.value,
                                              ),
                                            ],
                                          ),
                                          child: Stack(
                                            children: [
                                              // Top glass highlight strip
                                              Positioned(
                                                top: 0,
                                                left: 0,
                                                right: 0,
                                                child: Container(
                                                  height:
                                                      (barHeight - 5) * 0.45,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        const BorderRadius
                                                            .vertical(
                                                      top: Radius.circular(16),
                                                    ),
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topCenter,
                                                      end:
                                                          Alignment.bottomCenter,
                                                      colors: [
                                                        Colors.white
                                                            .withOpacity(0.35),
                                                        Colors.white
                                                            .withOpacity(0.0),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Ship — centered on the bar line,
                                    // moving with the progress the whole way
                                    Positioned(
                                      top: (stackHeight - shipSize) / 2,
                                      left: shipLeft,
                                      child: Transform.scale(
                                        scale: 0.9 + (0.15 * _flicker.value),
                                        child: Image.asset(
                                          'assets/images/loading.png',
                                          width: shipSize,
                                          height: shipSize,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 12),

                          // Percentage text
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [
                                Color(0xFFFF5252),
                                Color(0xFFB71C1C),
                              ],
                            ).createShader(bounds),
                            child: Text(
                              'Loading $percent%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}