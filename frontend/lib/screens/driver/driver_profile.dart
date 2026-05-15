import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/driver_layout.dart';
import '../../services/driver_api_service.dart';
import '../../env.dart';

class DriverProfile extends StatefulWidget {
  const DriverProfile({Key? key}) : super(key: key);

  @override
  _DriverProfileState createState() => _DriverProfileState();
}

class _DriverProfileState extends State<DriverProfile> {
  final DriverApiService _apiService = DriverApiService();
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _taxiData;
  bool _isLoading = true;
  String _errorMessage = "";
  final ImagePicker _picker = ImagePicker();
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    try {
      final profile = await _apiService.getProfile();
      Map<String, dynamic>? taxi;
      try {
        taxi = await _apiService.getTaxi();
      } catch (_) {}
      
      setState(() {
        _userData = profile;
        _taxiData = taxi;
        _isOnline = profile['is_active'] ?? true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading profile data";
        _isLoading = false;
      });
    }
  }

  String _resolveImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    if (rawUrl.startsWith('http')) return rawUrl;
    return '${Env.baseUrl}$rawUrl';
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
      request.files.add(http.MultipartFile.fromBytes(
        'profile_image',
        imageBytes,
        filename: image.name,
      ));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      await _loadAllData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated'), backgroundColor: Colors.green));
    } else {
      final data = jsonDecode(response.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['detail'] ?? 'Update failed'), backgroundColor: Colors.red));
    }
  }

  Future<void> _openEditProfileDialog() async {
    if (_userData == null) return;
    final nameCtrl = TextEditingController(text: _userData!['full_name'] ?? '');
    final emailCtrl = TextEditingController(text: _userData!['email'] ?? '');
    final phoneCtrl = TextEditingController(text: _userData!['phone'] ?? '');
    final passCtrl = TextEditingController();
    XFile? selImg;
    Uint8List? selImgBytes;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final img = await _picker.pickImage(source: ImageSource.gallery);
                    if (img != null) {
                      final b = await img.readAsBytes();
                      setDialogState(() { selImg = img; selImgBytes = b; });
                    }
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white12,
                    backgroundImage: selImgBytes != null ? MemoryImage(selImgBytes!) : null,
                    child: selImgBytes == null ? const Icon(Icons.camera_alt, color: Colors.white70) : null,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDialogField(nameCtrl, 'Full Name'),
                const SizedBox(height: 12),
                _buildDialogField(emailCtrl, 'Email'),
                const SizedBox(height: 12),
                _buildDialogField(phoneCtrl, 'Phone'),
                const SizedBox(height: 12),
                _buildDialogField(passCtrl, 'Current Password (required)', obscure: true),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              onPressed: () async {
                await _updateProfile(
                  fullName: nameCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  currentPassword: passCtrl.text,
                  image: selImg,
                  imageBytes: selImgBytes,
                );
                if (mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFCC00)),
              child: const Text('Save', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogField(TextEditingController ctrl, String hint, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
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

  Future<void> _openChangePasswordDialog() async {
    final oldPCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final newPCtrl = TextEditingController();
    bool useCode = false;
    bool isSending = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Change Password', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!useCode) ...[
                _buildDialogField(oldPCtrl, 'Old Password', obscure: true),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: isSending ? null : () async {
                      setDialogState(() => isSending = true);
                      try {
                        final res = await http.post(
                          Uri.parse('${Env.baseUrl}/auth/forgot-password'),
                          headers: {...Env.defaultHeaders, 'Content-Type': 'application/json'},
                          body: jsonEncode({'email': _userData?['email']}),
                        );
                        if (res.statusCode == 200) {
                          setDialogState(() => useCode = true);
                        }
                      } finally {
                        setDialogState(() => isSending = false);
                      }
                    },
                    child: isSending ? const CircularProgressIndicator() : const Text('Forgot Password?', style: TextStyle(color: Color(0xFFFFCC00))),
                  ),
                ),
              ] else ...[
                _buildDialogField(codeCtrl, '6-digit Code'),
              ],
              const SizedBox(height: 12),
              _buildDialogField(newPCtrl, 'New Password', obscure: true),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final userId = prefs.getInt('user_id');
                final Map<String, dynamic> body = {'new_password': newPCtrl.text};
                if (useCode) body['code'] = codeCtrl.text; else body['old_password'] = oldPCtrl.text;

                final res = await http.put(
                  Uri.parse('${Env.baseUrl}/users/change-password/$userId'),
                  headers: {...Env.defaultHeaders, 'Content-Type': 'application/json'},
                  body: jsonEncode(body),
                );
                if (res.statusCode == 200) {
                  if (mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated'))); }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFCC00)),
              child: const Text('Save', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStatus() async {
    try {
      await _apiService.updateStatus(!_isOnline);
      setState(() => _isOnline = !_isOnline);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DriverLayout(
      title: 'Profile',
      currentIndex: 3,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFCC00)))
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.white)))
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      /// HEADER
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Text("Driver Profile Settings", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                                SizedBox(width: 10),
                                Icon(Icons.local_taxi, color: Color(0xFFFFCC00)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            const Text("Manage your driver account and taxi", style: TextStyle(color: Colors.white70, fontSize: 16)),
                          ],
                        ),
                      ),

                      /// PROFILE CARD (Gradient)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFFCC00), Color(0xFFFF9900)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundImage: _userData?['image_url'] != null ? NetworkImage(_resolveImageUrl(_userData!['image_url'])) : null,
                              child: _userData?['image_url'] == null ? const Icon(Icons.person, size: 40) : null,
                            ),
                            const SizedBox(height: 10),
                            Text(_userData?['full_name'] ?? "Driver Name", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                            Text("Professional Driver • Verified", style: const TextStyle(fontSize: 14, color: Colors.black87)),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                _profileStat("${_userData?['total_trips'] ?? 0}", "Trips"),
                                const SizedBox(width: 10),
                                _profileStat("${_userData?['average_rating'] ?? 5.0}", "Rating", isRating: true),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// ACTIVITY & SUPPORT
                      _buildSectionContainer(
                        child: Column(
                          children: [
                            _buildSectionHeader(Icons.explore, "Activity & Support"),
                            const SizedBox(height: 10),
                            _buildNavigationItem(
                              icon: Icons.history,
                              title: "Ride History",
                              subtitle: "Review your completed and cancelled trips",
                              onTap: () => Navigator.pushNamed(context, '/driver/history'),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// PERSONAL INFORMATION
                      _buildSectionContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildSectionHeader(Icons.person, "Personal Information"),
                                IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: _openEditProfileDialog),
                              ],
                            ),
                            const SizedBox(height: 15),
                            _profileInfo(Icons.email, "Email", _userData?['email'] ?? "N/A"),
                            const SizedBox(height: 15),
                            _profileInfo(Icons.phone, "Phone", _userData?['phone'] ?? "N/A"),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// VEHICLE INFORMATION
                      _buildSectionContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(Icons.directions_car, "Vehicle Details"),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                Expanded(child: _profileInfo(Icons.branding_watermark, "Brand", _taxiData?['vehicle_brand'] ?? "N/A")),
                                Expanded(child: _profileInfo(Icons.model_training, "Model", _taxiData?['vehicle_model'] ?? "N/A")),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                Expanded(child: _profileInfo(Icons.calendar_today, "Year", _taxiData?['vehicle_year']?.toString() ?? "N/A")),
                                Expanded(child: _profileInfo(Icons.credit_card, "Plate", _taxiData?['plate_number'] ?? "N/A")),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// PERFORMANCE
                      _buildSectionContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(Icons.speed, "Performance Metrics"),
                            const SizedBox(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _perfMetric("Reliability", "98%", Colors.green),
                                _perfMetric("Acceptance", "85%", Color(0xFFFFCC00)),
                                _perfMetric("Rejection", "5%", Colors.red),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 15),

                      /// STATUS & SECURITY
                      _buildSectionContainer(
                        child: Column(
                          children: [
                            _buildSectionHeader(Icons.settings, "Account Settings"),
                            const SizedBox(height: 15),
                            _settingItem("Online Status", "Receive new ride requests", _isOnline, (v) => _toggleStatus()),
                            const Divider(color: Colors.white10),
                            _securityItem("Change Password", "Update your driver password", onTap: _openChangePasswordDialog),
                            const Divider(color: Colors.white10),
                            ListTile(
                              leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
                              title: const Text("Logout", style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                              onTap: () async {
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.clear();
                                if (mounted) Navigator.pushReplacementNamed(context, '/');
                              },
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

  Widget _profileStat(String number, String label, {bool isRating = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Row(
            children: [
              Text(number, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
              if (isRating) const Icon(Icons.star, size: 16, color: Colors.black),
            ],
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildSectionContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: child,
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFCC00), size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Color(0xFFFFCC00), fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _profileInfo(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFCC00), size: 18),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _perfMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }

  Widget _settingItem(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        Switch(value: value, activeColor: const Color(0xFFFFCC00), onChanged: onChanged),
      ],
    );
  }

  Widget _securityItem(String title, String subtitle, {VoidCallback? onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white54),
      onTap: onTap,
    );
  }

  Widget _buildNavigationItem({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white54),
    );
  }
}