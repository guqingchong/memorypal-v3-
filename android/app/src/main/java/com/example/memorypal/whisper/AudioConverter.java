package com.example.memorypal.whisper;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * 音频格式转换器
 *
 * 使用Android原生MediaCodec将各种音频格式转换为WAV格式
 * 支持: M4A, AAC, MP3, OGG, OPUS等
 */
public class AudioConverter {
    private static final String TAG = "AudioConverter";
    private static final int SAMPLE_RATE = 16000;
    private static final int CHANNELS = 1;

    /**
     * 将音频文件转换为WAV格式(16kHz, 16-bit, mono)
     *
     * @param inputPath 输入音频文件路径
     * @param outputPath 输出WAV文件路径
     * @return 是否转换成功
     */
    public static boolean convertToWav(String inputPath, String outputPath) {
        Log.d(TAG, "开始转换音频: " + inputPath + " -> " + outputPath);

        MediaExtractor extractor = null;
        MediaCodec codec = null;
        FileOutputStream outputStream = null;

        try {
            // 检查输入文件
            File inputFile = new File(inputPath);
            if (!inputFile.exists()) {
                Log.e(TAG, "输入文件不存在: " + inputPath);
                return false;
            }

            // 初始化MediaExtractor
            extractor = new MediaExtractor();
            extractor.setDataSource(inputPath);

            // 找到音频轨道
            int audioTrackIndex = -1;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat format = extractor.getTrackFormat(i);
                String mime = format.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("audio/")) {
                    audioTrackIndex = i;
                    Log.d(TAG, "找到音频轨道: " + i + ", MIME: " + mime);
                    break;
                }
            }

            if (audioTrackIndex == -1) {
                Log.e(TAG, "未找到音频轨道");
                return false;
            }

            // 选择音频轨道
            extractor.selectTrack(audioTrackIndex);
            MediaFormat inputFormat = extractor.getTrackFormat(audioTrackIndex);

            // 读取音频格式参数
            int channelCount = 2;
            int inputSampleRate = 44100;
            if (inputFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
            }
            if (inputFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                inputSampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            }
            Log.d(TAG, "输入音频格式: " + channelCount + "声道, " + inputSampleRate + "Hz");

            // 创建解码器
            String mime = inputFormat.getString(MediaFormat.KEY_MIME);
            codec = MediaCodec.createDecoderByType(mime);
            codec.configure(inputFormat, null, null, 0);
            codec.start();

            // 准备输出文件
            outputStream = new FileOutputStream(outputPath);

            // 预留WAV头空间(44字节)
            byte[] wavHeader = new byte[44];
            outputStream.write(wavHeader);

            // 构建音频上下文
            AudioContext context = new AudioContext();
            context.channelCount = channelCount;
            context.inputSampleRate = inputSampleRate;

            // 解码并写入PCM数据
            int totalSamples = decodeAudio(extractor, codec, outputStream, context);

            // 关闭输出流以便修改文件
            outputStream.close();
            outputStream = null;

