import 'package:flutter/material.dart';

import '../core/pulse_coordinator.dart';
import 'ring_painter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.core});

  final PulseCoordinator core;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final AnimationController pulseController;

  @override
  void initState() {
    super.initState();
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.core.engine;
    return AnimatedBuilder(
      animation: Listenable.merge([widget.core, engine, pulseController]),
      builder: (context, _) {
        final s = engine.snapshot;
        return Container(
          color: const Color(0xFF06080C),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: RingPainter(engine: engine, t: pulseController.value),
                        ),
                        Positioned(
                          left: 12,
                          top: 8,
                          child: _Tag(
                            text: engine.running ? 'LIVE TASK' : 'LIVE CORE',
                            active: engine.running,
                          ),
                        ),
                        Positioned(
                          right: 12,
                          top: 8,
                          child: _Tag(
                            text: engine.phase,
                            active: engine.running,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0A0D12),
                    border: Border(top: BorderSide(color: Color(0xFF292D36))),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          _Metric('CORE MASS', s.mass.toStringAsFixed(1)),
                          _Metric('PULSE', '${s.pulse}'),
                          _Metric('WORKERS', '${s.workers}'),
                          _Metric('PROCESSORS', '${s.processors}'),
                          _Metric('CRITICS', '${s.critics}'),
                          _Metric('TRUSTED', '${s.trustedKnowledge}'),
                          _Metric('REJECTED', '${engine.rejectedByCritic}'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _Line(label: 'MEMORY', value: widget.core.memoryStatus),
                      _Line(label: 'DOMAIN', value: widget.core.lastDomain),
                      _Line(label: 'CRITIC', value: widget.core.lastVerdict),
                      _Line(
                        label: 'WEB WORKER',
                        value: widget.core.lastUsedWeb
                            ? '${widget.core.lastSources.length} evidence hits'
                            : 'idle / no evidence',
                      ),
                      _Line(label: 'STATUS', value: widget.core.status),
                      if (widget.core.lastTask.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1218),
                            border: Border.all(color: const Color(0xFF242A34)),
                          ),
                          child: Text(
                            widget.core.lastTask,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Color(0xFFB9C0CC)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'LIVE ONLY · CORE GROWS FROM REAL TASKS · NO SYNTHETIC PULSE FARMING',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: .8,
                          color: Color(0xFF7D8490),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.active});
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xDD090B0F),
        border: Border.all(
          color: active ? const Color(0xFFFF641A) : const Color(0xFF353B46),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
          color: active ? const Color(0xFFFFA15B) : const Color(0xFF929AA8),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF101319),
        border: Border.all(color: const Color(0xFF2B3039)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: Color(0xFF747D8C), letterSpacing: .5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF727B89), letterSpacing: .4)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFCBD0D8)),
            ),
          ),
        ],
      ),
    );
  }
}
