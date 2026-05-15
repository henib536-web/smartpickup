import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../env.dart';
import 'login.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool obscureNew = true;
  bool obscureConfirm = true;
  bool isSendingCode = false;
  bool isResetting = false;

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _snack('Veuillez saisir votre email', Colors.red);
      return;
    }
    setState(() => isSendingCode = true);
    try {
      final response = await http.post(
        Uri.parse('${Env.baseUrl}/auth/forgot-password'),
        headers: {...Env.defaultHeaders, 'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      ).timeout(const Duration(seconds: 15));
      final data = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (response.statusCode == 200) {
        _snack(data['message']?.toString() ?? 'Code envoyé', Colors.green);
      } else {
        final detail = data['detail'];
        _snack(detail is String ? detail : 'Erreur', Colors.red);
      }
    } catch (e) {
      _snack('Erreur réseau: $e', Colors.red);
    } finally {
      if (mounted) setState(() => isSendingCode = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final np = _newPasswordController.text;
    if (email.isEmpty || code.isEmpty || np.isEmpty) {
      _snack('Remplissez tous les champs', Colors.red);
      return;
    }
    if (np.length < 6) {
      _snack('Le mot de passe doit faire au moins 6 caractères', Colors.red);
      return;
    }
    if (np != _confirmPasswordController.text) {
      _snack('Les mots de passe ne correspondent pas', Colors.red);
      return;
    }
    setState(() => isResetting = true);
    try {
      final response = await http.post(
        Uri.parse('${Env.baseUrl}/auth/reset-password'),
        headers: {...Env.defaultHeaders, 'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'code': code,
          'new_password': np,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (response.statusCode == 200) {
        _snack(data['message']?.toString() ?? 'Mot de passe mis à jour', Colors.green);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const Login()),
          );
        }
      } else {
        final detail = data['detail'];
        _snack(detail is String ? detail : 'Échec', Colors.red);
      }
    } catch (e) {
      _snack('Erreur réseau: $e', Colors.red);
    } finally {
      if (mounted) setState(() => isResetting = false);
    }
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Mot de passe oublié'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Saisissez votre email pour recevoir un code à 6 chiffres, puis choisissez un nouveau mot de passe.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Email'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: isSendingCode ? null : _sendCode,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFCC00),
                  side: const BorderSide(color: Color(0xFFFFCC00)),
                ),
                child: isSendingCode
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Envoyer le code'),
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Code à 6 chiffres'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _newPasswordController,
              obscureText: obscureNew,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Nouveau mot de passe').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                  onPressed: () => setState(() => obscureNew = !obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: obscureConfirm,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration('Confirmer le mot de passe').copyWith(
                suffixIcon: IconButton(
                  icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                  onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: isResetting ? null : _resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFCC00),
                  foregroundColor: Colors.black,
                ),
                child: isResetting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer le nouveau mot de passe'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF333333)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFCC00)),
        ),
      );
}
