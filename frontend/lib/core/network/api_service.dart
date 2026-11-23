import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, [this.statusCode = 500]);

  @override
  String toString() => message;
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  String? get token => _token;

  Map<String, String> _headers({Map<String, String>? extra}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Future<dynamic> post(String url, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers(),
        body: jsonEncode(body),
      );
      return _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      // Automatic fallback for web: try 127.0.0.1 if localhost failed, or proxy
      if (url.contains('localhost:5001')) {
        try {
          final fallbackUrl = url.replaceAll('localhost:5001', '127.0.0.1:5001');
          final response = await http.post(
            Uri.parse(fallbackUrl),
            headers: _headers(),
            body: jsonEncode(body),
          );
          return _processResponse(response);
        } catch (e2) {
          if (e2 is ApiException) rethrow;
          try {
            final proxyUrl = url.replaceAll('http://localhost:5001', '');
            final response = await http.post(
              Uri.parse(proxyUrl),
              headers: _headers(),
              body: jsonEncode(body),
            );
            return _processResponse(response);
          } catch (e3) {
            if (e3 is ApiException) rethrow;
          }
        }
      }
      throw ApiException('Network connection failed. Make sure the backend server is running.');
    }
  }

  Future<dynamic> get(String url) async {
    try {
      final response = await http.get(Uri.parse(url), headers: _headers());
      return _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      if (url.contains('localhost:5001')) {
        try {
          final fallbackUrl = url.replaceAll('localhost:5001', '127.0.0.1:5001');
          final response = await http.get(Uri.parse(fallbackUrl), headers: _headers());
          return _processResponse(response);
        } catch (e2) {
          if (e2 is ApiException) rethrow;
          try {
            final proxyUrl = url.replaceAll('http://localhost:5001', '');
            final response = await http.get(Uri.parse(proxyUrl), headers: _headers());
            return _processResponse(response);
          } catch (e3) {
            if (e3 is ApiException) rethrow;
          }
        }
      }
      throw ApiException('Network connection failed. Make sure the backend server is running.');
    }
  }

  Future<Uint8List> getBytes(String url) async {
    final response = await http.get(Uri.parse(url), headers: _headers());
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw ApiException('Download failed with status: ${response.statusCode}', response.statusCode);
  }

  Future<dynamic> put(String url, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
        Uri.parse(url),
        headers: _headers(),
        body: jsonEncode(body),
      );
      return _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network connection failed.');
    }
  }

  Future<dynamic> patch(String url, [Map<String, dynamic>? body]) async {
    try {
      final response = await http.patch(
        Uri.parse(url),
        headers: _headers(),
        body: body != null ? jsonEncode(body) : null,
      );
      return _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network connection failed.');
    }
  }

  Future<dynamic> delete(String url) async {
    try {
      final response = await http.delete(Uri.parse(url), headers: _headers());
      return _processResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network connection failed.');
    }
  }

  dynamic _processResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = response.body;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    } else {
      String errMsg = 'Request failed with status: ${response.statusCode}';
      if (decoded is Map && decoded.containsKey('error')) {
        errMsg = decoded['error'].toString();
      } else if (decoded is Map && decoded.containsKey('message')) {
        errMsg = decoded['message'].toString();
      }
      throw ApiException(errMsg, response.statusCode);
    }
  }
}
