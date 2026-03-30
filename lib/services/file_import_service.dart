import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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

  /// 从PDF提取文本（简化版，实际需要PDF解析库）
  Future<String> _extractFromPdf(String filePath) async {
    // TODO: 集成PDF解析库（如pdf_text或pdfx）
    // 暂时返回文件名作为占位
    return 'PDF文件: ${filePath.split('/').last}\n（需要集成PDF解析库）';
  }

  /// 从Word文档提取文本
  Future<String> _extractFromWord(String filePath) async {
    // TODO: 集成docx解析库
    return 'Word文件: ${filePath.split('/').last}\n（需要集成Word解析库）';
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
