package com.example.memorypal_v3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaRecorder
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.*

/**
 * 后台录音服务
 */
class RecordingService : Service() {

    companion object {
        const val TAG = "RecordingService"
        const val CHANNEL_ID = "recording_channel"
        const val NOTIFICATION_ID = 1001
    }

    private var mediaRecorder: MediaRecorder? = null
    private var isRecording = false
    private var currentFilePath: String? = null

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): RecordingService = this@RecordingService
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            when (it.action) {
                "START_RECORDING" -> {
                    val filePath = it.getStringExtra("filePath")
                    if (filePath != null) {
                        startRecording(filePath)
                    }
                }
                "STOP_RECORDING" -> {
                    stopRecording()
                }
            }
        }
        return START_STICKY
    }

    /**
     * 开始录音
     */
    fun startRecording(filePath: String): Boolean {
        if (isRecording) {
            Log.w(TAG, "已经在录音中")
            return false
        }

        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification())

        try {
            currentFilePath = filePath

            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(44100)
                setAudioEncodingBitRate(128000)
                setOutputFile(filePath)

                try {
                    prepare()
                    start()
                } catch (e: IOException) {
                    Log.e(TAG, "MediaRecorder准备失败", e)
                    throw e
                }
            }

            isRecording = true
            Log.i(TAG, "录音已启动: $filePath")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "启动录音失败", e)
            stopForeground(true)
            return false
        }
    }

    /**
     * 停止录音
     */
    fun stopRecording(): Boolean {
        if (!isRecording) {
            return false
        }

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
            stopForeground(true)

            Log.i(TAG, "录音已停止")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "停止录音失败", e)
            return false
        }
    }

    /**
     * 创建通知渠道（Android 8.0+）
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "录音服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "MemoryPal录音服务"
                setSound(null, null)
                enableVibration(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * 创建前台服务通知
     */
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MemoryPal 正在录音")
            .setContentText("24小时智能助理正在记录")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isRecording) {
            stopRecording()
        }
    }
}
