import 'package:flutter/material.dart';
import '../services/data_export_service.dart';

/// 数据导出设置区块
///
/// 让用户可以导出使用数据用于备份或分享优化建议
class DataExportSection extends StatefulWidget {
  const DataExportSection({super.key});

  @override
  State<DataExportSection> createState() => _DataExportSectionState();
}

class _DataExportSectionState extends State<DataExportSection> {
  final DataExportService _exportService = DataExportService();
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.download,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '数据导出',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '导出您的使用数据，可用于备份或分享给开发者获取个性化优化建议。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            _buildExportOption(
              icon: Icons.analytics,
              title: '导出统计数据',
              subtitle: '仅导出使用统计摘要，无敏感内容',
              onTap: () => _handleExport(() => _exportService.exportStatsSummary()),
            ),
            const Divider(height: 24),
            _buildExportOption(
              icon: Icons.calendar_today,
              title: '导出最近7天',
              subtitle: '导出最近一周的使用记录',
              onTap: () => _handleExport(() => _exportService.exportRecentData(anonymize: false)),
            ),
            const Divider(height: 24),
            _buildExportOption(
              icon: Icons.privacy_tip,
              title: '导出匿名数据（推荐）',
              subtitle: '移除姓名、地址等敏感信息，适合分享优化建议',
              onTap: () => _handleExport(() => _exportService.exportForOptimization()),
              isRecommended: true,
            ),
            const Divider(height: 24),
            _buildExportOption(
              icon: Icons.folder_zip,
              title: '导出全部数据',
              subtitle: '包含所有录音、笔记等完整数据',
              onTap: () => _handleExport(() => _exportService.exportAllData()),
            ),
            if (_isExporting) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isRecommended = false,
  }) {
    return InkWell(
      onTap: _isExporting ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isRecommended
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isRecommended
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '推荐',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleExport(Future<DataExportResult> Function() exportFunc) async {
    setState(() => _isExporting = true);

    try {
      final result = await exportFunc();

      if (!mounted) return;

      if (result.success) {
        _showExportSuccessDialog(result);
      } else {
        _showErrorSnackBar(result.errorMessage ?? '导出失败');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('导出出错: $e');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showExportSuccessDialog(DataExportResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.check_circle,
          color: Theme.of(context).colorScheme.primary,
          size: 48,
        ),
        title: const Text('导出成功'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件名: ${result.fileName}'),
            const SizedBox(height: 8),
            Text('记录数: ${result.recordCount}'),
            Text('文件大小: ${result.dataSizeFormatted}'),
            const SizedBox(height: 16),
            const Text(
              '您可以选择：',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '• 分享给开发者获取优化建议\n• 保存到安全位置备份\n• 通过邮件发送给自己',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后分享'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _exportService.shareExportedFile(
                result.filePath!,
                subject: 'MemoryPal 数据导出',
              );
            },
            icon: const Icon(Icons.share),
            label: const Text('立即分享'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
