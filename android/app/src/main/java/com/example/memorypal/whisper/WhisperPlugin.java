package com.example.memorypal.whisper;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Whisper本地语音转写插件 - Android实现
 *
 * 封装whisper.cpp的JNI调用
 */
public class WhisperPlugin implements MethodCallHandler {
    private static final String CHANNEL_NAME = "com.memorypal/whisper";
    private static final String TAG = "WhisperPlugin";
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    // 库加载状态（必须在初始化时捕获真实错误）
    private static boolean sLibraryLoaded = false;
    private static String sLibraryLoadError = null;

    // Native方法声明
    static {
        try {
            System.loadLibrary("whisper_jni");
            sLibraryLoaded = true;
            Log.i(TAG, "whisper_jni library loaded successfully");
        } catch (UnsatisfiedLinkError e) {
            sLibraryLoaded = false;
            sLibraryLoadError = e.getMessage();
            Log.e(TAG, "Failed to load whisper_jni library: " + e.getMessage(), e);
        } catch (Exception e) {
            sLibraryLoaded = false;
            sLibraryLoadError = e.getMessage();
            Log.e(TAG, "Unexpected error loading library: " + e.getMessage(), e);
        }
    }

    // 检查库是否加载成功
    private static boolean isLibraryLoaded() {
        return sLibraryLoaded;
    }

    // JNI方法
    private native long nativeInit(String modelPath);
    private native void nativeFree(long context);
    private native String nativeTranscribe(long context, String audioPath, String language);
    private native boolean nativeIsModelLoaded(long context);

    private Long whisperContext = null;

