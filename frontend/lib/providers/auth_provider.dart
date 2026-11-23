import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/api_config.dart';
import '../core/models/user_model.dart';
import '../core/network/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  UserModel? _currentUser;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = false;
  String? _errorMessage;
  String _activeView = 'dashboard';
  int? _activeCourseId;
  int? _activeCourseModuleTestId;
  int? _activeTestScheduleId;
  String? _rememberedEmail;

  UserModel? get currentUser => _currentUser;
  String? get rememberedEmail => _rememberedEmail;
  String? get userRole => _currentUser?.role;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get activeView => _activeView;
  int? get activeCourseId => _activeCourseId;
  int? get activeCourseModuleTestId => _activeCourseModuleTestId;
  int? get activeTestScheduleId => _activeTestScheduleId;
  bool get isAuthenticated => _currentUser != null;

  void setActiveView(String view) {
    _activeView = view;
    notifyListeners();
  }

  void openCoursePlayer(int courseId) {
    _activeCourseId = courseId;
    _activeView = 'course_player';
    notifyListeners();
  }

  void openCourseModuleTest(int testId) {
    _activeCourseModuleTestId = testId;
    _activeView = 'course_module_test';
    notifyListeners();
  }

  void openTestRunner(int scheduleId) {
    _activeTestScheduleId = scheduleId;
    _activeView = 'test_runner';
    notifyListeners();
  }

  Future<void> initAuth() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberedEmail = prefs.getString('kgpl_remember_email');
    final token = prefs.getString('kgpl_jwt_token');
    final userJson = prefs.getString('kgpl_user_data');

    if (token != null && userJson != null) {
      try {
        _apiService.setToken(token);
        _currentUser = UserModel.fromJson(jsonDecode(userJson));
        await fetchProfile();
      } catch (_) {
        await logout();
      }
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password,
      {bool rememberMe = true}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.post(ApiConfig.login, {
        'email': email.trim(),
        'password': password,
      });

      final token = response['token'];
      final user = UserModel.fromJson(response['user']);

      _apiService.setToken(token);
      _currentUser = user;
      _activeView = 'dashboard';

      final prefs = await SharedPreferences.getInstance();
      if (rememberMe) {
        _rememberedEmail = email.trim();
        await prefs.setString('kgpl_remember_email', _rememberedEmail!);
        await prefs.setString('kgpl_jwt_token', token);
        await prefs.setString('kgpl_user_data', jsonEncode(user.toJson()));
      } else {
        _rememberedEmail = null;
        await prefs.remove('kgpl_remember_email');
        await prefs.remove('kgpl_jwt_token');
        await prefs.remove('kgpl_user_data');
      }

      await fetchProfile();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    String role = 'intern',
    int? departmentId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.post(ApiConfig.register, {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'role': role,
        if (departmentId != null) 'department_id': departmentId,
      });

      final token = response['token'];
      final user = UserModel.fromJson(response['user']);

      _apiService.setToken(token);
      _currentUser = user;
      _activeView = 'dashboard';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kgpl_jwt_token', token);
      await prefs.setString('kgpl_user_data', jsonEncode(user.toJson()));

      await fetchProfile();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchPublicDepartments() async {
    try {
      final res = await _apiService.get(ApiConfig.publicDepartments);
      if (res is Map && res['departments'] is List) {
        return (res['departments'] as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  Future<void> fetchProfile() async {
    try {
      final res = await _apiService.get(ApiConfig.me);
      if (res is Map && res.containsKey('profile')) {
        _userProfile = res['profile'];
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    _currentUser = null;
    _userProfile = null;
    _apiService.setToken(null);
    _activeView = 'dashboard';

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kgpl_jwt_token');
    await prefs.remove('kgpl_user_data');

    notifyListeners();
  }
}
