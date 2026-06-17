import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../auth/driver_layout.dart';
import '../../services/driver_api_service.dart';
import '../../env.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key}) : super(key: key);

  @override
  _DriverDashboardState createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  bool _isOnline = true;
  int? _expandedRequestId;
  Timer? _locationTimer;
  Timer? _expiryTimer;
  LatLng? _currentPosition;

  final DriverApiService _apiService = DriverApiService();
  List<Map<String, dynamic>> _urgentRequests = [];
  bool _isLoading = false;
  List<LatLng> _previewRoutePoints = [];
  double? _previewDistance;
  int? _previewDuration;

  Map<String, dynamic>? _driverProfile;
  Map<String, dynamic>? _driverStats;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _startLocationTracking();
    _startExpiryTimer();
    // Set driver online in DB at startup
    _setOnlineStatus(true);
    
    // Auto-refresh every 10 seconds to sync available rides
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _isOnline) {
        _loadRequests(showLoading: false);
      }
    });
  }

  Future<void> _setOnlineStatus(bool isOnline) async {
    try {
      await _apiService.updateStatus(isOnline);
      debugPrint('[STATUS] Driver is_available set to $isOnline in DB');
    } catch (e) {
      debugPrint('[STATUS] Failed to update driver status: $e');
    }
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    try {
      Position p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) setState(() => _currentPosition = LatLng(p.latitude, p.longitude));
    } catch (e) {
      debugPrint('GPS initial error: $e');
    }

    _locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        Position p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation),
        );
        if (mounted) {
          final newPos = LatLng(p.latitude, p.longitude);
          setState(() => _currentPosition = newPos);
          try {
            _mapController.move(newPos, _mapController.camera.zoom);
          } catch (_) {}
          // Update location on backend
          try {
            await _apiService.updateLocation(p.latitude, p.longitude);
          } catch (e) {
            debugPrint('Error updating location to backend: $e');
          }
        }
      } catch (e) {
        debugPrint('GPS update error: $e');
      }
    });
  }

  Future<void> _loadRequests({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final data = await _apiService.getAvailableRides();
      
      Map<String, dynamic>? profile;
      try {
        profile = await _apiService.getProfile();
      } catch (e) {
        profile = null;
      }

      Map<String, dynamic>? stats;
      try {
        stats = await _apiService.getDriverStats();
      } catch (e) {
        stats = null;
      }

      setState(() {
        final now = DateTime.now().toUtc(); // ← use UTC to match server timestamps
        _urgentRequests = data.map((e) {
          final requestedAt = e['requested_at'] != null 
              ? DateTime.parse(e['requested_at']).toUtc() // ← parse as UTC
              : DateTime.now().toUtc();
          
          // Calculate remaining seconds out of 3600 (1 hour window)
          final diff = now.difference(requestedAt).inSeconds;
          final remaining = (3600 - diff).clamp(0, 3600);
          debugPrint('[EXPIRY] Ride ${e['request_id']}: requestedAt=$requestedAt, diff=${diff}s, remaining=${remaining}s');

          // Calculate direct distance to pickup if we have current position
          double? distToPickup;
          if (_currentPosition != null && e['pickup_lat'] != null && e['pickup_lng'] != null) {
            distToPickup = _calculateDistance(
              _currentPosition!.latitude, 
              _currentPosition!.longitude, 
              (e['pickup_lat'] as num).toDouble(), 
              (e['pickup_lng'] as num).toDouble()
            );
          }

          return {
            'id': e['request_id'],
            'userName': e['passenger_name'] ?? 'Inconnu',
            'userType': e['passenger_type'] ?? 'Standard',
            'pickup': e['pickup_location'] ?? 'N/A',
            'dropoff': e['dropoff_location'] ?? 'N/A',
            'pickupLat': e['pickup_lat'],
            'pickupLng': e['pickup_lng'],
            'dropoffLat': e['dropoff_lat'],
            'dropoffLng': e['dropoff_lng'],
            'time': e['scheduled_for'] != null 
                ? DateFormat('HH:mm').format(DateTime.parse(e['scheduled_for']))
                : 'NOW',
            'distance': '${e['distance_km'] ?? '?.?'} km',
            'duration': '${e['time_mins'] ?? '??'} min',
            'expiresIn': remaining,
            'distanceToPickup': distToPickup != null 
                ? '${distToPickup.toStringAsFixed(1)} km from you' 
                : null,
            'receivedAt': requestedAt,
            // priority_price est en DT (ex: 2.5), estimated_price est en millimes (ex: 12300)
            'priorityPrice': (e['priority_price'] as num?)?.toDouble() ?? 2.0,
            'estimatedPrice': e['estimated_price'] != null
                ? '${((e['estimated_price'] as num) / 1000).toStringAsFixed(3)} DT'
                : (e['priority_price'] != null && (e['priority_price'] as num).toDouble() > 2.0
                    ? '${(e['priority_price'] as num).toDouble().toStringAsFixed(3)} DT'
                    : 'N/A'),
            'basePrice': e['base_price'] != null ? '${((e['base_price'] as num) / 1000).toStringAsFixed(3)} DT' : '3.500 DT',
          };
        }).where((req) => (req['expiresIn'] as int) > 0).toList();
        
        _driverProfile = profile;
        _driverStats = stats;
        _isLoading = false;

        // Check and prompt for vehicle info — once per driver account only
        if (!_hasPromptedVehicleInfo && _driverProfile != null) {
          _hasPromptedVehicleInfo = true;
          final userId = _driverProfile!['user_id']?.toString() ?? '';
          final make = _driverProfile!['vehicle_make'];
          final model = _driverProfile!['vehicle_model'];
          final plate = _driverProfile!['vehicle_plate'];

          final missingVehicleInfo =
              (make == null || make.toString().isEmpty) &&
              (model == null || model.toString().isEmpty) &&
              (plate == null || plate.toString().isEmpty);

          if (missingVehicleInfo && userId.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            final key = 'vehicle_prompt_shown_$userId';
            final alreadyShown = prefs.getBool(key) ?? false;
            if (!alreadyShown) {
              await prefs.setBool(key, true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showVehicleInfoPrompt();
              });
            }
          }
        }

      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Load requests error: $e');
    }
  }

  bool _hasPromptedVehicleInfo = false;

  void _showVehicleInfoPrompt() {
    final makeController = TextEditingController();
    final modelController = TextEditingController();
    final colorController = TextEditingController();
    final plateController = TextEditingController();

    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Complete Your Profile',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Please enter your vehicle details. You can skip this and leave it empty in your profile if you prefer.',
                    style: TextStyle(color: Color(0xFFA0A0A0), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _buildVehicleField(makeController, 'Vehicle Make (e.g. Toyota)'),
                  const SizedBox(height: 12),
                  _buildVehicleField(modelController, 'Vehicle Model (e.g. Camry)'),
                  const SizedBox(height: 12),
                  _buildVehicleField(colorController, 'Vehicle Color (e.g. White)'),
                  const SizedBox(height: 12),
                  _buildVehicleField(plateController, 'License Plate'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Skip', style: TextStyle(color: Color(0xFF888888))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFCC00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: isSubmitting ? null : () async {
                  setDialogState(() => isSubmitting = true);
                  try {
                    await _apiService.updateProfile({
                      'vehicle_make': makeController.text.trim(),
                      'vehicle_model': modelController.text.trim(),
                      'vehicle_color': colorController.text.trim(),
                      'vehicle_plate': plateController.text.trim(),
                    });
                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vehicle info updated!'), backgroundColor: Colors.green),
                      );
                      _loadRequests(showLoading: false);
                    }
                  } catch (e) {
                    setDialogState(() => isSubmitting = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: isSubmitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Save'),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildVehicleField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555555)),
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _urgentRequests.isNotEmpty) {
        setState(() {
          for (var i = 0; i < _urgentRequests.length; i++) {
            if (_urgentRequests[i]['expiresIn'] > 0) {
              _urgentRequests[i]['expiresIn']--;
            }
          }
          // Remove expired requests
          _urgentRequests.removeWhere((req) => req['expiresIn'] <= 0);
        });
      }
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  void toggleRequestDetails(Map<String, dynamic> req) {
    final id = req['id'];
    setState(() {
      if (_expandedRequestId == id) {
        _expandedRequestId = null;
        _previewRoutePoints = [];
      } else {
        _expandedRequestId = id;
        _previewRoutePoints = [];
        _fetchPreviewRoute(req);
      }
    });
  }

  Future<void> _fetchPreviewRoute(Map<String, dynamic> req) async {
    final pLat = req['pickupLat'];
    final pLng = req['pickupLng'];
    final dLat = req['dropoffLat'];
    final dLng = req['dropoffLng'];

    if (pLat == null || pLng == null || dLat == null || dLng == null) return;

    final driverPos = _currentPosition;
    final String token = Env.mapboxToken;
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/'
      '$pLng,$pLat;$dLng,$dLat'
      '?geometries=geojson&overview=full&access_token=$token',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0] as Map<String, dynamic>;
          final coords = firstRoute['geometry']['coordinates'] as List;
          final points = coords
              .map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          
          if (mounted) {
            setState(() {
              _previewRoutePoints = points;
              _previewDistance = (firstRoute['distance'] as num).toDouble() / 1000;
              _previewDuration = ((firstRoute['duration'] as num).toDouble() / 60).round();
              
              req['distance'] = '${_previewDistance!.toStringAsFixed(1)} km';
              req['duration'] = '$_previewDuration min';
            });
          }
        }
      }

      if (driverPos != null) {
        final toPickupUrl = Uri.parse(
          'https://api.mapbox.com/directions/v5/mapbox/driving/'
          '${driverPos.longitude},${driverPos.latitude};$pLng,$pLat'
          '?access_token=$token',
        );
        final resToPickup = await http.get(toPickupUrl);
        if (resToPickup.statusCode == 200) {
          final data = jsonDecode(resToPickup.body);
          final routes = data['routes'] as List?;
          if (routes != null && routes.isNotEmpty) {
            final distToPickup = (routes[0]['distance'] as num).toDouble() / 1000;
            if (mounted) {
              setState(() {
                req['distanceToPickup'] = '${distToPickup.toStringAsFixed(1)} km to client';
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching preview route: $e');
    }
  }

  String formatTime(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371; // km
    final dLat = (lat2 - lat1) * (3.14159265358979323846 / 180);
    final dLon = (lon2 - lon1) * (3.14159265358979323846 / 180);
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
              (math.cos(lat1 * (3.14159265358979323846 / 180)) * 
               math.cos(lat2 * (3.14159265358979323846 / 180)) * 
               math.sin(dLon / 2) * math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return DriverLayout(
        title: 'Dashboard',
        currentIndex: 0,
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFCC00)),
        ),
      );
    }
    return DriverLayout(
      title: 'Dashboard',
      currentIndex: 0,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Driver Hub ',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome back, ${_driverProfile != null ? _driverProfile!['full_name'] : 'Driver'}! Manage all your rides here',
                  style: const TextStyle(color: Color(0xFFA0A0A0)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ─── Premium Status Toggle ───
            GestureDetector(
              onTap: () async {
                final newStatus = !_isOnline;
                setState(() => _isOnline = newStatus);
                await _setOnlineStatus(newStatus);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: _isOnline
                      ? const LinearGradient(
                          colors: [Color(0xFF0D9F4F), Color(0xFF06D6A0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFF1E1E2C), Color(0xFF2A2A3C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _isOnline
                          ? const Color(0xFF06D6A0).withOpacity(0.35)
                          : Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Animated icon container
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? Colors.white.withOpacity(0.2)
                            : const Color(0xFF3A3A4C),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _isOnline ? Icons.wifi : Icons.wifi_off,
                        color: _isOnline
                            ? Colors.white
                            : const Color(0xFF6B6B80),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isOnline ? 'You are Online' : 'You are Offline',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _isOnline
                                  ? Colors.white
                                  : const Color(0xFF8888A0),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _isOnline
                                ? 'Receiving ride requests'
                                : 'Tap to go online and receive rides',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isOnline
                                  ? Colors.white.withOpacity(0.7)
                                  : const Color(0xFF5A5A70),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Custom toggle switch
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 56,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        color: _isOnline
                            ? Colors.white.withOpacity(0.3)
                            : const Color(0xFF3A3A4C),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: _isOnline
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isOnline
                                ? Colors.white
                                : const Color(0xFF5A5A70),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ─── Empty State when no requests ───
            if ((_urgentRequests.isEmpty || !_isOnline)) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF111118),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF2A2A3C),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? const Color(0xFFFFCC00).withOpacity(0.1)
                            : const Color(0xFF3A3A4C).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        _isOnline ? Icons.hourglass_empty : Icons.cloud_off,
                        size: 36,
                        color: _isOnline
                            ? const Color(0xFFFFCC00)
                            : const Color(0xFF6B6B80),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isOnline
                          ? 'Waiting for ride requests...'
                          : 'You are currently offline',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isOnline
                          ? 'New rides will appear here automatically.\nStay online to receive requests nearby.'
                          : 'Go online to start receiving\nride requests from passengers.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B6B80),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],

            if (_urgentRequests.isNotEmpty && _isOnline) ...[
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFEF4444).withOpacity(0.2),
                      const Color(0xFFF97316).withOpacity(0.2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withOpacity(0.5),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.notifications_active,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                ' Urgent Requests',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_urgentRequests.length} ride${_urgentRequests.length > 1 ? 's' : ''} waiting for your response',
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ..._urgentRequests.map((req) {
                      final isExpanded = _expandedRequestId == req['id'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0A0A),
                          border: Border.all(color: const Color(0xFF333333)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF3B82F6),
                                        Color(0xFF06B6D4),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        req['userName'],
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const Text(
                                        'Standard',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFFA0A0A0),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFCC00).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFFFCC00), width: 1),
                                  ),
                                  child: Text(
                                    '+${(req['priorityPrice'] as double).toStringAsFixed(3)} DT',
                                    style: const TextStyle(color: Color(0xFFFFCC00), fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                             Text(
                               '${req['distance']} • ${req['duration']}${req['distanceToPickup'] != null ? ' • ${req['distanceToPickup']}' : ''}',
                               style: const TextStyle(
                                 fontSize: 12,
                                 color: Color(0xFFFFCC00),
                                 fontWeight: FontWeight.bold,
                               ),
                             ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.payments, color: Colors.greenAccent, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    req['estimatedPrice'] != 'N/A'
                                        ? 'Prix estimé: ${req['estimatedPrice']}'
                                        : 'Prix base: ${req['basePrice']}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A1A1A),
                                      border: Border.all(
                                        color: const Color(0xFF333333),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      children: [
                                        const Text(
                                          'Scheduled',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFFA0A0A0),
                                          ),
                                        ),
                                        Text(
                                          req['time'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFFFCC00),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFEF4444,
                                      ).withOpacity(0.1),
                                      border: Border.all(
                                        color: const Color(
                                          0xFFEF4444,
                                        ).withOpacity(0.3),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      children: [
                                        const Text(
                                          'EXPIRES IN',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFFF87171),
                                          ),
                                        ),
                                        Text(
                                          formatTime(req['expiresIn']),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFF87171),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (isExpanded) ...[
                              const SizedBox(height: 16),
                              Container(
                                height: 1,
                                color: const Color(0xFF333333),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF22C55E,
                                  ).withOpacity(0.1),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF22C55E,
                                    ).withOpacity(0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: Color(0xFF4ADE80),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'PICKUP LOCATION',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF4ADE80),
                                            ),
                                          ),
                                          Text(
                                            req['pickup'],
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFEF4444,
                                  ).withOpacity(0.1),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFEF4444,
                                    ).withOpacity(0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: Color(0xFFF87171),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'DROPOFF LOCATION',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFFF87171),
                                            ),
                                          ),
                                          Text(
                                            req['dropoff'],
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_previewRoutePoints.isNotEmpty && isExpanded)
                                Container(
                                  height: 150,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF333333)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: FlutterMap(
                                      options: MapOptions(
                                        initialCenter: _previewRoutePoints.isNotEmpty 
                                          ? _previewRoutePoints[0] 
                                          : const LatLng(36.8065, 10.1815),
                                        initialZoom: 12.0,
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${Env.mapboxToken}',
                                        ),
                                        PolylineLayer(
                                          polylines: [
                                            Polyline(
                                              points: _previewRoutePoints,
                                              color: const Color(0xFFFFCC00),
                                              strokeWidth: 3,
                                            ),
                                          ],
                                        ),
                                        MarkerLayer(
                                          markers: [
                                            Marker(
                                              point: _previewRoutePoints.first,
                                              child: const Icon(Icons.location_on, color: Colors.green, size: 20),
                                            ),
                                            Marker(
                                              point: _previewRoutePoints.last,
                                              child: const Icon(Icons.location_on, color: Colors.red, size: 20),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.info_outline,
                                      color: Color(0xFFFFCC00),
                                      size: 12,
                                    ),
                                    label: Text(
                                      isExpanded ? 'Hide' : 'Details',
                                      style: const TextStyle(
                                        color: Color(0xFFFFCC00),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onPressed: () =>
                                        toggleRequestDetails(req),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 8,
                                      ),
                                      side: const BorderSide(
                                        color: Color(0xFFFFCC00),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      backgroundColor: const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 3,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.check_circle,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    label: const Text(
                                      'Accept',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onPressed: () async {
                                      try {
                                        await _apiService.acceptRide(req['id']);
                                        setState(() {
                                          _urgentRequests.removeWhere(
                                            (r) => r['id'] == req['id'],
                                          );
                                        });
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('✅ Course acceptée !'),
                                              backgroundColor: Color(0xFF22C55E),
                                            ),
                                          );
                                          // Navigate to active ride
                                          Navigator.pushReplacementNamed(context, '/driver/active');
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Erreur: $e')),
                                          );
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 8,
                                      ),
                                      backgroundColor: const Color(0xFF22C55E),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  flex: 3,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.cancel,
                                      color: Color(0xFFF87171),
                                      size: 12,
                                    ),
                                    label: const Text(
                                      'Reject',
                                      style: TextStyle(
                                        color: Color(0xFFF87171),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onPressed: () async {
                                      try {
                                        await _apiService.cancelRide(req['id']);
                                      } catch (_) {}
                                      setState(() {
                                        _urgentRequests.removeWhere(
                                          (r) => r['id'] == req['id'],
                                        );
                                      });
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 8,
                                      ),
                                      side: const BorderSide(
                                        color: Color(0xFFEF4444),
                                        width: 2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      backgroundColor: const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ─── Stats Cards (always visible) ───
            if (_driverStats != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.today,
                      label: "Today",
                      value: '${_driverStats!['today_rides'] ?? 0}',
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.check_circle_outline,
                      label: 'Completed',
                      value: '${_driverStats!['completed_rides'] ?? 0}',
                      color: const Color(0xFF22C55E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.star_rounded,
                      label: 'Rating',
                      value: (_driverStats!['average_rating'] as num?)?.toStringAsFixed(1) ?? '0.0',
                      color: const Color(0xFFFFCC00),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.trending_up,
                      label: 'Accept Rate',
                      value: '${(_driverStats!['acceptance_rate'] as num?)?.toStringAsFixed(0) ?? '0'}%',
                      color: const Color(0xFFA855F7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ─── Performance Metrics ───
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF111118), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.speed, color: Color(0xFFFFCC00), size: 20),
                        SizedBox(width: 8),
                        Text("Performance Metrics", style: TextStyle(color: Color(0xFFFFCC00), fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _perfMetric("Reliability", "98%", Colors.green),
                        _perfMetric("Acceptance", "${(_driverStats!['acceptance_rate'] as num?)?.toStringAsFixed(0) ?? '0'}%", const Color(0xFFFFCC00)),
                        _perfMetric("Rejection", "${100 - ((_driverStats!['acceptance_rate'] as num?)?.toInt() ?? 0)}%", Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111118),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B6B80),
            ),
          ),
        ],
      ),
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
}