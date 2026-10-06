import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class QwenModelInstaller extends ChangeNotifier {
  // SMART brain (preferred)
  static const fileName = 'DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf';
  static const expectedSha256 =
      '1741e5b2d062b07acf048bf0d2c514dadf2a48f94e2b4aa0cfe069af3838ee2f';
  static const downloadUrl =
      'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf?download=true';
  static const minExpectedBytes = 1050000000;
  static const maxExpectedBytes = 1200000000;

  // FAST brain (kept as fallback if already installed)
  static const fastFileName = 'Qwen3-0.6B-Q4_0.gguf';
  static const fastExpectedSha256 =
      'da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4';
  static const fastExpectedBytes = 428970080;

  HttpClient? _client;
  bool downloading = false;
  bool verifying = false;
  bool installed = false;
  double progress = 0;
  String status = 'CHECKING LOCAL CORE...';
  String? modelPath;

  bool get smartActive => modelPath?.contains('DeepSeek-R1') ?? false;
  String get activeLabel => smartActive ? 'DeepSeek R1 1.5B SMART' : 'Qwen 0.6B FAST';

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

  Future<String> _fastPath() async {
    final dir = await _modelDir();
    return '${dir.path}${Platform.pathSeparator}$fastFileName';
  }

  Future<String?> installedPathIfValid({bool verifyHash = false}) async {
    final smartPath = await targetPath();
    final smart = File(smartPath);
    if (await smart.exists()) {
      final length = await smart.length();
      if (length >= minExpectedBytes && length <= maxExpectedBytes) {
        if (!verifyHash ||
            (await sha256.bind(smart.openRead()).first).toString() == expectedSha256) {
          return smartPath;
        }
      }
    }

    final fastPath = await _fastPath();
    final fast = File(fastPath);
    if (await fast.exists() && await fast.length() == fastExpectedBytes) {
      if (!verifyHash ||
          (await sha256.bind(fast.openRead()).first).toString() == fastExpectedSha256) {
        return fastPath;
      }
    }
    return null;
  }

  Future<void> refresh() async {
    final found = await installedPathIfValid();
    modelPath = found;
    installed = found != null;
    progress = installed ? 1 : 0;
    status = installed
        ? 'LOCAL BRAIN READY · $activeLabel'
        : 'SMART BRAIN NOT INSTALLED · DeepSeek 1.5B';
    notifyListeners();
  }

  Future<String?> prepare() async {
    final existing = await installedPathIfValid();
    if (existing == null) {
      installed = false;
      modelPath = null;
      status = 'SMART BRAIN NOT INSTALLED · DeepSeek 1.5B';
      notifyListeners();
      return null;
    }
    modelPath = existing;
    installed = true;
    progress = 1;
    status = 'LOCAL BRAIN READY · $activeLabel';
    notifyListeners();
    return existing;
  }

  Future<String> install() async {
    if (downloading || verifying) {
      throw StateError('Установка уже выполняется');
    }

    final smartPath = await targetPath();
    final existingSmart = File(smartPath);
    if (await existingSmart.exists() &&
        await existingSmart.length() >= minExpectedBytes) {
      final digest = await sha256.bind(existingSmart.openRead()).first;
      if (digest.toString() == expectedSha256) {
        modelPath = smartPath;
        installed = true;
        progress = 1;
        status = 'LOCAL BRAIN READY · DeepSeek R1 1.5B SMART';
        notifyListeners();
        return smartPath;
      }
    }

    final part = File('$smartPath.part');
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > maxExpectedBytes) {
      await part.delete();
      offset = 0;
    }

    downloading = true;
    installed = false;
    progress = 0;
    status = offset > 0
        ? 'RESUMING DEEPSEEK 1.5B...'
        : 'CONNECTING TO DEEPSEEK 1.5B...';
    notifyListeners();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    _client = client;
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(downloadUrl));
      request
        ..followRedirects = true
        ..maxRedirects = 10;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DreamPulse/0.9.7 Android',
      );
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException('HTTP ${response.statusCode} при загрузке DeepSeek');
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
        status = 'DOWNLOADING DEEPSEEK 1.5B ${(progress * 100).floor()}%';
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final length = await part.length();
      if (length < minExpectedBytes) {
        throw StateError('Загрузка DeepSeek не завершена: $length байт');
      }
      if (length > maxExpectedBytes) {
        await part.delete();
        throw StateError('Файл DeepSeek имеет неверный размер: $length байт');
      }

      downloading = false;
      verifying = true;
      progress = 0.997;
      status = 'VERIFYING DEEPSEEK 1.5B...';
      notifyListeners();

      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != expectedSha256) {
        await part.delete();
        throw StateError('SHA-256 DeepSeek 1.5B не совпал');
      }

      if (await existingSmart.exists()) await existingSmart.delete();
      await part.rename(smartPath);

      modelPath = smartPath;
      installed = true;
      progress = 1;
      status = 'LOCAL BRAIN READY · DeepSeek R1 1.5B SMART';
      return smartPath;
    } catch (e) {
      // Keep a valid partial file so the next attempt can resume.
      // Bad-size/hash files are deleted at validation above.
      // Keep the old FAST brain usable after a failed SMART download.
      final fallback = await installedPathIfValid();
      modelPath = fallback;
      installed = fallback != null;
      progress = installed ? 1 : 0;
      status = installed
          ? 'SMART INSTALL ERROR · FAST AVAILABLE'
          : 'INSTALL ERROR · $e';
      rethrow;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
      _client = null;
      downloading = false;
      verifying = false;
      notifyListeners();
    }
  }

  void cancel() {
    _client?.close(force: true);
    status = 'DOWNLOAD PAUSED';
    notifyListeners();
  }
}
