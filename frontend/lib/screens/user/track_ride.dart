import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../env.dart';

/// Énumération pour les statuts de course
enum RideStatus {
  confirmed,
  driverAssigned,
  driverApproaching,
  arrived,
  inProgress,
  completed
}

/// Page de suivi de course en temps réel
/// Équivalent de TrackRide.tsx en React
class TrackRidePage extends StatefulWidget {
  final Map<String, dynamic>? rideData;
  const TrackRidePage({Key? key, this.rideData}) : super(key: key);

  @override
  State<TrackRidePage> createState() => _TrackRidePageState();
}

class _TrackRidePageState extends State<TrackRidePage>
    with TickerProviderStateMixin {
  // État de la course
  RideStatus _rideStatus = RideStatus.driverApproaching;
  double _eta = 5.0; // minutes
  double _distance = 2.3; // km
  int _elapsedTime = 0; // secondes
  Timer? _updateTimer;

  // Map State
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;
  String _pickupAddress = "Loading...";
  String _dropoffAddress = "Loading...";
  List<LatLng> _routePoints = [];
  final MapController _mapController = MapController();
  double? _realDistance;
  double? _realDuration;

  // User Location State
  LatLng? _userLatLng;
  StreamSubscription<Position>? _positionStream;
  bool _isMapExpanded = false;

  // WebSocket for Real-time tracking
  WebSocketChannel? _channel;
  LatLng? _realDriverLatLng;

  // Real data from backend
  Map<String, dynamic>? _fetchedDriverData;
  Timer? _detailsTimer;

  // Contrôleurs d'animation
  late AnimationController _carAnimationController;
  late Animation<Offset> _carAnimation;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();

    // Animation de la voiture
    _carAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _carAnimation = Tween<Offset>(
      begin: const Offset(0.2, 0.4),
      end: const Offset(0.25, 0.25),
    ).animate(CurvedAnimation(
      parent: _carAnimationController,
      curve: Curves.easeInOut,
    ));

    // Animation de fade
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..forward();

    // Initialiser les points depuis rideData
    _initializeCoordinates();

    // Démarrer les mises à jour en temps réel
    _startRealTimeUpdates();
    
    // Suivi de la position réelle de l'utilisateur
    _initLocationTracking();

    // Récupérer les détails de la course et du chauffeur
    _startDetailsPolling();

    // Connect to WebSocket for real-time driver tracking
    _initWebSocket();
  }

  void _initWebSocket() {
    print("CLIENT WS: _initWebSocket called (channel=$_channel, hasPos=${_realDriverLatLng != null})");
    // If we already have a position, don't reconnect
    if (_channel != null && _realDriverLatLng != null) return; 
    
    // If we have a channel but no position, maybe it's stuck. Close it and try again.
    if (_channel != null) {
      print("CLIENT WS: Force closing old channel to retry...");
      _channel!.sink.close();
      _channel = null;
    }
    
    final data = widget.rideData;
    final rideId = data?['request_id'] ?? data?['id'];
    
    if (rideId != null) {
      try {
        final wsUrl = '${Env.baseUrl.replaceFirst('http', 'ws')}/rides/$rideId/ws';
        print("CLIENT WS ATTEMPTING CONNECTION to: $wsUrl");
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        
        _channel!.stream.listen((message) {
          print("CLIENT WS RECEIVED: $message");
          try {
            final dynamic decoded = (message is String) ? jsonDecode(message) : message;
            if (decoded['lat'] != null && decoded['lng'] != null) {
              final newLat = double.parse(decoded['lat'].toString());
              final newLng = double.parse(decoded['lng'].toString());
              
              if (mounted) {
                setState(() {
                  _realDriverLatLng = LatLng(newLat, newLng);
                });
                if (!_isMapExpanded) {
                  _mapController.move(_realDriverLatLng!, _mapController.camera.zoom);
                }
              }
            }
          } catch (e) {
            print("CLIENT WS PARSE ERROR: $e");
          }
        }, onError: (err) {
          print("CLIENT WS ERROR: $err");
          _channel = null; 
        }, onDone: () {
          print("CLIENT WS CLOSED");
          _channel = null; 
        });
        print("CLIENT WS HANDSHAKE SENT");
        _channel!.sink.add(jsonEncode({'type': 'client_ping'}));
        print("CLIENT WS: PING SENT");
      } catch (e) { 
        print('CLIENT WS INIT ERROR: $e');
        _channel = null;
      }
    } else {
      print("CLIENT WS SKIP: No Request ID yet");
    }
  }

  void _initializeCoordinates() {
    final data = widget.rideData;
    if (data != null) {
      _pickupAddress = data['pickup_location'] ?? 'Map Selection';
      _dropoffAddress = data['dropoff_location'] ?? 'Map Selection';

      if (data['pickup_lat'] != null && data['pickup_lng'] != null) {
        try {
          _pickupLatLng = LatLng(
            double.parse(data['pickup_lat'].toString()),
            double.parse(data['pickup_lng'].toString()),
          );
          
          // Centrer la carte sur le pickup
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pickupLatLng != null) {
              _mapController.move(_pickupLatLng!, 13);
            }
          });
        } catch (e) {
          debugPrint("Error parsing pickup coordinates: $e");
        }
      }
      
      if (data['dropoff_lat'] != null && data['dropoff_lng'] != null) {
        try {
          _dropoffLatLng = LatLng(
            double.parse(data['dropoff_lat'].toString()),
            double.parse(data['dropoff_lng'].toString()),
          );
        } catch (e) {
          debugPrint("Error parsing dropoff coordinates: $e");
        }
      }
      
      if (_pickupLatLng != null && _dropoffLatLng != null) {
        _getRoute();
      }
    }
  }

  Future<void> _initLocationTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied');
      return;
    }

    // Obtenir la position actuelle une fois
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _userLatLng = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint("Error getting initial position: $e");
    }

    // Écouter les mises à jour de position
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _userLatLng = LatLng(position.latitude, position.longitude);
        });
      }
    });
  }

  void _startDetailsPolling() {
    _fetchRideDetails();
    _detailsTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchRideDetails();
    });
  }

  Future<void> _fetchRideDetails() async {
    final data = widget.rideData;
    if (data == null || data['request_id'] == null) return;
    
    final requestId = data['request_id'];
    final url = "${Env.baseUrl}/rides/$requestId";
    
    try {
      final response = await http.get(Uri.parse(url), headers: Env.defaultHeaders);
      if (response.statusCode == 200) {
        final Map<String, dynamic> rideDetails = jsonDecode(response.body);
        debugPrint("API Response: $rideDetails");
        
        if (mounted) {
          setState(() {
            if (rideDetails['driver'] != null) {
              debugPrint("Driver found: ${rideDetails['driver']['name']}");
              _fetchedDriverData = rideDetails['driver'];
              
              // Mettre à jour le statut si nécessaire
              if (rideDetails['status'] == 'ACCEPTED' && _rideStatus == RideStatus.confirmed) {
                _rideStatus = RideStatus.driverAssigned;
              }
            }
          });
          _initWebSocket();
        }
      }
    } catch (e) {
      debugPrint("Error fetching ride details: $e");
    }
  }

  Future<void> _getRoute() async {
    if (_pickupLatLng == null || _dropoffLatLng == null) return;
    final token = Env.mapboxToken;
    final url = "https://api.mapbox.com/directions/v5/mapbox/driving/${_pickupLatLng!.longitude},${_pickupLatLng!.latitude};${_dropoffLatLng!.longitude},${_dropoffLatLng!.latitude}?overview=full&geometries=geojson&access_token=$token";
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["routes"] != null && (data["routes"] as List).isNotEmpty) {
          final route = data["routes"][0];
          final List coords = route["geometry"]["coordinates"];
          final double dist = route["distance"] / 1000.0; // meters to km
          final double dur = route["duration"] / 60.0;   // seconds to minutes

          setState(() {
            _routePoints = coords.map((c) => LatLng(c[1], c[0])).toList();
            _realDistance = dist;
            _realDuration = dur;
            _eta = dur; // Mettre à jour l'ETA affiché
            _distance = dist; // Mettre à jour la distance affichée
          });
        }
      } else {
        debugPrint("Mapbox API error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("Route error: $e");
    }
  }

  Future<void> _fetchAddress(LatLng point, bool isPickup) async {
    final token = Env.mapboxToken;
    final url = "https://api.mapbox.com/geocoding/v5/mapbox.places/${point.longitude},${point.latitude}.json?access_token=$token&types=place,region,address";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["features"] != null && (data["features"] as List).isNotEmpty) {
          final String name = data["features"][0]["text"];
          setState(() {
            if (isPickup) {
              _pickupAddress = name;
            } else {
              _dropoffAddress = name;
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Geocoding error: $e");
    }
  }

  LatLng? get _currentCarPosition {
    // Si nous recevons des coordonnées du chauffeur via WebSocket, on les utilise directement !
    if (_realDriverLatLng != null) {
      return _realDriverLatLng;
    }

    // Sinon, on garde le fallback de sécurité
    if (_rideStatus == RideStatus.driverApproaching || _rideStatus == RideStatus.arrived) {
      return _pickupLatLng;
    } else if (_rideStatus == RideStatus.inProgress) {
      return _pickupLatLng; // La simulation est supprimée pour laisser place au vrai GPS du chauffeur
    } else if (_rideStatus == RideStatus.completed) {
      return _dropoffLatLng;
    }
    return null;
  }

  void _startRealTimeUpdates() {
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_rideStatus == RideStatus.driverApproaching && _eta > 0) {
          _eta = math.max(0, _eta - 0.1);
          _distance = math.max(0, _distance - 0.05);
        } else if (_rideStatus == RideStatus.driverApproaching && _eta <= 0) {
          _rideStatus = RideStatus.arrived;
        }

        if (_rideStatus == RideStatus.inProgress) {
          double totalDurationSeconds = (_realDuration ?? 5.0) * 60.0;
          // Simulate faster for demo purposes (e.g., complete in 15-20 seconds)
          _elapsedTime += (totalDurationSeconds / 20).ceil(); 
          if (_elapsedTime >= totalDurationSeconds) {
            _elapsedTime = totalDurationSeconds.toInt();
            _rideStatus = RideStatus.completed;
          }
        }
      });
    });
  }

  @override
  void didUpdateWidget(TrackRidePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rideData?['request_id'] != oldWidget.rideData?['request_id']) {
      debugPrint("TrackRide: Ride ID changed, reconnecting WS...");
      _channel?.sink.close();
      _initWebSocket();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _positionStream?.cancel();
    _detailsTimer?.cancel();
    _channel?.sink.close();
    _carAnimationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber.replaceAll(RegExp(r'[^0-9+]'), ''),
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        throw 'Could not launch dialer';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    // Remove non-numeric characters
    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    
    // If it starts with 00, replace with nothing (wa.me expects country code)
    if (cleanNumber.startsWith('00')) {
      cleanNumber = cleanNumber.substring(2);
    }

    // Try multiple schemes
    final whatsappUrl = "whatsapp://send?phone=$cleanNumber";
    final httpsUrl = "https://wa.me/$cleanNumber";
    
    try {
      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(Uri.parse(httpsUrl))) {
        await launchUrl(Uri.parse(httpsUrl), mode: LaunchMode.externalApplication);
      } else {
        // Fallback for web or if schemes are not detected
        await launchUrl(Uri.parse(httpsUrl), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch WhatsApp. Please make sure it is installed.')),
        );
      }
    }
  }

  // Données de la course (fusionne données réelles et mock)
  Map<String, dynamic> get _rideData {
    final dynamic data = widget.rideData;
    return {
      'id': data?['request_id']?.toString() ?? 'R-2024',
      'pickup': {
        'address': data?['pickup_location'] ?? '123 Main Street, Downtown',
        'time': data?['scheduled_for'] != null 
            ? _formatIsoDate(data['scheduled_for']) 
            : '08:00 AM',
      },
      'dropoff': {
        'address': data?['dropoff_location'] ?? '456 School Road, Oakville',
        'distance': _realDistance != null ? '${_realDistance!.toStringAsFixed(1)} km' : 'Calcul...',
        'estimatedDuration': _realDuration != null ? '${_realDuration!.round()} min' : 'Calcul...',
      },
      'driver': {
        'name': _fetchedDriverData?['name'] ?? data?['driver_name'] ?? 'Michael Rodriguez',
        'rating': _fetchedDriverData?['rating'] ?? 4.9,
        'totalTrips': 1247,
        'phone': _fetchedDriverData?['phone'] ?? data?['driver_phone'] ?? '+1 (555) 987-6543',
        'vehicle': {
          'make': _fetchedDriverData?['vehicle_make'] ?? data?['vehicle_make'] ?? 'Toyota',
          'model': _fetchedDriverData?['vehicle_model'] ?? data?['vehicle_model'] ?? 'Camry',
          'color': _fetchedDriverData?['vehicle_color'] ?? data?['vehicle_color'] ?? 'Silver',
          'plate': _fetchedDriverData?['vehicle_plate'] ?? data?['vehicle_plate'] ?? 'ABC-1234',
        },
      },
      'scheduledTime': data?['scheduled_for'] != null 
          ? _formatIsoDate(data['scheduled_for']) 
          : '08:00 AM',
      'fare': (data?['priority_price'] != null)
          ? "${double.parse(data!['priority_price'].toString()).toStringAsFixed(3)} DT"
          : (data?['fare']?.toString() ?? '2.000 DT'),
    };
  }

  String _formatIsoDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}";
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("TrackRide Build: realPos=$_realDriverLatLng, status=$_rideStatus, hasMapPoints=${_routePoints.isNotEmpty}");
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(),
                const SizedBox(height: 24),

                // Barre de progression du statut
                _buildStatusProgressBar(),
                const SizedBox(height: 24),

                // Layout responsive
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildLeftColumn(),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 1,
                            child: _buildRightColumn(),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildLeftColumn(),
                          const SizedBox(height: 24),
                          _buildRightColumn(),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return FadeTransition(
      opacity: _fadeController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Track Your Ride ',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFCC00),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ride #${_rideData['id']} - Real-time tracking',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFFa0a0a0),
                ),
              ),
              if (_realDriverLatLng != null)
                const Icon(Icons.wifi_tethering, color: Color(0xFF22C55E), size: 16),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusProgressBar() {
    final statusSteps = [
      {'key': RideStatus.confirmed, 'label': 'Ride Confirmed', 'icon': Icons.check_circle},
      {'key': RideStatus.driverAssigned, 'label': 'Driver Assigned', 'icon': Icons.person},
      {'key': RideStatus.driverApproaching, 'label': 'Driver Approaching', 'icon': Icons.navigation},
      {'key': RideStatus.arrived, 'label': 'Driver Arrived', 'icon': Icons.location_on},
      {'key': RideStatus.inProgress, 'label': 'Ride in Progress', 'icon': Icons.directions_car},
      {'key': RideStatus.completed, 'label': 'Ride Completed', 'icon': Icons.check_circle},
    ];

    final currentStepIndex = statusSteps.indexWhere((step) => step['key'] == _rideStatus);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(statusSteps.length, (idx) {
            final step = statusSteps[idx];
            final isCompleted = idx <= currentStepIndex;
            
            return Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: isCompleted
                            ? const LinearGradient(
                                colors: [Color(0xFFFFCC00), Color(0xFFff9900)],
                              )
                            : null,
                        color: isCompleted ? null : const Color(0xFF0f0f0f),
                        border: isCompleted ? null : Border.all(color: const Color(0xFF333333), width: 2),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: isCompleted
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFFCC00).withOpacity(0.3),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        step['icon'] as IconData,
                        color: isCompleted ? Colors.black : const Color(0xFF555555),
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (MediaQuery.of(context).size.width > 600)
                      SizedBox(
                        width: 80,
                        child: Text(
                          step['label'] as String,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: isCompleted ? Colors.white : const Color(0xFF555555),
                            fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                  ],
                ),
                if (idx < statusSteps.length - 1)
                  Container(
                    width: 40,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 40),
                    decoration: BoxDecoration(
                      gradient: idx < currentStepIndex
                          ? const LinearGradient(
                              colors: [Color(0xFFFFCC00), Color(0xFFff9900)],
                            )
                          : null,
                      color: idx < currentStepIndex ? null : const Color(0xFF333333),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildLeftColumn() {
    return Column(
      children: [
        _buildLiveMap(),
        const SizedBox(height: 24),
        _buildRouteDetails(),
      ],
    );
  }

  Widget _buildLiveMap() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.navigation, color: Color(0xFFFFCC00), size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Live GPS Tracking',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              _buildCompactPicker("Pickup", _pickupAddress, Colors.green),
              const SizedBox(width: 8),
              _buildCompactPicker("Dropoff", _dropoffAddress, Colors.red),
            ],
          ),
          const SizedBox(height: 12),

          // Carte Réelle Mapbox
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            height: _isMapExpanded ? MediaQuery.of(context).size.height * 0.75 : 250,
            width: double.infinity,
            decoration: BoxDecoration(
                color: const Color(0xFF0f0f0f),
                border: Border.all(color: const Color(0xFF333333)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pickupLatLng ?? const LatLng(36.8, 10.1),
                    initialZoom: 13,
                    interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate, // Désactiver rotation pour simplicité
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: "https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${Env.mapboxToken}",
                    ),
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            color: const Color(0xFF99CC00),
                            strokeWidth: 4,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_pickupLatLng != null)
                          Marker(
                            point: _pickupLatLng!,
                            child: _buildMarker(Colors.green),
                          ),
                        if (_dropoffLatLng != null)
                          Marker(
                            point: _dropoffLatLng!,
                            child: _buildMarker(Colors.red),
                          ),
                        // Voiture animée (simulée pour le démo)
                        if ((_rideStatus == RideStatus.driverApproaching || 
                             _rideStatus == RideStatus.arrived || 
                             _rideStatus == RideStatus.inProgress || 
                             _rideStatus == RideStatus.completed ||
                             _realDriverLatLng != null) && 
                            _currentCarPosition != null)
                           Marker(
                            point: _currentCarPosition!, 
                            child: _buildCarMarker(),
                          ),
                        
                        // Position RÉELLE de l'utilisateur
                        if (_userLatLng != null)
                          Marker(
                            point: _userLatLng!,
                            child: _buildUserLocationMarker(),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          
          // Boutons d'action de la carte
          Row(
            children: [
              Expanded(
                child: _buildMapActionButton(
                  icon: _isMapExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                  label: _isMapExpanded ? 'Collapse Map' : 'Expand Map',
                  onTap: () {
                    setState(() {
                      _isMapExpanded = !_isMapExpanded;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMapActionButton(
                  icon: Icons.my_location,
                  label: 'Center Map',
                  onTap: () {
                    if (_userLatLng != null) {
                      _mapController.move(_userLatLng!, 14);
                    } else if (_pickupLatLng != null) {
                      _mapController.move(_pickupLatLng!, 13);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPicker(String label, String address, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on, color: color, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                address,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarker(Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildCarMarker() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFFFCC00),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFCC00).withOpacity(0.5),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.local_taxi,
        color: Colors.black,
        size: 28,
      ),
    );
  }

  Widget _buildUserLocationMarker() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildMapActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0f0f0f),
          border: Border.all(color: const Color(0xFF333333)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteDetails() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Route Details',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          
          // Pickup
          _buildLocationItem(
            icon: Icons.location_on,
            iconColor: Colors.green,
            backgroundColor: Colors.green.withOpacity(0.2),
            label: 'PICKUP LOCATION',
            address: _rideData['pickup']['address'],
            subtitle: 'Scheduled: ${_rideData['pickup']['time']}',
          ),
          
          const SizedBox(height: 16),
          
          // Ligne de progression
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 48,
                  color: const Color(0xFF333333),
                ),
                const SizedBox(width: 16),
                Text(
                  '${_rideData['dropoff']['distance']} • ${_rideData['dropoff']['estimatedDuration']}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFa0a0a0),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Dropoff
          _buildLocationItem(
            icon: Icons.location_on,
            iconColor: Colors.red,
            backgroundColor: Colors.red.withOpacity(0.2),
            label: 'DROPOFF LOCATION',
            address: _rideData['dropoff']['address'],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationItem({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required String label,
    required String address,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFa0a0a0),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFa0a0a0),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightColumn() {
    return Column(
      children: [
        _buildCurrentStatus(),
        const SizedBox(height: 24),
        _buildDriverInfo(),
        const SizedBox(height: 24),
        _buildTripSummary(),
        const SizedBox(height: 24),
        if (_rideStatus != RideStatus.completed) _buildActionButtons(),
      ],
    );
  }

  Widget _buildCurrentStatus() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFCC00), Color(0xFFff9900)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Status',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          
          if (_rideStatus == RideStatus.driverApproaching) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ETA',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                Text(
                  '${_eta.ceil()} min',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Distance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                Text(
                  '${_distance.toStringAsFixed(1)} km',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ] else if (_rideStatus == RideStatus.arrived) ...[
            const Center(
              child: Column(
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.black),
                  SizedBox(height: 8),
                  Text(
                    'Driver Has Arrived!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your driver is waiting for you',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_rideStatus == RideStatus.inProgress) ...[
            Center(
              child: Column(
                children: [
                  const Icon(Icons.directions_car, size: 64, color: Colors.black),
                  const SizedBox(height: 8),
                  const Text(
                    'Ride in Progress',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTime(_elapsedTime),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverInfo() {
    final driver = _rideData['driver'];
    final vehicle = driver['vehicle'];
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Driver',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (_realDriverLatLng != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      const Text('LIVE', style: TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Info du chauffeur
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.blue, Colors.cyan],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _getInitials(driver['name']),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver['name'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${driver['rating']}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFFa0a0a0),
                          ),
                        ),
                        const Text(
                          ' • ',
                          style: TextStyle(color: Color(0xFFa0a0a0)),
                        ),
                        Text(
                          '${driver['totalTrips']} trips',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFFa0a0a0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF333333)),
          const SizedBox(height: 16),
          
          // Détails du véhicule
          _buildInfoRow('Vehicle', '${vehicle['make']} ${vehicle['model']}'),
          const SizedBox(height: 12),
          _buildInfoRow('Color', vehicle['color']),
          const SizedBox(height: 12),
          _buildInfoRow('Plate', vehicle['plate']),
          
          const SizedBox(height: 24),
          
          // Boutons d'action
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openWhatsApp(driver['phone']),
                  icon: const Icon(Icons.phone, size: 20),
                  label: const Text('WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _makePhoneCall(driver['phone']),
                  icon: const Icon(Icons.call, size: 20),
                  label: const Text('Call'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF333333)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTripSummary() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trip Summary',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildInfoRow('Ride ID', _rideData['id']),
          const SizedBox(height: 12),
          _buildInfoRow('Distance', _rideData['dropoff']['distance']),
          const SizedBox(height: 12),
          _buildInfoRow('Duration', _rideData['dropoff']['estimatedDuration']),
          
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF333333)),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Fare',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFa0a0a0),
                ),
              ),
              Text(
                _rideData['fare'],
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFCC00),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        if (_rideStatus == RideStatus.driverApproaching)
          ElevatedButton(
            onPressed: () {
              setState(() {
                _rideStatus = RideStatus.inProgress;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFCC00),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Simulation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            // Action d'annulation
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red, width: 2),
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size(double.infinity, 0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Cancel Ride',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFFa0a0a0),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }
}
