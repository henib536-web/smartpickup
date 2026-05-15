import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class NewSchedule extends StatefulWidget {
  const NewSchedule({Key? key}) : super(key: key);

  @override
  _NewScheduleState createState() => _NewScheduleState();
}

class _NewScheduleState extends State<NewSchedule> {
  // Controllers
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _passengerNameController = TextEditingController();
  
  // Location states
  LatLng? pickup;
  LatLng? dropoff;
  
  // Selection mode
  String? selectionMode; // 'pickup' or 'dropoff'
  
  // Schedule data
  List<String> selectedDays = [];
  
  // Passenger information
  String passengerType = 'adult'; // 'adult', 'child', 'senior'
  
  // Route
  List<LatLng> route = [];
  
  // Message
  String message = "Click on the map to choose pickup point";

  @override
  void initState() {
    super.initState();
    // Start with pickup mode by default
    selectionMode = 'pickup';
  }

  // Fetch route from OSRM
  Future<void> getRoute() async {
    if (pickup == null || dropoff == null) return;

    String url = "https://router.project-osrm.org/route/v1/driving/"
        "${pickup!.longitude},${pickup!.latitude};"
        "${dropoff!.longitude},${dropoff!.latitude}"
        "?overview=full&geometries=geojson";

    try {
      var response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        if (data["routes"] != null && data["routes"].isNotEmpty) {
          List coords = data["routes"][0]["geometry"]["coordinates"];

          route.clear();

          for (var c in coords) {
            route.add(LatLng(c[1], c[0]));
          }

          setState(() {});
        }
      }
    } catch (e) {
      print("Error loading route: $e");
    }
  }

  // Handle map tap
  void handleMapTap(LatLng point) {
    if (selectionMode == 'pickup') {
      setState(() {
        pickup = point;
        selectionMode = 'dropoff'; // Automatically move to dropoff
        message = "Perfect! Now click on the map to choose the drop-off point";
      });
      _showSnackBar('Pickup point selected', Colors.green);
    } else if (selectionMode == 'dropoff') {
      setState(() {
        dropoff = point;
        selectionMode = null;
        message = "Excellent! Both points are selected. Configure your schedule.";
      });
      _showSnackBar('Drop-off point selected', Colors.green);
      getRoute();
    }
  }

  // Handle pickup button
  void handleSelectPickup() {
    setState(() {
      selectionMode = 'pickup';
      message = 'Click on the map to choose the pickup point';
    });
  }

  // Handle dropoff button
  void handleSelectDropoff() {
    if (pickup == null) {
      _showSnackBar('Please choose a pickup point first', Colors.red);
      return;
    }
    setState(() {
      selectionMode = 'dropoff';
      message = 'Click on the map to choose the drop-off point';
    });
  }

  // Clear locations
  void handleClearLocations() {
    setState(() {
      pickup = null;
      dropoff = null;
      route.clear();
      selectionMode = 'pickup';
      message = 'Click on the map to choose the pickup point';
    });
    _showSnackBar('Selections cleared', Colors.blue);
  }

  // Confirm schedule
  void handleConfirmSchedule() {
    if (pickup == null || dropoff == null) {
      _showSnackBar('Please select pickup and drop-off points on the map', Colors.red);
      return;
    }


    if (selectedDays.isEmpty) {
      _showSnackBar('Please select at least one day of the week', Colors.red);
      return;
    }

    if (_passengerNameController.text.trim().isEmpty) {
      _showSnackBar('Please enter passenger name', Colors.red);
      return;
    }

    // Simulate schedule creation
    _showSnackBar('Schedule created successfully!', Colors.green);
    
    // Navigate back after delay
    Future.delayed(const Duration(milliseconds: 1500), () {
      Navigator.pop(context);
    });
  }

  // Show snackbar
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Build day circle
  Widget _buildDayCircle(String shortName, String fullName) {
    final isSelected = selectedDays.contains(fullName);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            selectedDays.remove(fullName);
          } else {
            selectedDays.add(fullName);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? const Color(0xFFFFCC00)
              : Colors.white.withOpacity(0.1),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFCC00)
                : Colors.white.withOpacity(0.2),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFCC00).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            shortName,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  // Build map markers
  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    if (pickup != null) {
      markers.add(
        Marker(
          point: pickup!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_pin, color: Color(0xFFFFD700), size: 40),
        ),
      );
    }

    if (dropoff != null) {
      markers.add(
        Marker(
          point: dropoff!,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
        ),
      );
    }

    return markers;
  }

  // Format date for display
  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMMM dd, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  void dispose() {
   
    _timeController.dispose();
    _passengerNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header with back button
                _buildHeader(context),
                
                const SizedBox(height: 24),

                // Main content - Desktop: side by side, Mobile: stacked
                isDesktop
                    ? _buildDesktopLayout()
                    : _buildMobileLayout(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build header
  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
            label: const Text(
              'Back',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Title
        const Text(
          'New Schedule',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        const SizedBox(height: 8),
        
        const Text(
          'Configure your recurring trip in a few clicks',
          style: TextStyle(color: Colors.white70, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // Build desktop layout (side by side)
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left side - Map
        Expanded(
          flex: 1,
          child: _buildMapSection(height: 600),
        ),
        
        const SizedBox(width: 24),
        
        // Right side - Configuration
        Expanded(
          flex: 1,
          child: _buildConfigurationSection(),
        ),
      ],
    );
  }

  // Build mobile layout (stacked)
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildMapSection(height: 400),
        const SizedBox(height: 24),
        _buildConfigurationSection(),
      ],
    );
  }

  // Build map section
  Widget _buildMapSection({required double height}) {
    return Card(
      color: const Color.fromARGB(36, 143, 143, 102).withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map header
            Row(
              children: [
                const Icon(Icons.navigation, color: Color(0xFFFFCC00), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Interactive Map',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Text(
              message,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            
            const SizedBox(height: 16),
            
            // Map
            Container(
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: const LatLng(36.8065, 10.1815),
                  initialZoom: 8,
                  onTap: (tapPos, point) => handleMapTap(point),
                ),
                children: [
                  TileLayer(
  urlTemplate: "https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png",
  userAgentPackageName: 'com.example.smartpickup',
),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route,
                        strokeWidth: 5,
                        color: const Color(0xFF3B82F6),
                      )
                    ],
                  ),
                  MarkerLayer(markers: _buildMarkers()),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Quick action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: handleSelectPickup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCC00),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: selectionMode == 'pickup'
                            ? const BorderSide(color: Colors.white, width: 2)
                            : BorderSide.none,
                      ),
                    ),
                    icon: const Icon(Icons.location_on, size: 18),
                    label: Text(
                      pickup != null ? 'Change Pickup' : 'Pickup Point',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: handleSelectDropoff,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCC00),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: selectionMode == 'dropoff'
                            ? const BorderSide(color: Colors.white, width: 2)
                            : BorderSide.none,
                      ),
                    ),
                    icon: const Icon(Icons.location_on, size: 18),
                    label: Text(
                      dropoff != null ? 'Change Drop-off' : 'Drop-off Point',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
            
            // Clear button
            if (pickup != null || dropoff != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: handleClearLocations,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.location_off, size: 16),
                    label: const Text('Clear Points', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Build configuration section
  Widget _buildConfigurationSection() {
    return Card(
      color: const Color.fromARGB(36, 143, 143, 102).withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            const Text(
              'Schedule Configuration',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Define when and how often',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            
            const SizedBox(height: 20),
            
            // Location summary
            _buildLocationSummary(),
            
            const SizedBox(height: 20),
            
            // Passenger Information Section
            _buildPassengerInformation(),
            
            const SizedBox(height: 20),
            
           
            const SizedBox(height: 12),
            
            Row(
              children: [
               
                
                const SizedBox(width: 12),
                
                Expanded(
                  child: TextField(
                    controller: _timeController,
                    readOnly: true,
                    style: const TextStyle(color: Colors.black),
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: "Time",
                      suffixIcon: Icon(Icons.access_time),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    onTap: () async {
                      TimeOfDay? pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );

                      if (pickedTime != null) {
                        setState(() {
                          _timeController.text =
                              "${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}";
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Days selection
            const Text(
              'Repeat Days',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDayCircle('M', 'Monday'),
                _buildDayCircle('T', 'Tuesday'),
                _buildDayCircle('W', 'Wednesday'),
                _buildDayCircle('T', 'Thursday'),
                _buildDayCircle('F', 'Friday'),
                _buildDayCircle('S', 'Saturday'),
                _buildDayCircle('S', 'Sunday'),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Schedule summary
            if (selectedDays.isNotEmpty && 
                _timeController.text.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFCC00).withOpacity(0.1),
                  border: Border.all(color: const Color(0xFFFFCC00).withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Schedule Summary:',
                      style: TextStyle(
                        color: Color(0xFFFFCC00),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Every ${selectedDays.join(', ')}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    Text(
                      'At ${_timeController.text}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                   
                  ],
                ),
              ),
            
            const SizedBox(height: 20),
            
            // Confirm button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: pickup != null &&
                        dropoff != null &&
                        _timeController.text.isNotEmpty &&
                        selectedDays.isNotEmpty &&
                        _passengerNameController.text.trim().isNotEmpty
                    ? handleConfirmSchedule
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFCC00),
                  disabledBackgroundColor: Colors.grey[600],
                  foregroundColor: Colors.black,
                  disabledForegroundColor: Colors.grey[400],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle, size: 24),
                label: const Text(
                  'Create Schedule',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            const Text(
              'The schedule will be automatically repeated according to the selected days',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Build location summary
  Widget _buildLocationSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Pickup
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                ),
                child: const Icon(Icons.location_on, color: Color(0xFFFFD700), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pickup Point',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    pickup != null
                        ? Text(
                            'Lat: ${pickup!.latitude.toStringAsFixed(4)}, Lng: ${pickup!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          )
                        : const Text(
                            'Not selected',
                            style: TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                  ],
                ),
              ),
            ],
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
          ),
          
          // Dropoff
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.2),
                ),
                child: const Icon(Icons.location_on, color: Colors.red, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Drop-off Point',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    dropoff != null
                        ? Text(
                            'Lat: ${dropoff!.latitude.toStringAsFixed(4)}, Lng: ${dropoff!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          )
                        : const Text(
                            'Not selected',
                            style: TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build passenger information section
  Widget _buildPassengerInformation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title with icon
          Row(
            children: [
              const Icon(Icons.person, color: Color(0xFFFFCC00), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Passenger Information',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Passenger name input
          const Text(
            'Passenger Name',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passengerNameController,
            style: const TextStyle(color: Colors.black),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Enter passenger name',
              hintStyle: TextStyle(color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Passenger type selector
          const Text(
            'Passenger Type',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPassengerTypeButton('Adult', 'adult'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPassengerTypeButton('Child', 'child'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPassengerTypeButton('Senior', 'senior'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build passenger type button
  Widget _buildPassengerTypeButton(String label, String type) {
    final isSelected = passengerType == type;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          passengerType = type;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFCC00)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
