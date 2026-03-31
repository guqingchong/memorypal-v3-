# Whisper.cpp 原生集成指南

## 概述
本文档指导如何将 whisper.cpp 本地语音转写库原生集成到 Flutter 应用中。

## 系统要求
- **Flutter**: 3.22+
- **Android**: API 24+ (Android 7.0+)
- **iOS**: 12.0+
- **内存**: 至少 2GB 可用内存 (推荐 12GB+)
- **存储**: 模型文件 244MB

## 集成步骤

### Step 1: 下载 Whisper.cpp

```bash
cd D:/Claudeworkplace/memorypal_v3

# 克隆 whisper.cpp 仓库
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# 下载 small 模型 (244MB)
# Windows PowerShell:
Invoke-WebRequest -Uri "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin" -OutFile "ggml-small.bin"

# 或者使用 curl:
curl -L -o ggml-small.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

### Step 2: Android 集成

#### 2.1 复制原生代码
已创建的文件：
- `android/app/src/main/cpp/CMakeLists.txt`
- `android/app/src/main/cpp/whisper/whisper_jni.cpp`
- `android/app/src/main/java/com/example/memorypal/whisper/WhisperPlugin.java`

#### 2.2 修改 build.gradle
已添加 CMake 支持，确保以下配置存在：

```gradle
android {
    externalNativeBuild {
        cmake {
            path "src/main/cpp/CMakeLists.txt"
            version "3.10.2"
        }
    }
}
```

#### 2.3 链接 whisper.cpp 库

修改 `CMakeLists.txt`，添加 whisper 库：

```cmake
# 添加 whisper.cpp 子目录
add_subdirectory(
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../whisper.cpp
    ${CMAKE_CURRENT_BINARY_DIR}/whisper
)

# 链接 whisper 库
target_link_libraries(
    whisper
    whisper  # whisper.cpp 库
    android
    log
)
```

#### 2.4 完成 JNI 实现

修改 `whisper_jni.cpp`，实现真正的转写逻辑：

```cpp
#include "whisper.h"

// ... 在 nativeInit 中:
whisper_context* ctx = whisper_init_from_file(model_path);
return (jlong)ctx;

// ... 在 nativeTranscribe 中:
// 1. 加载音频为 16kHz float 数组
// 2. 调用 whisper_full()
// 3. 提取文本结果
```

### Step 3: iOS 集成

#### 3.1 创建 iOS 插件

创建 `ios/Runner/WhisperPlugin.swift`：

```swift
import Flutter
import UIKit

public class WhisperPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.memorypal/whisper"
    var whisperContext: OpaquePointer? = nil

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = WhisperPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            handleInitialize(call, result: result)
        case "transcribe":
            handleTranscribe(call, result: result)
        case "release":
            handleRelease(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelPath = args["modelPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: nil, details: nil))
            return
        }

        // TODO: 加载 whisper 模型
        // whisperContext = whisper_init_from_file(modelPath)

        result(true)
    }

    private func handleTranscribe(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let audioPath = args["audioPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: nil, details: nil))
            return
        }

        // TODO: 实现转写逻辑
        // 1. 加载音频
        // 2. 调用 whisper_full()
        // 3. 返回文本

        result("[iOS Whisper转写待实现]")
    }

    private func handleRelease(result: @escaping FlutterResult) {
        if let ctx = whisperContext {
            whisper_free(ctx)
            whisperContext = nil
        }
        result(true)
    }
}
```

#### 3.2 配置 Podfile

在 `ios/Podfile` 中添加：

```ruby
# 添加 whisper.cpp 依赖
# 需要创建本地 podspec 或使用 Swift Package Manager
```

#### 3.3 注册插件

在 `ios/Runner/AppDelegate.swift` 中注册：

```swift
import Flutter
import UIKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        WhisperPlugin.register(with: self.registrar(forPlugin: "WhisperPlugin")!)
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

### Step 4: 集成模型文件

#### 4.1 方式一：打包到 APK/IPA（不推荐，文件大）

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/models/ggml-small.bin
```

#### 4.2 方式二：首次启动下载（推荐）

在 `WhisperLocalService` 中已实现下载逻辑：

```dart
// 应用启动时检查并下载
if (!await isModelDownloaded()) {
  await downloadModel();
}
```

### Step 5: 测试验证

```dart
// 在应用启动时测试
void testWhisper() async {
  final whisper = WhisperLocalService();

  // 初始化
  final initialized = await whisper.initialize();
  print('Whisper初始化: $initialized');

  // 转写测试
  final result = await whisper.transcribe('/path/to/test.wav');
  print('转写结果: $result');
}
```

## 常见问题

### Q: 构建失败，找不到 whisper.h
A: 确保 whisper.cpp 仓库已克隆到项目根目录，并且 CMakeLists.txt 中的路径正确。

### Q: APK 体积过大
A: 使用动态下载模型文件，不要打包到 assets。或者只支持 arm64-v8a 架构。

### Q: 转写速度慢
A:
- 使用量化模型 (q5_1) 减少计算量
- 在后台 isolate 中执行转写
- 降低音频采样率或分段处理

### Q: 中文识别准确率低
A:
- 确保使用中文模型或 multilingual 模型
- 音频质量要好（16kHz, 清晰语音）
- 考虑使用 medium 或 large 模型

## 性能优化

### 1. 模型量化
使用量化后的模型减少内存占用：
- `ggml-small-q5_1.bin` (约 180MB)
- `ggml-small-q8_0.bin` (约 220MB)

### 2. 后台处理
在 isolate 中执行转写避免阻塞 UI：

```dart
import 'package:flutter/foundation.dart';

Future<String> transcribeInIsolate(String audioPath) async {
  return await compute(_transcribeWorker, audioPath);
}

String _transcribeWorker(String audioPath) {
  // 在 isolate 中执行转写
  final whisper = WhisperLocalService();
  return whisper.transcribe(audioPath);
}
```

### 3. 音频预处理
- 统一转换为 16kHz 采样率
- 单声道（mono）
- 16-bit PCM 格式

## 参考资源

- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- Flutter Platform Channels: https://docs.flutter.dev/platform-integration/platform-channels
- Android NDK: https://developer.android.com/ndk/guides

## 下一步

1. 下载 whisper.cpp 和模型文件
2. 完成 JNI/Swift 实现
3. 测试转写功能
4. 优化性能和用户体验
