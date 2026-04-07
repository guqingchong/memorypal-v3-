import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/recording_service.dart';
import 'services/database_service.dart';
import 'services/deepseek_service.dart';
import 'services/siliconflow_service.dart';
import 'services/ai_service_manager.dart';
import 'services/notification_service.dart';
import 'services/scheduler_service.dart';
import 'services/smart_reminder_engine.dart';
import 'services/developer_service.dart';
import 'services/kimi_service.dart';
import 'services/settings_service.dart';
import 'services/notification_router.dart';

Future<void> main() async {
  // 在Zone内完成所有初始化，避免Zone mismatch错误
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 初始化开发者服务
      final developerService = DeveloperService();
      developerService.initialize();

      // 初始化设置服务
      final settingsService = SettingsService();
      await settingsService.initialize();

      // 初始化AI服务管理器
      final aiManager = AIServiceManager();
      await aiManager.initialize();
      developerService.log('AI服务管理器已初始化，当前提供商: ${aiManager.currentProviderName}', tag: 'AppInit');

      // 兼容旧版本：加载Kimi API Key
      final kimiApiKey = await settingsService.getKimiApiKey();
      if (kimiApiKey != null && kimiApiKey.isNotEmpty) {
        KimiService().initialize(apiKey: kimiApiKey);
        developerService.log('Kimi服务已初始化', tag: 'AppInit');
      }

      // 加载其他AI服务的API Key (从SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      final deepseekApiKey = prefs.getString('deepseek_api_key');
      if (deepseekApiKey != null && deepseekApiKey.isNotEmpty) {
        DeepSeekService().initialize(apiKey: deepseekApiKey);
        developerService.log('DeepSeek服务已初始化', tag: 'AppInit');
      }

      final siliconflowApiKey = prefs.getString('siliconflow_api_key');
      if (siliconflowApiKey != null && siliconflowApiKey.isNotEmpty) {
        SiliconFlowService().initialize(apiKey: siliconflowApiKey);
        developerService.log('SiliconFlow服务已初始化', tag: 'AppInit');
      }

      // 捕获全局错误
      FlutterError.onError = (FlutterErrorDetails details) {
        developerService.log(
          'Flutter错误: \${details.exception}',
          level: LogLevel.error,
          tag: 'Flutter',
          error: details.exception,
          stackTrace: details.stack,
        );
        FlutterError.presentError(details);
      };

      // 捕获异步错误
      PlatformDispatcher.instance.onError = (error, stack) {
        developerService.log(
          '平台错误: \$error',
          level: LogLevel.error,
          tag: 'Platform',
          error: error,
          stackTrace: stack,
        );
        return true;
      };

      runApp(const MyApp());
    },
    (error, stack) {
      // Zone级别的错误捕获
      DeveloperService().log(
        '未捕获错误: \$error',
        level: LogLevel.error,
        tag: 'Zone',
        error: error,
        stackTrace: stack,
      );
    },
  )!;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // 设置通知路由的导航键
    NotificationRouter().setNavigatorKey(_navigatorKey);
    // 设置通知点击回调
    NotificationService().onNotificationTap = (payload) {
      NotificationRouter().handleNotificationTap(payload);
    };
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => DatabaseService()),
        Provider(create: (_) => RecordingService()..initialize()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'MemoryPal',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const AppInitializer(),
      ),
    );
  }
}

// 应用初始化器 - 检查首次启动
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isLoading = true;
  bool _isFirstLaunch = true;
  final _developerService = DeveloperService();

  @override
  void initState() {
    super.initState();
    _developerService.log('应用初始化开始', level: LogLevel.info, tag: 'AppInit');
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 初始化通知服务（失败不阻塞）
    try {
      _developerService.log('初始化通知服务...', tag: 'AppInit');
      await NotificationService().initialize();
      _developerService.log('通知服务初始化成功', tag: 'AppInit');
    } catch (e, stack) {
      _developerService.log(
        '通知服务初始化失败',
        level: LogLevel.error,
        tag: 'AppInit',
        error: e,
        stackTrace: stack,
      );
    }

    // 初始化定时任务调度器（失败不阻塞）
    try {
      _developerService.log('初始化调度器...', tag: 'AppInit');
      await SchedulerService().initialize();
      _developerService.log('调度器初始化成功', tag: 'AppInit');
    } catch (e, stack) {
      _developerService.log(
        '调度器初始化失败',
        level: LogLevel.error,
        tag: 'AppInit',
        error: e,
        stackTrace: stack,
      );
    }

    // 初始化智能提醒引擎（失败不阻塞）
    try {
      _developerService.log('初始化提醒引擎...', tag: 'AppInit');
      await SmartReminderEngine().initialize();
      _developerService.log('提醒引擎初始化成功', tag: 'AppInit');
    } catch (e, stack) {
      _developerService.log(
        '提醒引擎初始化失败',
        level: LogLevel.error,
        tag: 'AppInit',
        error: e,
        stackTrace: stack,
      );
    }

    // 检查是否首次启动
    try {
      final prefs = await SharedPreferences.getInstance();
      _isFirstLaunch = prefs.getBool('hasSeenOnboarding') != true;
      _developerService.log(
        '首选项检查完成，首次启动: \$_isFirstLaunch',
        tag: 'AppInit',
      );
    } catch (e, stack) {
      _developerService.log(
        '读取首选项失败',
        level: LogLevel.error,
        tag: 'AppInit',
        error: e,
        stackTrace: stack,
      );
      _isFirstLaunch = true;
    }

    await Future.delayed(const Duration(milliseconds: 500));

    _developerService.log('应用初始化完成', level: LogLevel.info, tag: 'AppInit');

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);

    setState(() {
      _isFirstLaunch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Material(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('加载中...'),
            ],
          ),
        ),
      );
    }

    if (_isFirstLaunch) {
      return OnboardingScreen(onComplete: _onOnboardingComplete);
    }

    return const HomeScreen();
  }
}
