package com.example.memorypal_v3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.SimpleDateFormat
import java.util.*

/**
 * 后台录音服务 - 使用AudioRecord录制WAV格式（兼容Whisper转写）
 */
class RecordingService : Service() {

    companion object {
        const val TAG = "RecordingService"
        const val CHANNEL_ID = "recording_channel"
        const val NOTIFICATION_ID = 1001

        // 音频参数
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        val BUFFER_SIZE = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
    }

    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var currentFilePath: String? = null
    private var recordingThread: Thread? = null

    private var pcmFile: File? = null
    private var pcmOutputStream: FileOutputStream? = null
    private var pcmDataSize = 0

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
     * 开始录音 - 使用AudioRecord录制PCM并保存为WAV
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

            // 先录制到临时PCM文件
            val tempPcmPath = filePath.replace(".wav", "_temp.pcm")
            pcmFile = File(tempPcmPath)
            pcmOutputStream = FileOutputStream(pcmFile)
            pcmDataSize = 0

            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                BUFFER_SIZE
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord初始化失败")
                stopForeground(true)
                return false
            }

            audioRecord?.startRecording()
            isRecording = true

            // 启动录音线程
            recordingThread = Thread { recordingLoop() }
            recordingThread?.start()

            Log.i(TAG, "录音已启动: $filePath")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "启动录音失败", e)
            stopForeground(true)
            return false
        }
    }

    private fun recordingLoop() {
        val buffer = ShortArray(BUFFER_SIZE / 2)

        while (isRecording) {
            try {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) {
                    writePcmData(buffer, read)
                }
            } catch (e: Exception) {
                Log.e(TAG, "读取音频数据失败", e)
            }
        }
    }

    private fun writePcmData(buffer: ShortArray, size: Int) {
        try {
            // 转换为字节数组（小端序）
            val bytes = ByteArray(size * 2)
            val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            for (i in 0 until size) {
                bb.putShort(buffer[i])
            }
            pcmOutputStream?.write(bytes)
            pcmDataSize += bytes.size
        } catch (e: Exception) {
            Log.e(TAG, "写入PCM数据失败", e)
        }
    }

    /**
     * 停止录音并转换为WAV格式
     */
    fun stopRecording(): Boolean {
        if (!isRecording) {
            return false
        }

        try {
            isRecording = false

            // 等待录音线程结束
            recordingThread?.join(1000)
            recordingThread = null

            // 停止AudioRecord
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null

            // 关闭PCM输出流
            pcmOutputStream?.close()
            pcmOutputStream = null

            // 转换为WAV格式
            pcmFile?.let { pcm ->
                val wavFile = File(currentFilePath ?: return@let)
                convertPcmToWav(pcm, wavFile, pcmDataSize)
                pcm.delete() // 删除临时PCM文件
            }

            stopForeground(true)

            Log.i(TAG, "录音已停止并保存为WAV: $currentFilePath")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "停止录音失败", e)
            return false
        }
    }

    /**
     * 将PCM数据转换为WAV格式
     */
    private fun convertPcmToWav(pcmFile: File, wavFile: File, pcmSize: Int) {
        try {
            val pcmData = pcmFile.readBytes()

            // 写入WAV头
            val wavData = ByteArray(44 + pcmData.size)
            val bb = ByteBuffer.wrap(wavData).order(ByteOrder.LITTLE_ENDIAN)

            // RIFF chunk
            bb.put("RIFF".toByteArray())
            bb.putInt(36 + pcmData.size)
            bb.put("WAVE".toByteArray())

            // fmt chunk
            bb.put("fmt ".toByteArray())
            bb.putInt(16) // Subchunk1Size
            bb.putShort(1) // AudioFormat (PCM)
            bb.putShort(1) // NumChannels (Mono)
            bb.putInt(SAMPLE_RATE)
            bb.putInt(SAMPLE_RATE * 2) // ByteRate
            bb.putShort(2) // BlockAlign
            bb.putShort(16) // BitsPerSample

            // data chunk
            bb.put("data".toByteArray())
            bb.putInt(pcmData.size)

            // PCM数据
            System.arraycopy(pcmData, 0, wavData, 44, pcmData.size)

            wavFile.writeBytes(wavData)
            Log.i(TAG, "WAV文件已创建: ${wavFile.absolutePath}, 大小: ${wavData.size} bytes")
        } catch (e: Exception) {
            Log.e(TAG, "转换WAV失败", e)
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
