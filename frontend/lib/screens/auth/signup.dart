import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'login.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../env.dart'; 
import 'package:url_launcher/url_launcher.dart';
class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  _SignupState createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  bool obscurePassword = true;
  bool terms = false;
  XFile? cinImage;
  XFile? jobCardImage;
  XFile? profileImage;
  Uint8List? cinImageBytes;
  Uint8List? jobCardImageBytes;
  Uint8List? profileImageBytes;
  bool isDriver = false;
  bool isLoading = false;

  final ImagePicker picker = ImagePicker();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmpasswordController = TextEditingController();
  final TextEditingController _licenseNumberController = TextEditingController();
  final TextEditingController _licenseExpiryController = TextEditingController();
  final TextEditingController _verificationCodeController = TextEditingController();

  bool sendingSignupCode = false;

  // --- LOGIQUE D'IMAGE SÉCURISÉE ---
  Future<void> pickImage(String type) async {
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        if (type == 'profile') {
          profileImage = image;
          profileImageBytes = bytes;
        }
        if (type == 'cin') {
          cinImage = image;
          cinImageBytes = bytes;
        }
        if (type == 'job') {
          jobCardImage = image;
          jobCardImageBytes = bytes;
        }
      });
    }
  }

  bool validatename(String fullname) => RegExp(r'^[a-zA-Z\s]{5,25}$').hasMatch(fullname);
  bool validateemail(String email) => RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  bool validatephone(String phone) => RegExp(r'^[0-9]{8}$').hasMatch(phone);
  bool validatepassword(String password) => RegExp(r'^[A-Z]+[\w.]{5,}$').hasMatch(password);

  Future<void> sendSignupCode() async {
    final email = _emailController.text.trim();
    if (!validateemail(email)) {
      _showSnackBar('Email invalide', Colors.red);
      return;
    }
    setState(() => sendingSignupCode = true);
    try {
      final response = await http.post(
        Uri.parse('${Env.baseUrl}/auth/send-signup-code'),
        headers: {...Env.defaultHeaders, 'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      ).timeout(const Duration(seconds: 15));
      final data = response.body.isNotEmpty ? json.decode(response.body) : {};
      if (response.statusCode == 200) {
        _showSnackBar(data['message']?.toString() ?? 'Code envoyé', Colors.green);
      } else {
        final detail = data['detail'];
        _showSnackBar(detail is String ? detail : 'Erreur', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Erreur réseau', Colors.red);
    } finally {
      if (mounted) setState(() => sendingSignupCode = false);
    }
  }

  Future<void> handleSignup() async {
    if (!validatename(_fullNameController.text) || !validateemail(_emailController.text) || !validatephone(_phoneController.text)) {
      _showSnackBar('Please check your information', Colors.red);
      return;
    }
    if (_passwordController.text != _confirmpasswordController.text) {
      _showSnackBar('Passwords do not match', Colors.red);
      return;
    }
    if (_verificationCodeController.text.trim().length != 6) {
      _showSnackBar('Saisissez le code à 6 chiffres reçu par email', Colors.red);
      return;
    }
    if (!terms) {
      _showSnackBar('Please accept terms', Colors.red);
      return;
    }
    if (isDriver && (cinImage == null || jobCardImage == null)) {
      _showSnackBar('Please add CIN image and driver card', Colors.red);
      return;
    }

    setState(() => isLoading = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${Env.baseUrl}/auth/signup'),
      );
      request.headers.addAll(Env.defaultHeaders);

      request.fields['full_name'] = _fullNameController.text.trim();
      request.fields['email'] = _emailController.text.trim();
      request.fields['phone'] = _phoneController.text.trim();
      request.fields['password'] = _passwordController.text;
      request.fields['verification_code'] = _verificationCodeController.text.trim();
      request.fields['role'] = isDriver ? "driver" : "commuter";

      if (profileImage != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'profile_image',
            profileImageBytes!,
            filename: profileImage!.name,
          ),
        );
      }

      if (isDriver) {
        request.fields['license_number'] = _licenseNumberController.text.trim();
        request.fields['license_expiry'] = _licenseExpiryController.text.trim();
        request.files.add(
          http.MultipartFile.fromBytes(
            'cin_image',
            cinImageBytes!,
            filename: cinImage!.name,
          ),
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'driver_card_image',
            jobCardImageBytes!,
            filename: jobCardImage!.name,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSnackBar('Account created!', Colors.green);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const Login()));
      } else {
        final error = json.decode(response.body);
        _showSnackBar(error['detail'] ?? 'Signup failed', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Network error', Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            const SizedBox(height: 50),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFCC00), Color(0xFFFF9900)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.directions_car,
                color: Colors.black,
                size: 30,
              ),
            ),
            const SizedBox(height: 15),
            const Text('SmartPickup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
            const SizedBox(height: 30),
            _buildRoleSelection(),
            const SizedBox(height: 20),
            _buildProfilePicker(),
            _buildTextField(_fullNameController, "Full Name"),
            _buildTextField(_emailController, "Email", icon: Icons.email),
            _buildVerificationRow(),
            _buildTextField(_phoneController, "Phone", icon: Icons.phone),
            _buildPasswordField(_passwordController, "Password"),
            _buildPasswordField(_confirmpasswordController, "Confirm Password"),
            if (isDriver) ...[
              const Divider(color: Colors.white24, height: 40),
              _buildDocPicker("CIN Image", cinImage, () => pickImage('cin')),
              const SizedBox(height: 10),
              _buildDocPicker("Driver Card", jobCardImage, () => pickImage('job')),
              _buildTextField(_licenseNumberController, "License Number"),
              _buildTextField(_licenseExpiryController, "License Expiry (YYYY-MM-DD)"),
            ],
            const SizedBox(height: 20),
            _buildTermsCheckbox(),
            const SizedBox(height: 20),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS DE DESIGN CORRIGÉS ---
  Widget _buildProfilePicker() {
    return GestureDetector(
      onTap: () => pickImage('profile'),
      child: CircleAvatar(
        radius: 45,
        backgroundColor: Colors.white10,
        backgroundImage: (profileImageBytes != null)
            ? MemoryImage(profileImageBytes!)
            : null,
        child: (profileImage == null) ? const Icon(Icons.camera_alt, color: Colors.white54) : null,
      ),
    );
  }

  Widget _buildDocPicker(String label, XFile? file, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
        child: (file != null) 
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                file == profileImage ? profileImageBytes! : file == cinImage ? cinImageBytes! : jobCardImageBytes!,
                fit: BoxFit.cover,
              ),
            )
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_a_photo, color: Color(0xFFFFCC00)),
              Text(label, style: const TextStyle(color: Colors.white70)),
            ]),
      ),
    );
  }

  // (Les autres widgets de texte/boutons restent identiques à votre version originale)
  Widget _buildRoleSelection() => Row(children: [
    Expanded(child: _buildRoleBtn("User", !isDriver, () => setState(() => isDriver = false))),
    const SizedBox(width: 10),
    Expanded(child: _buildRoleBtn("Driver", isDriver, () => setState(() => isDriver = true))),
  ]);

  Widget _buildRoleBtn(String t, bool s, VoidCallback o) => GestureDetector(onTap: o, child: Container(padding: const EdgeInsets.symmetric(vertical: 15), decoration: BoxDecoration(color: s ? const Color(0xFFFFCC00).withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(12), border: Border.all(color: s ? const Color(0xFFFFCC00) : Colors.white24)), child: Center(child: Text(t, style: const TextStyle(color: Colors.white)))));

  Widget _buildVerificationRow() => Padding(
        padding: const EdgeInsets.only(top: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _verificationCodeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Code email (6 chiffres)',
                  counterText: '',
                  prefixIcon: const Icon(Icons.verified_user, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: sendingSignupCode ? null : sendSignupCode,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFCC00),
                    side: const BorderSide(color: Color(0xFFFFCC00)),
                  ),
                  child: sendingSignupCode
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Envoyer'),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildTextField(TextEditingController c, String h, {IconData? icon}) => Padding(padding: const EdgeInsets.only(top: 15), child: TextField(controller: c, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: h, prefixIcon: Icon(icon, color: Colors.grey), filled: true, fillColor: const Color(0xFF1A1A1A), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))));

  Widget _buildPasswordField(TextEditingController c, String h) => Padding(padding: const EdgeInsets.only(top: 15), child: TextField(controller: c, obscureText: obscurePassword, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: h, suffixIcon: IconButton(icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => obscurePassword = !obscurePassword)), filled: true, fillColor: const Color(0xFF1A1A1A), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))));

  Widget _buildTermsCheckbox() => Row(children: [
        Checkbox(value: terms, onChanged: (v) => setState(() => terms = v!), activeColor: Colors.amber),
        const Text('Accept ', style: TextStyle(color: Colors.white70)),
        GestureDetector(
          onTap: _launchTermsPdf,
          child: const Text(
            'Terms & Conditions (PDF)',
            style: TextStyle(
              color: Colors.amber,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ]);

  Future<void> _launchTermsPdf() async {
    final Uri url = Uri.parse('https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'); // Remplacer par l'URL réelle du PDF
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) _showSnackBar("Impossible d'ouvrir le PDF", Colors.red);
    }
  }

  Widget _buildSubmitButton() => SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: isLoading ? null : handleSignup, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFCC00)), child: isLoading ? const CircularProgressIndicator() : const Text("SIGN UP", style: TextStyle(color: Colors.black))));
}