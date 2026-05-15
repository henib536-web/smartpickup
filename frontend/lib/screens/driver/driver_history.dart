import 'package:flutter/material.dart';
import '../auth/driver_layout.dart';
import '../../services/driver_api_service.dart';

class DriverHistory extends StatefulWidget {
  const DriverHistory({Key? key}) : super(key: key);

  @override
  _DriverHistoryState createState() => _DriverHistoryState();
}

class _DriverHistoryState extends State<DriverHistory> {
  final DriverApiService _apiService = DriverApiService();
  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;
  int _hoverIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final data = await _apiService.getDriverHistory();
      setState(() {
        _rides = data.map((e) => {
          'id': e['id']?.toString() ?? 'N/A',
          'date': e['date'] ?? 'N/A',
          'pickup': e['pickup'] ?? 'N/A',
          'dropoff': e['dropoff'] ?? 'N/A',
          'duration': e['duration'] ?? 'N/A',
          'rating': (e['rating'] as num?)?.toDouble() ?? 0.0,
          'status': e['status'] ?? 'completed',
          'passenger': e['passenger'] ?? 'Unknown',
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    int completedCount = _rides.where((r) => r['status'] == 'completed').length;
    double avgRating = _rides.isEmpty ? 0.0 : (_rides.map((r) => r['rating'] as double).reduce((a, b) => a + b) / _rides.length);

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFCC00)))
        : SingleChildScrollView(
            child: Column(
              children: [
                /// HEADER
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Text("Ride History", style: TextStyle(fontSize: 30, color: Colors.white, fontWeight: FontWeight.bold)),
                          SizedBox(width: 8),
                          Icon(Icons.history, color: Color(0xFFFFCC00), size: 30),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('View your past rides and performance statistics', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                ),

                /// STATISTICS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildStatCard(0, "${_rides.length}", "Total Rides", Icons.local_taxi, Colors.blueAccent),
                      _buildStatCard(1, "$completedCount", "Completed", Icons.check_circle, Colors.greenAccent),
                      _buildStatCard(2, avgRating.toStringAsFixed(1), "Avg Rating", Icons.star, Colors.orangeAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                /// RIDE LIST
                if (_rides.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: Text("No history available", style: TextStyle(color: Colors.grey))))
                else
                  ...List.generate(_rides.length, (index) {
                    final ride = _rides[index];
                    return _buildRideHoverCard(index + 10, ride);
                  }),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFFFFCC00),
        onPressed: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back, color: Colors.black),
      ),
    );
  }

  Widget _buildStatCard(int index, String data, String title, IconData icon, Color color) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverIndex = index),
      onExit: (_) => setState(() => _hoverIndex = -1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        transform: _hoverIndex == index ? (Matrix4.identity()..scale(1.03)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hoverIndex == index ? const Color(0xFFFFCC00) : Colors.white12, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data, style: const TextStyle(fontSize: 16, color: Colors.white70)),
                Text(title, style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideHoverCard(int index, Map<String, dynamic> ride) {
    bool isCompleted = ride['status'] == 'completed';
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverIndex = index),
      onExit: (_) => setState(() => _hoverIndex = -1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        transform: _hoverIndex == index ? (Matrix4.identity()..scale(1.02)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hoverIndex == index ? const Color(0xFFFFCC00) : Colors.white12, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(ride['date'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Completed', style: TextStyle(color: Colors.greenAccent, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Passenger: ${ride['passenger']}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            _buildLocationRow(Icons.circle, Colors.greenAccent, "Pickup", ride['pickup']),
            const SizedBox(height: 6),
            _buildLocationRow(Icons.circle, Colors.redAccent, "Dropoff", ride['dropoff']),
            const Divider(color: Colors.white12, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [const Icon(Icons.access_time, color: Colors.grey, size: 14), const SizedBox(width: 6), Text(ride['duration'], style: const TextStyle(color: Colors.grey, fontSize: 12))]),
                Row(
                  children: [
                    Text("${ride['rating']}", style: const TextStyle(color: Color(0xFFFFCC00), fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    const Icon(Icons.star, color: Color(0xFFFFCC00), size: 18),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 8),
        Text("$label: ", style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13))),
      ],
    );
  }
}