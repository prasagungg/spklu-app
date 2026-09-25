import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Baterai yang terisi mengikuti kemajuan pengisian.
///
/// [fill] adalah energi tersalur dibagi kWh yang dipesan — 1 kWh dari
/// 10 kWh berarti 0.1, dan cairannya berhenti di sepersepuluh tabung.
/// Nilainya dijepit 0..1 supaya bacaan backend yang melebihi pesanan
/// tidak menumpahkan cairan keluar tabung.
///
/// Ilustrasi PNG pada desain tidak dipakai di sini: cairannya tercetak
/// di satu ketinggian tetap, jadi gambar itu tidak pernah bisa bercerita
/// soal kemajuan. Bentuknya digambar ulang dengan token warna yang sama.
class BatteryGauge extends StatefulWidget {
  const BatteryGauge({super.key, required this.fill});

  final double fill;

  @override
  State<BatteryGauge> createState() => _BatteryGaugeState();
}

class _BatteryGaugeState extends State<BatteryGauge>
    with SingleTickerProviderStateMixin {
  /// Riak permukaan cairan — satu putaran penuh gelombang.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.58,
      // Kenaikan energi tiap detik kecil; transisi membuat cairannya
      // naik mulus alih-alih melompat.
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.fill.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        builder: (context, fill, _) => AnimatedBuilder(
          animation: _wave,
          builder: (context, _) => CustomPaint(
            painter: _BatteryPainter(fill: fill, phase: _wave.value),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter({required this.fill, required this.phase});

  final double fill;

  /// 0..1, satu putaran gelombang.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final capHeight = size.height * 0.06;
    final capWidth = size.width * 0.34;

    final body = Rect.fromLTWH(
      0,
      capHeight,
      size.width,
      size.height - capHeight,
    );
    final bodyShape = RRect.fromRectAndRadius(
      body,
      Radius.circular(size.width * 0.22),
    );

    _paintCap(canvas, size, capWidth, capHeight);

    // Tabung kaca: bagian yang belum terisi.
    canvas.drawRRect(bodyShape, Paint()..color = AppColors.batteryGlass);

    final liquid = _paintLiquid(canvas, bodyShape, body);

    canvas.drawRRect(
      bodyShape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.035
        ..color = AppColors.batteryGlassBorder,
    );

    _paintBolt(canvas, size, liquid);
  }

  void _paintCap(Canvas canvas, Size size, double width, double height) {
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH((size.width - width) / 2, 0, width, height * 1.6),
        topLeft: Radius.circular(height * 0.6),
        topRight: Radius.circular(height * 0.6),
      ),
      Paint()..color = AppColors.batteryCap,
    );
  }

  /// Cairan dengan permukaan bergelombang, digambar dari dasar tabung.
  ///
  /// Mengembalikan bentuk cairannya supaya petir bisa diwarnai putih
  /// hanya pada bagian yang terendam.
  Path? _paintLiquid(Canvas canvas, RRect shape, Rect body) {
    if (fill <= 0) return null;

    canvas.save();
    canvas.clipRRect(shape.deflate(body.width * 0.05));

    final surfaceY = body.bottom - body.height * fill;
    final amplitude = body.width * 0.035;
    final path = Path()..moveTo(body.left, surfaceY);

    // Dua gelombang penuh selebar tabung, digeser mengikuti [phase].
    for (var x = 0.0; x <= body.width; x += 2) {
      final t = x / body.width;
      final y = surfaceY + sin((t * 2 + phase) * 2 * pi) * amplitude;
      path.lineTo(body.left + x, y);
    }

    path
      ..lineTo(body.right, body.bottom)
      ..lineTo(body.left, body.bottom)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = AppColors.batteryLiquidGradient.createShader(
          Rect.fromLTRB(body.left, surfaceY, body.right, body.bottom),
        ),
    );

    // Pendar tipis di permukaan, supaya cairannya terlihat hidup.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = amplitude * 0.8
        ..color = AppColors.batteryLiquidGlow,
    );

    canvas.restore();

    return path;
  }

  /// Petir di tengah tabung, sama seperti ilustrasi aslinya.
  ///
  /// Digambar dua nada: biru pucat di atas permukaan cairan, putih pada
  /// bagian yang terendam. Putih saja hilang di tabung yang masih
  /// kosong, karena kacanya pun terang.
  void _paintBolt(Canvas canvas, Size size, Path? liquid) {
    final w = size.width * 0.34;
    final h = size.height * 0.28;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;

    // Poligon petir dalam satuan 0..1, lalu diskalakan ke kotaknya.
    const points = [
      Offset(0.58, 0),
      Offset(0.1, 0.55),
      Offset(0.44, 0.55),
      Offset(0.36, 1),
      Offset(0.9, 0.42),
      Offset(0.54, 0.42),
    ];

    final path = Path()
      ..addPolygon([
        for (final p in points) Offset(left + p.dx * w, top + p.dy * h),
      ], true);

    canvas.drawPath(path, Paint()..color = AppColors.batteryGlassBorder);

    if (liquid == null) return;

    canvas.save();
    canvas.clipPath(liquid);
    canvas.drawPath(path, Paint()..color = AppColors.surface);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.fill != fill || old.phase != phase;
}
