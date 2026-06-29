import 'package:cosmic_fury/src/pages/page.dart';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/flame.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'dart:math';
import 'dart:ui' as ui;

class IntroPage extends StatefulWidget {
  const IntroPage({Key? key}) : super(key: key);

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainPage()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = 100.w;
    final screenHeight = 100.h;

    return Scaffold(
      body: GameWidget(
        game: LoadingGame(
          screenWidth: screenWidth,
          screenHeight: screenHeight,
        ),
      ),
    );
  }
}

const List<String> _messages = [
  'LOADING SHIPS...',
  'LOADING SPELLS...',
  'CALIBRATING WEAPONS...',
  'CHECKING FUEL...',
  'LOADING LEVELS...',
  'SYSTEMS ONLINE...',
];

class _Ship {
  double x, y, vx, vy, size, opacity, life;
  Color color;
  double angle;

  _Ship({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.color,
    required this.angle,
  }) : life = 0;
}

class LoadingGame extends FlameGame {
  final double screenWidth;
  final double screenHeight;

  double _progress  = 0.0;
  double _elapsed   = 0.0;
  double _glowPulse = 0.0;
  int    _msgIndex  = 0;
  double _dotTimer  = 0.0;
  int    _dotCount  = 0;

  late ui.Image _backgroundImage;
  bool _bgLoaded = false;

  late ui.Image _loadShipImage;
  bool _shipLoaded = false;

  final List<_Ship> _ships = [];
  final Random _rng = Random();

