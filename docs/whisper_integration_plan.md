# 本地Whisper集成计划

## 目标
集成 whisper.cpp 本地语音转写，实现完全离线的语音转文字功能。

## 系统配置要求
- **内存**: 12GB (用户配置) ✅ 足够运行small模型
- **存储**: 1TB (用户配置) ✅ 充足
- **推荐模型**: ggml-small.bin (244MB)

## 集成步骤

### Step 1: 添加依赖

在 `pubspec.yaml` 中添加：
```yaml
dependencies:
  # 本地Whisper集成（待选择方案）
  # 方案A: speech_to_text (系统识别，快速)
  speech_to_text: ^6.5.0

  # 方案B: whisper_flutter (第三方封装)
  # whisper_flutter: ^latest

  # 方案C: 原生集成 whisper.cpp (推荐最终方案)
  # 需要手动集成，见下方说明
```

### Step 2: 下载模型文件

```bash
# 创建模型目录
mkdir -p assets/models

# 下载small模型
curl -L -o assets/models/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin

# 在pubspec.yaml中声明
flutter:
  assets:
    - assets/models/ggml-small.bin
```

### Step 3: 实现Whisper服务

创建 `lib/services/whisper_local_service.dart`：

```dart
/// 本地Whisper转写服务
///
/// 封装 whisper.cpp 的Dart调用
class WhisperLocalService {
  static final WhisperLocalService _instance = WhisperLocalService._internal();
  factory WhisperLocalService() => _instance;
  WhisperLocalService._internal();

  bool _isInitialized = false;
  String? _modelPath;

  /// 初始化Whisper模型
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    // TODO: 加载模型文件到内存
    // 1. 从assets复制到私有目录
    // 2. 初始化 whisper.cpp 上下文
    // 3. 设置参数（语言、线程数等）

    _isInitialized = true;
    return true;
  }

  /// 转写音频文件
  Future<String?> transcribe(String audioPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    // TODO: 调用 whisper.cpp 进行转写
    // 返回转写文本

    return null;
  }
}
```

### Step 4: 修改转写服务

修改 `transcription_service.dart`：

```dart
class TranscriptionService {
  final _whisperService = WhisperLocalService();

  Future<TranscriptionResult?> transcribe(String audioPath, ...) async {
    // 1. 尝试本地Whisper转写
    final whisperResult = await _transcribeWithWhisper(audioPath);
    if (whisperResult != null) {
      // 2. 使用Kimi分析转写文本（提取待办等）
      return await _enrichWithKimi(whisperResult);
    }

    // 3. 降级到关键词提取
    return await _transcribeWithLocal(audioPath, recordingMeta: recordingMeta);
  }
}
```

## 技术方案选择

### 方案A: speech_to_text (最快，1小时)
- 使用系统自带的语音识别
- 优点：无需模型文件，5分钟集成
- 缺点：依赖设备，隐私问题，需要网络（部分设备）

### 方案B: whisper_flutter (较快，半天)
- 使用社区封装的Flutter插件
- 优点：纯Dart实现，容易集成
- 缺点：可能不够稳定，控制粒度低

### 方案C: 原生集成 whisper.cpp (推荐，1-2天)
- 直接集成C++库
- 优点：性能最好，完全控制
- 缺点：需要写Platform Channel，复杂

## 推荐实现路径

**阶段1** (今天): 使用 `speech_to_text` 快速验证
**阶段2** (本周): 集成 `whisper.cpp` 原生库

## 资源链接

- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- 模型下载: https://huggingface.co/ggerganov/whisper.cpp
- Flutter Platform Channel: https://docs.flutter.dev/platform-integration/platform-channels

## 注意事项

1. **模型文件较大** (244MB)，考虑首次启动时下载而非打包
2. **首次加载较慢**，需要预加载模型到内存
3. **多语言支持**，small模型支持中文但准确率不如英文
4. **后台处理**，长录音需要在Isolate中处理避免UI卡顿
