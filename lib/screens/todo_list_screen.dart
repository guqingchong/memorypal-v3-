import 'package:flutter/material.dart';
import '../services/database_service.dart';

/// 待办列表屏幕
class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<Map<String, dynamic>> _todos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTodos();
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);
    try {
      final todos = await _databaseService.getTodos(includeCompleted: true);
      setState(() {
        _todos = todos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('加载待办失败: $e');
    }
  }

  Future<void> _toggleTodo(int id, bool isCompleted) async {
    if (isCompleted) {
      await _databaseService.completeTodo(id);
    }
    _loadTodos();
  }

  Future<void> _deleteTodo(int id) async {
    await _databaseService.deleteTodo(id);
    _loadTodos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('待办事项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTodos,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _todos.isEmpty
              ? _buildEmptyState()
              : _buildTodoList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTodoDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '没有待办事项',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮添加',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _todos.length,
      itemBuilder: (context, index) {
        final todo = _todos[index];
        final isCompleted = todo['is_completed'] == 1;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Checkbox(
              value: isCompleted,
              onChanged: (value) => _toggleTodo(todo['id'], value ?? false),
            ),
            title: Text(
              todo['content'] ?? '',
              style: TextStyle(
                decoration: isCompleted ? TextDecoration.lineThrough : null,
                color: isCompleted ? Colors.grey : null,
              ),
            ),
            subtitle: todo['deadline'] != null
                ? Text(
                    '截止: ${_formatDeadline(todo['deadline'])}',
                    style: TextStyle(
                      color: _isOverdue(todo['deadline']) ? Colors.red : Colors.grey,
                    ),
                  )
                : null,
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteTodo(todo['id']),
            ),
          ),
        );
      },
    );
  }

  String _formatDeadline(int deadline) {
    final date = DateTime.fromMillisecondsSinceEpoch(deadline);
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  bool _isOverdue(int deadline) {
    return DateTime.fromMillisecondsSinceEpoch(deadline).isBefore(DateTime.now());
  }

  void _showAddTodoDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加待办'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入待办内容',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await _databaseService.insertTodo({
                  'content': controller.text,
                  'is_completed': 0,
                  'created_at': DateTime.now().millisecondsSinceEpoch,
                });
                if (mounted) {
                  Navigator.pop(context);
                  _loadTodos();
                }
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
