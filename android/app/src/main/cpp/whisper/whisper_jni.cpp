#include <jni.h>
#include <string>
#include <vector>
#include <fstream>
#include <cstring>
#include <android/log.h>

#include "whisper.h"

#define LOG_TAG "WhisperJNI"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// 音频采样率
#define SAMPLE_RATE 16000

// 辅助：读取4字节小端int32
template<typename T>
static T read_le(const char* p) {
    T val = 0;
    for (size_t i = 0; i < sizeof(T); i++) {
        val |= (static_cast<uint8_t>(p[i]) << (8 * i));
    }
    return val;
}

// 将音频文件读取为 16kHz float 数组
// 支持 WAV 格式（需要是 16kHz, 16-bit, mono）
bool read_wav_file(const std::string& fname, std::vector<float>& pcmf32) {
    std::ifstream file(fname, std::ios::binary);
    if (!file.is_open()) {
        LOGE("Failed to open audio file: %s", fname.c_str());
        return false;
    }

    // 读取 RIFF 和 WAVE 标记
    char riff[4], wave[4];
    file.read(riff, 4);
    file.seekg(4, std::ios::cur); // 跳过文件大小
    file.read(wave, 4);

    if (strncmp(riff, "RIFF", 4) != 0 || strncmp(wave, "WAVE", 4) != 0) {
        LOGE("Not a valid WAV file: %s", fname.c_str());
        return false;
    }

    int16_t audio_format = 0;
    int16_t num_channels = 0;
    int32_t sample_rate = 0;
    int16_t bits_per_sample = 0;
    int32_t data_size = 0;
    std::vector<int16_t> pcm16;
    bool found_fmt = false;
    bool found_data = false;

    // 遍历 chunk
    while (file.good() && !file.eof()) {
        char chunk_id[4];
        char chunk_size_raw[4];
        file.read(chunk_id, 4);
        if (file.gcount() < 4) break;
        file.read(chunk_size_raw, 4);
        if (file.gcount() < 4) break;

        int32_t chunk_size = read_le<int32_t>(chunk_size_raw);

        if (strncmp(chunk_id, "fmt ", 4) == 0) {
            std::vector<char> fmt_data(chunk_size);
            file.read(fmt_data.data(), chunk_size);
            if (chunk_size >= 16) {
                audio_format = read_le<int16_t>(fmt_data.data() + 0);
                num_channels = read_le<int16_t>(fmt_data.data() + 2);
                sample_rate = read_le<int32_t>(fmt_data.data() + 4);
                bits_per_sample = read_le<int16_t>(fmt_data.data() + 14);
                found_fmt = true;
            }
        } else if (strncmp(chunk_id, "data", 4) == 0) {
            data_size = chunk_size;
            // 防止奇数 data_size 导致越界：多预留一个 int16_t 的空间
            pcm16.resize((data_size + 1) / 2);
            file.read(reinterpret_cast<char*>(pcm16.data()), data_size);
            found_data = true;
            break; // data 是最后一个需要的 chunk
        } else {
            // 跳过未知 chunk（如 JUNK、LIST、INFO 等）
            if (chunk_size > 0) {
                file.seekg(chunk_size, std::ios::cur);
            }
        }
    }

    if (!found_fmt || !found_data) {
        LOGE("WAV file missing fmt or data chunk: %s", fname.c_str());
        return false;
    }

    LOGD("WAV Info: format=%d, channels=%d, rate=%d, bits=%d, size=%d",
         audio_format, num_channels, sample_rate, bits_per_sample, data_size);

    if (audio_format != 1) { // PCM
        LOGE("Unsupported audio format (must be PCM)");
        return false;
    }

    // 转换为 float 并处理采样率和声道
    pcmf32.clear();

    if (sample_rate == SAMPLE_RATE) {
        // 同采样率：只需将多声道混音为单声道
        if (num_channels == 1) {
            for (int16_t sample : pcm16) {
                pcmf32.push_back(sample / 32768.0f);
            }
        } else {
            // 通用多声道混音（交错格式）
            for (size_t i = 0; i < pcm16.size(); i += num_channels) {
                float sum = 0.0f;
                for (int16_t ch = 0; ch < num_channels; ch++) {
                    if (i + ch < pcm16.size()) {
                        sum += pcm16[i + ch];
                    }
                }
                pcmf32.push_back((sum / num_channels) / 32768.0f);
            }
        }
    } else if (sample_rate != SAMPLE_RATE) {
        // 重采样（简单线性插值）+ 多声道混音
        float ratio = (float)sample_rate / SAMPLE_RATE;
        size_t num_samples = pcm16.size() / num_channels;
        size_t target_samples = (size_t)(num_samples / ratio);

        for (size_t i = 0; i < target_samples; i++) {
            float src_frame = i * ratio;
            size_t idx = (size_t)src_frame;
            float frac = src_frame - idx;

            if (idx + 1 < num_samples) {
                float sample = 0;
                if (num_channels == 1) {
                    sample = pcm16[idx] * (1 - frac) + pcm16[idx + 1] * frac;
                } else {
                    // 通用多声道：先对每声道插值，再混音为单声道
                    float sum = 0.0f;
                    for (int16_t ch = 0; ch < num_channels; ch++) {
                        size_t base = idx * num_channels + ch;
                        size_t next = (idx + 1) * num_channels + ch;
                        if (next < pcm16.size()) {
                            sum += pcm16[base] * (1 - frac) + pcm16[next] * frac;
                        }
                    }
                    sample = sum / num_channels;
                }
                pcmf32.push_back(sample / 32768.0f);
            }
        }
    }

    LOGD("Loaded %zu samples", pcmf32.size());
    return !pcmf32.empty();
}

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_example_memorypal_whisper_WhisperPlugin_nativeInit(
        JNIEnv *env,
        jobject thiz,
        jstring modelPath) {

    const char *model_path = env->GetStringUTFChars(modelPath, nullptr);
    LOGD("Initializing Whisper model: %s", model_path);

    // 设置上下文参数
    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false;  // Android 上通常不使用 GPU
    cparams.flash_attn = false;

    // 初始化模型
    struct whisper_context *ctx = whisper_init_from_file_with_params(model_path, cparams);

    env->ReleaseStringUTFChars(modelPath, model_path);

    if (ctx == nullptr) {
        LOGE("Failed to initialize Whisper model");
        return 0;
    }

    LOGD("Whisper model initialized successfully");
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT void JNICALL
Java_com_example_memorypal_whisper_WhisperPlugin_nativeFree(
        JNIEnv *env,
        jobject thiz,
        jlong context) {

    if (context != 0) {
        struct whisper_context *ctx = reinterpret_cast<struct whisper_context *>(context);
        LOGD("Freeing Whisper context");
        whisper_free(ctx);
    }
}

JNIEXPORT jstring JNICALL
Java_com_example_memorypal_whisper_WhisperPlugin_nativeTranscribe(
        JNIEnv *env,
        jobject thiz,
        jlong context,
        jstring audioPath,
        jstring language) {

    if (context == 0) {
        LOGE("Whisper context is null");
        return env->NewStringUTF("");
    }

    const char *audio_path = env->GetStringUTFChars(audioPath, nullptr);
    const char *lang = env->GetStringUTFChars(language, nullptr);

    LOGD("Transcribing audio: %s, language: %s", audio_path, lang);

    // 读取音频文件
    std::vector<float> pcmf32;
    if (!read_wav_file(audio_path, pcmf32)) {
        LOGE("Failed to read audio file");
        env->ReleaseStringUTFChars(audioPath, audio_path);
        env->ReleaseStringUTFChars(language, lang);
        return env->NewStringUTF("[Error: Failed to read audio file]");
    }

    struct whisper_context *ctx = reinterpret_cast<struct whisper_context *>(context);

    // 设置转写参数
    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.translate = false;
    wparams.language = lang;
    wparams.n_threads = 4;  // 使用4线程
    wparams.offset_ms = 0;
    wparams.duration_ms = 0;
    wparams.token_timestamps = false;
    wparams.suppress_blank = true;

    LOGD("Running whisper_full with %zu samples", pcmf32.size());

    // 执行转写
    int ret = whisper_full(ctx, wparams, pcmf32.data(), pcmf32.size());

    env->ReleaseStringUTFChars(audioPath, audio_path);
    env->ReleaseStringUTFChars(language, lang);

    if (ret != 0) {
        LOGE("whisper_full failed with code: %d", ret);
        return env->NewStringUTF("[Error: Transcription failed]");
    }

    // 提取转写结果
    int n_segments = whisper_full_n_segments(ctx);
    LOGD("Transcription complete: %d segments", n_segments);

    std::string result_text;
    for (int i = 0; i < n_segments; i++) {
        const char *text = whisper_full_get_segment_text(ctx, i);
        if (text) {
            result_text += text;
            if (i < n_segments - 1) {
                result_text += " ";  // 段之间加空格
            }
        }
    }

    // 清理文本（去除多余空格）
    // 简单清理
    size_t start = result_text.find_first_not_of(" \t\n\r");
    if (start == std::string::npos) {
        return env->NewStringUTF("");
    }
    size_t end = result_text.find_last_not_of(" \t\n\r");
    result_text = result_text.substr(start, end - start + 1);

    LOGD("Transcription result: %s", result_text.c_str());

    return env->NewStringUTF(result_text.c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_example_memorypal_whisper_WhisperPlugin_nativeIsModelLoaded(
        JNIEnv *env,
        jobject thiz,
        jlong context) {

    return context != 0;
}

} // extern "C"
