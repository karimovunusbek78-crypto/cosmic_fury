import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

class NavBar extends StatefulWidget {
  final int selectedIndex;

  /// Called with the tapped tab's index. The parent (MainShell) owns
  /// navigation/state — NavBar just reports the tap. This is what lets
  /// NavBar's State (and its AnimationControllers) survive tab switches:
  /// nothing ever tears this widget down.
  final ValueChanged<int> onTabSelected;

  const NavBar({
    Key? key,
    required this.selectedIndex,
    required this.onTabSelected,
  }) : super(key: key);

  @override
  _NavBarState createState() => _NavBarState();
}

class _NavBarState extends State<NavBar> with TickerProviderStateMixin {
  late AnimationController _flickerController;

  // Drives the "pop" burst on the pill + selected icon whenever the
  // selection changes. Elastic curve gives it a springy, alive feel
  // instead of a flat linear scale.
  late AnimationController _popController;
  late Animation<double> _popAnim;

  final List<_NavItem> _items = const [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.checkroom_rounded, label: 'Skins'),
    _NavItem(icon: Icons.auto_fix_high_rounded, label: 'Spells'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    // Single continuous controller (0 -> 1 looping), driven by a sine
    // wave in the builder for a smooth, natural flicker without the
    // overhead of a particle system or a nested Flutter engine view.
    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..value = 1.0; // start settled, not mid-bounce

    _popAnim = CurvedAnimation(
      parent: _popController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void didUpdateWidget(covariant NavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _popController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flickerController.dispose();
    _popController.dispose();
    super.dispose();
  }

  void _handleTap(int index) {
    if (index == widget.selectedIndex) return;
    HapticFeedback.selectionClick();
    widget.onTabSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        // Merge both controllers into one listenable so we only rebuild
        // once per frame even though two animations are running.
        animation: Listenable.merge([_flickerController, _popController]),
        builder: (context, child) {
          // Smooth natural flicker: blend of two sine waves at different
          // speeds, normalized to 0.6-1.0. No jank, no particle spawning.
          final t = _flickerController.value * 2 * pi;
          final flicker = 0.8 + 0.1 * sin(t) + 0.1 * sin(t * 2.3 + 1.4);

          // Elastic pop value overshoots past 1.0 then settles — that
          // overshoot is what reads as "bouncy" rather than robotic.
          final pop = _popAnim.value;
          final pillScale = 0.82 + 0.18 * pop;

          return Container(
            padding: EdgeInsets.symmetric(horizontal: 2.8.w, vertical: 1.05.h),
            decoration: BoxDecoration(
              color: const Color(0xFF120404),
              borderRadius: BorderRadius.circular(6.w),
              border: Border.all(
                color: const Color(0xFFFF5252).withOpacity(0.4),
                width: 0.3.w,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF1744).withOpacity(0.25 * flicker),
                  blurRadius: 5.w * flicker,
                  spreadRadius: 0.3.w * flicker,
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / _items.length;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Sliding fiery pill — slides with a slight overshoot
                    // (easeOutBack) so it feels like it has weight/momentum,
                    // then pops in scale on arrival for extra juice.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutBack,
                      left: tabWidth * widget.selectedIndex,
                      top: 0,
                      bottom: 0,
                      width: tabWidth,
                      child: Center(
                        child: Transform.scale(
                          scale: pillScale,
                          child: Container(
                            width: tabWidth - 3.w,
                            padding: EdgeInsets.symmetric(vertical: 0.95.h),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4.w),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFC107),
                                  Color(0xFFFF3D00),
                                  Color(0xFFB71C1C),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFD50000)
                                      .withOpacity(0.55 * flicker),
                                  blurRadius: 3.w * flicker,
                                  spreadRadius: 0.25.w * flicker,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Icons + labels row (sits above the sliding pill)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(_items.length, (index) {
                        final isSelected = widget.selectedIndex == index;
                        final item = _items[index];

                        // Only the freshly-selected tab gets the elastic
                        // pop; everything else uses a calm ease.
                        final scale = isSelected
                            ? 0.92 + 0.08 * (0.7 + 0.3 * pop)
                            : 0.92;

                        return GestureDetector(
                          onTap: () => _handleTap(index),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: tabWidth,
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 0.85.h),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedScale(
                                    duration:
                                        const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    scale: isSelected ? scale.clamp(0.0, 1.06) : 0.92,
                                    child: Icon(
                                      item.icon,
                                      size: 5.8.w,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.45),
                                    ),
                                  ),
                                  SizedBox(height: 0.35.h),
                                  AnimatedDefaultTextStyle(
                                    duration:
                                        const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    style: TextStyle(
                                      fontSize: 9.1.sp,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.45),
                                    ),
                                    child: Text(item.label),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}