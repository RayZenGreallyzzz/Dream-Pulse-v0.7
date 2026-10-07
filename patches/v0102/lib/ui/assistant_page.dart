import 'package:flutter/material.dart';

import '../avatar/avatar_session.dart';
import '../avatar/speech_controller.dart';
import '../core/pulse_coordinator.dart';
import '../llm/brain_router.dart';
import '../llm/deepseek_model_installer.dart';
import '../llm/local_deepseek_backend.dart';
import '../voice/voice_input_controller.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.session,
    required this.speech,
    required this.voiceInput,
    required this.brain,
    required this.localBrain,
    required this.installer,
    required this.core,
  });

  final AvatarSession session;
  final SpeechController speech;
  final VoiceInputController voiceInput;
  final BrainRouter brain;
  final LocalDeepSeekBackend localBrain;
  final DeepSeekModelInstaller installer;
  final PulseCoordinator core;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final input = TextEditingController();
  final messages = <_Message>[];

  bool busy = false;
  bool autoSpeak = true;
  bool dialogMode = false;
  bool thinking = false;
  bool forceWeb = false;
  String status = 'Dream Pulse готов';

  @override
  void initState() {
    super.initState();
    widget.localBrain.addListener(_syncStatus);
    widget.brain.groq.addListener(_syncStatus);
    widget.brain.api.addListener(_syncStatus);
    widget.voiceInput.addListener(_syncVoice);
    widget.installer.addListener(_syncStatus);
  }

  void _syncStatus() {
    if (mounted) setState(() {});
  }

  void _syncVoice() {
    if (!mounted) return;
    if (widget.voiceInput.listening && widget.voiceInput.partial.isNotEmpty) {
      input.text = widget.voiceInput.partial;
      input.selection = TextSelection.collapsed(offset: input.text.length);
    }
    setState(() {});
  }

  bool get _thinkAvailable {
    switch (widget.brain.mode) {
      case BrainMode.groq:
        return widget.brain.groq.ready;
      case BrainMode.deepseek:
        return widget.brain.api.ready;
      case BrainMode.local:
        return false;
      case BrainMode.auto:
        return widget.brain.groq.ready;
    }
  }

  String get _modeLabel {
    switch (widget.brain.mode) {
      case BrainMode.auto:
        return 'AUTO';
      case BrainMode.groq:
        return 'GROQ FREE';
      case BrainMode.local:
        return 'LOCAL';
      case BrainMode.deepseek:
        return 'DEEPSEEK';
    }
  }

  String get _brainStatus {
    switch (widget.brain.mode) {
      case BrainMode.auto:
        if (widget.brain.groq.ready) return 'GPT-OSS 120B';
        if (widget.localBrain.ready) return 'DeepSeek 1.5B';
        return 'настрой Groq Free';
      case BrainMode.groq:
        return widget.brain.groq.ready
            ? 'GPT-OSS 120B'
            : 'нужен Groq key';
      case BrainMode.local:
        if (widget.localBrain.ready) return 'DeepSeek 1.5B';
        if (widget.installer.downloading) return widget.installer.status;
        return widget.installer.installed
            ? 'DeepSeek 1.5B · не загружен'
            : 'DeepSeek 1.5B · не установлен';
      case BrainMode.deepseek:
        return widget.brain.api.ready
            ? 'DeepSeek Flash'
            : 'нужен DeepSeek key';
    }
  }

  Future<bool> _ensureBrainReady() async {
    if (widget.brain.mode == BrainMode.groq) {
      if (!widget.brain.groq.ready) {
        await _showBrainSheet();
        return widget.brain.groq.ready;
      }
      return true;
    }

    if (widget.brain.mode == BrainMode.deepseek) {
      if (!widget.brain.api.ready) {
        await _showBrainSheet();
        return widget.brain.api.ready;
      }
      return true;
    }

    if (widget.brain.mode == BrainMode.auto && widget.brain.groq.ready) {
      return true;
    }

    if (widget.localBrain.ready) return true;

    final path = await widget.installer.prepare();
    if (path == null) {
      await _showBrainSheet();
      return false;
    }

    try {
      await widget.localBrain.load(path);
      return widget.localBrain.ready;
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка LOCAL · $e');
      return false;
    }
  }

  Future<void> _installLocal() async {
    try {
      final path = await widget.installer.install();
      await widget.localBrain.load(path);
      if (!mounted) return;
      setState(() {
        widget.brain.mode = BrainMode.local;
        thinking = false;
        status = 'DeepSeek 1.5B готов';
      });
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка загрузки · $e');
    }
  }

  Future<void> _showBrainSheet() async {
    if (!mounted) return;
    final groqKey = TextEditingController();
    final deepSeekKey = TextEditingController();

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0D0E12),
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> saveGroq() async {
              try {
                await widget.brain.groq.saveApiKey(groqKey.text);
                groqKey.clear();
                widget.brain.mode = BrainMode.auto;
                if (sheetContext.mounted) setSheetState(() {});
                if (mounted) setState(() {});
              } catch (e) {
                if (mounted) setState(() => status = 'Groq · $e');
              }
            }

            Future<void> saveDeepSeek() async {
              try {
                await widget.brain.api.saveApiKey(deepSeekKey.text);
                deepSeekKey.clear();
                widget.brain.mode = BrainMode.deepseek;
                if (sheetContext.mounted) setSheetState(() {});
                if (mounted) setState(() {});
              } catch (e) {
                if (mounted) setState(() => status = 'DeepSeek API · $e');
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  MediaQuery.viewInsetsOf(context).bottom + 18,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Мозг Dream Pulse',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'AUTO бесплатно: Groq 120B → LOCAL 1.5B. Платный DeepSeek никогда не включается автоматически.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9498A3),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 18,
                        children: BrainMode.values.map((mode) {
                          final selected = widget.brain.mode == mode;
                          final label = switch (mode) {
                            BrainMode.auto => 'AUTO',
                            BrainMode.groq => 'GROQ',
                            BrainMode.local => 'LOCAL',
                            BrainMode.deepseek => 'DEEPSEEK',
                          };
                          return TextButton(
                            onPressed: () {
                              widget.brain.mode = mode;
                              if (mode == BrainMode.local) thinking = false;
                              setSheetState(() {});
                              if (mounted) setState(() {});
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 36),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFFFF7A2F)
                                    : const Color(0xFF8D919B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'GROQ FREE · GPT-OSS 120B',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.brain.groq.ready
                            ? 'Ключ сохранён · AUTO использует Groq первым'
                            : 'Нужен бесплатный API key с console.groq.com',
                        style: const TextStyle(
                          color: Color(0xFF9498A3),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: groqKey,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          hintText: 'Groq API key',
                          filled: true,
                          fillColor: Color(0xFF15161B),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: saveGroq,
                            child: const Text('Сохранить Groq key'),
                          ),
                          if (widget.brain.groq.ready)
                            TextButton(
                              onPressed: () async {
                                await widget.brain.groq.clearApiKey();
                                if (sheetContext.mounted) {
                                  setSheetState(() {});
                                }
                                if (mounted) setState(() {});
                              },
                              child: const Text('Удалить'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'LOCAL · DeepSeek 1.5B',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.localBrain.ready
                            ? widget.localBrain.status
                            : widget.installer.status,
                        style: const TextStyle(
                          color: Color(0xFF9498A3),
                          fontSize: 12,
                        ),
                      ),
                      if (widget.installer.downloading) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: widget.installer.progress > 0
                              ? widget.installer.progress
                              : null,
                          minHeight: 3,
                        ),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: widget.installer.downloading
                              ? widget.installer.cancel
                              : _installLocal,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            widget.localBrain.ready
                                ? 'Локальная модель загружена'
                                : widget.installer.downloading
                                    ? 'Остановить загрузку'
                                    : widget.installer.installed
                                        ? 'Загрузить в память'
                                        : 'Скачать ~1.12 ГБ',
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'DEEPSEEK API · платный · только вручную',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        widget.brain.api.ready
                            ? 'DeepSeek API key сохранён'
                            : 'Не нужен для AUTO',
                        style: const TextStyle(
                          color: Color(0xFF9498A3),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: deepSeekKey,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          hintText: 'DeepSeek API key',
                          filled: true,
                          fillColor: Color(0xFF15161B),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: saveDeepSeek,
                            child: const Text('Сохранить DeepSeek key'),
                          ),
                          if (widget.brain.api.ready)
                            TextButton(
                              onPressed: () async {
                                await widget.brain.api.clearApiKey();
                                if (sheetContext.mounted) {
                                  setSheetState(() {});
                                }
                                if (mounted) setState(() {});
                              },
                              child: const Text('Удалить'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      groqKey.dispose();
      deepSeekKey.dispose();
    }
  }

  Future<void> _toggleMic() async {
    if (widget.voiceInput.listening) {
      await widget.voiceInput.stop();
      return;
    }
    await widget.speech.stop();
    await widget.voiceInput.start(onFinal: (text) {
      input.text = text;
      if (dialogMode) _send(textOverride: text);
    });
  }

  Future<void> _send({String? textOverride}) async {
    final text = (textOverride ?? input.text).trim();
    if (text.isEmpty || busy) return;

    await widget.speech.stop();
    if (!await _ensureBrainReady()) return;

    setState(() {
      busy = true;
      messages.add(_Message(user: true, text: text));
      input.clear();
      status = 'Dream Pulse думает…';
    });

    try {
      final answerBuffer = StringBuffer();
      var assistantIndex = -1;
      var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

      await for (final chunk in widget.core.askStream(
        text,
        thinking: thinking && _thinkAvailable,
        allowWeb: forceWeb,
      )) {
        if (chunk.isEmpty) continue;
        answerBuffer.write(chunk);
        if (!mounted) return;

        final now = DateTime.now();
        final shouldPaint =
            now.difference(lastPaint).inMilliseconds >= 45 ||
            chunk.endsWith('.') ||
            chunk.endsWith('!') ||
            chunk.endsWith('?') ||
            chunk.contains('\n');
        if (!shouldPaint) continue;

        final partial = answerBuffer.toString();
        setState(() {
          if (assistantIndex < 0) {
            assistantIndex = messages.length;
            messages.add(_Message(user: false, text: partial));
          } else {
            messages[assistantIndex] =
                _Message(user: false, text: partial);
          }
          status = '${widget.brain.lastBackend} · ${widget.core.status}';
        });
        lastPaint = now;
      }

      final answer = answerBuffer.toString().trim();
      if (!mounted) return;

      if (answer.isNotEmpty) {
        setState(() {
          if (assistantIndex < 0) {
            messages.add(_Message(user: false, text: answer));
          } else {
            messages[assistantIndex] =
                _Message(user: false, text: answer);
          }
          status = '${widget.brain.lastBackend} · готов';
        });

        if (autoSpeak) {
          final speechFuture = widget.speech.speak(
            answer,
            expression: widget.core.personality.voiceExpression,
          );
          if (dialogMode) {
            speechFuture.then((_) async {
              if (!mounted || busy || !dialogMode) return;
              await Future<void>.delayed(
                const Duration(milliseconds: 250),
              );
              if (!mounted || busy || !dialogMode) return;
              await widget.voiceInput.start(onFinal: (spoken) {
                input.text = spoken;
                _send(textOverride: spoken);
              });
            }).catchError((_) {});
          } else {
            speechFuture.catchError((_) {});
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      final clean = _publicError(e);
      setState(() {
        messages.add(
          _Message(
            user: false,
            text: 'Не получилось ответить: $clean',
          ),
        );
        status = 'Ошибка';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _publicError(Object error) {
    final raw = error.toString();

    if (raw.contains('GROQ_LIMIT')) {
      return 'бесплатный лимит Groq временно исчерпан. AUTO переключится на LOCAL, если локальная модель загружена.';
    }
    if (raw.contains('GROQ_AUTH') || raw.contains('401')) {
      return 'Groq отклонил API key. Проверь ключ в настройках мозга.';
    }
    if (raw.contains('Contains invalid characters')) {
      return 'ошибка кодировки сетевого запроса.';
    }
    if (raw.contains('SocketException') ||
        raw.contains('Connection') ||
        raw.contains('timed out') ||
        raw.contains('TimeoutException')) {
      return 'нет соединения с онлайн-моделью.';
    }

    var clean = raw
        .replaceFirst('Bad state: ', '')
        .replaceFirst('StateError: ', '')
        .replaceFirst('Exception: ', '');

    // Never expose prompts, JSON payloads, keys or internal Core instructions.
    if (clean.contains('{"model"') ||
        clean.contains('"messages"') ||
        clean.contains('DREAM PULSE PERSONA') ||
        clean.contains('USER TASK:')) {
      return 'онлайн-модель не приняла запрос.';
    }

    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length > 180) {
      clean = '${clean.substring(0, 180)}…';
    }
    return clean.isEmpty ? 'неизвестная ошибка' : clean;
  }

  void _setMode(BrainMode mode) {
    setState(() {
      widget.brain.mode = mode;
      if (mode == BrainMode.local) thinking = false;
    });
  }

  @override
  void dispose() {
    widget.localBrain.removeListener(_syncStatus);
    widget.brain.groq.removeListener(_syncStatus);
    widget.brain.api.removeListener(_syncStatus);
    widget.voiceInput.removeListener(_syncVoice);
    widget.installer.removeListener(_syncStatus);
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.localBrain,
        widget.brain.groq,
        widget.brain.api,
        widget.brain,
        widget.installer,
        widget.voiceInput,
        widget.core,
      ]),
      builder: (context, _) => SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 10, 2),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _showBrainSheet,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_modeLabel · $_brainStatus',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE7E7EA),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'AUTO: Groq Free → LOCAL · без платного fallback',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF777B85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<BrainMode>(
                    tooltip: 'Выбрать мозг',
                    initialValue: widget.brain.mode,
                    color: const Color(0xFF15161B),
                    onSelected: _setMode,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: BrainMode.auto,
                        child: Text('AUTO · FREE → LOCAL'),
                      ),
                      PopupMenuItem(
                        value: BrainMode.groq,
                        child: Text('GROQ FREE · 120B'),
                      ),
                      PopupMenuItem(
                        value: BrainMode.local,
                        child: Text('LOCAL · DeepSeek 1.5B'),
                      ),
                      PopupMenuItem(
                        value: BrainMode.deepseek,
                        child: Text('DEEPSEEK API · платный'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFFA8ABB4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Wrap(
                spacing: 18,
                runSpacing: 4,
                children: [
                  _TextToggle(
                    label: autoSpeak ? 'Голос · on' : 'Голос',
                    active: autoSpeak,
                    onTap: () => setState(() => autoSpeak = !autoSpeak),
                  ),
                  _TextToggle(
                    label: dialogMode ? 'Диалог · on' : 'Диалог',
                    active: dialogMode,
                    onTap: () => setState(() => dialogMode = !dialogMode),
                  ),
                  _TextToggle(
                    label: _thinkAvailable
                        ? (thinking ? 'Think · on' : 'Think')
                        : 'Think · online',
                    active: thinking && _thinkAvailable,
                    enabled: _thinkAvailable,
                    onTap: () {
                      if (!_thinkAvailable) {
                        setState(
                          () => status =
                              'Think доступен через Groq Free или DeepSeek API',
                        );
                        return;
                      }
                      setState(() => thinking = !thinking);
                    },
                  ),
                  _TextToggle(
                    label: forceWeb ? 'Web · всегда' : 'Web · auto',
                    active: true,
                    onTap: () => setState(() => forceWeb = !forceWeb),
                  ),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? const _EmptyChat()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      itemCount: messages.length,
                      itemBuilder: (_, i) => _PlainMessage(messages[i]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.voiceInput.listening
                      ? '🎙 ${widget.voiceInput.partial.isEmpty ? 'слушаю…' : widget.voiceInput.partial}'
                      : status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF737782),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: busy ? null : _toggleMic,
                    icon: Icon(
                      widget.voiceInput.listening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                    ),
                    color: const Color(0xFF9A9EA8),
                  ),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF14151A),
                        borderRadius: BorderRadius.all(
                          Radius.circular(20),
                        ),
                      ),
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Напиши сообщение…',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: busy ? widget.brain.stop : _send,
                    icon: Icon(
                      busy
                          ? Icons.stop_circle_outlined
                          : Icons.arrow_upward_rounded,
                    ),
                    color: const Color(0xFFFF7A2F),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message {
  const _Message({required this.user, required this.text});

  final bool user;
  final String text;
}

class _PlainMessage extends StatelessWidget {
  const _PlainMessage(this.message);

  final _Message message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.user ? 'Вы' : 'Dream Pulse',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: message.user
                  ? const Color(0xFF8D919B)
                  : const Color(0xFFFF7A2F),
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            message.text,
            style: TextStyle(
              fontSize: 15,
              height: 1.48,
              color: message.user
                  ? const Color(0xFFD6D7DB)
                  : const Color(0xFFF0F0F2),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextToggle extends StatelessWidget {
  const _TextToggle({
    required this.label,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? const Color(0xFF4E5159)
        : active
            ? const Color(0xFFFF7A2F)
            : const Color(0xFF858994);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Dream Pulse',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Groq Free 120B  →  LOCAL DeepSeek 1.5B\nWeb Worker и память остаются в Dream Pulse.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xFF858994),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
