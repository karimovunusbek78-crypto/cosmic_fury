import 'package:cosmic_fury/src/pages/main/top/top_profile_bar.dart';
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF010409),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.3,
            colors: [
              Color(0xFF0A192F),
              Color(0xFF010409),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const TopProfileBar(),

              const Spacer(),

              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 10,
                      child: _CosmicButton(
                        title: "УЛУЧШЕНИЯ",
                        icon: Icons.keyboard_double_arrow_up_rounded,
                        onTap: () {},
                        isPrimary: false,
                      ),
                    ),

                    SizedBox(width: 3.w),

                    Expanded(
                      flex: 12,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: _CosmicButton(
                              title: "ИГРАТЬ",
                              icon: Icons.play_arrow_rounded,
                              onTap: () {},
                              isPrimary: true,
                            ),
                          );
                        },
                      ),
                    ),

                    SizedBox(width: 3.w),

                    Expanded(
                      flex: 10,
                      child: _CosmicButton(
                        title: "СПЕЛЛЫ",
                        icon: Icons.bolt_rounded,
                        onTap: () {},
                        isPrimary: false,
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

// ─── Cosmic Button ────────────────────────────────────────────────────────────

class _CosmicButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _CosmicButton({
    required this.title,
    required this.icon,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  State<_CosmicButton> createState() => _CosmicButtonState();
}

class _CosmicButtonState extends State<_CosmicButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 80),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.fastOutSlowIn),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double computedHeight = widget.isPrimary ? 8.5.h : 7.2.h;

    const Color navbarCyan = Color(0xFF4DD8E8);
    const Color navbarBlue = Color(0xFF16324F);

    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: ClipPath(
          clipper: _TrapezoidClipper(),
          child: Container(
            height: computedHeight,
            decoration: const BoxDecoration(
              color: Color(0xFF040B14),
            ),
            child: CustomPaint(
              painter: _TrapezoidGradientBorderPainter(
                borderGradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.fromARGB(255, 28, 205, 225), navbarBlue],
                ),
                borderWidth: widget.isPrimary ? 2.5 : 1.5,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      color: navbarCyan.withOpacity(0.8),
                      size: widget.isPrimary ? 22.sp : 19.sp,
                    ),
                    SizedBox(height: 0.2.h),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.cyanAccent.withOpacity(0.75),
                        fontSize: widget.isPrimary ? 11.5.sp : 10.0.sp,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Trapezoid Clipper ───────────────────────────────────────────────────────

class _TrapezoidClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    double cutWidth = size.width * 0.15;

    path.moveTo(cutWidth, 0);
    path.lineTo(size.width - cutWidth, 0);
    path.lineTo(size.width, size.height * 0.32);
    path.lineTo(size.width, size.height * 0.82);
    path.lineTo(size.width - cutWidth * 0.5, size.height);
    path.lineTo(cutWidth * 0.5, size.height);
    path.lineTo(0, size.height * 0.82);
    path.lineTo(0, size.height * 0.32);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// ─── Trapezoid Gradient Border Painter ───────────────────────────────────────

class _TrapezoidGradientBorderPainter extends CustomPainter {
  final Gradient borderGradient;
  final double borderWidth;

  _TrapezoidGradientBorderPainter({
    required this.borderGradient,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final path = Path();
    double cutWidth = size.width * 0.15;

    path.moveTo(cutWidth, 0);
    path.lineTo(size.width - cutWidth, 0);
    path.lineTo(size.width, size.height * 0.32);
    path.lineTo(size.width, size.height * 0.82);
    path.lineTo(size.width - cutWidth * 0.5, size.height);
    path.lineTo(cutWidth * 0.5, size.height);
    path.lineTo(0, size.height * 0.82);
    path.lineTo(0, size.height * 0.32);
    path.close();

    final paint = Paint()
      ..shader = borderGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrapezoidGradientBorderPainter oldDelegate) {
    return oldDelegate.borderGradient != borderGradient ||
        oldDelegate.borderWidth != borderWidth;
  }
}