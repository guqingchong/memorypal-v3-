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

    // Native方法声明
    static {
        System.loadLibrary("whisper_jni");
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
        final String modelPath = call.argument("modelPath");

        if (modelPath == null || modelPath.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Model path is required", null);
            return;
        }

        // 检查模型文件是否存在
        File modelFile = new File(modelPath);
        if (!modelFile.exists()) {
            result.error("MODEL_NOT_FOUND", "Model file not found: " + modelPath, null);
            return;
        }

        executor.execute(() -> {
            try {
                // 释放之前的上下文
                if (whisperContext != null) {
                    nativeFree(whisperContext);
                }

                // 初始化新的上下文
                long context = nativeInit(modelPath);

                if (context == 0) {
                    mainHandler.post(() -> {
                        result.error("INIT_FAILED", "Failed to initialize Whisper model", null);
                    });
                    return;
                }

                whisperContext = context;

                mainHandler.post(() -> {
                    result.success(true);
                });

            } catch (Exception e) {
                mainHandler.post(() -> {
                    result.error("INIT_ERROR", e.getMessage(), null);
                });
            }
        });
    }

    private void handleTranscribe(MethodCall call, Result result) {
        final String audioPath = call.argument("audioPath");
        final String language = call.argument("language");

        if (whisperContext == null) {
            result.error("NOT_INITIALIZED", "Whisper not initialized", null);
            return;
        }

        if (audioPath == null || audioPath.isEmpty()) {
            result.error("INVALID_ARGUMENT", "Audio path is required", null);
            return;
        }

        // 检查音频文件
        File audioFile = new File(audioPath);
        if (!audioFile.exists()) {
            result.error("AUDIO_NOT_FOUND", "Audio file not found: " + audioPath, null);
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
                    boolean converted = AudioConverter.convertToWav(audioPath, wavPath);
                    if (!converted) {
                        mainHandler.post(() -> {
                            result.error("CONVERT_FAILED", "Failed to convert audio to WAV format", null);
                        });
                        return;
                    }

                    isConverted = true;
                    Log.d(TAG, "Audio converted to: " + wavPath);
                }

                // 执行转写
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
                        result.success(transcribedText);
                    } else {
                        result.error("TRANSCRIBE_FAILED", "Transcription returned empty result", null);
                    }
                });

            } catch (Exception e) {
                // 清理临时文件
                if (isConverted) {
                    File tempFile = new File(wavPath);
                    if (tempFile.exists()) {
                        tempFile.delete();
                    }
                }

                mainHandler.post(() -> {
                    result.error("TRANSCRIBE_ERROR", e.getMessage(), null);
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
