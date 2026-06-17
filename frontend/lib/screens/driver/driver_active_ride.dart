import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../services/driver_api_service.dart';
import '../../services/location_permission_service.dart';
import '../auth/driver_layout.dart';
import '../../env.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:url_launcher/url_launcher.dart';

class DriverActiveRide extends StatefulWidget {
  const DriverActiveRide({Key? key}) : super(key: key);

  @override
  _DriverActiveRideState createState() => _DriverActiveRideState();
}

class _DriverActiveRideState extends State<DriverActiveRide>
    with TickerProviderStateMixin {
  // ── GPS & Map ─────────────────────────────────────────────────────────
  Timer? _locationTimer;
  Timer? _roamTimer;
  Timer? _rideRefreshTimer;
  Timer? _socketTimer;
  Timer? _simulationTimer;
  LatLng? _currentPosition;
  LatLng? _originalPosition;
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];
  bool _mapReady = false;
  bool _permissionGranted = false;
  StreamSubscription<Position>? _positionSubscription;
  bool _simulateMode = false;
  double _taxiHeading = 0.0;
  LatLng? _prevPosition;

  // ── WebSocket ─────────────────────────────────────────────────────────
  WebSocketChannel? _locationChannel;
  int? _driverId;

  // ── Ride data ─────────────────────────────────────────────────────────
  final DriverApiService _apiService = DriverApiService();
  Map<String, dynamic>? _activeRide;
  bool _isLoading = true;
  bool _rideStarted = false;
  bool _isActionLoading = false;
  double? _routeDistanceKm;
  int? _routeDurationMin;
  bool _isMapExpanded = false;
  bool _isSharingLocation = false; // Disabled by default

  // ── Animation pulse ───────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const String _mapboxToken = Env.mapboxToken;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(_pulseController);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDriverProfile();
      final bool granted = kIsWeb ? await _requestWebLocationPermission() : await LocationPermissionService.requestWithDialog(context);
      if (mounted) {
        setState(() => _permissionGranted = granted);
        if (granted) await _initLocationAndRide(); else setState(() => _isLoading = false);
      }
    });
  }

  void _initWebSocket() async {
    if (_activeRide == null) {
      print("DRIVER WS: No active ride yet, skipping WS init");
      return;
    }
    if (_locationChannel != null) return; // Already connected
    final rideId = _activeRide!['request_id'];
    try {
      final wsUrl = '${Env.baseUrl.replaceFirst('http', 'ws')}/rides/$rideId/ws';
      print("DRIVER WS: Connecting to $wsUrl");
      
      _locationChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _locationChannel!.stream.listen(
        (msg) => print("DRIVER WS RECV: $msg"),
        onError: (err) {
          print("DRIVER WS ERROR: $err");
          _locationChannel = null;
        },
        onDone: () {
          print("DRIVER WS CLOSED");
          _locationChannel = null;
        }
      );
      print("DRIVER WS: Connected to ride $rideId");
    } catch (e) { 
      print('DRIVER WS INIT ERROR: $e'); 
      _locationChannel = null;
    }
  }

  Future<void> _loadDriverProfile() async {
    try {
      final profile = await _apiService.getProfile();
      if (mounted) setState(() => _driverId = profile['user_id']);
    } catch (_) { if (mounted) setState(() => _driverId = 1); }
  }

  Future<void> _initLocationAndRide() async {
    await _startLocationTracking();
    await _loadActiveRide();
    _startActiveRidePolling();
    _startSocketPublishing();
  }

  Future<bool> _requestWebLocationPermission() async {
    final p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      final r = await Geolocator.requestPermission();
      return r == LocationPermission.always || r == LocationPermission.whileInUse;
    }
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  Future<void> _startLocationTracking() async {
    if (_simulateMode) return;
    try {
      Position pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) setState(() { _currentPosition = LatLng(pos.latitude, pos.longitude); _originalPosition ??= _currentPosition; });
    } catch (_) {}

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 5)).listen((pos) {
      if (!mounted) return;
      final newPos = LatLng(pos.latitude, pos.longitude);
      _updateTaxiHeading(newPos);
      setState(() { _currentPosition = newPos; _originalPosition ??= newPos; });
      _onPositionUpdated();
    });

    _locationTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      try {
        Position pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation));
        if (mounted) {
          final newPos = LatLng(pos.latitude, pos.longitude);
          _updateTaxiHeading(newPos);
          setState(() { _currentPosition = newPos; _originalPosition ??= newPos; });
          _onPositionUpdated();
        }
      } catch (_) {}
    });
  }

  void _updateTaxiHeading(LatLng newPos) {
    if (_currentPosition == null) return;
    final dLat = newPos.latitude - _currentPosition!.latitude;
    final dLng = newPos.longitude - _currentPosition!.longitude;
    if (dLat.abs() < 0.000001 && dLng.abs() < 0.000001) return;
    setState(() => _taxiHeading = math.atan2(dLng, dLat) * (180 / math.pi));
  }

  Future<void> _onPositionUpdated() async {
    if (_currentPosition != null && _mapReady) {
      try { _mapController.move(_currentPosition!, _mapController.camera.zoom); } catch (_) {}
    }
    if (_activeRide != null) {
      final now = DateTime.now();
      if (_lastRouteFetchAt != null && now.difference(_lastRouteFetchAt!) < const Duration(seconds: 6)) return;
      _lastRouteFetchAt = now;
      await _fetchRoute();
      _focusMapOnRide();
    }
  }

  void _startSocketPublishing() {
    _socketTimer?.cancel();
    _socketTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isSharingLocation) {
        _publishCurrentPositionToSocket();
      }
    });
  }

  void _publishCurrentPositionToSocket() {
    if (_currentPosition == null || _activeRide == null) return;
    // If WS is closed, reconnect first and retry next tick
    if (_locationChannel == null) {
      _initWebSocket();
      return;
    }
    try {
      final payload = jsonEncode({
        'lat': _currentPosition!.latitude, 
        'lng': _currentPosition!.longitude, 
        'timestamp': DateTime.now().toIso8601String(),
        'ride_id': _activeRide!['request_id'],
        'simulated': _simulateMode
      });
      _locationChannel!.sink.add(payload);
      print("DRIVER WS SENT: lat=${_currentPosition!.latitude}, lng=${_currentPosition!.longitude}");
    } catch (e) { 
      print("DRIVER WS SEND ERROR: $e");
      _locationChannel = null; // Mark as dead so next tick reconnects
    }
  }

  void _toggleSimulationMode() {
    setState(() => _simulateMode = !_simulateMode);
    if (_simulateMode) {
      _positionSubscription?.cancel(); _locationTimer?.cancel(); _startSimulationMovement();
      _showSnack('Simulation mode ON', const Color(0xFF60A5FA));
    } else {
      _simulationTimer?.cancel(); _startLocationTracking();
      _showSnack('GPS mode ON', const Color(0xFF4ADE80));
    }
  }

  void _startSimulationMovement() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _activeRide == null) return;
      final target = _getDestinationCoords(); if (target == null) return;
      final current = _currentPosition ?? target;
      const step = 0.00035;
      final dLat = target.latitude - current.latitude, dLng = target.longitude - current.longitude;
      final distance = math.sqrt(dLat * dLat + dLng * dLng);
      if (distance < step) { setState(() => _currentPosition = target); _onPositionUpdated(); return; }
      final next = LatLng(current.latitude + (dLat / distance) * step, current.longitude + (dLng / distance) * step);
      _updateTaxiHeading(next);
      setState(() => _currentPosition = next);
      _onPositionUpdated();
    });
  }

  LatLng? _getDestinationCoords() {
    if (_activeRide == null) return null;
    final prefix = _rideStarted ? 'dropoff' : 'pickup';
    final lat = _activeRide!['${prefix}_lat'], lng = _activeRide!['${prefix}_lng'];
    return (lat != null && lng != null) ? LatLng((lat as num).toDouble(), (lng as num).toDouble()) : null;
  }

  bool _isFetchingRoute = false;
  DateTime? _lastRouteFetchAt;
  Future<void> _fetchRoute() async {
    if (_currentPosition == null || _activeRide == null || _isFetchingRoute) return;
    _isFetchingRoute = true;
    final dest = _getDestinationCoords(); if (dest == null) { _isFetchingRoute = false; return; }
    final url = Uri.parse('https://api.mapbox.com/directions/v5/mapbox/driving/${_currentPosition!.longitude},${_currentPosition!.latitude};${dest.longitude},${dest.latitude}?geometries=geojson&overview=full&access_token=$_mapboxToken');
    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final r = routes[0];
          final points = (r['geometry']['coordinates'] as List).map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          if (mounted) setState(() { _routePoints = points; _routeDistanceKm = (r['distance'] as num).toDouble() / 1000; _routeDurationMin = ((r['duration'] as num).toDouble() / 60).round(); });
        }
      }
    } catch (_) {} finally { _isFetchingRoute = false; }
  }

  void _focusMapOnRide() {
    if (!_mapReady) return;
    
    List<LatLng> pointsToInclude = [];
    if (_currentPosition != null) pointsToInclude.add(_currentPosition!);
    
    if (_activeRide != null) {
      final pLat = _activeRide!['pickup_lat'];
      final pLng = _activeRide!['pickup_lng'];
      final dLat = _activeRide!['dropoff_lat'];
      final dLng = _activeRide!['dropoff_lng'];
      
      if (pLat != null && pLng != null) pointsToInclude.add(LatLng((pLat as num).toDouble(), (pLng as num).toDouble()));
      if (dLat != null && dLng != null) pointsToInclude.add(LatLng((dLat as num).toDouble(), (dLng as num).toDouble()));
    }
    
    if (_routePoints.isNotEmpty) pointsToInclude.addAll(_routePoints);
    
    if (pointsToInclude.isEmpty) return;

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in pointsToInclude) {
      if (p.latitude < minLat) minLat = p.latitude; if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude; if (p.longitude > maxLng) maxLng = p.longitude;
    }
    
    final latP = (maxLat - minLat) * 0.2, lngP = (maxLng - minLng) * 0.2;
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(minLat - latP, minLng - lngP), 
        LatLng(maxLat + latP, maxLng + lngP)
      ), 
      padding: const EdgeInsets.all(50)
    ));
  }

  void _startActiveRidePolling() {
    _rideRefreshTimer?.cancel();
    _rideRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) => _loadActiveRide(silent: true));
  }

  Future<void> _loadActiveRide({bool silent = false}) async {
    try {
      final ride = await _apiService.getActiveRide();
      if (mounted) {
        setState(() { _activeRide = ride; if (!silent) _isLoading = false; _rideStarted = ride != null && ride['ride_started'] == true; if (ride == null) { _routeDistanceKm = null; _routeDurationMin = null; _routePoints = []; } });
        if (ride != null) { await _fetchRoute(); _focusMapOnRide(); if (_locationChannel == null) _initWebSocket(); }
      }
    } catch (_) { if (mounted && !silent) setState(() => _isLoading = false); }
  }

  Future<void> _startRide() async {
    if (_activeRide == null) return;
    setState(() => _isActionLoading = true);
    try {
      await _apiService.updateRideStatus(_activeRide!['request_id'], 'start');
      if (mounted) {
        setState(() { 
          _rideStarted = true; 
          _isActionLoading = false; 
          _routePoints = []; 
          _routeDistanceKm = null; 
          _routeDurationMin = null; 
        });
      }
      _showSnack('Ride started! ', const Color(0xFF4ADE80));
      await _fetchRoute();
    } catch (e) { 
      if (mounted) setState(() => _isActionLoading = false);
      _showSnack('Failed to start ride: $e', Colors.red);
    }
  }

  Future<void> _endRide() async {
    if (_activeRide == null) return;
    setState(() => _isActionLoading = true);
    try {
      await _apiService.updateRideStatus(_activeRide!['request_id'], 'complete');
      _locationChannel?.sink.close(); _locationChannel = null;
      if (mounted) {
        setState(() { 
          _activeRide = null; 
          _rideStarted = false; 
          _routePoints = []; 
          _routeDistanceKm = null; 
          _routeDurationMin = null; 
          _isActionLoading = false; 
        });
      }
      _showSnack('Ride completed! ', const Color(0xFFFFCC00));
    } catch (e) { 
      if (mounted) setState(() => _isActionLoading = false);
      _showSnack('Failed to complete ride: $e', Colors.red);
    }
  }

  void _showSnack(String m, Color c) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: c, behavior: SnackBarBehavior.floating)); }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      _showSnack('Passenger phone number not available', Colors.orange);
      return;
    }
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } catch (e) { 
      _showSnack('Could not launch dialer: $e', Colors.red); 
    }
  }

  Future<void> _openWhatsApp(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      _showSnack('Passenger phone number not available', Colors.orange);
      return;
    }
    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNumber.startsWith('00')) cleanNumber = cleanNumber.substring(2);
    
    // Most reliable way for modern Android/iOS
    final whatsappUri = Uri.parse("whatsapp://send?phone=$cleanNumber");
    final httpsUri = Uri.parse("https://wa.me/$cleanNumber");
    
    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(httpsUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) { 
      _showSnack('Could not launch WhatsApp', Colors.red); 
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel(); _roamTimer?.cancel(); _rideRefreshTimer?.cancel(); _socketTimer?.cancel(); _simulationTimer?.cancel(); _positionSubscription?.cancel(); _pulseController.dispose(); _mapController.dispose(); _locationChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return DriverLayout(title: 'Active Ride', currentIndex: 2, child: const Center(child: CircularProgressIndicator(color: Color(0xFFFFCC00))));
    if (!_permissionGranted) return DriverLayout(title: 'Active Ride', currentIndex: 2, child: _buildPermissionDenied());

    return DriverLayout(
      title: 'Active Ride',
      currentIndex: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0a0a0a),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildStatusProgressBar(),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              bool isWide = constraints.maxWidth > 900;
              return isWide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 2, child: _buildLeftColumn()), const SizedBox(width: 24), Expanded(flex: 1, child: _buildRightColumn())]) : Column(children: [_buildLeftColumn(), const SizedBox(height: 24), _buildRightColumn()]);
            }),
          ]),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.location_off, color: Color(0xFFF87171), size: 72), const SizedBox(height: 20), const Text('Location required', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 20), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFCC00), foregroundColor: Colors.black), onPressed: () async { final b = await _requestWebLocationPermission(); setState(() => _permissionGranted = b); if (b) _initLocationAndRide(); }, child: const Text('Allow Location'))]));

  Widget _buildHeader() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Active Ride Tracking 🚕', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFFFCC00))), const SizedBox(height: 8), Text(_activeRide != null ? 'REF-${_activeRide!['request_id'].toString().padLeft(4, '0')} - Real-time tracking' : 'Available for rides', style: const TextStyle(fontSize: 16, color: Color(0xFFa0a0a0)))]);

  Widget _buildStatusProgressBar() {
    final steps = [{'l': 'Accepted', 'i': Icons.check_circle}, {'l': 'Arrived', 'i': Icons.location_on}, {'l': 'In Progress', 'i': Icons.directions_car}, {'l': 'Completed', 'i': Icons.flag}];
    int current = -1;
    if (_activeRide != null) { final s = _activeRide!['status']; if (s == 'COMPLETED') current = 3; else if (_rideStarted) current = 2; else if (s == 'ARRIVED' || s == 'IN_PROGRESS') current = 1; else current = 0; }
    return Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF1a1a1a), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(16)), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: List.generate(steps.length, (idx) {
      bool done = idx <= current;
      return Row(children: [
        Column(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(gradient: done ? const LinearGradient(colors: [Color(0xFFFFCC00), Color(0xFFff9900)]) : null, color: done ? null : const Color(0xFF0f0f0f), border: done ? null : Border.all(color: const Color(0xFF333333), width: 2), borderRadius: BorderRadius.circular(24)), child: Icon(steps[idx]['i'] as IconData, color: done ? Colors.black : const Color(0xFF555555), size: 24)),
          const SizedBox(height: 8),
          Text(steps[idx]['l'] as String, style: TextStyle(fontSize: 10, color: done ? Colors.white : const Color(0xFF555555), fontWeight: done ? FontWeight.w600 : FontWeight.normal)),
        ]),
        if (idx < steps.length - 1) Container(width: 40, height: 2, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(gradient: idx < current ? const LinearGradient(colors: [Color(0xFFFFCC00), Color(0xFFff9900)]) : null, color: idx < current ? null : const Color(0xFF333333))),
      ]);
    }))));
  }

  Widget _buildLeftColumn() => Column(children: [_buildMapCard(), const SizedBox(height: 24), if (_activeRide != null) _buildRouteDetails()]);

  Widget _buildMapCard() => Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF1a1a1a), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: const [Icon(Icons.navigation, color: Color(0xFFFFCC00), size: 24), SizedBox(width: 8), Text('Live GPS Tracking', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))]),
    const SizedBox(height: 16),
    if (_activeRide != null) Row(children: [_buildCompactLoc("Pickup", _activeRide!['pickup_location'] ?? '...', Colors.green), const SizedBox(width: 8), _buildCompactLoc("Dropoff", _activeRide!['dropoff_location'] ?? '...', Colors.red)]),
    const SizedBox(height: 12),
    _buildMap(),
  ]));

  Widget _buildCompactLoc(String l, String a, Color c) => Expanded(child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(Icons.location_on, color: c, size: 14), const SizedBox(width: 6), Expanded(child: Text(a, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis))])));

  Widget _buildRouteDetails() => Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF1a1a1a), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Route Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
    const SizedBox(height: 24),
    _buildLocItem(icon: Icons.location_on, color: Colors.green, label: 'PICKUP', addr: _activeRide!['pickup_location'] ?? '...'),
    Padding(padding: const EdgeInsets.only(left: 24), child: Container(width: 2, height: 40, color: const Color(0xFF333333))),
    _buildLocItem(icon: Icons.location_on, color: Colors.red, label: 'DROPOFF', addr: _activeRide!['dropoff_location'] ?? '...'),
  ]));

  Widget _buildLocItem({required IconData icon, required Color color, required String label, required String addr}) => Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFa0a0a0))), Text(addr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))]))]);

  Widget _buildRightColumn() => Column(children: [_buildStatusCard(), const SizedBox(height: 24), if (_activeRide != null) _buildPassengerCard(), const SizedBox(height: 24), if (_activeRide != null) _buildActionBtn()]);

  Widget _buildStatusCard() {
    String t = "Status", d = "Waiting...";
    if (_activeRide != null) { if (_rideStarted) { t = "In Progress"; d = "Driving..."; } else { t = "On the way"; d = "Picking up..."; } }
    return Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFCC00), Color(0xFFff9900)]), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)), 
      const SizedBox(height: 16), 
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('DISTANCE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 10)),
          Text('${_routeDistanceKm?.toStringAsFixed(1) ?? '--'} km', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('ETA', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 10)),
          Text('${_routeDurationMin ?? '--'} min', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black)),
        ]),
      ]), 
      Text(d, style: const TextStyle(fontSize: 14, color: Colors.black87))
    ]));
  }

  Widget _buildPassengerCard() => Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF1a1a1a), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Passenger', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
    const SizedBox(height: 16),
    Row(children: [Container(width: 64, height: 64, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.blue, Colors.cyan]), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.person, color: Colors.white, size: 32)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_activeRide!['passenger'] ?? 'Passenger', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), const Text('Regular User', style: TextStyle(color: Color(0xFFa0a0a0)))]))]),
    const SizedBox(height: 24),
    Row(children: [
      Expanded(child: ElevatedButton.icon(onPressed: () => _openWhatsApp(_activeRide!['passenger_phone']), icon: const Icon(Icons.message), label: const Text('WhatsApp'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))), 
      const SizedBox(width: 12), 
      Expanded(child: OutlinedButton.icon(onPressed: () => _makePhoneCall(_activeRide!['passenger_phone']), icon: const Icon(Icons.call), label: const Text('Call'), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF333333)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))))
    ]),
    const SizedBox(height: 16),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isSharingLocation ? const Color(0xFF22C55E).withOpacity(0.1) : const Color(0xFF333333).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isSharingLocation ? const Color(0xFF22C55E).withOpacity(0.3) : const Color(0xFF333333)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.share_location, color: _isSharingLocation ? const Color(0xFF22C55E) : Colors.white54, size: 20),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Live Location', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(_isSharingLocation ? 'Sharing with client' : 'Location private', style: TextStyle(color: _isSharingLocation ? const Color(0xFF22C55E) : Colors.white54, fontSize: 10)),
                ],
              ),
            ],
          ),
          Switch(
            value: _isSharingLocation,
            activeColor: const Color(0xFF22C55E),
            onChanged: (val) {
              setState(() => _isSharingLocation = val);
              if (val) {
                // Connect WS immediately and publish first position right away
                if (_locationChannel == null) _initWebSocket();
                Future.delayed(const Duration(milliseconds: 300), _publishCurrentPositionToSocket);
                _showSnack('Location sharing enabled! 📍', const Color(0xFF22C55E));
              } else {
                _showSnack('Location sharing disabled', Colors.grey);
              }
            },
          ),
        ],
      ),
    ),
  ]));

  Widget _buildActionBtn() {
    if (_isActionLoading) return const CircularProgressIndicator();
    if (_activeRide == null) return const SizedBox.shrink();

    bool canClick = true;
    String btnText = _rideStarted ? 'COMPLETE RIDE' : 'START RIDE';
    Color btnColor = _rideStarted ? Colors.red : const Color(0xFFFFCC00);

    // Geofencing for START RIDE
    if (!_rideStarted && _currentPosition != null) {
      final pLat = _activeRide!['pickup_lat'];
      final pLng = _activeRide!['pickup_lng'];
      if (pLat != null && pLng != null) {
        final double dist = Geolocator.distanceBetween(
          _currentPosition!.latitude, _currentPosition!.longitude,
          (pLat as num).toDouble(), (pLng as num).toDouble()
        );
        
        if (dist > 100) { // More than 100 meters away
          canClick = false;
          btnText = 'GET CLOSER TO PICKUP (${(dist/1000).toStringAsFixed(1)}km)';
          btnColor = Colors.grey.shade800;
        }
      }
    }

    return ElevatedButton(
      onPressed: canClick ? (_rideStarted ? _endRide : _startRide) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: btnColor,
        foregroundColor: canClick ? Colors.black : Colors.white24,
        disabledBackgroundColor: btnColor,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: canClick ? 4 : 0,
      ),
      child: Text(btnText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
    );
  }

  Widget _buildMap() => AnimatedContainer(duration: const Duration(milliseconds: 400), height: _isMapExpanded ? 600 : 300, decoration: BoxDecoration(color: const Color(0xFF0f0f0f), border: Border.all(color: const Color(0xFF333333)), borderRadius: BorderRadius.circular(12)), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(children: [
    FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: _currentPosition ?? const LatLng(36.8065, 10.1815), initialZoom: 15.0, onMapReady: () => _mapReady = true), children: [
      TileLayer(urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$_mapboxToken'),
      if (_routePoints.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _routePoints, color: const Color(0xFF99CC00), strokeWidth: 4.0)]),
      MarkerLayer(markers: [
        if (_activeRide != null && _activeRide!['pickup_lat'] != null) Marker(point: LatLng((_activeRide!['pickup_lat'] as num).toDouble(), (_activeRide!['pickup_lng'] as num).toDouble()), child: _marker(Colors.green)),
        if (_activeRide != null && _activeRide!['dropoff_lat'] != null) Marker(point: LatLng((_activeRide!['dropoff_lat'] as num).toDouble(), (_activeRide!['dropoff_lng'] as num).toDouble()), child: _marker(Colors.red)),
        if (_currentPosition != null) Marker(point: _currentPosition!, child: _taxiMarker()),
      ]),
    ]),
    Positioned(top: 10, right: 10, child: FloatingActionButton.small(onPressed: () => setState(() => _isMapExpanded = !_isMapExpanded), child: Icon(_isMapExpanded ? Icons.fullscreen_exit : Icons.fullscreen))),
    Positioned(bottom: 10, left: 10, child: FloatingActionButton.small(backgroundColor: _simulateMode ? Colors.blue : null, onPressed: _toggleSimulationMode, child: const Icon(Icons.smart_toy))),
  ])));

  Widget _marker(Color c) => Container(width: 24, height: 24, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))]));
  Widget _taxiMarker() => Transform.rotate(angle: _taxiHeading * (math.pi / 180), child: Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFFFCC00), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)), child: const Icon(Icons.local_taxi, size: 20)));
}