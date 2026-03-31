import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:docx_to_text/docx_to_text.dart';
import 'database_service.dart';

/// 文件导入服务
/// 处理PDF、Word、图片等文件的导入和文本提取
class FileImportService {
  static final FileImportService _instance = FileImportService._internal();
  factory FileImportService() => _instance;
  FileImportService._internal();

  final _databaseService = DatabaseService();
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  /// 导入文件
  Future<ImportResult?> importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'md', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;
      final filePath = file.path;

      if (filePath == null) {
        return ImportResult.success(
          message: '无法获取文件路径',
          extractedText: '',
        );
      }

      // 根据文件类型提取文本
      String extractedText = '';
      final extension = filePath.split('.').last.toLowerCase();

      switch (extension) {
        case 'pdf':
          extractedText = await _extractFromPdf(filePath);
          break;
        case 'doc':
        case 'docx':
          extractedText = await _extractFromWord(filePath);
          break;
        case 'txt':
        case 'md':
          extractedText = await _extractFromText(filePath);
          break;
        case 'jpg':
        case 'jpeg':
        case 'png':
          extractedText = await _extractFromImage(filePath);
          break;
        default:
          return ImportResult.error('不支持的文件类型: $extension');
      }

      // 保存到数据库
      final importedFile = {
        'file_name': file.name,
        'file_path': filePath,
        'file_type': extension,
        'extracted_text': extractedText,
        'imported_at': DateTime.now().millisecondsSinceEpoch,
      };

      await _databaseService.insertImportedFile(importedFile);

      return ImportResult.success(
        message: '文件导入成功',
        fileName: file.name,
        extractedText: extractedText,
      );
    } catch (e) {
      return ImportResult.error('导入失败: $e');
    }
  }

  /// 从PDF提取文本（暂禁用，等待pdf_text插件更新）
  Future<String> _extractFromPdf(String filePath) async {
    // 由于 pdf_text 插件与 Android Gradle Plugin 8.0+ 存在兼容性问题
    // 暂时禁用 PDF 文本提取功能
    // TODO: 寻找替代方案或等待插件更新
    return '[PDF功能暂不可用]\n\n'
        '由于技术兼容性问题，PDF文本提取功能暂时禁用。\n'
        '建议：\n'
        '1. 将PDF转换为图片后导入，使用OCR识别\n'
        '2. 复制PDF中的文本粘贴到文字笔记\n'
        '3. 等待后续版本更新';
  }

  /// 从Word文档提取文本
  Future<String> _extractFromWord(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return 'Word文件不存在';
      }

      // 读取文件字节
      final bytes = await file.readAsBytes();

      // 使用docx_to_text解析
      final text = docxToText(bytes, handleNumbering: true);

      if (text.trim().isEmpty) {
        return 'Word文档内容为空';
      }

      // 限制文本长度
      final maxLength = 50000;
      if (text.length > maxLength) {
        return '${text.substring(0, maxLength)}\n\n[内容过长，已截断]';
      }

      return text;
    } catch (e) {
      print('Word解析失败: $e');
      return 'Word解析失败: $e';
    }
  }

  /// 从文本文件提取内容
  Future<String> _extractFromText(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return '';
  }

  /// 从图片OCR提取文本
  Future<String> _extractFromImage(String filePath) async {
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      return 'OCR识别失败: $e';
    }
  }

  /// 释放资源
  void dispose() {
    _textRecognizer.close();
  }
}

/// 导入结果
class ImportResult {
  final bool success;
  final String message;
  final String? fileName;
  final String? extractedText;

  ImportResult({
    required this.success,
    required this.message,
    this.fileName,
    this.extractedText,
  });

  factory ImportResult.success({
    required String message,
    String? fileName,
    String? extractedText,
  }) {
    return ImportResult(
      success: true,
      message: message,
      fileName: fileName,
      extractedText: extractedText,
    );
  }

  factory ImportResult.error(String message) {
    return ImportResult(
      success: false,
      message: message,
    );
  }
}
