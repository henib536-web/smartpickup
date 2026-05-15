import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Ajouté
import 'dart:convert';
import 'signup.dart';
import 'forgot_password.dart';
import 'userlayout.dart';
import '../../env.dart'; 
import '../../services/fcm_service.dart';
class Login extends StatefulWidget {
  const Login({super.key});

  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> {
  bool rememberMe = false;
  bool obscurePassword = true;
  bool isLoading = false;
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez remplir tous les champs'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      isLoading = true;
    });
    
    try {
      final response = await http.post(
      Uri.parse('${Env.baseUrl}/auth/login'),
        headers: {
          ...Env.defaultHeaders,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'remember_me': rememberMe,
        }),
      ).timeout(const Duration(seconds: 10));
      
      setState(() {
        isLoading = false;
      });
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // --- CORRECTION : Sauvegarde de l'ID et du Token ---
        final prefs = await SharedPreferences.getInstance();
        const storage = FlutterSecureStorage();
        
        final int? userId = data['user_id'] ?? data['id'];
        if (userId != null) {
          await prefs.setInt('user_id', userId);
        }
        if (data['full_name'] != null) {
          await prefs.setString('user_name', data['full_name']);
        }
        if (data['role'] != null) {
          await prefs.setString('user_role', data['role']);
        }
        if (data['access_token'] != null) {
          await storage.write(key: 'access_token', value: data['access_token']);
        }
        
        // Mettre à jour le token FCM pour les notifications
        try {
          await FCMService().refreshAndSendToken();
        } catch (e) {
          print("Erreur lors de la mise à jour du token FCM: $e");
        }
        // ---------------------------------------

        if (context.mounted) {
          final String role = (data['role'] ?? 'commuter').toString();
          Navigator.pushReplacementNamed(
            context,
            role == 'driver' ? '/driver/dashboard' : '/userlayout',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bienvenue ${data['full_name']}!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final error = json.decode(response.body);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error['detail'] ?? 'Login failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Le reste de votre build reste strictement identique...
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFCC00), Color(0xFFFF9900)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFCC00).withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: Colors.black,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Smart Pickup",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Welcome Back",
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 5),
              const Text(
                "Sign in to your account",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),

              Card(
                color: const Color.fromARGB(36, 143, 143, 102).withOpacity(0.3),
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  width: screenWidth > 900 ? 500 : screenWidth * 0.9,
                  padding: EdgeInsets.all(screenWidth < 400 ? 24 : 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("Email", style: TextStyle(color: Colors.white)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _emailController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "your@email.com",
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF0F0F0F),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF333333)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFFCC00)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text("Password", style: TextStyle(color: Colors.white)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        obscureText: obscurePassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "••••••••",
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF0F0F0F),
                          prefixIcon: const Icon(Icons.lock, color: Color(0xFFA0A0A0)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF333333)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFFCC00)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ForgotPassword(),
                              ),
                            );
                          },
                          child: const Text(
                            "Forgot password?",
                            style: TextStyle(
                              color: Color(0xFFFFCC00),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 45,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFCC00),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                  ),
                                )
                              : const Text(
                                  "Sign in",
                                  style: TextStyle(color: Colors.black),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account? ",
                            style: TextStyle(color: Colors.white),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              Navigator.pushNamed(context, '/signup');
                            },
                            child: const Text(
                              "Create Account",
                              style: TextStyle(
                                color: Color(0xFFFFCC00),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}