import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whisper平台通道 - 调用原生代码
///
/// 封装与Android/iOS原生层的通信
class WhisperPlatformChannel {
  static const MethodChannel _channel =
      MethodChannel('com.memorypal/whisper');

  static WhisperPlatformChannel? _instance;
  static WhisperPlatformChannel get instance =>
      _instance ??= WhisperPlatformChannel._();
  WhisperPlatformChannel._();

  /// 初始化Whisper模型
  ///
  /// [modelPath] 模型文件本地路径
  Future<bool> initialize(String modelPath) async {
    try {
      final result = await _channel.invokeMethod<bool>('initialize', {
        'modelPath': modelPath,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Whisper初始化错误: ${e.message}');
      return false;
    }
  }

  /// 转写音频文件
  ///
  /// [audioPath] 音频文件路径
  /// [language] 语言代码 (默认 'zh')
  Future<String?> transcribe(String audioPath, {String language = 'zh'}) async {
    try {
      final result = await _channel.invokeMethod<String>('transcribe', {
        'audioPath': audioPath,
        'language': language,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Whisper转写错误: ${e.message}');
      return null;
    }
  }

  /// 释放资源
  Future<bool> release() async {
    try {
      final result = await _channel.invokeMethod<bool>('release');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 检查模型是否已加载
  Future<bool> isModelLoaded() async {
    try {
      final result = await _channel.invokeMethod<bool>('isModelLoaded');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
