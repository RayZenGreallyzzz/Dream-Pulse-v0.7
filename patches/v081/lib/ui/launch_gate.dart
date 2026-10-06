import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../llm/qwen_model_installer.dart';
import 'assistant_shell.dart';

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key});

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  late final QwenModelInstaller installer;
  bool checking = true;
  String? error;

  @override
  void initState() {
    super.initState();
    installer = QwenModelInstaller()..addListener(_sync);
    _refresh();
  }

  Future<void> _refresh() async {
    await installer.refresh();
    if (mounted) setState(() => checking = false);
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  Future<void> _install() async {
    setState(() => error = null);
    try {
      await installer.install();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void _openAssistant() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AssistantShell()),
    );
  }

  @override
  void dispose() {
    installer.removeListener(_sync);
    installer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installing = installer.downloading || installer.verifying;
    final ready = installer.installed;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 700;
            return Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF030405)),
                Positioned.fill(
                  top: compact ? 72 : 90,
                  bottom: compact ? 214 : 250,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: DreamPulseEmblem(),
                  ),
                ),
                const Positioned(
                  left: 20,
                  right: 20,
                  top: 18,
                  child: Column(
                    children: [
                      Text(
                        'DREAM PULSE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 5.5,
                          color: Color(0xFFFF6A16),
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'LOCAL CORE · v0.8.1',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 2.2,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xEE090B0F),
                      border: Border.all(color: const Color(0xFF5A2D17)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              color: ready
                                  ? const Color(0xFF62E7A7)
                                  : const Color(0xFFFF6A16),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                checking ? 'CHECKING LOCAL CORE...' : installer.status,
                                style: const TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 0.8,
                                  color: Color(0xFFE5E7EB),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        if (installing) ...[
                          LinearProgressIndicator(
                            value: installer.progress > 0 ? installer.progress : null,
                            minHeight: 6,
                            backgroundColor: const Color(0xFF1B1D22),
                            valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6A16)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(installer.progress * 100).clamp(0, 100).toStringAsFixed(1)}% · Qwen3 1.7B Q4_K_M · ~1.28 GB',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFB7BBC4)),
                          ),
                        ] else ...[
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: checking ? null : (ready ? _openAssistant : _install),
                              child: Text(
                                ready
                                    ? 'ЗАПУСТИТЬ DREAM PULSE'
                                    : 'УСТАНОВИТЬ QWEN 1.7B · ~1.28 GB',
                              ),
                            ),
                          ),
                          if (!ready) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 42,
                              child: OutlinedButton(
                                onPressed: _openAssistant,
                                child: const Text('ПРОПУСТИТЬ · БЕЗ LOCAL BRAIN'),
                              ),
                            ),
                          ],
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            error!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFFF8A65), fontSize: 11),
                          ),
                        ],
                        const SizedBox(height: 9),
                        const Text(
                          'Модель загружается один раз и затем работает локально без интернета.',
                          style: TextStyle(color: Color(0xFF7F8792), fontSize: 10.5),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class DreamPulseEmblem extends StatelessWidget {
  const DreamPulseEmblem({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DreamPulseEmblemPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _DreamPulseEmblemPainter extends CustomPainter {
  static const orange = Color(0xFFFF5A0A);
  static const fire = Color(0xFFFF8B2C);
  static const ember = Color(0xFFB62B08);
  static const stone = Color(0xFF17191D);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.36;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          fire.withValues(alpha: 0.40),
          orange.withValues(alpha: 0.14),
          Colors.transparent,
        ],
        stops: const [0, .48, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.28));
    canvas.drawCircle(c, r * 1.28, glow);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, r * .032)
      ..color = orange;
    canvas.drawCircle(c, r * .86, ring);
    ring
      ..strokeWidth = math.max(1, r * .012)
      ..color = fire.withValues(alpha: .70);
    canvas.drawCircle(c, r * 1.00, ring);

    final rayPaint = Paint()
      ..color = stone
      ..style = PaintingStyle.fill;
    final rayEdge = Paint()
      ..color = ember
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * .014);
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final tip = c + Offset(math.cos(a), math.sin(a)) * (r * 1.23);
      final left = c + Offset(math.cos(a - .11), math.sin(a - .11)) * (r * .77);
      final right = c + Offset(math.cos(a + .11), math.sin(a + .11)) * (r * .77);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(path, rayPaint);
      canvas.drawPath(path, rayEdge);
    }

    canvas.drawCircle(
      Offset(c.dx, c.dy - r * .20),
      r * .34,
      Paint()..color = const Color(0xFFFFC066),
    );

    final groundY = c.dy + r * .47;
    final cityPaint = Paint()..color = const Color(0xFF111216);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, r * .012)
      ..color = const Color(0xFF2C2D31);

    final widths = <double>[.09, .075, .10, .065, .18, .07, .10, .07, .09];
    final heights = <double>[.35, .49, .42, .29, .82, .31, .50, .38, .33];
    double x = c.dx - r * .72;
    for (var i = 0; i < widths.length; i++) {
      final w = r * widths[i];
      final h = r * heights[i];
      final rect = Rect.fromLTWH(x, groundY - h, w, h);
      canvas.drawRect(rect, cityPaint);
      canvas.drawRect(rect, outline);
      final spire = Path()
        ..moveTo(x + w * .5, groundY - h - w * .75)
        ..lineTo(x + w * .08, groundY - h)
        ..lineTo(x + w * .92, groundY - h)
        ..close();
      canvas.drawPath(spire, cityPaint);
      canvas.drawPath(spire, outline);
      x += w + r * .065;
    }

    final towerX = c.dx;
    final towerTop = groundY - r * .82;
    final towerW = r * .18;
    final tower = Path()
      ..moveTo(towerX, towerTop - r * .22)
      ..lineTo(towerX - towerW * .32, towerTop)
      ..lineTo(towerX - towerW * .50, groundY)
      ..lineTo(towerX + towerW * .50, groundY)
      ..lineTo(towerX + towerW * .32, towerTop)
      ..close();
    canvas.drawPath(tower, cityPaint);
    canvas.drawPath(tower, outline);

    final windowPaint = Paint()..color = const Color(0xFFFFB348);
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(towerX, towerTop + r * (.11 + i * .135)),
          width: towerW * .14,
          height: r * .055,
        ),
        windowPaint,
      );
    }

    final horizon = Paint()
      ..color = orange.withValues(alpha: .72)
      ..strokeWidth = math.max(1, r * .016);
    canvas.drawLine(
      Offset(c.dx - r * .72, groundY),
      Offset(c.dx + r * .72, groundY),
      horizon,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
