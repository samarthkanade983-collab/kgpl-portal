import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/api_config.dart';
import '../core/network/api_service.dart';
import 'auth_provider.dart';

class NotificationProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  Timer? _pollTimer;
  int? _userId;
  bool _disposed = false;

  List<Map<String, dynamic>> _announcements = [];
  int _unreadCount = 0;
  int _lastSeenAnnouncementId = 0;
  Map<String, dynamic>? _bannerAnnouncement;
  bool _isFetching = false;

  List<Map<String, dynamic>> get announcements => _announcements;
  int get unreadCount => _unreadCount;
  Map<String, dynamic>? get bannerAnnouncement => _bannerAnnouncement;
  bool get hasUnread =>
      _unreadCount > 0 ||
      (_announcements.isNotEmpty && (_announcements.first['id'] as int) > _lastSeenAnnouncementId);

  void syncAuth(AuthProvider auth) {
    final user = auth.currentUser;
    if (user == null) {
      if (_userId != null) {
        _userId = null;
        _pollTimer?.cancel();
        _pollTimer = null;
        _announcements = [];
        _unreadCount = 0;
        _lastSeenAnnouncementId = 0;
        _bannerAnnouncement = null;
        Future.microtask(_notify);
      }
      return;
    }
    if (_userId == user.id) return;
    _userId = user.id;
    _announcements = [];
    _unreadCount = 0;
    _bannerAnnouncement = null;
    _loadLastSeen().then((_) => refresh());
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> _loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSeenAnnouncementId = prefs.getInt('kgpl_last_seen_announcement_$_userId') ?? 0;
  }

  Future<void> _saveLastSeen(int id) async {
    _lastSeenAnnouncementId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('kgpl_last_seen_announcement_$_userId', id);
  }

  Future<void> refresh() async {
    if (_userId == null || _isFetching) return;
    _isFetching = true;
    try {
      final results = await Future.wait([
        _api.get(ApiConfig.announcements),
        _api.get(ApiConfig.notifications),
      ]);
      if (_disposed || _userId == null) return;

      final annList = (results[0]['announcements'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final previousTopId = _announcements.isNotEmpty ? (_announcements.first['id'] as int) : 0;
      _announcements = annList;
      _unreadCount = (results[1]['unread_count'] as num?)?.toInt() ?? 0;

      if (annList.isNotEmpty) {
        final topId = annList.first['id'] as int;
        final isNew = topId > _lastSeenAnnouncementId && topId > previousTopId;
        if (isNew && _bannerAnnouncement == null) {
          _bannerAnnouncement = annList.first;
        } else if (_bannerAnnouncement == null && previousTopId == 0 && topId > _lastSeenAnnouncementId) {
          _bannerAnnouncement = annList.first;
        }
      }
      _notify();
    } catch (_) {
      // Polling is best-effort; keep previous state on transient failures.
    } finally {
      _isFetching = false;
    }
  }

  Future<void> markAllRead() async {
    if (_userId == null) return;
    if (_announcements.isNotEmpty) {
      await _saveLastSeen(_announcements.first['id'] as int);
    }
    _bannerAnnouncement = null;
    final hadUnread = _unreadCount > 0;
    _unreadCount = 0;
    _notify();
    if (hadUnread) {
      try {
        await _api.post(ApiConfig.notificationsMarkRead, {});
      } catch (_) {}
    }
  }

  void dismissBanner() {
    final banner = _bannerAnnouncement;
    _bannerAnnouncement = null;
    if (banner != null) {
      final id = banner['id'] as int;
      if (id > _lastSeenAnnouncementId) {
        _saveLastSeen(id);
      }
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}