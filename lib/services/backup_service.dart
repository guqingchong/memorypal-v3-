import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

/// 数据备份服务
/// 支持加密备份导出和导入恢复
class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  final DatabaseService _databaseService = DatabaseService();

  /// 导出所有数据为加密备份
  ///
  /// [password] 加密密码（可选）
  /// 返回备份文件路径
  Future<String?> exportBackup({String? password}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final backupDir = Directory('${tempDir.path}/backup_$timestamp');
      await backupDir.create(recursive: true);

      // 1. 导出SQLite数据库
      final dbPath = await _getDatabasePath();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.copy('${backupDir.path}/memorypal.db');
      }

      // 2. 导出设置JSON
      final settings = await _databaseService.getSettings();
      final settingsFile = File('${backupDir.path}/settings.json');
      await settingsFile.writeAsString(jsonEncode(settings));

      // 3. 导出元数据
      final metadata = {
        'version': 1,
        'timestamp': timestamp,
        'exported_at': DateTime.now().toIso8601String(),
        'has_password': password != null && password.isNotEmpty,
      };
      final metaFile = File('${backupDir.path}/metadata.json');
      await metaFile.writeAsString(jsonEncode(metadata));

      // 4. 打包为ZIP
      final zipPath = '${tempDir.path}/memorypal_backup_$timestamp.zip';
      await _createZip(backupDir.path, zipPath);

      // 5. 可选：加密ZIP
      final finalPath = password != null && password.isNotEmpty
          ? await _encryptFile(zipPath, password)
          : zipPath;

      // 6. 清理临时目录
      await backupDir.delete(recursive: true);
      if (password != null && password.isNotEmpty) {
        await File(zipPath).delete(); // 删除未加密的ZIP
      }

      return finalPath;
    } catch (e) {
      debugPrint('导出备份失败: $e');
      return null;
    }
  }

  /// 从备份文件恢复数据
  ///
  /// [backupPath] 备份文件路径
  /// [password] 解密密码（如果备份已加密）
  /// 返回是否恢复成功
  Future<bool> importBackup(String backupPath, {String? password}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extractDir = Directory('${tempDir.path}/restore_$timestamp');
      await extractDir.create(recursive: true);

      // 1. 可选：解密文件
      String? zipPath = backupPath;
      if (password != null && password.isNotEmpty) {
        zipPath = await _decryptFile(backupPath, password);
        if (zipPath == null) {
          throw Exception('解密失败，密码可能错误');
        }
      }

      // 2. 解压ZIP
      final success = await _extractZip(zipPath, extractDir.path);
      if (!success) {
        throw Exception('解压备份文件失败');
      }

      // 3. 验证元数据
      final metaFile = File('${extractDir.path}/metadata.json');
      if (!await metaFile.exists()) {
        throw Exception('备份文件损坏，缺少元数据');
      }
      final metadata = jsonDecode(await metaFile.readAsString());
      debugPrint('恢复备份版本: ${metadata['version']}');

      // 4. 恢复数据库
      final dbFile = File('${extractDir.path}/memorypal.db');
      if (await dbFile.exists()) {
        // 备份当前数据库
        final currentDbPath = await _getDatabasePath();
        final backupCurrent = File(currentDbPath);
        if (await backupCurrent.exists()) {
          await backupCurrent.copy('$currentDbPath.backup_${DateTime.now().millisecondsSinceEpoch}');
        }

        // 关闭当前数据库连接
        await _databaseService.close();

        // 替换数据库文件
        final currentDbFile = File(currentDbPath);
        await currentDbFile.delete();
        await dbFile.copy(currentDbPath);

        // 重新初始化数据库服务
        await _databaseService.database;
      }

      // 5. 清理临时文件
      await extractDir.delete(recursive: true);
      if (password != null && password.isNotEmpty && zipPath != backupPath) {
        await File(zipPath).delete();
      }

      return true;
    } catch (e) {
      debugPrint('导入备份失败: $e');
      return false;
    }
  }

  /// 选择备份文件并恢复
  Future<bool> pickAndRestoreBackup({String? password}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'mpb'], // mpb = MemoryPal Backup
      );

      if (result == null || result.files.single.path == null) {
        return false;
      }

      return await importBackup(result.files.single.path!, password: password);
    } catch (e) {
      debugPrint('选择备份文件失败: $e');
      return false;
    }
  }

  /// 分享备份文件
  Future<void> shareBackup(String backupPath) async {
    // 使用file_picker的saveFile让用户选择保存位置
    final fileName = path.basename(backupPath);
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '保存备份文件',
      fileName: fileName,
      allowedExtensions: ['zip', 'mpb'],
      type: FileType.custom,
    );

    if (result != null) {
      final sourceFile = File(backupPath);
      final targetFile = File(result);
      await sourceFile.copy(targetFile.path);
    }
  }

  /// 清除所有数据
  Future<void> clearAllData() async {
    // 1. 清除数据库
    final dbPath = await _getDatabasePath();
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await _databaseService.close();
      await dbFile.delete();
    }

    // 2. 清除录音文件
    final appDir = await getApplicationDocumentsDirectory();
    final recordingDir = Directory('${appDir.path}/recordings');
    if (await recordingDir.exists()) {
      await recordingDir.delete(recursive: true);
    }

    // 3. 清除导入的文件
    final importDir = Directory('${appDir.path}/imports');
    if (await importDir.exists()) {
      await importDir.delete(recursive: true);
    }

    // 4. 重新初始化数据库
    await _databaseService.database;
  }

  /// 获取数据库路径
  Future<String> _getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return path.join(dbPath, 'memorypal.db');
  }

  /// 创建ZIP压缩文件
  Future<void> _createZip(String sourceDir, String targetPath) async {
    final archive = Archive();
    final dir = Directory(sourceDir);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = path.relative(entity.path, from: sourceDir);
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      }
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData != null) {
      await File(targetPath).writeAsBytes(zipData);
    }
  }

  /// 解压ZIP文件
  Future<bool> _extractZip(String zipPath, String targetDir) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filePath = path.join(targetDir, file.name);
        if (file.isFile) {
          final data = file.content as List<int>;
          await File(filePath).create(recursive: true);
          await File(filePath).writeAsBytes(data);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }
      return true;
    } catch (e) {
      debugPrint('解压失败: $e');
      return false;
    }
  }

  /// 简单加密文件（使用XOR）
  /// 注意：这不是强加密，仅提供基本保护
  Future<String?> _encryptFile(String filePath, String password) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final passwordBytes = utf8.encode(password);
      final encrypted = _xorEncrypt(bytes, passwordBytes);

      final encryptedPath = '$filePath.enc';
      await File(encryptedPath).writeAsBytes(encrypted);

      return encryptedPath;
    } catch (e) {
      debugPrint('加密失败: $e');
      return null;
    }
  }

  /// 解密文件
  Future<String?> _decryptFile(String filePath, String password) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final passwordBytes = utf8.encode(password);
      final decrypted = _xorEncrypt(bytes, passwordBytes);

      final decryptedPath = filePath.endsWith('.enc')
          ? filePath.substring(0, filePath.length - 4)
          : '$filePath.dec';
      await File(decryptedPath).writeAsBytes(decrypted);

      return decryptedPath;
    } catch (e) {
      debugPrint('解密失败: $e');
      return null;
    }
  }

  /// XOR加密/解密（对称）
  List<int> _xorEncrypt(List<int> data, List<int> key) {
    final result = <int>[];
    for (var i = 0; i < data.length; i++) {
      result.add(data[i] ^ key[i % key.length]);
    }
    return result;
  }

  /// 获取备份文件信息
  Future<Map<String, dynamic>?> getBackupInfo(String backupPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory('${tempDir.path}/info_${DateTime.now().millisecondsSinceEpoch}');
      await extractDir.create(recursive: true);

      // 尝试解压（假设未加密）
      final success = await _extractZip(backupPath, extractDir.path);
      if (!success) {
        await extractDir.delete(recursive: true);
        return null;
      }

      final metaFile = File('${extractDir.path}/metadata.json');
      if (!await metaFile.exists()) {
        await extractDir.delete(recursive: true);
        return null;
      }

      final metadata = jsonDecode(await metaFile.readAsString());
      await extractDir.delete(recursive: true);

      return metadata;
    } catch (e) {
      debugPrint('获取备份信息失败: $e');
      return null;
    }
  }
}
