import 'package:flutter/material.dart';

import '../llm/deepseek_model_installer.dart';
import 'assistant_shell.dart';

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key});

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  late final DeepSeekModelInstaller installer;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    installer = DeepSeekModelInstaller()..addListener(_sync);
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
    try {
      await installer.install();
    } catch (_) {}
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
    return Scaffold(
      backgroundColor: const Color(0xFF090A0E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              const Text(
                'Dream Pulse',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'LOCAL DeepSeek 1.5B  ↔  DeepSeek API',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF90949E),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'v0.10',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF60646E),
                ),
              ),
              const Spacer(flex: 3),
              if (checking)
                const Text(
                  'Проверяю локальную модель…',
                  style: TextStyle(
                    color: Color(0xFF8C909A),
                  ),
                )
              else ...[
                Text(
                  installer.installed
                      ? 'DeepSeek 1.5B установлен'
                      : 'Локальный DeepSeek не установлен',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB6B8BF),
                  ),
                ),
                if (installer.downloading) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: installer.progress > 0
                        ? installer.progress
                        : null,
                    minHeight: 3,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    installer.status,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7F838D),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              TextButton(
                onPressed: checking ? null : _openAssistant,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                ),
                child: const Text(
                  'Открыть Dream Pulse',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!installer.installed)
                TextButton(
                  onPressed: installer.downloading
                      ? installer.cancel
                      : _install,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    installer.downloading
                        ? 'Остановить загрузку'
                        : 'Скачать LOCAL 1.5B · ~1.12 ГБ',
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'API настраивается внутри чата. Локальная модель необязательна.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: Color(0xFF666A73),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
