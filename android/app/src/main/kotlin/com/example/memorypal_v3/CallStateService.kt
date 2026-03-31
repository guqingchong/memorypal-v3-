package com.example.memorypal_v3

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.content.Context
import android.os.Build
import android.util.Log

/**
 * 通话状态监听服务
 *
 * 监听电话状态变化，配合系统自动通话录音功能：
 * 1. 通话开始时暂停 MemoryPal 环境录音
 * 2. 通话结束时恢复录音并导入系统录音
 */
class CallStateService : Service() {
    companion object {
        const val TAG = "CallStateService"
        const val CHANNEL_NAME = "com.memorypal/call_state"

        // 通话状态
        const val CALL_STATE_IDLE = 0      // 空闲
        const val CALL_STATE_RINGING = 1   // 响铃
        const val CALL_STATE_OFFHOOK = 2   // 通话中

        // 录音导入目录（各品牌手机）
        val RECORDING_PATHS = mapOf(
            "huawei" to "/Sounds/Recorder/",
            "xiaomi" to "/MIUI/sound_recorder/",
            "oppo" to "/Recordings/",
            "vivo" to "/录音/",
            "samsung" to "/Sounds/Recorder/",
            "generic" to "/Recordings/"
        )
    }

    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var lastCallState = CALL_STATE_IDLE
    private var callStartTime: Long = 0

    // 是否在通话中（用于判断通话结束后的处理）
    private var wasInCall = false

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "CallStateService created")
        initPhoneStateListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "CallStateService started")
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        phoneStateListener?.let {
            telephonyManager?.listen(it, PhoneStateListener.LISTEN_NONE)
        }
        Log.d(TAG, "CallStateService destroyed")
    }

    private fun initPhoneStateListener() {
        telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

        phoneStateListener = object : PhoneStateListener() {
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                super.onCallStateChanged(state, phoneNumber)

                when (state) {
                    TelephonyManager.CALL_STATE_IDLE -> {
                        Log.d(TAG, "Call state: IDLE")
                        if (wasInCall) {
                            // 通话刚结束
                            onCallEnded()
                            wasInCall = false
                        }
                        lastCallState = CALL_STATE_IDLE
                    }

                    TelephonyManager.CALL_STATE_RINGING -> {
                        Log.d(TAG, "Call state: RINGING, number: $phoneNumber")
                        onCallRinging(phoneNumber)
                        lastCallState = CALL_STATE_RINGING
                    }

                    TelephonyManager.CALL_STATE_OFFHOOK -> {
                        Log.d(TAG, "Call state: OFFHOOK")
                        if (lastCallState == CALL_STATE_RINGING || lastCallState == CALL_STATE_IDLE) {
                            // 开始通话（接听或拨打）
                            onCallStarted(phoneNumber)
                            wasInCall = true
                            callStartTime = System.currentTimeMillis()
                        }
                        lastCallState = CALL_STATE_OFFHOOK
                    }
                }
            }
        }

        // 注册监听器
        telephonyManager?.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
    }

    /**
     * 通话开始（接听或拨打）
     */
    private fun onCallStarted(phoneNumber: String?) {
        Log.d(TAG, "Call started, number: $phoneNumber")

        // 通知 Flutter 层暂停环境录音
        sendCallStateToFlutter("call_started", phoneNumber)

        // 显示通知
        showNotification("通话中", "MemoryPal 已暂停环境录音")
    }

    /**
     * 通话响铃（来电）
     */
    private fun onCallRinging(phoneNumber: String?) {
        Log.d(TAG, "Call ringing, number: $phoneNumber")

        // 通知 Flutter 层
        sendCallStateToFlutter("call_ringing", phoneNumber)
    }

    /**
     * 通话结束
     */
    private fun onCallEnded() {
        Log.d(TAG, "Call ended")

        val callDuration = System.currentTimeMillis() - callStartTime
        Log.d(TAG, "Call duration: ${callDuration / 1000} seconds")

        // 通知 Flutter 层恢复录音并导入系统录音
        sendCallStateToFlutter("call_ended", duration = callDuration)

        // 延迟执行导入（等待系统完成录音保存）
        Thread {
            Thread.sleep(3000) // 等待3秒
            scanAndImportSystemRecordings()
        }.start()

        showNotification("通话结束", "MemoryPal 已恢复录音，正在导入通话录音...")
    }

    /**
     * 扫描并导入系统通话录音
     */
    private fun scanAndImportSystemRecordings() {
        Log.d(TAG, "Scanning system recordings...")

        // 这里通过 MethodChannel 通知 Dart 层执行导入
        // Dart 层有文件访问权限，可以扫描外部存储
        sendCallStateToFlutter("import_recordings", null)
    }

    /**
     * 发送通话状态到 Flutter
     */
    private fun sendCallStateToFlutter(state: String, phoneNumber: String? = null, duration: Long = 0) {
        val intent = Intent("com.memorypal.CALL_STATE_CHANGED").apply {
            putExtra("state", state)
            putExtra("phoneNumber", phoneNumber)
            putExtra("duration", duration)
        }
        sendBroadcast(intent)
    }

    /**
     * 显示状态栏通知
     */
    private fun showNotification(title: String, message: String) {
        // 这里简化实现，实际应该创建 NotificationManager
        Log.d(TAG, "Notification: $title - $message")
    }
}
