import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../env.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String errorMessage = "";
  bool rideConfirm = false;
  bool driverAlert = false;
  bool promoOffers = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null) {
        setState(() {
          errorMessage = "Utilisateur non connecté";
          isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('${Env.baseUrl}/users/profile/$userId'),
        headers: Env.defaultHeaders,
      );

      if (response.statusCode == 200) {
        setState(() {
          userData = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = "Erreur lors de la récupération des données";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Erreur de connexion au serveur";
        isLoading = false;
      });
    }
  }

  String _resolveImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) {
      return '';
    }
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    return '${Env.baseUrl}$rawUrl';
  }

  Future<void> _openEditProfileDialog() async {
    if (userData == null) return;

    final nameController = TextEditingController(
      text: userData?['full_name']?.toString() ?? '',
    );
    final emailController = TextEditingController(
      text: userData?['email']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: userData?['phone']?.toString() ?? '',
    );
    final currentPasswordController = TextEditingController();
    XFile? selectedImage;
    Uint8List? selectedImageBytes;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text(
                'Edit profile',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final image = await _picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          final bytes = await image.readAsBytes();
                          setDialogState(() {
                            selectedImage = image;
                            selectedImageBytes = bytes;
                          });
                        }
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: Container(
                          width: 80,
                          height: 80,
                          color: Colors.white12,
                          child: selectedImageBytes != null
                              ? Image.memory(selectedImageBytes!, fit: BoxFit.cover)
                              : (_resolveImageUrl(userData?['image_url']?.toString()).isNotEmpty
                                  ? Image.network(
                                      _resolveImageUrl(userData?['image_url']?.toString()),
                                      headers: Env.defaultHeaders,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white70),
                                    )
                                  : const Icon(Icons.camera_alt, color: Colors.white70)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDialogField(nameController, 'Full name'),
                    const SizedBox(height: 12),
                    _buildDialogField(emailController, 'Email'),
                    const SizedBox(height: 12),
                    _buildDialogField(phoneController, 'Phone'),
                    const SizedBox(height: 12),
                    _buildDialogField(currentPasswordController, 'Current Password (required)', obscureText: true),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _updateProfile(
                      fullName: nameController.text.trim(),
                      email: emailController.text.trim(),
                      phone: phoneController.text.trim(),
                      currentPassword: currentPasswordController.text,
                      image: selectedImage,
                      imageBytes: selectedImageBytes,
                    );
                    if (mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFCC00),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogField(TextEditingController controller, String hint, {bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _updateProfile({
    required String fullName,
    required String email,
    required String phone,
    required String currentPassword,
    XFile? image,
    Uint8List? imageBytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null) return;

    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('${Env.baseUrl}/users/profile/$userId'),
    );
    request.headers.addAll(Env.defaultHeaders);
    request.fields['full_name'] = fullName;
    request.fields['email'] = email;
    request.fields['phone'] = phone;
    request.fields['current_password'] = currentPassword;

    if (image != null && imageBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'profile_image',
          imageBytes,
          filename: image.name,
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      await prefs.setString('user_name', fullName);
      await _fetchUserProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      final data = jsonDecode(response.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['detail']?.toString() ?? 'Profile update failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openChangePasswordDialog() async {
    final oldPasswordController = TextEditingController();
    final codeController = TextEditingController();
    final newPasswordController = TextEditingController();
    
    bool useCode = false;
    bool isSendingCode = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text('Change Password', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!useCode) ...[
                    TextField(
                      controller: oldPasswordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Old Password',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isSendingCode ? null : () async {
                          setDialogState(() => isSendingCode = true);
                          try {
                            final res = await http.post(
                              Uri.parse('${Env.baseUrl}/auth/forgot-password'),
                              headers: {...Env.defaultHeaders, 'Content-Type': 'application/json'},
                              body: jsonEncode({'email': userData?['email']}),
                            );
                            if (res.statusCode == 200) {
                              setDialogState(() => useCode = true);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Code sent to email'), backgroundColor: Colors.green),
                                );
                              }
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Failed to send code'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          } finally {
                            setDialogState(() => isSendingCode = false);
                          }
                        },
                        child: isSendingCode 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Forgot Password?', style: TextStyle(color: Color(0xFFFFCC00))),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: codeController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '6-digit Code',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'New Password',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final oldP = oldPasswordController.text;
                    final codeP = codeController.text;
                    final newP = newPasswordController.text;
                    
                    if ((!useCode && oldP.isEmpty) || (useCode && codeP.isEmpty) || newP.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    final prefs = await SharedPreferences.getInstance();
                    final userId = prefs.getInt('user_id');

                    final Map<String, dynamic> body = {'new_password': newP};
                    if (useCode) {
                      body['code'] = codeP;
                    } else {
                      body['old_password'] = oldP;
                    }

                    final res = await http.put(
                      Uri.parse('${Env.baseUrl}/users/change-password/$userId'),
                      headers: {
                        ...Env.defaultHeaders,
                        'Content-Type': 'application/json',
                      },
                      body: jsonEncode(body),
                    );

                    if (res.statusCode == 200) {
                      if (context.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password updated successfully'), backgroundColor: Colors.green),
                        );
                      }
                    } else {
                      final data = jsonDecode(res.body);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(data['detail'] ?? 'Error'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFCC00)),
                  child: const Text('Save', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFCC00)))
          : errorMessage.isNotEmpty
              ? Center(child: Text(errorMessage, style: const TextStyle(color: Colors.white)))
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      /// HEADER
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Row(
                              children: [
                                Text(
                                  "My Profile Settings",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                
                              ],
                            ),
                            SizedBox(height: 5),
                            Text(
                              "Manage your account and preferences",
                              style: TextStyle(color: Colors.white70, fontSize: 16),
                            ),
                          ],
                        ),
                      ),

                      /// PROFILE CARD
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFCC00), Color(0xFFFF9900)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: _resolveImageUrl(
                                        userData?['image_url']?.toString(),
                                      )
                                      .isNotEmpty
                                  ? Image.network(
                                      _resolveImageUrl(
                                        userData?['image_url']?.toString(),
                                      ),
                                      headers: Env.defaultHeaders,
                                      height: 80,
                                      width: 80,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _buildFallbackAvatar(),
                                    )
                                  : _buildFallbackAvatar(),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              userData?['full_name'] ?? "User Name",
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              "Member since ${userData?['created_at'] ?? '2026'}",
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                profileStat("48", "Total Rides"),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// NOUVELLE SECTION : ACTIVITY & SUPPORT (Historique et Rapports)
                      _buildSectionContainer(
                        child: Column(
                          children: [
                            _buildSectionHeader(Icons.explore, "Activity & Support"),
                            const SizedBox(height: 10),
                            _buildNavigationItem(
                              icon: Icons.history,
                              title: "Ride History",
                              subtitle: "View your past trips and receipts",
                              onTap: () {
                                // Remplacez par votre navigation vers user/historique
                                  Navigator.pushNamed(context, '/user/history');

                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// PERSONAL INFORMATION
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(16),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Personal Information",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.white),
                                  onPressed: _openEditProfileDialog,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            profileInfo(Icons.person, "Full Name", userData?['full_name'] ?? "N/A"),
                            const SizedBox(height: 15),
                            profileInfo(Icons.email, "Email", userData?['email'] ?? "N/A"),
                            const SizedBox(height: 15),
                            profileInfo(Icons.phone, "Phone", userData?['phone'] ?? "N/A"),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// NOTIFICATIONS SECTION
                      _buildSectionContainer(
                        child: Column(
                          children: [
                            _buildSectionHeader(Icons.notifications, "Notification Preferences"),
                            const SizedBox(height: 15),
                            settingItem("Ride confirmations", "Get notified when your ride is confirmed", rideConfirm, (v) => setState(() => rideConfirm = v)),
                            const Divider(color: Colors.white10),
                            settingItem("Driver arrival alerts", "Alert when driver is nearby", driverAlert, (v) => setState(() => driverAlert = v)),
                            const Divider(color: Colors.white10),
                            settingItem("Promotional offers", "Receive special deals and discounts", promoOffers, (v) => setState(() => promoOffers = v)),
                            const SizedBox(height: 20),
                            
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// SECURITY SECTION
                      _buildSectionContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(Icons.security, "Security & Privacy"),
                            const SizedBox(height: 15),
                            securityItem("Change Password", "Update your account password", onTap: _openChangePasswordDialog),
                            const SizedBox(height: 10),
                            securityItem("Two-Factor Authentication", "Add an extra layer of security"),
                            const Divider(color: Colors.white10),
                            securityItem(
                              "Logout", 
                              "Sign out of your account", 
                              onTap: () async {
                                final prefs = await SharedPreferences.getInstance();
                                final userId = prefs.getInt('user_id');
                                // Effacer le token FCM du backend pour éviter les notifs croisées
                                if (userId != null) {
                                  try {
                                    await http.delete(
                                      Uri.parse('${Env.baseUrl}/users/fcm-token/$userId'),
                                      headers: Env.defaultHeaders,
                                    );
                                  } catch (_) {}
                                }
                                await prefs.clear();
                                if (mounted) Navigator.pushReplacementNamed(context, "/");
                              },
                              isDanger: true,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFallbackAvatar() {
    final name = userData?['full_name']?.toString() ?? 'U';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    return Container(
      height: 80,
      width: 80,
      color: Colors.black26,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // --- WIDGETS DE STYLE RÉUTILISABLES ---

  Widget _buildSectionContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFCC00)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(color: Color(0xFFFFCC00), fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildNavigationItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white54),
    );
  }
}

// Widgets externes (Stat, Info, Item)
Widget profileStat(String number, String label) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(number, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black)),
      ],
    ),
  );
}

Widget profileInfo(IconData icon, String title, String value) {
  return Row(
    children: [
      Icon(icon, color: const Color(0xFFFFCC00)),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    ],
  );
}

Widget settingItem(String title, String subtitle, bool value, Function(bool) onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        Switch(value: value, activeColor: const Color(0xFFFFCC00), onChanged: onChanged),
      ],
    ),
  );
}

Widget securityItem(String title, String subtitle, {VoidCallback? onTap, bool isDanger = false}) {
  return _SecurityItem(title: title, subtitle: subtitle, onTap: onTap, isDanger: isDanger);
}

class _SecurityItem extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDanger;
  const _SecurityItem({required this.title, required this.subtitle, this.onTap, this.isDanger = false});

  @override
  State<_SecurityItem> createState() => _SecurityItemState();
}

class _SecurityItemState extends State<_SecurityItem> {
  bool isHover = false;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap ?? () {},
      onHover: (val) => setState(() => isHover = val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isHover ? const Color(0xFFFFCC00) : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              widget.isDanger ? Icons.logout : Icons.security, 
              color: widget.isDanger ? Colors.redAccent : const Color(0xFFFFCC00)
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title, 
                    style: TextStyle(
                      color: widget.isDanger ? Colors.redAccent : Colors.white, 
                      fontSize: 15, 
                      fontWeight: FontWeight.bold
                    )
                  ),
                  Text(widget.subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: widget.isDanger ? Colors.redAccent.withOpacity(0.5) : Colors.white54),
          ],
        ),
      ),
    );
  }
}