            // 写入WAV头
            if (totalSamples > 0) {
                writeWavHeader(outputPath, totalSamples);
                Log.d(TAG, "音频转换成功, 样本数: " + totalSamples);
                return true;
            } else {
                Log.e(TAG, "解码后没有音频数据");
                return false;
            }

        } catch (Exception e) {
            Log.e(TAG, "音频转换失败: " + e.getMessage(), e);
            return false;
        } finally {
            try {
                if (outputStream != null) {
                    outputStream.close();
                }
            } catch (IOException e) {
                Log.w(TAG, "关闭输出流失败: " + e.getMessage());
            }
            if (codec != null) {
                codec.stop();
                codec.release();
            }
            if (extractor != null) {
                extractor.release();
            }
        }
    }

    /**
     * 音频处理上下文，保存跨Buffer的状态
     */
    private static class AudioContext {
        int channelCount = 2;
        int inputSampleRate = 44100;
        double sampleAccumulator = 0.0;
    }

    /**
     * 解码音频数据
     */
    private static int decodeAudio(MediaExtractor extractor, MediaCodec codec,
            FileOutputStream outputStream, AudioContext context) throws IOException {

        ByteBuffer[] inputBuffers = codec.getInputBuffers();
        ByteBuffer[] outputBuffers = codec.getOutputBuffers();

        MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
        boolean isEOS = false;
        int totalSamples = 0;

        while (!isEOS) {
            // 输入数据
            int inputBufferIndex = codec.dequeueInputBuffer(10000);
            if (inputBufferIndex >= 0) {
                ByteBuffer inputBuffer = inputBuffers[inputBufferIndex];
                int sampleSize = extractor.readSampleData(inputBuffer, 0);

                if (sampleSize < 0) {
                    codec.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                    isEOS = true;
                } else {
                    long presentationTime = extractor.getSampleTime();
                    codec.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTime, 0);
                    extractor.advance();
                }
            }

            // 输出数据
            int outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10000);
            while (outputBufferIndex >= 0) {
                ByteBuffer outputBuffer = outputBuffers[outputBufferIndex];

                // 处理输出数据：重采样到16kHz单声道
                byte[] pcmData = processOutputBuffer(outputBuffer, bufferInfo, context);
                if (pcmData != null && pcmData.length > 0) {
                    outputStream.write(pcmData);
                    totalSamples += pcmData.length / 2; // 16-bit samples
                }

                codec.releaseOutputBuffer(outputBufferIndex, false);
                outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 0);

                if ((bufferInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    isEOS = true;
                    break;
                }
            }

            // 处理输出格式变化
            if (outputBufferIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED) {
                outputBuffers = codec.getOutputBuffers();
            } else if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                MediaFormat newFormat = codec.getOutputFormat();
                Log.d(TAG, "输出格式变化: " + newFormat);
                if (newFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                    context.channelCount = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
                    Log.d(TAG, "更新声道数: " + context.channelCount);
                }
                if (newFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                    context.inputSampleRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                    Log.d(TAG, "更新采样率: " + context.inputSampleRate);
                }
            }
        }

        return totalSamples;
    }

    /**
     * 处理输出缓冲区：转换为16kHz单声道16-bit PCM
     *
     * 支持动态声道数(1/2/n)和动态采样率降采样
     */
    private static byte[] processOutputBuffer(ByteBuffer buffer, MediaCodec.BufferInfo info, AudioContext context) {
        buffer.position(info.offset);
        buffer.limit(info.offset + info.size);

        int bytesPerFrame = context.channelCount * 2;
        if (bytesPerFrame <= 0) {
            bytesPerFrame = 2;
        }

        // 估算输出大小：每个输入帧最多输出一个16-bit mono样本
        byte[] output = new byte[info.size / bytesPerFrame * 2 + 8];
        int outputPos = 0;

        double sampleStep = context.inputSampleRate / (double) SAMPLE_RATE;
        if (sampleStep <= 0) {
            sampleStep = 1.0;
        }

        while (buffer.remaining() >= bytesPerFrame && outputPos < output.length - 2) {
            // 读取一帧的所有声道并混音为单声道
            long frameSum = 0;
            for (int ch = 0; ch < context.channelCount; ch++) {
                frameSum += buffer.getShort();
            }
            int mixed = (int) (frameSum / context.channelCount);

            // 降采样：按采样率比例抽取帧
            context.sampleAccumulator += 1.0;
            if (context.sampleAccumulator >= sampleStep) {
                output[outputPos++] = (byte) (mixed & 0xFF);
                output[outputPos++] = (byte) ((mixed >> 8) & 0xFF);
                context.sampleAccumulator -= sampleStep;
            }
        }

        if (outputPos > 0) {
            byte[] result = new byte[outputPos];
            System.arraycopy(output, 0, result, 0, outputPos);
            return result;
        }

        return null;
    }

    /**
     * 写入WAV文件头
     */
    private static void writeWavHeader(String wavPath, int totalSamples) throws IOException {
        File wavFile = new File(wavPath);
        if (!wavFile.exists()) {
            throw new IOException("WAV文件不存在");
        }

        int byteRate = SAMPLE_RATE * CHANNELS * 2; // 16-bit = 2 bytes
        int dataSize = totalSamples * 2;
        int fileSize = 36 + dataSize;

        byte[] header = new byte[44];

        // RIFF chunk
        System.arraycopy("RIFF".getBytes(), 0, header, 0, 4);
        writeInt32(header, 4, fileSize);
        System.arraycopy("WAVE".getBytes(), 0, header, 8, 4);

        // fmt chunk
        System.arraycopy("fmt ".getBytes(), 0, header, 12, 4);
        writeInt32(header, 16, 16); // Subchunk1Size
        writeInt16(header, 20, (short) 1); // AudioFormat (PCM)
        writeInt16(header, 22, (short) CHANNELS); // NumChannels
        writeInt32(header, 24, SAMPLE_RATE); // SampleRate
        writeInt32(header, 28, byteRate); // ByteRate
        writeInt16(header, 32, (short) (CHANNELS * 2)); // BlockAlign
        writeInt16(header, 34, (short) 16); // BitsPerSample

        // data chunk
        System.arraycopy("data".getBytes(), 0, header, 36, 4);
        writeInt32(header, 40, dataSize);

        // 写入文件头
        java.io.RandomAccessFile raf = new java.io.RandomAccessFile(wavFile, "rw");
        raf.seek(0);
        raf.write(header);
        raf.close();
    }

    private static void writeInt16(byte[] buffer, int offset, short value) {
        buffer[offset] = (byte) (value & 0xFF);
        buffer[offset + 1] = (byte) ((value >> 8) & 0xFF);
    }

    private static void writeInt32(byte[] buffer, int offset, int value) {
        buffer[offset] = (byte) (value & 0xFF);
        buffer[offset + 1] = (byte) ((value >> 8) & 0xFF);
        buffer[offset + 2] = (byte) ((value >> 16) & 0xFF);
        buffer[offset + 3] = (byte) ((value >> 24) & 0xFF);
    }

    /**
     * 检查是否需要转换格式
     */
    public static boolean needsConversion(String filePath) {
        String lowerPath = filePath.toLowerCase();
        return lowerPath.endsWith(".m4a") ||
               lowerPath.endsWith(".aac") ||
               lowerPath.endsWith(".mp3") ||
               lowerPath.endsWith(".ogg") ||
               lowerPath.endsWith(".opus") ||
               lowerPath.endsWith(".oga") ||
               lowerPath.endsWith(".3gp");
    }
}
