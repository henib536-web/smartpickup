import 'package:flutter/material.dart';
import 'package:test_windows/main.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:test_windows/env.dart';

// Top-level function to handle background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
}

class FCMService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  Future<void> init() async {
    // 1. Demander les permissions de notification
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');

    // 2. Gérer les messages en arrière-plan
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3. Gérer les messages au premier plan
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
        
        // Show visual SnackBar
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.notification?.title ?? "Notification",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(message.notification?.body ?? ""),
              ],
            ),
            backgroundColor: const Color(0xFF1a1a1a),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFFFCC00), width: 1.5),
            ),
            duration: const Duration(seconds: 4),
            margin: const EdgeInsets.only(top: 40, left: 20, right: 20),
            dismissDirection: DismissDirection.up,
            action: SnackBarAction(
              label: 'OK',
              textColor: const Color(0xFFFFCC00),
              onPressed: () {},
            ),
          ),
        );
      }
    });

    // 4. Obtenir le token FCM et l'envoyer au backend
    try {
      String? token = await _firebaseMessaging.getToken();
      print('FCM Token: $token');
      
      if (token != null) {
        await updateTokenOnBackend(token);
      }
    } catch (e) {
      print("Erreur lors de la récupération du token FCM : $e");
    }
    
    // 5. Écouter le rafraîchissement du token
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
       updateTokenOnBackend(newToken);
    });
  }

  /// Récupère le token actuel et l'envoie au serveur si l'utilisateur est connecté.
  Future<void> refreshAndSendToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await updateTokenOnBackend(token);
      }
    } catch (e) {
      print("Erreur lors du rafraîchissement du token FCM : $e");
    }
  }

  Future<void> updateTokenOnBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? userId = prefs.getInt('user_id');
      if (userId != null) {
        final response = await http.put(
            Uri.parse('${Env.baseUrl}/users/fcm-token/$userId'),
            headers: {
              'Content-Type': 'application/json',
              ...Env.defaultHeaders,
            },
            body: jsonEncode({'fcm_token': token}),
          );
          if (response.statusCode == 200) {
            print('FCM Token mis à jour avec succès sur le serveur');
          } else {
            print('Échec de la mise à jour du FCM Token: ${response.statusCode} - ${response.body}');
          }
      }
    } catch (e) {
      print('Erreur lors de la mise à jour du FCM Token: $e');
    }
  }
}
