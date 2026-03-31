# Whisper.cpp 集成设置脚本

## 快速开始

运行以下命令完成设置（在 Windows PowerShell 中）：

```powershell
# 1. 进入项目目录
cd D:\Claudeworkplace\memorypal_v3

# 2. 克隆 whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git

# 3. 下载 small 模型 (244MB)
cd whisper.cpp

# 使用 PowerShell 下载
Invoke-WebRequest -Uri "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin" `
    -OutFile "ggml-small.bin"

# 或者使用浏览器下载后复制到该目录
# https://huggingface.co/ggerganov/whisper.cpp/tree/main

# 4. 验证模型文件
if (Test-Path "ggml-small.bin") {
    $size = (Get-Item "ggml-small.bin").Length / 1MB
    Write-Host "模型下载成功: $([math]::Round($size, 1)) MB"
} else {
    Write-Host "模型下载失败"
}

# 5. 返回项目根目录
cd ..
```

## 下一步：完成原生实现

### Android 端

1. **修改 CMakeLists.txt** 链接 whisper 库：

```cmake
# 在 android/app/src/main/cpp/CMakeLists.txt 中添加：

# 添加 whisper.cpp 子目录
add_subdirectory(
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../whisper.cpp
    ${CMAKE_CURRENT_BINARY_DIR}/whisper
)

# 链接 whisper 库
target_link_libraries(
    whisper
    whisper
    android
    log
)

# 包含 whisper 头文件
target_include_directories(
    whisper
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../whisper.cpp
)
```

2. **实现 JNI 函数** - 修改 `whisper_jni.cpp`：

```cpp
#include "whisper.h"

JNIEXPORT jlong JNICALL
Java_com_example_memorypal_whisper_WhisperPlugin_nativeInit(...) {
    const char *model_path = env->GetStringUTFChars(modelPath, nullptr);
    whisper_context* ctx = whisper_init_from_file(model_path);
    env->ReleaseStringUTFChars(modelPath, model_path);
    return (jlong)ctx;
}

JNIEXPORT jstring JNICALL
Java_com_example_memorypal_whisper_WhisperPlugin_nativeTranscribe(...) {
    // 实现转写逻辑
    // 参考: whisper.cpp/examples/main/main.cpp
}
```

3. **构建 APK** 测试：

```bash
flutter build apk --release
```

### iOS 端

1. **添加 Swift 实现** - 创建 `ios/Runner/WhisperPlugin.swift`

2. **链接 whisper 库** - 使用 CocoaPods 或 Swift Package Manager

3. **注册插件** - 在 `AppDelegate.swift` 中注册

## 参考实现

完整的 whisper.cpp 调用示例：

```cpp
// 1. 初始化
whisper_context* ctx = whisper_init_from_file("ggml-small.bin");

// 2. 加载音频 (需要实现音频解码为 16kHz float 数组)
std::vector<float> pcmf32 = load_audio("audio.wav");

// 3. 设置参数
whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
wparams.translate = false;
wparams.language = "zh";
wparams.n_threads = 4;

// 4. 执行转写
whisper_full(ctx, wparams, pcmf32.data(), pcmf32.size());

// 5. 提取结果
int n_segments = whisper_full_n_segments(ctx);
std::string result;
for (int i = 0; i < n_segments; i++) {
    result += whisper_full_get_segment_text(ctx, i);
}

// 6. 释放
whisper_free(ctx);
```

## 音频预处理

转写前需要将音频转换为 whisper 要求的格式：
- 采样率：16000 Hz
- 格式：32-bit float
- 声道：单声道 (mono)

可以使用 FFmpeg 进行转换：

```bash
ffmpeg -i input.mp3 -ar 16000 -ac 1 -f f32le output.raw
```

## 测试

```dart
// 在 main.dart 中测试
void testWhisper() async {
  final whisper = WhisperLocalService();

  // 检查模型
  final downloaded = await whisper.isModelDownloaded();
  print('模型已下载: $downloaded');

  // 初始化
  final initialized = await whisper.initialize();
  print('初始化成功: $initialized');

  // 转写
  final result = await whisper.transcribe('/path/to/audio.wav');
  print('转写结果: $result');
}
```

## 故障排除

### 问题1: CMake 找不到 whisper.cpp
**解决**: 确保 whisper.cpp 在项目根目录，并且 CMakeLists.txt 中的相对路径正确

### 问题2: 模型加载失败
**解决**:
- 检查模型文件是否存在
- 检查文件权限
- 确保模型文件完整（未损坏）

### 问题3: 转写返回空结果
**解决**:
- 检查音频格式是否为 16kHz
- 检查音频文件是否有声音
- 查看原生层日志

### 问题4: APK 体积过大
**解决**:
- 不要打包模型到 assets
- 改为首次启动下载
- 只支持 arm64-v8a 架构

## 完成检查清单

- [ ] whisper.cpp 已克隆
- [ ] ggml-small.bin 已下载 (244MB)
- [ ] Android CMakeLists.txt 已配置
- [ ] Android JNI 实现已完成
- [ ] iOS Swift 实现已完成
- [ ] Dart 代码调用测试通过
- [ ] 转写功能正常工作