    public static void registerWith(FlutterEngine flutterEngine) {
        final MethodChannel channel = new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            CHANNEL_NAME
        );
        channel.setMethodCallHandler(new WhisperPlugin());
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "initialize":
                handleInitialize(call, result);
                break;
            case "transcribe":
                handleTranscribe(call, result);
                break;
            case "release":
                handleRelease(result);
                break;
            case "isModelLoaded":
                result.success(whisperContext != null);
                break;
            default:
                result.notImplemented();
        }
    }

    private void handleInitialize(MethodCall call, Result result) {
        // 首先检查库是否加载成功
        if (!isLibraryLoaded()) {
            String detail = sLibraryLoadError != null ? sLibraryLoadError : "unknown";
            Log.e(TAG, "Whisper JNI library not loaded. Cannot initialize. Error: " + detail);
            result.error("LIBRARY_NOT_LOADED",
                "Whisper native library not loaded. Please ensure the app was built correctly with CMake. Error: " + detail,
                null);
            return;
        }

        final String modelPath = call.argument("modelPath");

        Log.d(TAG, "Initializing Whisper model, path: " + modelPath);

        if (modelPath == null || modelPath.isEmpty()) {
            Log.e(TAG, "Model path is null or empty");
            result.error("INVALID_ARGUMENT", "Model path is required", null);
            return;
        }

        // 检查模型文件是否存在
        File modelFile = new File(modelPath);
        if (!modelFile.exists()) {
            Log.e(TAG, "Model file not found: " + modelPath);
            result.error("MODEL_NOT_FOUND", "Model file not found: " + modelPath, null);
            return;
        }

        // 检查文件大小（模型文件应该至少有几MB）
        long fileSize = modelFile.length();
        Log.d(TAG, "Model file size: " + fileSize + " bytes");
        if (fileSize < 1024 * 1024) { // 小于1MB可能无效
            Log.w(TAG, "Model file seems too small: " + fileSize + " bytes");
        }

        executor.execute(() -> {
            try {
                // 释放之前的上下文
                if (whisperContext != null) {
                    Log.d(TAG, "Freeing previous whisper context");
                    nativeFree(whisperContext);
                    whisperContext = null;
                }

                // 初始化新的上下文
                Log.d(TAG, "Calling nativeInit...");
                long context = nativeInit(modelPath);

                if (context == 0) {
                    Log.e(TAG, "nativeInit returned 0, initialization failed");
                    mainHandler.post(() -> {
                        result.error("INIT_FAILED", "Failed to initialize Whisper model - nativeInit returned 0", null);
                    });
                    return;
                }

                whisperContext = context;
                Log.i(TAG, "Whisper model initialized successfully, context: " + context);

                mainHandler.post(() -> {
                    result.success(true);
                });

            } catch (UnsatisfiedLinkError e) {
                Log.e(TAG, "Native library not loaded: " + e.getMessage(), e);
                mainHandler.post(() -> {
                    result.error("LIBRARY_NOT_LOADED", "Whisper native library not loaded. Please check build configuration.", e.getMessage());
                });
            } catch (Exception e) {
                Log.e(TAG, "Initialization error: " + e.getMessage(), e);
                mainHandler.post(() -> {
                    result.error("INIT_ERROR", e.getMessage(), Log.getStackTraceString(e));
                });
            }
        });
    }

    private void handleTranscribe(MethodCall call, Result result) {
        // 首先检查库是否加载成功
        if (!isLibraryLoaded()) {
            String detail = sLibraryLoadError != null ? sLibraryLoadError : "unknown";
            Log.e(TAG, "Whisper JNI library not loaded. Cannot transcribe. Error: " + detail);
            result.error("LIBRARY_NOT_LOADED",
                "Whisper native library not loaded. Please ensure the app was built correctly with CMake. Error: " + detail,
                null);
            return;
        }

        final String audioPath = call.argument("audioPath");
        final String language = call.argument("language");

        Log.d(TAG, "Transcribe called, audioPath: " + audioPath + ", language: " + language);

        if (whisperContext == null) {
            Log.e(TAG, "Whisper not initialized");
            result.error("NOT_INITIALIZED", "Whisper not initialized. Please call initialize() first.", null);
            return;
        }

        if (audioPath == null || audioPath.isEmpty()) {
            Log.e(TAG, "Audio path is null or empty");
            result.error("INVALID_ARGUMENT", "Audio path is required", null);
            return;
        }

        // 检查音频文件
        File audioFile = new File(audioPath);
        if (!audioFile.exists()) {
            Log.e(TAG, "Audio file not found: " + audioPath);
            result.error("AUDIO_NOT_FOUND", "Audio file not found: " + audioPath, null);
            return;
        }

        long audioFileSize = audioFile.length();
        Log.d(TAG, "Audio file size: " + audioFileSize + " bytes");
        if (audioFileSize == 0) {
            result.error("AUDIO_EMPTY", "Audio file is empty", null);
            return;
        }

        executor.execute(() -> {
            String wavPath = audioPath;
            boolean isConverted = false;

            try {
                // 检查是否需要格式转换
                if (AudioConverter.needsConversion(audioPath)) {
                    Log.d(TAG, "Audio needs conversion: " + audioPath);

                    // 创建临时WAV文件
                    File tempWav = new File(audioFile.getParent(),
                        "temp_" + System.currentTimeMillis() + ".wav");
                    wavPath = tempWav.getAbsolutePath();

                    // 转换音频格式
                    Log.d(TAG, "Converting audio to WAV...");
                    boolean converted = AudioConverter.convertToWav(audioPath, wavPath);
                    if (!converted) {
                        Log.e(TAG, "Audio conversion failed");
                        mainHandler.post(() -> {
                            result.error("CONVERT_FAILED", "Failed to convert audio to WAV format. The audio format may not be supported.", null);
                        });
                        return;
                    }

                    isConverted = true;
                    Log.d(TAG, "Audio converted to: " + wavPath);
                } else {
                    Log.d(TAG, "Audio is already in WAV format or no conversion needed");
                }

                // 执行转写
                Log.d(TAG, "Starting transcription...");
                String transcribedText = nativeTranscribe(
                    whisperContext,
                    wavPath,
                    language != null ? language : "zh"
                );

                // 清理临时文件
                if (isConverted) {
                    File tempFile = new File(wavPath);
                    if (tempFile.exists()) {
                        tempFile.delete();
                        Log.d(TAG, "Temporary WAV file deleted");
                    }
                }

                mainHandler.post(() -> {
                    if (transcribedText != null && !transcribedText.isEmpty()) {
                        Log.i(TAG, "Transcription successful, text length: " + transcribedText.length());
                        result.success(transcribedText);
                    } else {
                        Log.w(TAG, "Transcription returned empty result");
                        result.error("TRANSCRIBE_EMPTY", "Transcription returned empty result. The audio may not contain recognizable speech.", null);
                    }
                });

            } catch (UnsatisfiedLinkError e) {
                Log.e(TAG, "Native method not found: " + e.getMessage(), e);
                // 清理临时文件
                if (isConverted) {
                    File tempFile = new File(wavPath);
                    if (tempFile.exists()) {
                        tempFile.delete();
                    }
                }
                mainHandler.post(() -> {
                    result.error("NATIVE_METHOD_NOT_FOUND", "Native transcribe method not found. Library may not be loaded correctly.", e.getMessage());
                });
            } catch (Exception e) {
                Log.e(TAG, "Transcription error: " + e.getMessage(), e);
                // 清理临时文件
                if (isConverted) {
                    File tempFile = new File(wavPath);
                    if (tempFile.exists()) {
                        tempFile.delete();
                    }
                }

                mainHandler.post(() -> {
                    result.error("TRANSCRIBE_ERROR", e.getMessage(), Log.getStackTraceString(e));
                });
            }
        });
    }

    private void handleRelease(Result result) {
        executor.execute(() -> {
            if (whisperContext != null) {
                nativeFree(whisperContext);
                whisperContext = null;
            }
            mainHandler.post(() -> result.success(true));
        });
    }
}
