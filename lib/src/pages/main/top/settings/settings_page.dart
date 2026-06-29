import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  static const Color hudCyan = Color(0xFF4DD8E8);
  static const Color bgDark = Color(0xFF0A1622);
  static const Color bgCard = Color(0xFF0E1F30);
  static const Color borderCol = Color(0xFF1C3A52);
  static const Color textDim = Color(0xFF7A93A8);

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  double _music = 0.6;
  double _sfx = 0.6;
  double _voice = 0.6;

  bool _vibration = true;
  bool _notifications = true;
  bool _powerSaving = false;
  bool _highQuality = true;

  String _language = 'Русский';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      child: Container(
        constraints: BoxConstraints(maxWidth: 100.w),
        padding: EdgeInsets.fromLTRB(4.w, 2.5.h, 4.w, 2.h),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SettingsDialog.bgDark, const Color(0xFF050C14)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SettingsDialog.hudCyan.withOpacity(0.5), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: SettingsDialog.hudCyan.withOpacity(0.15),
              blurRadius: 30,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Sticky header — stays fixed while content scrolls ──
            _buildHeader(context),
            SizedBox(height: 2.h),

            // ── Scrollable body ────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _sectionLabel('ЗВУК'),
                    SizedBox(height: 1.h),
                    _SliderRow(icon: Icons.music_note_rounded, label: 'Музыка', value: _music, onChanged: (v) => setState(() => _music = v)),
                    SizedBox(height: 1.2.h),
                    _SliderRow(icon: Icons.graphic_eq_rounded, label: 'Звуковые эффекты', value: _sfx, onChanged: (v) => setState(() => _sfx = v)),
                    SizedBox(height: 1.2.h),
                    _SliderRow(icon: Icons.chat_bubble_outline_rounded, label: 'Голос', value: _voice, onChanged: (v) => setState(() => _voice = v)),

                    SizedBox(height: 2.h),
                    _sectionLabel('ЯЗЫК'),
                    SizedBox(height: 1.h),
                    _LanguageRow(
                      language: _language,
                      onTap: () async {
                        final selected = await _showLanguagePicker(context);
                        if (selected != null) setState(() => _language = selected);
                      },
                    ),

                    SizedBox(height: 2.h),
                    _sectionLabel('ИГРА'),
                    SizedBox(height: 0.5.h),
                    _ToggleRow(
                      icon: Icons.vibration_rounded,
                      label: 'Вибрация',
                      value: _vibration,
                      onChanged: (v) => setState(() => _vibration = v),
                    ),
                    _ToggleRow(
                      icon: Icons.notifications_none_rounded,
                      label: 'Уведомления',
                      value: _notifications,
                      onChanged: (v) => setState(() => _notifications = v),
                    ),
                    _ToggleRow(
                      icon: Icons.battery_charging_full_rounded,
                      label: 'Энергосбережение',
                      value: _powerSaving,
                      onChanged: (v) => setState(() => _powerSaving = v),
                    ),
                    _ToggleRow(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Высокое качество графики',
                      value: _highQuality,
                      onChanged: (v) => setState(() => _highQuality = v),
                    ),

                    SizedBox(height: 1.5.h),
                    _sectionLabel('АККАУНТ'),
                    SizedBox(height: 1.h),
                    _AccountRow(onTap: () {}),

                    SizedBox(height: 2.h),
                    Row(
                      children: [
                        Expanded(child: _SmallActionButton(icon: Icons.headset_mic_rounded, label: 'ПОДДЕРЖКА', onTap: () {})),
                        SizedBox(width: 2.w),
                        Expanded(child: _SmallActionButton(icon: Icons.shield_outlined, label: 'ПОЛИТИКА', onTap: () {})),
                        SizedBox(width: 2.w),
                        Expanded(child: _SmallActionButton(icon: Icons.info_outline_rounded, label: 'ОБ ИГРЕ', onTap: () {})),
                      ],
                    ),

                    SizedBox(height: 1.8.h),
                    _ExitButton(onTap: () {}),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: Text(
            'НАСТРОЙКИ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19.sp,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Positioned(
          right: 0,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 8.w,
              height: 8.w,
              decoration: BoxDecoration(
                color: const Color(0xFF040B14),
                shape: BoxShape.circle,
                border: Border.all(color: SettingsDialog.hudCyan, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: SettingsDialog.hudCyan.withOpacity(0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(Icons.close_rounded, color: SettingsDialog.hudCyan, size: 16.sp),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            color: SettingsDialog.hudCyan,
            fontSize: 13.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        SizedBox(width: 2.w),
        Expanded(
          child: Container(
            height: 1,
            color: SettingsDialog.borderCol,
          ),
        ),
      ],
    );
  }

  Future<String?> _showLanguagePicker(BuildContext context) {
    const langs = ['Русский', 'English', 'Español', 'Deutsch'];
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: SettingsDialog.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: langs
              .map((l) => ListTile(
                    title: Text(l, style: TextStyle(color: Colors.white, fontSize: 13.sp)),
                    onTap: () => Navigator.pop(ctx, l),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ─── Sub widgets ───────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 18.sp),
        SizedBox(width: 2.5.w),
        SizedBox(
          width: 30.w,
          child: Text(
            label,
            style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: SettingsDialog.hudCyan,
              inactiveTrackColor: SettingsDialog.borderCol,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(value: value, onChanged: onChanged),
          ),
        ),
        SizedBox(width: 1.w),
        Icon(Icons.volume_up_rounded, color: SettingsDialog.hudCyan, size: 18.sp),
      ],
    );
  }
}

class _LanguageRow extends StatelessWidget {
  final String language;
  final VoidCallback onTap;

  const _LanguageRow({required this.language, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.public_rounded, color: Colors.white.withOpacity(0.8), size: 18.sp),
        SizedBox(width: 2.5.w),
        Text('Язык', style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600)),
        const Spacer(),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 0.8.h),
            decoration: BoxDecoration(
              color: SettingsDialog.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SettingsDialog.borderCol, width: 1.2),
            ),
            child: Row(
              children: [
                Text(language, style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600)),
                SizedBox(width: 2.w),
                Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.6), size: 18.sp),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 0.8.h),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.8), size: 18.sp),
          SizedBox(width: 2.5.w),
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600)),
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: SettingsDialog.hudCyan,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: SettingsDialog.borderCol,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AccountRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, color: Colors.white.withOpacity(0.8), size: 18.sp),
          SizedBox(width: 2.5.w),
          Text('Аккаунт', style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('Гость', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.sp, fontWeight: FontWeight.w600)),
          SizedBox(width: 1.w),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.5), size: 18.sp),
        ],
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 1.2.h, horizontal: 1.w),
        decoration: BoxDecoration(
          color: SettingsDialog.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SettingsDialog.borderCol, width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SettingsDialog.hudCyan, size: 18.sp),
            SizedBox(height: 0.5.h),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.w700, letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExitButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ExitButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 1.4.h),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withOpacity(0.7), width: 1.3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18.sp),
            SizedBox(width: 2.w),
            Text(
              'ВЫЙТИ ИЗ ИГРЫ',
              style: TextStyle(color: Colors.redAccent, fontSize: 13.sp, fontWeight: FontWeight.w800, letterSpacing: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}