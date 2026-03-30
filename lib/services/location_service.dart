import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'database_service.dart';

// 位置服务 - 采集位置信息并缓存地址
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final _databaseService = DatabaseService();
  Position? _lastPosition;
  Timer? _locationTimer;

  // 速度阈值 (m/s)
  static const double _speedThreshold = 1.0;

  // 采集间隔
  static const Duration _movingInterval = Duration(minutes: 5);
  static const Duration _stationaryInterval = Duration(minutes: 30);

  // 当前位置流
  final _positionController = StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionController.stream;

  // 初始化
  Future<void> initialize() async {
    // 检查位置服务是否启用
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('位置服务未启用');
    }

    // 检查权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('位置权限被拒绝');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('位置权限被永久拒绝');
    }
  }

  // 开始位置采集
  Future<void> startLocationTracking() async {
    await initialize();

    // 立即获取一次位置
    await _updateLocation();

    // 启动定时采集
    _scheduleNextUpdate();
  }

  // 停止位置采集
  void stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  // 调度下一次更新
  void _scheduleNextUpdate() {
    _locationTimer?.cancel();

    // 根据移动状态决定间隔
    final interval = _isMoving() ? _movingInterval : _stationaryInterval;

    _locationTimer = Timer(interval, () async {
      await _updateLocation();
      _scheduleNextUpdate();
    });
  }

  // 判断是否正在移动
  bool _isMoving() {
    if (_lastPosition == null) return true;
    return _lastPosition!.speed > _speedThreshold;
  }

  // 更新位置
  Future<void> _updateLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      _lastPosition = position;
      _positionController.add(position);

      // 触发地址解析（异步，不阻塞）
      _resolveAddress(position.latitude, position.longitude);
    } catch (e) {
      print('获取位置失败: $e');
    }
  }

  // 解析地址（带缓存）
  Future<String?> _resolveAddress(double lat, double lon) async {
    // 先检查缓存
    final cached = await _databaseService.getCachedAddress(lat, lon);
    if (cached != null) {
      return cached;
    }

    try {
      // 使用反向地理编码
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = '${place.street}, ${place.locality}, ${place.administrativeArea}';

        // 缓存地址
        await _databaseService.cacheAddress(
          lat,
          lon,
          address,
          placeName: place.name,
          placeType: _inferPlaceType(place),
        );

        return address;
      }
    } catch (e) {
      print('反向地理编码失败: $e');
    }

    return null;
  }

  // 推断地点类型
  String? _inferPlaceType(Placemark place) {
    final name = place.name?.toLowerCase() ?? '';
    final street = place.street?.toLowerCase() ?? '';

    // 简单的启发式规则
    if (name.contains('home') || name.contains('家')) return 'home';
    if (name.contains('work') || name.contains('公司') || name.contains('office')) return 'work';
    if (street.contains('gym') || street.contains('健身')) return 'gym';
    if (street.contains('restaurant') || street.contains('餐厅')) return 'restaurant';

    return 'other';
  }

  // 获取当前位置（同步）
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
    } catch (e) {
      print('获取当前位置失败: $e');
      return null;
    }
  }

  // 获取当前位置并解析地址
  Future<LocationInfo?> getCurrentLocationInfo() async {
    final position = await getCurrentPosition();
    if (position == null) return null;

    final address = await _resolveAddress(position.latitude, position.longitude);

    return LocationInfo(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
      timestamp: DateTime.now(),
    );
  }

  // 释放资源
  void dispose() {
    stopLocationTracking();
    _positionController.close();
  }
}

// 位置信息
class LocationInfo {
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime timestamp;

  LocationInfo({
    required this.latitude,
    required this.longitude,
    this.address,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}
