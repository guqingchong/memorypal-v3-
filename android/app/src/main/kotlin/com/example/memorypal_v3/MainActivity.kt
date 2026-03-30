package com.example.memorypal_v3

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val RECORDING_CHANNEL = "com.memorypal/recording"
    private val WECHAT_CHANNEL = "com.memorypal/wechat"
    private val WHISPER_CHANNEL = "com.memorypal/whisper"

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
                            val intent = Intent(this, RecordingService::class.java).apply {
                                putExtra("filePath", filePath)
                                putExtra("isVoiceNote", call.argument<Boolean>("isVoiceNote") ?: false)
                            }
                            startService(intent)
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
                    "startBackgroundRecording" -> {
                        val directory = call.argument<String>("directory")
                        val segmentDuration = call.argument<Int>("segmentDuration") ?: 300
                        if (directory != null) {
                            val intent = Intent(this, BackgroundRecordingService::class.java).apply {
                                putExtra("directory", directory)
                                putExtra("segmentDuration", segmentDuration)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } else {
                            result.error("INVALID_PATH", "目录路径为空", null)
                        }
                    }
                    "stopBackgroundRecording" -> {
                        val intent = Intent(this, BackgroundRecordingService::class.java)
                        stopService(intent)
                        result.success(true)
                    }
                    "isBackgroundRecordingRunning" -> {
                        result.success(isServiceRunning(BackgroundRecordingService::class.java))
                    }
                    else -> result.notImplemented()
                }
            }

        // 微信导入检测通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WECHAT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkUsageStatsPermission" -> {
                        result.success(checkUsageStatsPermission())
                    }
                    "openUsageStatsSettings" -> {
                        openUsageStatsSettings()
                        result.success(true)
                    }
                    "getForegroundApp" -> {
                        if (checkUsageStatsPermission()) {
                            result.success(getForegroundAppPackage())
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Whisper通道（模拟实现）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WHISPER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        // 初始化Whisper（需要集成whisper.cpp）
                        result.success(true)
                    }
                    "loadModel" -> {
                        val modelPath = call.argument<String>("modelPath")
                        result.success(true)
                    }
                    "transcribe" -> {
                        val audioPath = call.argument<String>("audioPath")
                        // 模拟转写结果
                        result.success(mapOf(
                            "text" to "这是模拟的转写结果。实际集成需要whisper.cpp库。",
                            "language" to "zh",
                            "segments" to emptyList<Map<String, Any>>()
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        for (service in manager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.name == service.service.className) {
                return true
            }
        }
        return false
    }

    // Usage Stats 权限检查
    private fun checkUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), packageName
            )
        }
        return mode == android.app.AppOpsManager.MODE_ALLOWED
    }

    // 打开 Usage Stats 设置页面
    private fun openUsageStatsSettings() {
        val intent = Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS)
        startActivity(intent)
    }

    // 获取前台应用包名
    private fun getForegroundAppPackage(): String? {
        if (!checkUsageStatsPermission()) return null

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
        val time = System.currentTimeMillis()
        val stats = usageStatsManager.queryUsageStats(
            android.app.usage.UsageStatsManager.INTERVAL_DAILY,
            time - 1000 * 10,
            time
        )

        return stats?.maxByOrNull { it.lastTimeUsed }?.packageName
    }
}
