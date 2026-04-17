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
        val BUFFER_SIZE = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT).let {
            // 使用较大缓冲区（约1~2秒音频），降低read循环频率，减少CPU唤醒
            if (it > 0) kotlin.math.max(it * 16, 32768) else 32768
        }

        // VAD参数
        const val VAD_THRESHOLD_DB = 25.0  // 音量阈值(dB) - 降低到25dB使检测更敏感
        const val VAD_SILENCE_TIMEOUT_MS = 3000L  // 静音超过3秒停止保存
        const val MIN_RECORDING_DURATION_MS = 1000L  // 最少录制1秒 - 降低门槛
        const val MAX_SEGMENT_DURATION_MS = 5 * 60 * 1000L  // 最大5分钟分段

        // VAD节流：每N个buffer计算一次RMS，降低空闲功耗
        const val VAD_SKIP_INTERVAL = 5

        // Manifest批量写入：累积N条或N分钟后flush
        const val MANIFEST_FLUSH_COUNT = 5
        const val MANIFEST_FLUSH_INTERVAL_MS = 5 * 60 * 1000L
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

    // 通知更新控制
    private var lastNotificationUpdateTime: Long = 0
    private val NOTIFICATION_UPDATE_INTERVAL_MS = 30000L // 30秒

    // WakeLock防止CPU休眠
    private var wakeLock: PowerManager.WakeLock? = null

    // VAD节流计数器
    private var vadSkipCounter = 0

    // Manifest内存缓存与批量写入
    private val segmentBuffer = mutableListOf<Map<String, Any>>()
    private var lastManifestFlushTime: Long = 0

    // 复用的PCM写入缓冲区，避免每次分配新数组
    private var reuseBytes = ByteArray(0)
    private var reuseByteBuffer: ByteBuffer? = null

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
            // 10分钟超时，避免长时间持有WakeLock导致耗电发热
            wakeLock?.acquire(10 * 60 * 1000L)
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
                    // 若未读满缓冲区，让出CPU时间片，避免忙等
                    if (read < buffer.size) {
                        Thread.sleep(50)
                    }
                } else if (read < 0) {
                    // AudioRecord错误码处理
                    Log.e(TAG, "AudioRecord读取错误: $read")
                    when (read) {
                        AudioRecord.ERROR_INVALID_OPERATION -> Log.e(TAG, "ERROR_INVALID_OPERATION")
                        AudioRecord.ERROR_BAD_VALUE -> Log.e(TAG, "ERROR_BAD_VALUE")
                        AudioRecord.ERROR_DEAD_OBJECT -> {
                            Log.e(TAG, "ERROR_DEAD_OBJECT，尝试重启录音")
                            restartRecording()
                            return
                        }
                        AudioRecord.ERROR -> Log.e(TAG, "ERROR")
                    }
                    Thread.sleep(500)
                }
            } catch (e: Exception) {
                Log.e(TAG, "读取音频数据失败", e)
                Thread.sleep(500)
            }
        }
    }

    private fun restartRecording() {
        stopRecording()
        handler.postDelayed({
            if (isRecording) {
                startRecording()
            }
        }, 1000)
    }

    private fun processAudioBuffer(buffer: ShortArray, readSize: Int) {
        vadSkipCounter++

        val now = System.currentTimeMillis()
        val isVoice: Boolean

        // 节流VAD计算：每VAD_SKIP_INTERVAL个buffer计算一次RMS
        // 若已处于语音激活状态，降低skip频率以提高响应
        val skipInterval = if (isVoiceActive) 1 else VAD_SKIP_INTERVAL
        if (vadSkipCounter % skipInterval == 0) {
            val rms = calculateRMS(buffer, readSize)
            val db = 20 * kotlin.math.log10(rms + 1e-10)
            isVoice = db > VAD_THRESHOLD_DB

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
        } else {
            // 跳过RMS计算时，沿用上一帧的语音状态（保守估计：继续录音）
            isVoice = isVoiceActive
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

        // 每30秒更新一次通知（基于时间而非语音检测次数）
        if (now - lastNotificationUpdateTime > NOTIFICATION_UPDATE_INTERVAL_MS) {
            lastNotificationUpdateTime = now
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
            val byteCount = size * 2
            // 按需扩容复用缓冲区
            if (reuseBytes.size < byteCount) {
                reuseBytes = ByteArray(byteCount)
                reuseByteBuffer = ByteBuffer.wrap(reuseBytes).order(ByteOrder.LITTLE_ENDIAN)
            }
            val bb = reuseByteBuffer!!
            bb.clear()
            for (i in 0 until size) {
                bb.putShort(buffer[i])
            }

            currentFos?.write(reuseBytes, 0, byteCount)
            currentPcmSize += byteCount
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

        // 分段结束时强制 flush manifest，降低丢失风险
        flushSegmentManifest()

        // 重置状态
        isVoiceActive = false
        currentPcmFile = null
        currentFos = null
        currentPcmSize = 0
    }

    /**
     * 通知Flutter层有新录音段保存
     * manifest 先写入内存缓存，批量 flush 到磁盘，降低 I/O 频率
     */
    private fun notifySegmentSaved(filePath: String, duration: Long = 0) {
        segmentBuffer.add(mapOf(
            "filePath" to filePath,
            "duration" to duration,
            "timestamp" to System.currentTimeMillis()
        ))
        flushSegmentManifestIfNeeded()

        val intent = Intent("com.memorypal.SEGMENT_SAVED").apply {
            putExtra("filePath", filePath)
            putExtra("duration", duration)
            // 设置包名确保只有本应用能接收
            setPackage(packageName)
        }
        sendBroadcast(intent)
        Log.d(TAG, "已发送录音保存广播: $filePath, duration: ${duration}ms")
    }

    /**
     * 满足条件时触发 manifest flush：累积条目数或时间间隔
     */
    private fun flushSegmentManifestIfNeeded() {
        val now = System.currentTimeMillis()
        if (segmentBuffer.size >= MANIFEST_FLUSH_COUNT ||
            (segmentBuffer.isNotEmpty() && now - lastManifestFlushTime > MANIFEST_FLUSH_INTERVAL_MS)
        ) {
            flushSegmentManifest()
        }
    }

    /**
     * 将内存中的 segmentBuffer 写入持久化 manifest 文件（原子写）
     */
    private fun flushSegmentManifest() {
        if (segmentBuffer.isEmpty()) return

        try {
            val manifestFile = File(outputDirectory, "background_segments.json")
            val entries = mutableListOf<Map<String, Any>>()

            // 读取已有条目
            if (manifestFile.exists()) {
                try {
                    val content = manifestFile.readText()
                    val array = org.json.JSONArray(content)
                    for (i in 0 until array.length()) {
                        val obj = array.getJSONObject(i)
                        entries.add(mapOf(
                            "filePath" to obj.getString("filePath"),
                            "duration" to obj.getLong("duration"),
                            "timestamp" to obj.getLong("timestamp")
                        ))
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Manifest解析失败，将重建", e)
                }
            }

            entries.addAll(segmentBuffer)
            segmentBuffer.clear()
            lastManifestFlushTime = System.currentTimeMillis()

            val jsonArray = org.json.JSONArray()
            for (entry in entries) {
                val obj = org.json.JSONObject()
                obj.put("filePath", entry["filePath"])
                obj.put("duration", entry["duration"])
                obj.put("timestamp", entry["timestamp"])
                jsonArray.put(obj)
            }

            val tempFile = File(outputDirectory, "background_segments.json.tmp")
            tempFile.writeText(jsonArray.toString())

            // 尝试原子替换 manifest，失败则回退到先删后重命名
            val moved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    java.nio.file.Files.move(
                        tempFile.toPath(),
                        manifestFile.toPath(),
                        java.nio.file.StandardCopyOption.ATOMIC_MOVE,
                        java.nio.file.StandardCopyOption.REPLACE_EXISTING
                    )
                    true
                } catch (e: Exception) {
                    false
                }
            } else {
                false
            }

            if (!moved) {
                if (manifestFile.exists() && !manifestFile.delete()) {
                    Log.w(TAG, "无法删除旧manifest文件")
                }
                if (!tempFile.renameTo(manifestFile)) {
                    Log.e(TAG, "Manifest重命名失败")
                }
            }
            Log.d(TAG, "Manifest已写入: ${manifestFile.absolutePath}, 共 ${entries.size} 条")
        } catch (e: Exception) {
            Log.e(TAG, "写入manifest失败", e)
        }
    }

    private fun convertPcmToWav(pcmFile: File): File? {
        return try {
            val timestamp = pcmFile.name.removePrefix("voice_").removeSuffix("_temp.pcm")
            val wavFile = File(outputDirectory, "voice_$timestamp.wav")
            val pcmLength = pcmFile.length()

            FileOutputStream(wavFile).use { fos ->
                // 写入WAV头（44 bytes）
                val header = ByteArray(44)
                val bb = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)

                // RIFF chunk
                bb.put("RIFF".toByteArray())
                bb.putInt(36 + pcmLength.toInt())
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
                bb.putInt(pcmLength.toInt())

                fos.write(header)

                // 流式复制PCM数据，避免全量载入内存
                val chunk = ByteArray(32768)
                java.io.FileInputStream(pcmFile).use { fis ->
                    var read: Int
                    while (fis.read(chunk).also { read = it } > 0) {
                        fos.write(chunk, 0, read)
                    }
                }
            }
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
        // 服务销毁前强制 flush 内存中的 manifest，避免数据丢失
        flushSegmentManifest()
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
