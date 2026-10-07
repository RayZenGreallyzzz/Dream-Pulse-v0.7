import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DeepSeekModelInstaller extends ChangeNotifier {
  static const fileName = 'DeepSeek-R1-1.5B-Q4_K_M.gguf';
  static const _legacyDeepSeekName =
      'DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf';
  static const _oldQwenName = 'Qwen3-0.6B-Q4_0.gguf';

  static const expectedSha256 =
      '1741e5b2d062b07acf048bf0d2c514dadf2a48f94e2b4aa0cfe069af3838ee2f';
  static const downloadUrl =
      'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf?download=true';
  static const minExpectedBytes = 1050000000;
  static const maxExpectedBytes = 1200000000;

  HttpClient? _client;
  bool downloading = false;
  bool verifying = false;
  bool installed = false;
  double progress = 0;
  String status = 'Проверяю локальный DeepSeek…';
  String? modelPath;

  Future<Directory> _modelDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> targetPath() async {
    final dir = await _modelDir();
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  Future<void> _cleanupOldQwenAndMigrate() async {
    final dir = await _modelDir();

    for (final name in [_oldQwenName, '$_oldQwenName.part']) {
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    final target = File(await targetPath());
    if (await target.exists()) return;

    final legacy = File(
      '${dir.path}${Platform.pathSeparator}$_legacyDeepSeekName',
    );
    if (await legacy.exists()) {
      try {
        await legacy.rename(target.path);
      } catch (_) {}
    }
  }

  Future<String?> installedPathIfValid({bool verifyHash = false}) async {
    await _cleanupOldQwenAndMigrate();
    final path = await targetPath();
    final file = File(path);
    if (!await file.exists()) return null;

    final length = await file.length();
    if (length < minExpectedBytes || length > maxExpectedBytes) return null;

    if (verifyHash) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != expectedSha256) return null;
    }
    return path;
  }

  Future<void> refresh() async {
    final found = await installedPathIfValid();
    modelPath = found;
    installed = found != null;
    progress = installed ? 1 : 0;
    status = installed
        ? 'DeepSeek 1.5B готов'
        : 'Локальный DeepSeek 1.5B не установлен';
    notifyListeners();
  }

  Future<String?> prepare() async {
    final found = await installedPathIfValid();
    modelPath = found;
    installed = found != null;
    progress = installed ? 1 : 0;
    status = installed
        ? 'DeepSeek 1.5B готов'
        : 'Локальный DeepSeek 1.5B не установлен';
    notifyListeners();
    return found;
  }

  Future<String> install() async {
    if (downloading || verifying) {
      throw StateError('Загрузка уже выполняется');
    }

    await _cleanupOldQwenAndMigrate();
    final target = await targetPath();
    final existing = File(target);

    if (await existing.exists() &&
        await existing.length() >= minExpectedBytes) {
      final digest = await sha256.bind(existing.openRead()).first;
      if (digest.toString() == expectedSha256) {
        modelPath = target;
        installed = true;
        progress = 1;
        status = 'DeepSeek 1.5B готов';
        notifyListeners();
        return target;
      }
    }

    final part = File('$target.part');
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > maxExpectedBytes) {
      await part.delete();
      offset = 0;
    }

    downloading = true;
    verifying = false;
    installed = false;
    progress = 0;
    status = offset > 0
        ? 'Продолжаю загрузку DeepSeek 1.5B…'
        : 'Загружаю DeepSeek 1.5B…';
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    _client = client;
    IOSink? sink;

    try {
      final request = await client.getUrl(Uri.parse(downloadUrl));
      request
        ..followRedirects = true
        ..maxRedirects = 10;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DreamPulse/0.10 Android',
      );
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'HTTP ${response.statusCode} при загрузке DeepSeek',
        );
      }

      if (offset > 0 && response.statusCode == HttpStatus.ok) {
        await part.delete();
        offset = 0;
      }

      final total = response.contentLength > 0
          ? offset + response.contentLength
          : maxExpectedBytes;
      var received = offset;

      sink = part.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        progress = (received / total).clamp(0.0, 0.995);
        status =
            'DeepSeek 1.5B · ${(progress * 100).floor()}%';
        notifyListeners();
      }

      await sink.flush();
      await sink.close();
      sink = null;

      final length = await part.length();
      if (length < minExpectedBytes || length > maxExpectedBytes) {
        throw StateError('Файл DeepSeek загружен не полностью: $length байт');
      }

      downloading = false;
      verifying = true;
      progress = 0.997;
      status = 'Проверяю DeepSeek 1.5B…';
      notifyListeners();

      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != expectedSha256) {
        await part.delete();
        throw StateError('SHA-256 DeepSeek 1.5B не совпал');
      }

      if (await existing.exists()) await existing.delete();
      await part.rename(target);

      modelPath = target;
      installed = true;
      verifying = false;
      progress = 1;
      status = 'DeepSeek 1.5B готов';
      notifyListeners();
      return target;
    } catch (e) {
      downloading = false;
      verifying = false;
      status = 'Ошибка загрузки DeepSeek: $e';
      notifyListeners();
      rethrow;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
      _client = null;
    }
  }

  Future<void> cancel() async {
    _client?.close(force: true);
    _client = null;
    downloading = false;
    verifying = false;
    status = 'Загрузка остановлена';
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.close(force: true);
    super.dispose();
  }
}
