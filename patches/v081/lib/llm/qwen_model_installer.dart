import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class QwenModelInstaller extends ChangeNotifier {
  static const fileName = 'Qwen3-1.7B-Q4_K_M.gguf';
  static const expectedSha256 =
      'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5';
  static const downloadUrl =
      'https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/daeb8e2d528a760970442092f6bf1e55c3b659eb/Qwen3-1.7B-Q4_K_M.gguf';
  static const expectedBytes = 1280000000;

  HttpClient? _client;
  bool downloading = false;
  bool verifying = false;
  bool installed = false;
  double progress = 0;
  String status = 'CHECKING LOCAL CORE...';
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

  Future<String?> installedPathIfValid({bool verifyHash = false}) async {
    final path = await targetPath();
    final file = File(path);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length < 1000000000) return null;
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
        ? 'LOCAL BRAIN READY · Qwen3 1.7B Q4'
        : 'LOCAL BRAIN NOT INSTALLED';
    notifyListeners();
  }

  Future<String> install() async {
    if (downloading || verifying) {
      throw StateError('Установка уже выполняется');
    }
    final existing = await installedPathIfValid();
    if (existing != null) {
      modelPath = existing;
      installed = true;
      progress = 1;
      status = 'LOCAL BRAIN READY · Qwen3 1.7B Q4';
      notifyListeners();
      return existing;
    }

    final path = await targetPath();
    final part = File('$path.part');
    if (await part.exists()) await part.delete();

    downloading = true;
    installed = false;
    progress = 0;
    status = 'CONNECTING TO QWEN CORE...';
    notifyListeners();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    _client = client;
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(downloadUrl));
      request
        ..followRedirects = true
        ..maxRedirects = 10;
      request.headers.set(HttpHeaders.userAgentHeader, 'DreamPulse/0.8.1');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode} при загрузке Qwen');
      }

      final total = response.contentLength > 0
          ? response.contentLength
          : expectedBytes;
      var received = 0;
      sink = part.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        progress = (received / total).clamp(0.0, 0.995);
        status = 'DOWNLOADING QWEN ${(progress * 100).floor()}%';
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final length = await part.length();
      if (length < 1000000000) {
        throw StateError('Файл модели неполный: $length байт');
      }

      downloading = false;
      verifying = true;
      progress = 0.997;
      status = 'VERIFYING LOCAL BRAIN...';
      notifyListeners();
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != expectedSha256) {
        throw StateError('SHA-256 модели не совпал');
      }

      final target = File(path);
      if (await target.exists()) await target.delete();
      await part.rename(path);
      modelPath = path;
      installed = true;
      progress = 1;
      status = 'LOCAL BRAIN READY · Qwen3 1.7B Q4';
      return path;
    } catch (e) {
      if (await part.exists()) await part.delete();
      installed = false;
      modelPath = null;
      progress = 0;
      status = 'INSTALL ERROR · $e';
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
    status = 'DOWNLOAD CANCELLED';
    notifyListeners();
  }
}
