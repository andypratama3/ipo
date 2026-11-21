import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Klien tipis untuk backend IPOS. Alamat & token disimpan di luar kelas ini
/// (di database lokal) supaya berganti server tidak perlu membuat ulang objek.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String _baseUrl = '';
  String _token = '';

  String get baseUrl => _baseUrl;
  String get token => _token;
  bool get isConfigured => _baseUrl.isNotEmpty;

  static String normalizeBase(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');

  void configure({required String baseUrl, required String token}) {
    _baseUrl = normalizeBase(baseUrl);
    _token = token.trim();
  }

  void setToken(String token) => _token = token.trim();

  Future<Map<String, dynamic>> get(String path) =>
      _send('GET', path, body: null);

  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, [Object? body]) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path, [Object? body]) =>
      _send('DELETE', path, body: body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_baseUrl.isEmpty) {
      throw ApiException('Alamat server belum diatur.');
    }
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token.isNotEmpty) headers['Authorization'] = 'Bearer $_token';

    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      final text = response.body;
      dynamic decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Backend mengirim { error: kode, message: teks manusia }. Dahulukan
        // `message` supaya pengguna melihat alasan yang bisa dibaca.
        final detail = decoded is Map
            ? (decoded['message']?.toString() ??
                decoded['error']?.toString() ??
                '')
            : '';
        throw ApiException(
          'HTTP ${response.statusCode}${detail.isEmpty ? '' : ' — $detail'}',
          status: response.statusCode,
        );
      }
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Server tidak merespons (waktu habis).');
    } catch (error) {
      throw ApiException('Tidak bisa menghubungi server. ${error.toString()}');
    }
  }

  void dispose() => _client.close();
}
