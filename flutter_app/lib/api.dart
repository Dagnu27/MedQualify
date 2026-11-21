import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl();

  String baseUrl;
  late final Dio dio;
  String? token;

  static String _defaultBaseUrl() {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:3001';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://127.0.0.1:3001';
    return 'http://127.0.0.1:3001';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('careaudit_token');
    final savedBase = prefs.getString('careaudit_base_url');
    if (savedBase != null && savedBase.isNotEmpty) {
      baseUrl = savedBase;
    }
    dio = Dio(BaseOptions(
      baseUrl: '$baseUrl/api',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (token != null && token!.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }));
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url;
    dio.options.baseUrl = '$url/api';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('careaudit_base_url', url);
  }

  Future<void> _persistToken(String? value) async {
    token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('careaudit_token');
    } else {
      await prefs.setString('careaudit_token', value);
    }
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
  }) async {
    try {
      final response = await dio.request<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(method: method),
      );
      return response.data ?? {};
    } on DioException catch (error) {
      throw _wrap(error);
    }
  }

  ApiException _wrap(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return ApiException(
        'Unable to connect to the account service. Keep the development server running and try again.',
      );
    }
    final data = error.response?.data;
    if (data is Map && data['error'] is String) {
      return ApiException(data['error'] as String, status: error.response?.statusCode);
    }
    return ApiException(
      'The account service could not complete that request.',
      status: error.response?.statusCode,
    );
  }

  Future<UserAccount?> me() async {
    try {
      final payload = await request('/auth/me');
      return UserAccount.fromJson(Map<String, dynamic>.from(payload['user'] as Map));
    } on ApiException catch (error) {
      if (error.status == 401) return null;
      rethrow;
    }
  }

  Future<UserAccount> login({
    required String role,
    required String username,
    required String password,
  }) async {
    final payload = await request(
      '/auth/login',
      method: 'POST',
      data: {'role': role, 'username': username, 'password': password},
    );
    await _persistToken(payload['token']?.toString());
    return UserAccount.fromJson(Map<String, dynamic>.from(payload['user'] as Map));
  }

  Future<void> logout() async {
    try {
      await request('/auth/logout', method: 'POST');
    } catch (_) {}
    await _persistToken(null);
  }

  Future<Map<String, dynamic>> adminOverview() => request('/admin/overview');

  Future<void> addInspector({
    required String name,
    required String username,
    required String password,
  }) async {
    await request(
      '/admin/inspectors',
      method: 'POST',
      data: {'name': name, 'username': username, 'password': password},
    );
  }

  Future<void> toggleInspector(String id, bool active) async {
    await request('/admin/inspectors/$id', method: 'PATCH', data: {'active': active});
  }

  Future<void> resetInspector(String id, String password) async {
    await request(
      '/admin/inspectors/$id/reset-password',
      method: 'POST',
      data: {'password': password},
    );
  }

  Future<UserAccount> updateAdmin(Map<String, dynamic> payload) async {
    final response = await request('/admin/profile', method: 'PUT', data: payload);
    return UserAccount.fromJson(Map<String, dynamic>.from(response['admin'] as Map));
  }

  Future<List<InspectionRecord>> inspections() async {
    final payload = await request('/inspections');
    final rows = payload['inspections'] as List<dynamic>? ?? [];
    return rows
        .map((row) => InspectionRecord.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> submitInspection(InspectionRecord record) async {
    await request('/inspections/submit', method: 'POST', data: {'record': record.toJson()});
  }

  Future<Uint8List> downloadReport(String recordId, String format) async {
    final path = format == 'pdf'
        ? '/inspections/${Uri.encodeComponent(recordId)}/pdf'
        : '/inspections/${Uri.encodeComponent(recordId)}/export/$format';
    try {
      final response = await dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 2)),
      );
      return Uint8List.fromList(response.data ?? []);
    } on DioException catch (error) {
      throw _wrap(error);
    }
  }
}
