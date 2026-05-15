import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../auth/driver_layout.dart';
import '../../services/driver_api_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class DriverRequests extends StatefulWidget {
  const DriverRequests({Key? key}) : super(key: key);

  @override
  _DriverRequestsState createState() => _DriverRequestsState();
}

class _DriverRequestsState extends State<DriverRequests> {
  int? _expandedRequestId;

  final DriverApiService _apiService = DriverApiService();
  List<Map<String, dynamic>> _urgentRequests = [];
  bool _isLoading = true;
  List<LatLng> _previewRoutePoints = [];
  LatLng? _currentPosition;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _startLocationTracking();
  }

  Future<void> _startLocationTracking() async {
    try {
      Position p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) setState(() => _currentPosition = LatLng(p.latitude, p.longitude));
    } catch (_) {}

    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        Position p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        );
        if (mounted) setState(() => _currentPosition = LatLng(p.latitude, p.longitude));
      } catch (_) {}
    });
  }

  Future<void> _loadRequests() async {
    try {
      final data = await _apiService.getAcceptedRides();
      setState(() {
        _urgentRequests = data.map((e) => {
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
              ? DateTime.parse(e['scheduled_for']).hour.toString().padLeft(2, '0') + ":" + 
                DateTime.parse(e['scheduled_for']).minute.toString().padLeft(2, '0')
              : 'NOW',
          'distance': '${e['distance_km'] ?? '?.?'} km',
          'duration': '${e['time_mins'] ?? '??'} min',
          'expiresIn': 0, 
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
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

    final String token = Env.mapboxToken;
    
    // Ride route
    final url = Uri.parse('https://api.mapbox.com/directions/v5/mapbox/driving/$pLng,$pLat;$dLng,$dLat?geometries=geojson&overview=full&access_token=$token');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final r = routes[0];
          final points = (r['geometry']['coordinates'] as List).map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          if (mounted) {
            setState(() {
              _previewRoutePoints = points;
              req['distance'] = '${((r['distance'] as num) / 1000).toStringAsFixed(1)} km';
              req['duration'] = '${((r['duration'] as num) / 60).round()} min';
            });
          }
        }
      }

      if (_currentPosition != null) {
        final toPickupUrl = Uri.parse('https://api.mapbox.com/directions/v5/mapbox/driving/${_currentPosition!.longitude},${_currentPosition!.latitude};$pLng,$pLat?access_token=$token');
        final resToPickup = await http.get(toPickupUrl);
        if (resToPickup.statusCode == 200) {
          final data = jsonDecode(resToPickup.body);
          final routes = data['routes'] as List?;
          if (routes != null && routes.isNotEmpty) {
            final d = (routes[0]['distance'] as num) / 1000;
            if (mounted) setState(() => req['distanceToPickup'] = '${d.toStringAsFixed(1)} km to client');
          }
        }
      }
    } catch (_) {}
  }

  String formatTime(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // The exact same highly optimized flex layout from dashboard
    return DriverLayout(
      title: 'Requests',
      currentIndex: 1,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Accepted Rides ', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Manage your currently accepted and scheduled rides', style: TextStyle(color: Color(0xFFA0A0A0))),
            const SizedBox(height: 24),
            
            if (_urgentRequests.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Text("No accepted rides at the moment.", style: TextStyle(color: Color(0xFFA0A0A0))),
                ),
              ),

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
                            gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(req['userName'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                              Text(req['userType'], style: const TextStyle(fontSize: 14, color: Color(0xFFA0A0A0)), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('${req['distance']} • ${req['duration']}${req['distanceToPickup'] != null ? ' • ${req['distanceToPickup']}' : ''}', style: const TextStyle(fontSize: 12, color: Color(0xFFFFCC00), fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              border: Border.all(color: const Color(0xFF333333)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text('Scheduled', style: TextStyle(fontSize: 10, color: Color(0xFFA0A0A0))),
                                Text(req['time'], style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFCC00)), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E).withOpacity(0.1),
                              border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text('STATUS', style: TextStyle(fontSize: 10, color: Color(0xFF4ADE80))),
                                const Text('Accepted', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4ADE80)), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isExpanded) ...[
                      const SizedBox(height: 16),
                      Container(height: 1, color: const Color(0xFF333333)),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withOpacity(0.1),
                          border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: Color(0xFF4ADE80), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('PICKUP LOCATION', style: TextStyle(fontSize: 10, color: Color(0xFF4ADE80))),
                                  Text(req['pickup'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.1),
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: Color(0xFFF87171), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('DROPOFF LOCATION', style: TextStyle(fontSize: 10, color: Color(0xFFF87171))),
                                  Text(req['dropoff'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_previewRoutePoints.isNotEmpty && isExpanded)
                        Container(
                          height: 150,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF333333))),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FlutterMap(
                              options: MapOptions(initialCenter: _previewRoutePoints.first, initialZoom: 12.0),
                              children: [
                                TileLayer(urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${Env.mapboxToken}'),
                                PolylineLayer(polylines: [Polyline(points: _previewRoutePoints, color: const Color(0xFFFFCC00), strokeWidth: 3)]),
                                MarkerLayer(markers: [
                                  Marker(point: _previewRoutePoints.first, child: const Icon(Icons.location_on, color: Colors.green, size: 20)),
                                  Marker(point: _previewRoutePoints.last, child: const Icon(Icons.location_on, color: Colors.red, size: 20)),
                                ]),
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
                            icon: const Icon(Icons.info_outline, color: Color(0xFFFFCC00), size: 12),
                            label: Text(isExpanded ? 'Hide' : 'Details', style: const TextStyle(color: Color(0xFFFFCC00), fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () => toggleRequestDetails(req),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              side: const BorderSide(color: Color(0xFFFFCC00)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              backgroundColor: const Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.map, color: Colors.white, size: 12),
                            label: const Text('Track', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () {
                              Navigator.pushNamed(context, '/driver/active');
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              backgroundColor: const Color(0xFFFFCC00),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 3,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.cancel, color: Color(0xFFF87171), size: 12),
                            label: const Text('Cancel', style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () async {
                              try {
                                await _apiService.cancelRide(req['id']);
                                setState(() {
                                  _urgentRequests.removeWhere((r) => r['id'] == req['id']);
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Course annulée')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Erreur: $e')),
                                  );
                                }
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              side: const BorderSide(color: Color(0xFFEF4444), width: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              backgroundColor: const Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}