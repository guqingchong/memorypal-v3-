# Whisper.cpp 快速设置脚本
# 运行方式: PowerShell -ExecutionPolicy Bypass -File setup_whisper.ps1

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MemoryPal - Whisper.cpp 设置脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ProjectDir = "D:\Claudeworkplace\memorypal_v3"
$WhisperDir = "$ProjectDir\whisper.cpp"
$ModelFile = "$WhisperDir\ggml-small.bin"

# 检查项目目录
if (-not (Test-Path $ProjectDir)) {
    Write-Error "项目目录不存在: $ProjectDir"
    exit 1
}

Set-Location $ProjectDir

# 1. 克隆 whisper.cpp
Write-Host "[1/4] 检查 whisper.cpp..." -ForegroundColor Yellow

if (Test-Path $WhisperDir) {
    Write-Host "  ✓ whisper.cpp 已存在" -ForegroundColor Green
} else {
    Write-Host "  正在克隆 whisper.cpp..." -ForegroundColor Gray
    git clone https://github.com/ggerganov/whisper.cpp.git
    if ($LASTEXITCODE -ne 0) {
        Write-Error "克隆失败"
        exit 1
    }
    Write-Host "  ✓ 克隆成功" -ForegroundColor Green
}

# 2. 下载模型
Write-Host ""
Write-Host "[2/4] 检查模型文件..." -ForegroundColor Yellow

Set-Location $WhisperDir

if (Test-Path $ModelFile) {
    $Size = (Get-Item $ModelFile).Length / 1MB
    Write-Host "  ✓ 模型已存在: $([math]::Round($Size, 1)) MB" -ForegroundColor Green
} else {
    Write-Host "  正在下载 ggml-small.bin (244MB)..." -ForegroundColor Gray
    Write-Host "  这可能需要几分钟..." -ForegroundColor Gray

    try {
        Invoke-WebRequest `
            -Uri "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin" `
            -OutFile $ModelFile `
            -MaximumRetryCount 3

        $Size = (Get-Item $ModelFile).Length / 1MB
        Write-Host "  ✓ 下载成功: $([math]::Round($Size, 1)) MB" -ForegroundColor Green
    } catch {
        Write-Error "下载失败: $_"
        Write-Host ""
        Write-Host "请手动下载:"
        Write-Host "1. 访问 https://huggingface.co/ggerganov/whisper.cpp/tree/main"
        Write-Host "2. 下载 ggml-small.bin"
        Write-Host "3. 复制到: $WhisperDir"
        exit 1
    }
}

# 3. 验证文件
Write-Host ""
Write-Host "[3/4] 验证文件..." -ForegroundColor Yellow

$RequiredFiles = @(
    "$WhisperDir\whisper.h",
    "$WhisperDir\whisper.cpp",
    "$WhisperDir\ggml.h"
)

$MissingFiles = @()
foreach ($File in $RequiredFiles) {
    if (-not (Test-Path $File)) {
        $MissingFiles += $File
    }
}

if ($MissingFiles.Count -eq 0) {
    Write-Host "  ✓ 所有文件完整" -ForegroundColor Green
} else {
    Write-Warning "以下文件缺失:"
    $MissingFiles | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}

# 4. 显示下一步
Write-Host ""
Write-Host "[4/4] 设置完成!" -ForegroundColor Green
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "下一步操作:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. 完成 Android JNI 实现:"
Write-Host "   编辑: android/app/src/main/cpp/whisper/whisper_jni.cpp"
Write-Host "   参考: whisper.cpp/examples/main/main.cpp"
Write-Host ""
Write-Host "2. 修改 CMakeLists.txt 链接 whisper:"
Write-Host "   编辑: android/app/src/main/cpp/CMakeLists.txt"
Write-Host "   添加: add_subdirectory(whisper.cpp)"
Write-Host ""
Write-Host "3. 构建测试:"
Write-Host "   flutter build apk --debug"
Write-Host ""
Write-Host "详细指南: docs/WHISPER_INTEGRATION_GUIDE.md"
Write-Host ""
