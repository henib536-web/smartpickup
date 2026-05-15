import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../env.dart';

class UserApiService {
  final String baseUrl = Env.baseUrl;
  final storage = const FlutterSecureStorage();

  Future<Map<String, String>> _getHeaders() async {
    final token = await storage.read(key: 'access_token');
    return {
      ...Env.defaultHeaders,
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<Map<String, dynamic>>> getUserRides() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) throw Exception('User not logged in');

    final response = await http.get(
      Uri.parse('$baseUrl/rides/user/$userId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load rides: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) throw Exception('User not logged in');

    // Assuming there is a profile endpoint or we use the auth/me if available
    // For now, let's check if there is a specific user route
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load profile');
    }
  }
}
