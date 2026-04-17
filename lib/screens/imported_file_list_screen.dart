import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/database_service.dart';

/// 导入文件列表页面 - 支持批量删除
class ImportedFileListScreen extends StatefulWidget {
  const ImportedFileListScreen({super.key});

  @override
  State<ImportedFileListScreen> createState() => _ImportedFileListScreenState();
}

class _ImportedFileListScreenState extends State<ImportedFileListScreen> {
  final _databaseService = DatabaseService();
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;

  // 批量选择模式
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    try {
      final files = await _databaseService.getImportedFiles(limit: 1000);
      if (mounted) {
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载导入文件失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_files.map((f) => f['id'] as int));
    });
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认批量删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个导入文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 删除实际文件
      for (final id in _selectedIds) {
        final file = _files.firstWhere((f) => f['id'] == id, orElse: () => {});
        if (file.isNotEmpty) {
          final filePath = file['file_path'] as String?;
          if (filePath != null) {
            try {
              final f = File(filePath);
              if (await f.exists()) {
                await f.delete();
              }
            } catch (e) {
              debugPrint('删除文件失败: $e');
            }
          }
        }
      }
      await _databaseService.deleteImportedFiles(_selectedIds.toList());
      _exitSelectionMode();
      _loadFiles();
    }
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这个导入文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final id = file['id'] as int;
      final filePath = file['file_path'] as String?;
      if (filePath != null) {
        try {
          final f = File(filePath);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (e) {
          debugPrint('删除文件失败: $e');
        }
      }
      await _databaseService.deleteImportedFile(id);
      _loadFiles();
    }
  }

  Future<void> _showFileOptions(Map<String, dynamic> file) async {
    final filePath = file['file_path'] as String?;
    final fileName = file['file_name'] as String? ?? '未知文件';
    final extractedText = file['extracted_text'] as String?;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '路径: $filePath',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制路径'),
                onTap: () {
                  if (filePath != null) {
                    Clipboard.setData(ClipboardData(text: filePath));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('路径已复制到剪贴板')),
                    );
                  }
                },
              ),
              if (extractedText != null && extractedText.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.text_snippet),
                  title: const Text('查看提取的文本'),
                  onTap: () {
                    Navigator.pop(context);
                    _showExtractedText(fileName, extractedText);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('删除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteFile(file);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExtractedText(String fileName, String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fileName),
        content: SingleChildScrollView(
          child: Text(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('已选中 ${_selectedIds.length} 项')
            : const Text('导入文件管理'),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: [
          if (_isSelectionMode) ...[
            TextButton(
              onPressed: _selectAll,
              child: const Text('全选'),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteSelectedFiles,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadFiles,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? _buildEmptyState()
              : _buildFileList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '还没有导入的文件',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            '在首页点击"导入文件"添加',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    final groupedFiles = _groupFilesByDate();

    return RefreshIndicator(
      onRefresh: _loadFiles,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groupedFiles.length,
        itemBuilder: (context, index) {
          final group = groupedFiles[index];
          return _buildDateGroup(group);
        },
      ),
    );
  }

  List<_DateGroup> _groupFilesByDate() {
    final groups = <_DateGroup>[];
    DateTime? currentDate;
    List<Map<String, dynamic>> currentGroup = [];

    for (final file in _files) {
      final importedAt = DateTime.fromMillisecondsSinceEpoch(file['imported_at'] as int);
      final date = DateTime(importedAt.year, importedAt.month, importedAt.day);

      if (currentDate == null || currentDate != date) {
        if (currentGroup.isNotEmpty) {
          groups.add(_DateGroup(currentDate!, currentGroup));
        }
        currentDate = date;
        currentGroup = [file];
      } else {
        currentGroup.add(file);
      }
    }

    if (currentGroup.isNotEmpty && currentDate != null) {
      groups.add(_DateGroup(currentDate, currentGroup));
    }

    return groups;
  }

  Widget _buildDateGroup(_DateGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8, bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatDateHeader(group.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.purple,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.files.length}个文件',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        ...group.files.map((f) => _buildFileCard(f)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFileCard(Map<String, dynamic> file) {
    final fileType = file['file_type'] as String? ?? 'unknown';
    final fileName = file['file_name'] as String? ?? '未知文件';
    final id = file['id'] as int;
    final isSelected = _selectedIds.contains(id);

    final iconData = _getFileIcon(fileType);
    final iconColor = _getFileColor(fileType);

    Widget cardContent = Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isSelectionMode
            ? () => _toggleSelection(id)
            : () => _showFileOptions(file),
        onLongPress: !_isSelectionMode
            ? () => _toggleSelection(id)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(id),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(iconData, color: iconColor, size: 24),
                ),
              if (!_isSelectionMode) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fileType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isSelectionMode)
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                ),
            ],
          ),
        ),
      ),
    );

    if (_isSelectionMode) {
      return cardContent;
    }

    return Dismissible(
      key: Key('imported_file_$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteFile(file),
      child: cardContent,
    );
  }

  IconData _getFileIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
      case 'md':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'txt':
      case 'md':
        return Colors.grey.shade700;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.green;
      default:
        return Colors.purple;
    }
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return '今天';
    } else if (dateToCheck == yesterday) {
      return '昨天';
    } else {
      return '${date.month}月${date.day}日 ${['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday - 1]}';
    }
  }
}

class _DateGroup {
  final DateTime date;
  final List<Map<String, dynamic>> files;

  _DateGroup(this.date, this.files);
}