  LoadingGame({required this.screenWidth, required this.screenHeight});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _backgroundImage = await Flame.images.load('intro_background.png');
      _bgLoaded = true;
    } catch (_) {}

    try {
      _loadShipImage = await Flame.images.load('load_ship.png');
      _shipLoaded = true;
    } catch (_) {}

    for (int i = 0; i < 18; i++) {
      _spawnShip(initial: true);
    }
  }

  void _spawnShip({bool initial = false}) {
    final colors = [
      Colors.cyanAccent,
      Colors.cyan,
      Colors.lightBlueAccent,
      Colors.white,
      Colors.blueAccent,
    ];
    final angle = -pi / 2 + (_rng.nextDouble() - 0.5) * 0.5;
    final speed = _rng.nextDouble() * 1.2 + 0.5;
    _ships.add(_Ship(
      x: _rng.nextDouble() * screenWidth,
      y: initial ? _rng.nextDouble() * screenHeight : screenHeight + 20,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
      size: _rng.nextDouble() * 5 + 3,
      opacity: _rng.nextDouble() * 0.6 + 0.35,
      color: colors[_rng.nextInt(colors.length)],
      angle: angle + pi / 2,
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    _progress  = (_elapsed / 5.0).clamp(0.0, 1.0);
    _glowPulse = (sin(_elapsed * 3.0) + 1) / 2;

    _dotTimer += dt;
    if (_dotTimer >= 0.4) {
      _dotTimer = 0;
      _dotCount = (_dotCount + 1) % 4;
    }

    _msgIndex = ((_progress * _messages.length).floor())
        .clamp(0, _messages.length - 1);

    for (final s in _ships) {
      s.x    += s.vx;
      s.y    += s.vy;
      s.life += dt;
      s.opacity -= dt * 0.04;
    }
    _ships.removeWhere((s) => s.y < -30 || s.opacity <= 0);
    while (_ships.length < 22) {
      _spawnShip();
    }
  }

  void _drawParticleShip(Canvas canvas, _Ship s) {
    final sz = s.size;
    final paint = Paint()
      ..color = s.color.withOpacity(s.opacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(s.x, s.y);
    canvas.rotate(s.angle);

    final body = Path()
      ..moveTo(0, -sz)
      ..lineTo(-sz * 0.38, sz * 0.6)
      ..lineTo( sz * 0.38, sz * 0.6)
      ..close();
    canvas.drawPath(body, paint);

    final lWing = Path()
      ..moveTo(-sz * 0.38, sz * 0.2)
      ..lineTo(-sz * 0.9,  sz * 0.7)
      ..lineTo(-sz * 0.38, sz * 0.6)
      ..close();
    canvas.drawPath(lWing, paint);

    final rWing = Path()
      ..moveTo( sz * 0.38, sz * 0.2)
      ..lineTo( sz * 0.9,  sz * 0.7)
      ..lineTo( sz * 0.38, sz * 0.6)
      ..close();
    canvas.drawPath(rWing, paint);

    canvas.drawCircle(
      Offset(0, sz * 0.6),
      sz * 0.25,
      Paint()
        ..color = Colors.cyanAccent.withOpacity((s.opacity * 0.8).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final w = screenWidth;
    final h = screenHeight;

    // ── 1. Background ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF000510),
    );
    if (_bgLoaded) {
      canvas.drawImageRect(
        _backgroundImage,
        Rect.fromLTWH(0, 0,
            _backgroundImage.width.toDouble(),
            _backgroundImage.height.toDouble()),
        Rect.fromLTWH(0, 0, w, h),
        Paint()..color = Colors.white.withOpacity(0.85),
      );
    }

    // ── 2. Particle ships ──
    for (final s in _ships) {
      _drawParticleShip(canvas, s);
    }

    // ── 3. Bottom vignette ──
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.58, w, h * 0.42),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.58),
          Offset(0, h),
          [Colors.transparent, Colors.black.withOpacity(0.94)],
        ),
    );

    // ── 4. Layout ──
    final bottomPad = h * 0.06;
    final barHeight  = h * 0.013;
    final barWidth   = w * 0.72;
    final barX       = (w - barWidth) / 2;
    final barY       = h - bottomPad - barHeight;
    final percentY   = barY - h * 0.055;
    final msgY       = percentY - h * 0.042;
    final dots = '.' * _dotCount;
    final msg  = _messages[_msgIndex].replaceAll('...', dots.isEmpty ? '   ' : dots);

    _drawText(canvas,
      text: msg, fontSize: w / 26,
      color: Color.lerp(Colors.cyan[300], Colors.blue[300], _glowPulse)!,
      y: msgY, w: w, letterSpacing: 2.5, fontWeight: FontWeight.w600,
    );

    _drawText(canvas,
      text: '${(_progress * 100).toInt()}%', fontSize: w / 14,
      color: Colors.white,
      y: percentY, w: w, letterSpacing: 1, fontWeight: FontWeight.w800,
    );

    // ── Bar background ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barY, barWidth, barHeight),
          Radius.circular(barHeight)),
      Paint()..color = Colors.white.withOpacity(0.08),
    );

    // ── Bar border ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barY, barWidth, barHeight),
          Radius.circular(barHeight)),
      Paint()
        ..color = Colors.cyan.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // ── Bar fill ──
    if (_progress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(barX, barY, barWidth * _progress, barHeight),
            Radius.circular(barHeight)),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(barX, 0),
            Offset(barX + barWidth, 0),
            [
              const Color(0xFF00E5FF),
              const Color(0xFF0091EA),
              const Color(0xFF6200EA),
            ],
            [0.0, 0.6, 1.0],
          ),
      );

      // ── load_ship.png — small, horizontal, exactly on tip ──
      if (_shipLoaded) {
        final tipX    = barX + barWidth * _progress;
        final barMidY = barY + barHeight / 2;

        // Small size — just 4x bar height
        final shipH = barHeight * 4.0;
        final shipW = shipH * (_loadShipImage.width / _loadShipImage.height);

        canvas.drawImageRect(
          _loadShipImage,
          Rect.fromLTWH(0, 0,
              _loadShipImage.width.toDouble(),
              _loadShipImage.height.toDouble()),
          Rect.fromCenter(
            center: Offset(tipX, barMidY),
            width: shipW,
            height: shipH,
          ),
          Paint(),
        );
      }
    }

    // ── Segment ticks ──
    for (int i = 1; i < 10; i++) {
      final tx = barX + barWidth * i / 10;
      canvas.drawLine(
        Offset(tx, barY + barHeight * 0.2),
        Offset(tx, barY + barHeight * 0.8),
        Paint()
          ..color = Colors.white.withOpacity(0.15)
          ..strokeWidth = 0.6,
      );
    }
  }

  void _drawText(Canvas canvas, {
    required String text,
    required double fontSize,
    required Color color,
    required double y,
    required double w,
    double letterSpacing = 0,
    FontWeight fontWeight = FontWeight.normal,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset((w - painter.width) / 2, y));
  }
}