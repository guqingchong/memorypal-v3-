package com.example.memorypal_v3

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.memorypal.whisper.WhisperPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest

class MainActivity : FlutterActivity() {
    private val RECORDING_CHANNEL = "com.memorypal/recording"
    private val WECHAT_CHANNEL = "com.memorypal/wechat"
    private val WHISPER_CHANNEL = "com.memorypal/whisper"
    private val CALL_STATE_CHANNEL = "com.memorypal/call_state"

    private var callStateReceiver: BroadcastReceiver? = null
    private var callStateMethodChannel: MethodChannel? = null

    companion object {
        private const val PERMISSION_REQUEST_CODE = 1001
    }

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

        // 注册Whisper插件
        WhisperPlugin.registerWith(flutterEngine)

        // 通话状态监听通道
        callStateMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_STATE_CHANNEL)
        setupCallStateReceiver()
        startCallStateService()
    }

    /**
     * 设置通话状态广播接收器
     */
    private fun setupCallStateReceiver() {
        callStateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val state = intent.getStringExtra("state")
                val phoneNumber = intent.getStringExtra("phoneNumber")
                val duration = intent.getLongExtra("duration", 0)

                Log.d("MainActivity", "Call state: $state, number: $phoneNumber")

                // 转发到 Flutter
                val args = hashMapOf<String, Any?>(
                    "state" to state,
                    "phoneNumber" to phoneNumber,
                    "duration" to duration
                )
                callStateMethodChannel?.invokeMethod("onCallStateChanged", args)
            }
        }

        // 注册广播接收器
        val filter = IntentFilter("com.memorypal.CALL_STATE_CHANGED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(callStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(callStateReceiver, filter)
        }
    }

    /**
     * 启动通话状态监听服务
     */
    private fun startCallStateService() {
        // 检查 READ_PHONE_STATE 权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
                != PackageManager.PERMISSION_GRANTED) {
                // 请求权限
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.READ_PHONE_STATE),
                    PERMISSION_REQUEST_CODE
                )
                Log.d("MainActivity", "Requesting READ_PHONE_STATE permission")
                return
            }
        }

        // 权限已授予，启动服务
        startCallStateServiceInternal()
    }

    private fun startCallStateServiceInternal() {
        try {
            val intent = Intent(this, CallStateService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d("MainActivity", "CallStateService started")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to start CallStateService: ${e.message}")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d("MainActivity", "READ_PHONE_STATE permission granted")
                // 权限已授予，现在启动服务
                startCallStateServiceInternal()
            } else {
                Log.w("MainActivity", "READ_PHONE_STATE permission denied")
                // 权限被拒绝，不启动服务（应用仍可正常使用其他功能）
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        callStateReceiver?.let { unregisterReceiver(it) }
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
