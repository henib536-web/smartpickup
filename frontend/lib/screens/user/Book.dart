import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../env.dart';
class BookRide extends StatefulWidget {
  const BookRide({Key? key}) : super(key: key);

  @override
  _BookRideState createState() => _BookRideState();
}

class _BookRideState extends State<BookRide> {
  // Controllers
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _passengerNameController = TextEditingController();

  // States
  bool isRecurring = false;
  LatLng? pickup;
  LatLng? dropoff;
  String? selectionMode = 'pickup';
  List<String> selectedDays = [];
  String passengerType = 'adult';
  List<LatLng> route = [];
  String message = "Tap the map to set your pickup point";
  String pickupAddress = "Map Selection";
  String dropoffAddress = "Map Selection";
  String currentZoneName = "Tunisie";

  // --- Tarification ---
  static const int basePriceDefault = 3500; // millimes
  static const int pricePerKm = 500;        // millimes par km
  static const int fixedFee = 900;           // frais fixes millimes
  int clientBasePrice = basePriceDefault;    // le client peut augmenter
  double? distanceKm;
  int? estimatedPrice; // en millimes

  @override
  void initState() {
    super.initState();
    _initializeDefaults();
  }

  void _initializeDefaults() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() {
      _dateController.text = today;
      _startDateController.text = today;
    });

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _passengerNameController.text = prefs.getString('user_name') ?? "";
    });
  }

  /// Calcule le prix en millimes selon la formule :
  /// clientBasePrice + (distanceKm * 500) + 900
  void _calculatePrice() {
    if (distanceKm != null) {
      setState(() {
        estimatedPrice = (clientBasePrice + (distanceKm! * pricePerKm) + fixedFee).round();
      });
    }
  }

  Future<void> getRoute() async {
    if (pickup == null || dropoff == null) return;
    final String url = "https://api.mapbox.com/directions/v5/mapbox/driving/${pickup!.longitude},${pickup!.latitude};${dropoff!.longitude},${dropoff!.latitude}?overview=full&geometries=geojson&access_token=${Env.mapboxToken}";
    try {
      var response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data["routes"] != null && data["routes"].isNotEmpty) {
          List coords = data["routes"][0]["geometry"]["coordinates"];
          double distanceMeters = (data["routes"][0]["distance"] as num).toDouble();
          setState(() {
            route = coords.map((c) => LatLng(c[1], c[0])).toList();
            distanceKm = distanceMeters / 1000.0;
          });
          _calculatePrice();
        }
      }
    } catch (e) {
      debugPrint("Route error: $e");
    }
  }

  Future<void> _fetchAddress(LatLng point, bool isPickup) async {
    final url = "https://api.mapbox.com/geocoding/v5/mapbox.places/${point.longitude},${point.latitude}.json?access_token=${Env.mapboxToken}&types=place,region,address";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["features"] != null && (data["features"] as List).isNotEmpty) {
          final String name = data["features"][0]["text"];
          setState(() {
            if (isPickup) {
              pickupAddress = name;
              currentZoneName = name; // On garde currentZoneName pour la zone globale
            } else {
              dropoffAddress = name;
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Geocoding error: $e");
    }
  }

  void handleMapTap(LatLng point) {
    if (point.latitude < 30.0 || point.latitude > 38.0 || point.longitude < 7.0 || point.longitude > 12.0) {
      _showSnackBar("Veuillez sélectionner un point en Tunisie.", Colors.red);
      return;
    }
    setState(() {
      if (selectionMode == 'pickup') {
        pickup = point;
        selectionMode = 'dropoff';
        message = "Now, select your destination";
        _fetchAddress(point, true);
      } else if (selectionMode == 'dropoff') {
        dropoff = point;
        message = "Route points selected!";
        _fetchAddress(point, false);
      }
    });
    if (pickup != null && dropoff != null) getRoute();
  }

  bool _isSubmitting = false;

  Future<void> _handleBooking() async {
    if (_isSubmitting) return;

    if (pickup == null || dropoff == null || _timeController.text.isEmpty || _passengerNameController.text.isEmpty) {
      _showSnackBar("Please fill all required fields", Colors.red);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final int userId = prefs.getInt('user_id') ?? 0;
    final String connectedUserName = prefs.getString('user_name') ?? "";

    // --- CORRECTION DU FORMAT DE L'HEURE ---
    String timePart = _timeController.text.trim();
    // On s'assure que l'heure est au format HH:mm:ss sans doublons
    if (timePart.split(':').length == 2) {
      timePart = "$timePart:00";
    }

    // Construction du payload pour FastAPI
    Map<String, dynamic> body = {
      "client_id": userId,
      "passenger_id": _passengerNameController.text.trim() == connectedUserName ? userId : null,
      "passenger_name": _passengerNameController.text.trim(),
      "zone_name": currentZoneName,
      "pickup_location": pickupAddress,
      "dropoff_location": dropoffAddress,
      "pickup_lat": pickup!.latitude,
      "pickup_lng": pickup!.longitude,
      "dropoff_lat": dropoff!.latitude,
      "dropoff_lng": dropoff!.longitude,
      "scheduled_flag": isRecurring,
      "passenger_type": passengerType,
    };

    if (isRecurring) {
      if (_startDateController.text.isEmpty || _endDateController.text.isEmpty || selectedDays.isEmpty) {
        _showSnackBar("Please complete recurring details", Colors.red);
        setState(() => _isSubmitting = false);
        return;
      }
      body["pickup_time"] = "${_startDateController.text}T$timePart";
      body["start_date"] = body["pickup_time"];
      body["end_date"] = "${_endDateController.text}T$timePart";
      body["selected_days"] = selectedDays;
    } else {
      body["pickup_time"] = "${_dateController.text}T$timePart";
    }

    body["priority_price"] = clientBasePrice / 1000.0; // Convertir millimes en DT
    body["distance_km"] = distanceKm;
    body["estimated_price"] = estimatedPrice;

    try {
      final response = await http.post(
        Uri.parse('${Env.baseUrl}/rides/book'),
        headers: {
          ...Env.defaultHeaders,
          "Content-Type": "application/json",
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSnackBar("Ride successfully booked!", Colors.green);
        Navigator.pushReplacementNamed(context, '/user');
      } else {
        debugPrint("Backend Error: ${response.body}");
        _showSnackBar("Error: Check console for details", Colors.red);
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      _showSnackBar("Connection failed. Check your server.", Colors.red);
      setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Book a Ride", style: TextStyle(color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pushReplacementNamed(context, '/user')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildLocationPickers(),
            const SizedBox(height: 15),
            _buildMapSection(),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic)),
            const SizedBox(height: 20),
            _buildFormSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationPickers() {
    return Row(
      children: [
        _buildMapActionButton("Pick-up", pickup, selectionMode == 'pickup', const Color(0xFFFFCC00), Icons.my_location, () => setState(() => selectionMode = 'pickup')),
        const SizedBox(width: 10),
        _buildMapActionButton("Drop-off", dropoff, selectionMode == 'dropoff', Colors.redAccent, Icons.location_on, () => setState(() => selectionMode = 'dropoff')),
      ],
    );
  }

  Widget _buildMapActionButton(String label, LatLng? coords, bool isActive, Color color, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? color : Colors.white12, width: 2),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: isActive ? color : Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text(
                      coords != null 
                        ? (label == "Pick-up" ? pickupAddress : dropoffAddress)
                        : "Tap to set",
                      style: const TextStyle(color: Colors.white, fontSize: 12, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Passenger Name", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
            controller: _passengerNameController,
            style: const TextStyle(color: Colors.black),
            decoration: InputDecoration(
                hintText: "Enter name",
                filled: true,
                fillColor: Colors.white,
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => _passengerNameController.clear()),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 20),
          const Text("Passenger Type", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildTypeButton("Adult", "adult"),
              const SizedBox(width: 8),
              _buildTypeButton("Child", "child"),
              const SizedBox(width: 8),
              _buildTypeButton("Senior", "senior"),
            ],
          ),
          const SizedBox(height: 25),
          _buildToggleRecurring(),
          const SizedBox(height: 20),
          if (!isRecurring) ...[
            _buildDateField(_dateController, "Date", Icons.calendar_today),
          ] else ...[
            Row(
              children: [
                Expanded(child: _buildDateField(_startDateController, "From", Icons.date_range)),
                const SizedBox(width: 10),
                Expanded(child: _buildDateField(_endDateController, "To", Icons.event_available)),
              ],
            ),
            const SizedBox(height: 15),
            _buildDaysSelector(),
          ],
          const SizedBox(height: 15),
          _buildTimeField(),
          const SizedBox(height: 20),
          _buildPriorityPriceSelector(),
          const SizedBox(height: 30),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildTypeButton(String label, String type) {
    bool isSelected = passengerType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => passengerType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: isSelected ? const Color(0xFFFFCC00) : Colors.white10, borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }

  Widget _buildToggleRecurring() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Recurring schedule", style: TextStyle(color: Colors.white70)),
          Switch(value: isRecurring, activeColor: const Color(0xFFFFCC00), onChanged: (v) => setState(() => isRecurring = v)),
        ],
      ),
    );
  }

  Widget _buildDateField(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      readOnly: true,
      onTap: () async {
        DateTime? d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2027));
        if (d != null) setState(() => ctrl.text = DateFormat('yyyy-MM-dd').format(d));
      },
      decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _buildTimeField() {
    return TextField(
      controller: _timeController,
      readOnly: true,
      onTap: () async {
        TimeOfDay? t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
        if (t != null) {
          // Formatage strict HH:mm
          final String h = t.hour.toString().padLeft(2, '0');
          final String m = t.minute.toString().padLeft(2, '0');
          setState(() => _timeController.text = "$h:$m");
        }
      },
      decoration: InputDecoration(hintText: "Pickup Time", prefixIcon: const Icon(Icons.access_time), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
    );
  }

  Widget _buildDaysSelector() {
    List<String> short = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    List<String> full = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        bool isSel = selectedDays.contains(full[i]);
        return GestureDetector(
          onTap: () => setState(() => isSel ? selectedDays.remove(full[i]) : selectedDays.add(full[i])),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: isSel ? const Color(0xFFFFCC00) : Colors.white10,
            child: Text(short[i], style: TextStyle(color: isSel ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        );
      }),
    );
  }

  Widget _buildMapSection() {
    return Container(
      height: 280,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(initialCenter: const LatLng(36.8, 10.1), initialZoom: 10, onTap: (_, p) => handleMapTap(p)),
          children: [
            TileLayer(
              urlTemplate: "https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${Env.mapboxToken}",
            ),
            PolylineLayer(polylines: [Polyline(points: route, color: const Color(0xFFFFCC00), strokeWidth: 4)]),
            MarkerLayer(markers: [
              if (pickup != null) Marker(point: pickup!, child: const Icon(Icons.my_location, color: Color(0xFFFFCC00), size: 30)),
              if (dropoff != null) Marker(point: dropoff!, child: const Icon(Icons.location_on, color: Colors.red, size: 30)),
            ]),
          ],
        ),
      ),
    );
  }

  int _calculateOccurrences() {
    if (!isRecurring || _startDateController.text.isEmpty || _endDateController.text.isEmpty || selectedDays.isEmpty) return 0;
    try {
      final start = DateTime.parse(_startDateController.text);
      final end = DateTime.parse(_endDateController.text);
      int count = 0;
      for (var d = start; d.isBefore(end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
        String dayName = DateFormat('EEEE').format(d);
        if (selectedDays.contains(dayName)) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Widget _buildPriorityPriceSelector() {
    final String priceDisplay = estimatedPrice != null
        ? "${(estimatedPrice! / 1000).toStringAsFixed(3)} DT"
        : "--";
    final String distanceDisplay = distanceKm != null
        ? "${distanceKm!.toStringAsFixed(1)} km"
        : "Sélectionnez les points";
    final String basePriceDisplay = "${(clientBasePrice / 1000).toStringAsFixed(3)} DT";

    int occurrences = isRecurring ? _calculateOccurrences() : 1;
    String totalPeriodDisplay = "";
    if (isRecurring && estimatedPrice != null) {
      if (occurrences > 0) {
        totalPeriodDisplay = "${((estimatedPrice! * occurrences) / 1000).toStringAsFixed(3)} DT ($occurrences courses)";
      } else {
        totalPeriodDisplay = "Sélectionnez des jours valides";
      }
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFCC00).withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFFCC00), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Distance
          Row(
            children: [
              const Icon(Icons.straighten, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text("Distance: $distanceDisplay",
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          // Prix estimé total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isRecurring ? "Prix estimé / course" : "Prix estimé",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(priceDisplay,
                      style: const TextStyle(color: Color(0xFFFFCC00), fontSize: 22, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          if (isRecurring && estimatedPrice != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.orangeAccent, size: 16),
                const SizedBox(width: 6),
                Text("Total Période: $totalPeriodDisplay",
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          const Divider(color: Colors.white24, height: 24),
          // Détail de la formule
          if (distanceKm != null) ...[
            _buildPriceDetailRow("Prix de base", basePriceDisplay),
            _buildPriceDetailRow("Distance (${distanceKm!.toStringAsFixed(1)} km × 0.500 DT)",
                "${((distanceKm! * pricePerKm) / 1000).toStringAsFixed(3)} DT"),
            _buildPriceDetailRow("Frais fixes", "0.900 DT"),
          ],
          const SizedBox(height: 12),
          // Ajustement du prix de base par le client
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text("Augmenter le prix de base",
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                Row(
                  children: [
                    if (clientBasePrice > basePriceDefault)
                      IconButton(
                        onPressed: () {
                          setState(() => clientBasePrice -= 500);
                          _calculatePrice();
                        },
                        icon: const Icon(Icons.remove_circle, color: Colors.white70, size: 28),
                      ),
                    Text(basePriceDisplay,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    IconButton(
                      onPressed: () {
                        setState(() => clientBasePrice += 500);
                        _calculatePrice();
                      },
                      icon: const Icon(Icons.add_circle, color: Color(0xFFFFCC00), size: 28),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFCC00), padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: _isSubmitting ? null : _handleBooking,
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
              )
            : Text(isRecurring ? "Confirm Schedule" : "Book Now", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }
}