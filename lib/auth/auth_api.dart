import 'dart:convert';
import 'package:dio/dio.dart';

import '../models/dtos.dart';

class AuthApi {
  final Dio _dio;

  AuthApi(this._dio);

  Future<TokenResponse> login({required String username, required String password}) async {
    final resp = await _dio.post(
      '/auth/login',
      data: {'username': username, 'password': password},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return TokenResponse.fromJson(_asMap(resp.data));
  }

  Future<TokenResponse> refresh({required String refreshToken}) async {
    final resp = await _dio.post(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return TokenResponse.fromJson(_asMap(resp.data));
  }

  Future<void> logout({required String refreshToken}) async {
    await _dio.post(
      '/auth/logout',
      data: {'refreshToken': refreshToken},
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    throw StateError('Unerwartetes Response-Format: ${data.runtimeType}');
  }
}
