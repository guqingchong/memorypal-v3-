cmake_minimum_required(VERSION 3.14)
project("memorypal_whisper")

# 设置C++标准
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Whisper.cpp 路径
set(WHISPER_CPP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../whisper.cpp/whisper.cpp)

# 添加 whisper.cpp 子目录
# 注意：我们需要只构建库，不构建示例
add_subdirectory(
    ${WHISPER_CPP_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}/whisper
)

# 创建JNI库
add_library(
    whisper_jni
    SHARED
    whisper/whisper_jni.cpp
)

# 包含目录
target_include_directories(
    whisper_jni
    PRIVATE
    ${WHISPER_CPP_DIR}/include
    ${WHISPER_CPP_DIR}/ggml/include
)

# 链接库
target_link_libraries(
    whisper_jni
    whisper  # whisper.cpp 库
    ggml     # ggml 库
    android
    log
)
