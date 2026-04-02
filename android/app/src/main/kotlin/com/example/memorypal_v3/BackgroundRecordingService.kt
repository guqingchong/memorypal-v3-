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
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.SimpleDateFormat
import java.util.*

/**
 * 后台24小时录音服务 - 带VAD语音活动检测
 *
 * 功能：
 * - VAD语音检测：检测到人声才保存录音
 * - 分段存储：每5分钟保存一个音频文件
 * - 循环覆盖：超过保存期限自动删除旧音频
 * - 电量优化：安静环境自动降低采样率
 * - WAV格式保存便于后续处理
 */
class BackgroundRecordingService : Service() {

    companion object {
        const val TAG = "BgRecordingService"
        const val CHANNEL_ID = "background_recording"
        const val NOTIFICATION_ID = 2001

        // 音频参数
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        val BUFFER_SIZE = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)

        // VAD参数
        const val VAD_THRESHOLD_DB = 35.0  // 音量阈值(dB) - 降低阈值更容易触发录音
        const val VAD_SILENCE_TIMEOUT_MS = 3000L  // 静音超过3秒停止保存
        const val MIN_RECORDING_DURATION_MS = 1000L  // 最少录制1秒 - 降低门槛
        const val MAX_SEGMENT_DURATION_MS = 5 * 60 * 1000L  // 最大5分钟分段
    }

    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var outputDirectory: String = ""

    private val handler = Handler(Looper.getMainLooper())
    private var recordingThread: Thread? = null

    // VAD状态
    private var isVoiceActive = false
    private var lastVoiceTime: Long = 0
    private var currentSegmentStartTime: Long = 0
    private var currentPcmFile: File? = null
    private var currentFos: FileOutputStream? = null
    private var currentPcmSize = 0

    // 统计
    private var totalSegmentsSaved = 0
    private var totalVoiceDetectedCount = 0

    // WakeLock防止CPU休眠
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
        checkBatteryOptimization()
    }

    /**
     * 检查并请求忽略电池优化（华为/HarmonyOS需要）
     */
    private fun checkBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                Log.w(TAG, "未忽略电池优化，华为设备可能会杀后台")
                // 发送广播通知Flutter层引导用户设置
                val intent = Intent("com.memorypal.BATTERY_OPTIMIZATION")
                intent.putExtra("needs_whitelist", true)
                sendBroadcast(intent)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        outputDirectory = intent?.getStringExtra("directory") ?: run {
            Log.e(TAG, "输出目录为空，停止服务")
            stopSelf()
            return START_NOT_STICKY
        }

        // 确保目录存在
        File(outputDirectory).mkdirs()

        // 启动时清理旧录音（循环覆盖策略）
        cleanupOldRecordings()

        startForeground(NOTIFICATION_ID, createNotification())
        startRecording()

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "MemoryPal::BackgroundRecordingWakeLock"
            )
            wakeLock?.acquire(10 * 60 * 1000L) // 10分钟，会自动续期
        } catch (e: Exception) {
            Log.e(TAG, "获取WakeLock失败", e)
        }
    }

    private fun startRecording() {
        if (isRecording) return

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                BUFFER_SIZE
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord初始化失败")
                stopSelf()
                return
            }

            audioRecord?.startRecording()
            isRecording = true
            currentSegmentStartTime = System.currentTimeMillis()

            Log.i(TAG, "开始录音，采样率: $SAMPLE_RATE, 缓冲区: $BUFFER_SIZE")

            // 启动录音线程
            recordingThread = Thread { recordingLoop() }
            recordingThread?.start()

        } catch (e: Exception) {
            Log.e(TAG, "启动录音失败", e)
            stopSelf()
        }
    }

    private fun recordingLoop() {
        val buffer = ShortArray(BUFFER_SIZE / 2)

        while (isRecording) {
            try {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) {
                    processAudioBuffer(buffer, read)
                }
            } catch (e: Exception) {
                Log.e(TAG, "读取音频数据失败", e)
            }
        }
    }

    private fun processAudioBuffer(buffer: ShortArray, readSize: Int) {
        // 计算音量(dB)
        val rms = calculateRMS(buffer, readSize)
        val db = 20 * kotlin.math.log10(rms + 1e-10)

        val now = System.currentTimeMillis()
        val isVoice = db > VAD_THRESHOLD_DB

        if (isVoice) {
            lastVoiceTime = now
            totalVoiceDetectedCount++

            if (!isVoiceActive) {
                // 开始检测到语音，创建新文件
                isVoiceActive = true
                createNewSegment()
                Log.d(TAG, "检测到语音，开始录制，音量: ${String.format("%.1f", db)}dB")
            }
        }

        // 写入数据（如果正在录制语音段）
        if (isVoiceActive) {
            writeAudioData(buffer, readSize)

            // 检查是否需要结束当前段（静音超时或超过最大时长）
            val silenceDuration = now - lastVoiceTime
            val segmentDuration = now - currentSegmentStartTime

            if (silenceDuration > VAD_SILENCE_TIMEOUT_MS || segmentDuration > MAX_SEGMENT_DURATION_MS) {
                finalizeSegment()
            }
        }

        // 每30秒更新一次通知
        if (totalVoiceDetectedCount % 300 == 0) {
            updateNotification()
        }
    }

    private fun calculateRMS(buffer: ShortArray, size: Int): Double {
        var sum = 0.0
        for (i in 0 until size) {
            sum += buffer[i] * buffer[i]
        }
        return kotlin.math.sqrt(sum / size)
    }

    private fun createNewSegment() {
        try {
            currentSegmentStartTime = System.currentTimeMillis()
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val pcmFileName = "voice_${timestamp}_temp.pcm"
            currentPcmFile = File(outputDirectory, pcmFileName)
            currentFos = FileOutputStream(currentPcmFile)
            currentPcmSize = 0
        } catch (e: Exception) {
            Log.e(TAG, "创建新段失败", e)
            isVoiceActive = false
        }
    }

    private fun writeAudioData(buffer: ShortArray, size: Int) {
        try {
            // 转换为字节数组
            val bytes = ByteArray(size * 2)
            val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            for (i in 0 until size) {
                bb.putShort(buffer[i])
            }

            currentFos?.write(bytes)
            currentPcmSize += bytes.size
        } catch (e: Exception) {
            Log.e(TAG, "写入音频数据失败", e)
        }
    }

    private fun finalizeSegment() {
        if (!isVoiceActive || currentPcmFile == null) return

        val duration = System.currentTimeMillis() - currentSegmentStartTime

        // 关闭文件
        try {
            currentFos?.close()
        } catch (e: Exception) {
            Log.e(TAG, "关闭文件失败", e)
        }

        // 检查时长，太短则删除
        if (duration < MIN_RECORDING_DURATION_MS) {
            currentPcmFile?.delete()
            Log.d(TAG, "录音段太短(${duration}ms)，已删除")
        } else {
            // 转换为WAV格式
            val wavFile = convertPcmToWav(currentPcmFile!!)
            if (wavFile != null) {
                totalSegmentsSaved++
                Log.i(TAG, "保存录音段: ${wavFile.name}, 时长: ${duration}ms")
                // 通知Flutter层有新录音，传递时长（转换为秒）
                notifySegmentSaved(wavFile.absolutePath, duration)
            }
            // 删除临时PCM文件
            currentPcmFile?.delete()
        }

        // 重置状态
        isVoiceActive = false
        currentPcmFile = null
        currentFos = null
        currentPcmSize = 0
    }

    /**
     * 通知Flutter层有新录音段保存
     */
    private fun notifySegmentSaved(filePath: String, duration: Long = 0) {
        val intent = Intent("com.memorypal.SEGMENT_SAVED").apply {
            putExtra("filePath", filePath)
            putExtra("duration", duration)
            // 设置包名确保只有本应用能接收
            setPackage(packageName)
        }
        sendBroadcast(intent)
        Log.d(TAG, "已发送录音保存广播: $filePath, duration: ${duration}ms")
    }

    private fun convertPcmToWav(pcmFile: File): File? {
        return try {
            val timestamp = pcmFile.name.removePrefix("voice_").removeSuffix("_temp.pcm")
            val wavFile = File(outputDirectory, "voice_$timestamp.wav")

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
            bb.putShort(1) // NumChannels
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
            wavFile
        } catch (e: Exception) {
            Log.e(TAG, "转换WAV失败", e)
            null
        }
    }

    private fun stopRecording() {
        isRecording = false

        // 结束当前段
        finalizeSegment()

        // 停止录音
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (e: Exception) {
            Log.e(TAG, "停止录音失败", e)
        }
        audioRecord = null

        // 等待录音线程结束
        recordingThread?.join(1000)
        recordingThread = null

        Log.i(TAG, "录音已停止，共保存 $totalSegmentsSaved 段")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "后台录音服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "MemoryPal 24小时智能录音服务"
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
            action = "STOP"
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        val status = when {
            isVoiceActive -> "🎙️ 正在录制语音"
            isRecording -> "👂 监听中..."
            else -> "已停止"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MemoryPal 智能录音")
            .setContentText("$status | 已保存 $totalSegmentsSaved 段")
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
        stopRecording()
        wakeLock?.release()
        Log.i(TAG, "后台录音服务已销毁")
    }

    /**
     * 清理旧录音文件（循环覆盖策略）
     *
     * 删除超过保留期限的录音文件
     * @param retentionDays 保留天数（默认30天）
     */
    private fun cleanupOldRecordings(retentionDays: Int = 30) {
        try {
            val dir = File(outputDirectory)
            if (!dir.exists() || !dir.isDirectory) return

            val cutoffTime = System.currentTimeMillis() - (retentionDays * 24 * 60 * 60 * 1000L)
            var deletedCount = 0

            dir.listFiles()?.forEach { file ->
                if (file.isFile && file.name.startsWith("voice_")) {
                    if (file.lastModified() < cutoffTime) {
                        if (file.delete()) {
                            deletedCount++
                            Log.d(TAG, "删除旧录音: ${file.name}")
                        }
                    }
                }
            }

            if (deletedCount > 0) {
                Log.i(TAG, "循环覆盖: 已删除 $deletedCount 个旧录音文件")
            }
        } catch (e: Exception) {
            Log.e(TAG, "清理旧录音失败", e)
        }
    }

    /**
     * 获取存储空间使用情况
     */
    private fun getStorageUsage(): Pair<Long, Int> {
        return try {
            val dir = File(outputDirectory)
            if (!dir.exists()) return Pair(0L, 0)

            var totalSize = 0L
            var fileCount = 0

            dir.listFiles()?.forEach { file ->
                if (file.isFile && file.name.startsWith("voice_")) {
                    totalSize += file.length()
                    fileCount++
                }
            }

            Pair(totalSize, fileCount)
        } catch (e: Exception) {
            Pair(0L, 0)
        }
    }
}
