package com.example.memorypal_v3

import android.content.Intent
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val RECORDING_CHANNEL = "com.memorypal/recording"
    private var recordingService: RecordingService? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 录音服务通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRecording" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath != null) {
                            // 启动后台服务
                            val intent = Intent(this, RecordingService::class.java)
                            startService(intent)

                            // 等待服务启动后录音
                            // 简化版：直接返回成功，实际应该绑定服务后调用
                            result.success(true)
                        } else {
                            result.error("INVALID_PATH", "文件路径为空", null)
                        }
                    }
                    "stopRecording" -> {
                        val intent = Intent(this, RecordingService::class.java)
                        stopService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
