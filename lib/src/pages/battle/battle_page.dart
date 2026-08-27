import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

class BattlePage extends StatelessWidget {
  const BattlePage({Key? key}) : super(key: key);

  static const _bg   = Color(0xFF050C16);
  static const _cyan = Color(0xFF4DD8FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.6),
          radius: 1.2,
          colors: [Color(0xFF3A1620), _bg],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.gps_fixed_rounded,
              size: 8.h,
              color: _cyan.withOpacity(0.85),
            ),
            SizedBox(height: 2.h),
            Text(
              'БОЙ',
              style: TextStyle(
                color: _cyan,
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}