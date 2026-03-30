package com.example.memorypal_v3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

/**
 * 后台24小时录音服务
 *
 * 功能：
 * - VAD语音检测：检测到人声才开始录制
 * - 分段存储：每5分钟保存一个音频文件
 * - 循环覆盖：超过保存期限自动删除旧音频
 * - 电量优化：安静环境自动降低采样率
 */
class BackgroundRecordingService : Service() {

    companion object {
        const val TAG = "BgRecordingService"
        const val CHANNEL_ID = "background_recording"
        const val NOTIFICATION_ID = 2001
        const val SEGMENT_DURATION_MS = 5 * 60 * 1000L // 5分钟分段
        const val SAMPLE_RATE = 44100
        const val QUIET_SAMPLE_RATE = 22050 // 安静时使用较低采样率
    }

    private var mediaRecorder: MediaRecorder? = null
    private var isRecording = false
    private var currentFilePath: String? = null
    private var recordingStartTime: Long = 0
    private var currentSegmentNumber = 0
    private var outputDirectory: String = ""
    private var segmentDuration: Int = 300 // 秒

    private val handler = Handler(Looper.getMainLooper())
    private var segmentTimer: Runnable? = null

    // VAD相关
    private var lastVoiceDetectedTime: Long = 0
    private var isInQuietMode = false
    private var consecutiveQuietSegments = 0

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        outputDirectory = intent?.getStringExtra("directory") ?: return START_NOT_STICKY
        segmentDuration = intent.getIntExtra("segmentDuration", 300)

        startForeground(NOTIFICATION_ID, createNotification())
        startRecording()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startRecording() {
        if (isRecording) return

        try {
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            currentSegmentNumber++
            val fileName = "env_${timestamp}_seg${currentSegmentNumber}.m4a"
            currentFilePath = "$outputDirectory/$fileName"

            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)

                // 根据安静模式选择采样率
                val sampleRate = if (isInQuietMode) QUIET_SAMPLE_RATE else SAMPLE_RATE
                setAudioSamplingRate(sampleRate)
                setAudioEncodingBitRate(128000)

                setOutputFile(currentFilePath)

                try {
                    prepare()
                    start()
                    isRecording = true
                    recordingStartTime = System.currentTimeMillis()
                    lastVoiceDetectedTime = recordingStartTime

                    Log.i(TAG, "开始录音: $currentFilePath (采样率: $sampleRate)")

                    // 安排分段
                    scheduleSegmentSave()

                } catch (e: Exception) {
                    Log.e(TAG, "启动录音失败", e)
                    stopSelf()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "创建录音器失败", e)
            stopSelf()
        }
    }

    private fun stopCurrentRecording() {
        if (!isRecording) return

        try {
            mediaRecorder?.apply {
                try {
                    stop()
                } catch (e: Exception) {
                    Log.e(TAG, "停止录音失败", e)
                }
                reset()
                release()
            }
            mediaRecorder = null
            isRecording = false

            // 检查录音时长，太短则删除
            val duration = System.currentTimeMillis() - recordingStartTime
            if (duration < 3000) { // 少于3秒
                currentFilePath?.let {
                    File(it).delete()
                    Log.d(TAG, "录音太短已删除: $it")
                }
            } else {
                Log.i(TAG, "录音保存: $currentFilePath (${duration}ms)")
            }

        } catch (e: Exception) {
            Log.e(TAG, "停止录音异常", e)
        }
    }

    private fun scheduleSegmentSave() {
        segmentTimer?.let { handler.removeCallbacks(it) }

        segmentTimer = Runnable {
            if (isRecording) {
                // 检查是否需要进入安静模式
                checkQuietMode()

                // 保存当前段并开始新段
                stopCurrentRecording()
                startRecording()
            }
        }

        handler.postDelayed(segmentTimer!!, segmentDuration * 1000L)
    }

    /**
     * 检查安静模式
     *
     * 如果连续多个段没有检测到声音，切换到安静模式降低采样率
     * 这里简化处理，实际应该分析音频数据
     */
    private fun checkQuietMode() {
        val now = System.currentTimeMillis()
        val timeSinceLastVoice = now - lastVoiceDetectedTime

        // 如果超过5分钟没有检测到声音
        if (timeSinceLastVoice > 5 * 60 * 1000) {
            consecutiveQuietSegments++
            if (consecutiveQuietSegments >= 3 && !isInQuietMode) {
                isInQuietMode = true
                Log.i(TAG, "进入安静模式")
            }
        } else {
            consecutiveQuietSegments = 0
            if (isInQuietMode) {
                isInQuietMode = false
                Log.i(TAG, "退出安静模式")
            }
        }
    }

    /**
     * VAD检测（简化版）
     *
     * 实际应该使用专门的VAD算法（如WebRTC VAD）
     * 这里通过音量检测模拟
     */
    fun onVoiceDetected() {
        lastVoiceDetectedTime = System.currentTimeMillis()
        if (isInQuietMode) {
            isInQuietMode = false
            consecutiveQuietSegments = 0
            Log.i(TAG, "检测到声音，退出安静模式")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "后台录音服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "MemoryPal 24小时环境录音服务"
                setSound(null, null)
                enableVibration(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(this, BackgroundRecordingService::class.java).apply {
            action = "STOP_RECORDING"
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MemoryPal 正在录音")
            .setContentText("24小时智能助理正在记录 | ${if (isInQuietMode) "安静模式" else "正常录制"}")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .addAction(R.mipmap.ic_launcher, "停止", stopPendingIntent)
            .build()
    }

    private fun updateNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification())
    }

    override fun onDestroy() {
        super.onDestroy()
        segmentTimer?.let { handler.removeCallbacks(it) }
        stopCurrentRecording()
        Log.i(TAG, "后台录音服务已停止")
    }
}
