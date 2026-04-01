import 'package:shared_preferences/shared_preferences.dart';

/// 设置服务 - 管理应用设置持久化
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  SharedPreferences? _prefs;

  // 键名常量
  static const String _kKimiApiKey = 'kimi_api_key';
  static const String _kAutoRecording = 'auto_recording_enabled';
  static const String _kRecordingQuality = 'recording_quality';

  /// 初始化
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 确保已初始化
  Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await initialize();
    }
  }

  // ===== Kimi API Key =====

  /// 获取Kimi API Key
  Future<String?> getKimiApiKey() async {
    await _ensureInitialized();
    return _prefs?.getString(_kKimiApiKey);
  }

  /// 设置Kimi API Key
  Future<bool> setKimiApiKey(String apiKey) async {
    await _ensureInitialized();
    return await _prefs?.setString(_kKimiApiKey, apiKey) ?? false;
  }

  /// 清除Kimi API Key
  Future<bool> clearKimiApiKey() async {
    await _ensureInitialized();
    return await _prefs?.remove(_kKimiApiKey) ?? false;
  }

  // ===== 自动录音 =====

  /// 获取自动录音状态
  Future<bool> getAutoRecordingEnabled() async {
    await _ensureInitialized();
    return _prefs?.getBool(_kAutoRecording) ?? false;
  }

  /// 设置自动录音状态
  Future<bool> setAutoRecordingEnabled(bool enabled) async {
    await _ensureInitialized();
    return await _prefs?.setBool(_kAutoRecording, enabled) ?? false;
  }

  // ===== 录音质量 =====

  /// 获取录音质量
  Future<String> getRecordingQuality() async {
    await _ensureInitialized();
    return _prefs?.getString(_kRecordingQuality) ?? '标准';
  }

  /// 设置录音质量
  Future<bool> setRecordingQuality(String quality) async {
    await _ensureInitialized();
    return await _prefs?.setString(_kRecordingQuality, quality) ?? false;
  }
}
