import 'package:dio/dio.dart';
import '../models/dtos.dart';

class AuthApi {
  final Dio _dio;

  AuthApi(this._dio);

  Future<TokenResponse> login({required String username, required String password}) async {
    final resp = await _dio.post('/auth/login', data: {'username': username, 'password': password});
    return TokenResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<TokenResponse> refresh({required String refreshToken}) async {
    final resp = await _dio.post('/auth/refresh', data: {'refreshToken': refreshToken});
    return TokenResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> logout({required String refreshToken}) async {
    await _dio.post('/auth/logout', data: {'refreshToken': refreshToken});
  }
}
