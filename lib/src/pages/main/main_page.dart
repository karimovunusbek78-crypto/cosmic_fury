import 'package:cosmic_fury/src/pages/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:responsive_sizer/responsive_sizer.dart';



class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final List<_NavItemData> _items = const [
    _NavItemData(icon: Icons.home_rounded,           label: 'ГЛАВНАЯ'),
    _NavItemData(icon: Icons.rocket_launch_rounded,  label: 'КОРАБЛИ'),
    _NavItemData(icon: Icons.gps_fixed_rounded,      label: 'БОЙ'),
    _NavItemData(icon: Icons.calendar_month_rounded, label: 'СОБЫТИЯ'),
    _NavItemData(icon: Icons.apps_rounded,           label: 'ЕЩЁ'),
  ];

  // Each nav tab maps 1:1 to its own page/class — add a new tab here and a
  // matching widget here, in the same order as `_items` above.
  final List<Widget> _pages = const [
    HomePage(),
    ShipsPage(),
    BattlePage(),
    EventsPage(),
    MorePage(),
  ];

  void _onTap(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.lightImpact();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _pages[_currentIndex],
      bottomNavigationBar: _GalacticBottomNav(
        items: _items,
        currentIndex: _currentIndex,
        onTap: _onTap,
      ),
    );
  }
}

// ── Main content (starfield backdrop) ──────────────────────────────────────

class _GalacticMainContent extends StatelessWidget {
  const _GalacticMainContent();

  static const _bg = Color(0xFF050C16);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.6),
              radius: 1.2,
              colors: [Color(0xFF0A2040), _bg],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData({required this.icon, required this.label});
}

// ── Bottom nav ────────────────────────────────────────────────────────────────
// Main nav tabs with a sliding, bouncy indicator and a slow ambient pulse
// that breathes life into the active tab even when nothing is being tapped.

class _GalacticBottomNav extends StatefulWidget {
  final List<_NavItemData> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GalacticBottomNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<_GalacticBottomNav> createState() => _GalacticBottomNavState();
}

class _GalacticBottomNavState extends State<_GalacticBottomNav>
    with SingleTickerProviderStateMixin {
  static const _cyan = Color(0xFF4DD8FF);
  static const _dim  = Color(0xFF55708A);
  static const _bg   = Color(0xFF050C16);
  static const double _indicatorWidthFraction = 0.16; // relative to tab slot

  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(
          top: BorderSide(color: _cyan.withOpacity(0.25), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: _cyan.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 9.5.h,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / widget.items.length;
              final indicatorWidth = tabWidth * _indicatorWidthFraction;
              return Stack(
                children: [
                  // Sliding indicator with an overshoot "bounce" on arrival
                  // and a slow ambient glow pulse while idle.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    top: 1.4.h,
                    left: tabWidth * widget.currentIndex +
                        (tabWidth - indicatorWidth) / 2,
                    width: indicatorWidth,
                    height: 3,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        final p = _pulse.value;
                        return Container(
                          decoration: BoxDecoration(
                            color: _cyan,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: _cyan.withOpacity(0.55 + 0.3 * p),
                                blurRadius: 5 + 5 * p,
                                spreadRadius: 0.5 + 1 * p,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    children: List.generate(widget.items.length, (i) {
                      final isActive = i == widget.currentIndex;
                      return Expanded(
                        child: _NavTabButton(
                          data: widget.items[i],
                          isActive: isActive,
                          activeColor: _cyan,
                          inactiveColor: _dim,
                          pulse: _pulse,
                          onTap: () => widget.onTap(i),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Individual nav tab ───────────────────────────────────────────────────────
// Handles its own press feedback (quick squash on tap-down) plus a richer
// "arrival" animation when it becomes the active tab: the icon hops up and
// scales in with a slight overshoot, a soft halo blooms behind it and keeps
// breathing gently, the color crossfades instead of snapping, and the label
// eases into its bolder, wider-spaced active style.

class _NavTabButton extends StatefulWidget {
  final _NavItemData data;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final Animation<double> pulse;
  final VoidCallback onTap;

  const _NavTabButton({
    required this.data,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.pulse,
    required this.onTap,
  });

  @override
  State<_NavTabButton> createState() => _NavTabButtonState();
}

class _NavTabButtonState extends State<_NavTabButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final color = isActive ? widget.activeColor : widget.inactiveColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 1.4.h + 3 + 0.4.h),
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Ambient glow halo — blooms in when active, breathes gently
                AnimatedBuilder(
                  animation: widget.pulse,
                  builder: (context, _) {
                    final p = isActive ? widget.pulse.value : 0.0;
                    return AnimatedOpacity(
                      opacity: isActive ? 0.22 + 0.22 * p : 0.0,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutBack,
                        width: isActive ? 4.4.h : 2.4.h,
                        height: isActive ? 4.4.h : 2.4.h,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              widget.activeColor.withOpacity(0.9),
                              widget.activeColor.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Icon hops up and overshoots slightly into place
                AnimatedSlide(
                  offset: isActive ? const Offset(0, -0.22) : Offset.zero,
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutBack,
                  child: AnimatedScale(
                    scale: isActive ? 1.18 : 1.0,
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutBack,
                    child: TweenAnimationBuilder<Color?>(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                      tween: ColorTween(begin: color, end: color),
                      builder: (context, animatedColor, _) {
                        return Icon(
                          widget.data.icon,
                          size: 2.8.h,
                          color: animatedColor,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              height: isActive ? 0.9.h : 0.5.h,
            ),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: isActive ? 12.sp : 11.5.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: isActive ? 0.9 : 0.5,
                color: color,
              ),
              child: Text(widget.data.label),
            ),
          ],
        ),
      ),
    );
  }
}