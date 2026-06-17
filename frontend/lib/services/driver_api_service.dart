import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../env.dart';

class DriverApiService {
  static String get baseUrl => "${Env.baseUrl}/api/driver";
  final _storage = const FlutterSecureStorage();

  // On suppose que le token est sauvegardé lors du login
  Future<Map<String, String>> _getHeaders() async {
    String? token = await _storage.read(key: 'access_token');
    return {
      ...Env.defaultHeaders,
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // --- Profil & Véhicule ---
  
  Future<int?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }
  
  Future<Map<String, dynamic>> getProfile() async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.get(Uri.parse('$baseUrl/profile/$userId'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load profile');
    }
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.put(
      Uri.parse('$baseUrl/profile/$userId'),
      headers: await _getHeaders(),
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update profile');
    }
  }

  Future<Map<String, dynamic>> getTaxi() async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.get(Uri.parse('$baseUrl/taxi/$userId'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load taxi info');
    }
  }

  Future<Map<String, dynamic>> updateStatus(bool isOnline) async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.put(
      Uri.parse('$baseUrl/status/$userId'),
      headers: await _getHeaders(),
      body: json.encode({'is_online': isOnline}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update status');
    }
  }

  Future<Map<String, dynamic>> updateLocation(double lat, double lng) async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.put(
      Uri.parse('$baseUrl/location/$userId'),
      headers: await _getHeaders(),
      body: json.encode({'lat': lat, 'lng': lng}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update location');
    }
  }

  // --- Courses ---

  Future<List<dynamic>> getAvailableRides() async {
    final userId = await _getUserId();
    final uri = Uri.parse('$baseUrl/rides/available').replace(
      queryParameters: userId != null ? {'driver_id': userId.toString()} : null
    );
    final response = await http.get(uri, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load available rides');
    }
  }

  Future<List<dynamic>> getAcceptedRides() async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.get(Uri.parse('$baseUrl/rides/accepted/$userId'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load accepted rides');
    }
  }

  Future<List<dynamic>> getDriverHistory() async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.get(Uri.parse('$baseUrl/rides/history/$userId'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load history');
    }
  }

  Future<Map<String, dynamic>> acceptRide(int requestId) async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final uri = Uri.parse('$baseUrl/rides/$requestId/accept')
        .replace(queryParameters: {'driver_id': userId.toString()});

    final response = await http.post(uri, headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to accept ride: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> cancelRide(int requestId) async {
    final response = await http.post(
      Uri.parse('${Env.baseUrl}/rides/$requestId/cancel'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to cancel ride');
    }
  }

  Future<Map<String, dynamic>> updateRideStatus(int requestId, String action) async {
    final response = await http.put(
      Uri.parse('$baseUrl/rides/$requestId/status'),
      headers: await _getHeaders(),
      body: json.encode({'action': action}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to update ride status');
    }
  }

  Future<Map<String, dynamic>?> getActiveRide() async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.get(Uri.parse('$baseUrl/rides/active/$userId'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      // FastAPI renvoie 'null' si l'endpoint retourne None
      if (jsonResponse == null) return null;
      return jsonResponse;
    } else {
      throw Exception('Failed to load active ride');
    }
  }

  Future<Map<String, dynamic>> getDriverStats() async {
    final userId = await _getUserId();
    if (userId == null) throw Exception("User ID not found");

    final response = await http.get(Uri.parse('$baseUrl/stats/$userId'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load driver stats');
    }
  }
}
