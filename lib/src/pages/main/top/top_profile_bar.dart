import 'package:cosmic_fury/src/pages/page.dart';
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

// ─── Top Profile Bar ──────────────────────────────────────────────────────────

class TopProfileBar extends StatelessWidget {
  final String name;
  const TopProfileBar({this.name = 'Игрок'});

  static const Color hudCyan = Color(0xFF4DD8E8);
  static const Color hudGold = Color(0xFFFFD966);
  static const Color hudGem  = Color(0xFFC49AFF);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 2.h, 4.w, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _ProfileWithLevel(level: 1),

              SizedBox(width: 4.w),

              Expanded(
                child: _ExperienceIndicator(
                  currentXp: 150,
                  maxXp: 300,
                  name: name,
                ),
              ),

              SizedBox(width: 3.w),

              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    barrierColor: Colors.black.withOpacity(0.6),
                    builder: (_) => const SettingsDialog(),
                  );
                },
                child: Container(
                  width: 10.w,
                  height: 10.w,
                  decoration: BoxDecoration(
                    color: const Color(0xFF040B14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: hudCyan, width: 1.6),
                  ),
                  child: Icon(
                    Icons.settings_rounded,
                    color: hudCyan,
                    size: 18.sp,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 1.8.h),

          Row(
            children: [
              Expanded(
                child: _CurrencyCard(
                  imagePath: 'assets/images/coin.png',
                  value: '4 850',
                  accentColor: hudGold,
                  glowColor: const Color(0xFFC8820A),
                  borderColor: const Color(0xFF3A2F00),
                  bgStart: const Color(0xFF0E0900),
                  onAdd: () {},
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: _CurrencyCard(
                  imagePath: 'assets/images/gem.png',
                  value: '120',
                  accentColor: hudGem,
                  glowColor: const Color(0xFF6428C8),
                  borderColor: const Color(0xFF1A0A30),
                  bgStart: const Color(0xFF0C0618),
                  onAdd: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Currency Card ────────────────────────────────────────────────────────────

class _CurrencyCard extends StatelessWidget {
  final String imagePath;
  final String value;
  final Color accentColor;
  final Color glowColor;
  final Color borderColor;
  final Color bgStart;
  final VoidCallback onAdd;

  const _CurrencyCard({
    required this.imagePath,
    required this.value,
    required this.accentColor,
    required this.glowColor,
    required this.borderColor,
    required this.bgStart,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 0.5.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgStart, const Color(0xFF040B14)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 10.w,
            height: 10.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: glowColor.withOpacity(0.5),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.monetization_on_rounded,
                color: accentColor,
                size: 10.w,
              ),
            ),
          ),

          SizedBox(width: 2.w),

          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: accentColor,
                fontSize: 14.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                height: 1.1,
              ),
            ),
          ),

          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 5.5.w,
              height: 5.5.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accentColor, width: 1.4),
              ),
              child: Icon(Icons.add, color: accentColor, size: 14.sp),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Profile With Level ───────────────────────────────────────────────────────

class _ProfileWithLevel extends StatelessWidget {
  final int level;
  const _ProfileWithLevel({required this.level});

  @override
  Widget build(BuildContext context) {
    final double photoSize = 14.w;
    final double badgeSize = 6.w;

    return SizedBox(
      width: photoSize,
      height: photoSize + badgeSize * 0.5,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: photoSize,
            height: photoSize,
            decoration: BoxDecoration(
              color: const Color(0xFF040B14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: TopProfileBar.hudCyan,
                width: 1.6,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/profile.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_rounded,
                  color: TopProfileBar.hudCyan,
                  size: photoSize * 0.6,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF040B14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: TopProfileBar.hudCyan,
                  width: 1.6,
                ),
              ),
              child: Text(
                '$level',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Experience Indicator ─────────────────────────────────────────────────────

class _ExperienceIndicator extends StatelessWidget {
  final int currentXp;
  final int maxXp;
  final String name;

  const _ExperienceIndicator({
    required this.currentXp,
    required this.maxXp,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final double progress =
        maxXp <= 0 ? 0 : (currentXp / maxXp).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'ОПЫТ',
              style: TextStyle(
                color: TopProfileBar.hudCyan,
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),

        SizedBox(height: 0.8.h),

        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 1.2.h,
            backgroundColor: const Color(0xFF16324F),
            valueColor:
                const AlwaysStoppedAnimation(TopProfileBar.hudCyan),
          ),
        ),

        SizedBox(height: 0.5.h),

        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$currentXp / $maxXp XP',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}