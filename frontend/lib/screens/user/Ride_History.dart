import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../env.dart';
import 'package:intl/intl.dart';

class RideHistory extends StatefulWidget {
  const RideHistory({Key? key}) : super(key: key);

  @override
  State<RideHistory> createState() => _RideHistoryState();
}

class _RideHistoryState extends State<RideHistory> {
  int hoverIndex = -1;
  List<Map<String, dynamic>> _historyRides = [];
  bool _isLoading = true;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId == null) return;

      final res = await http.get(
        Uri.parse('${Env.baseUrl}/rides/user/$userId'),
        headers: Env.defaultHeaders,
      );

      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        final now = DateTime.now();

        setState(() {
          _historyRides = data.where((ride) {
            final status = (ride['status'] ?? '').toString().toUpperCase();
            if (status == 'COMPLETED' || status == 'CANCELLED') return true;
            
            // Also include past scheduled rides that aren't completed/cancelled yet
            if (ride['scheduled_for'] != null) {
              try {
                final schedDate = DateTime.parse(ride['scheduled_for']);
                return schedDate.isBefore(now);
              } catch (_) {}
            }
            return false;
          }).map((e) => e as Map<String, dynamic>).toList();
          
          // Sort by date (newest first)
          _historyRides.sort((a, b) {
            final dateA = DateTime.tryParse(a['scheduled_for'] ?? '') ?? DateTime(2000);
            final dateB = DateTime.tryParse(b['scheduled_for'] ?? '') ?? DateTime(2000);
            return dateB.compareTo(dateA);
          });

          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to load history";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Connection error";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFFCC00))),
      );
    }

    // Calculate stats
    final totalRides = _historyRides.length;
    final completedRides = _historyRides.where((r) => r['status'] == 'COMPLETED').length;
    final avgRating = _historyRides.where((r) => r['rating'] != null)
        .fold(0.0, (sum, r) => sum + (r['rating'] as num)) / 
        (_historyRides.where((r) => r['rating'] != null).length.clamp(1, 1000));

    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
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
                        "Ride History",
                        style: TextStyle(
                          fontSize: 30,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.history, color: Color(0xFFFFCC00), size: 30),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'View your past rides and statistics',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            /// STATISTICS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  buildStatisticsHoverCard(0, "$totalRides", "Total Rides", Icons.directions_car, Colors.blueAccent),
                  buildStatisticsHoverCard(1, "${(completedRides * 12.5).toStringAsFixed(1)} DT", "Total Spent", Icons.attach_money, Colors.greenAccent),
                  buildStatisticsHoverCard(2, avgRating.toStringAsFixed(1), "Avg Rating", Icons.star, Colors.orangeAccent),
                ],
              ),
            ),

            const SizedBox(height: 30),

            /// HISTORY LIST
            if (_historyRides.isEmpty)
              const Center(child: Text("No history available", style: TextStyle(color: Colors.white70)))
            else
              ..._historyRides.asMap().entries.map((entry) {
                final idx = entry.key + 10; // offset for hover index
                final ride = entry.value;
                final dateStr = ride['scheduled_for'] != null 
                    ? DateFormat('EEEE, MMM d').format(DateTime.parse(ride['scheduled_for']))
                    : "Urgent Ride";
                
                return buildScheduleHoverCard(
                  idx,
                  dateStr,
                  "Status: ${ride['status']}",
                  ride['pickup_location'] ?? 'Unknown',
                  ride['dropoff_location'] ?? 'Unknown',
                  ride['scheduled_for'] != null ? DateFormat('HH:mm').format(DateTime.parse(ride['scheduled_for'])) : "Now",
                  ride['price'] != null ? "${ride['price']} DT" : "15 DT",
                  "12 mins",
                  ride['status'] == 'COMPLETED',
                );
              }).toList(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// 🔥 STAT HOVER
  Widget buildStatisticsHoverCard(
    int index,
    String data,
    String title,
    IconData icon,
    Color color,
  ) {
    return MouseRegion(
      onEnter: (_) => setState(() => hoverIndex = index),
      onExit: (_) => setState(() => hoverIndex = -1),
      child: buildStatisticsCard(title, data, icon, color, hoverIndex == index),
    );
  }

  /// 🔥 SCHEDULE HOVER
  Widget buildScheduleHoverCard(
    int index,
    String title,
    String subtitle,
    String pickup,
    String dropoff,
    String days,
    String price,
    String duration,
    bool isCompleted,
  ) {
    return MouseRegion(
      onEnter: (_) => setState(() => hoverIndex = index),
      onExit: (_) => setState(() => hoverIndex = -1),
      child: buildScheduleCard(
        title,
        subtitle,
        pickup,
        dropoff,
        days,
        price,
        duration,
        isCompleted,
        hoverIndex == index,
      ),
    );
  }
}

/// 🔥 STAT CARD
Widget buildStatisticsCard(
  String title,
  String data,
  IconData icon,
  Color color,
  bool isHover,
) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: double.infinity,
    height: 90,
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

    transform: isHover ? (Matrix4.identity()..scale(1.03)) : Matrix4.identity(),

    decoration: BoxDecoration(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isHover ? const Color(0xFFFFCC00) : Colors.white12,
        width: 1.5,
      ),
      boxShadow: isHover
          ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ]
          : [],
    ),
    child: Row(
      children: [
        Icon(icon, size: 30, color: color),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(data, style: TextStyle(fontSize: 16, color: Colors.grey[400])),
            const SizedBox(height: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// 🔥 SCHEDULE CARD
Widget buildScheduleCard(
  String title,
  String subtitle,
  String pickup,
  String dropoff,
  String days,
  String price,
  String duration,
  bool isCompleted,
  bool isHover,
) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(16),

    transform: isHover ? (Matrix4.identity()..scale(1.02)) : Matrix4.identity(),

    decoration: BoxDecoration(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isHover ? const Color(0xFFFFCC00) : Colors.white12,
        width: 1.5,
      ),
    ),

    child: Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                if (isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 10),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: Colors.orangeAccent,
                  size: 14,
                ),
                const SizedBox(width: 6),
                const Text(
                  "Pickup:",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    pickup,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: Colors.deepOrange,
                  size: 14,
                ),
                const SizedBox(width: 6),
                const Text(
                  "Dropoff:",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    dropoff,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),

            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.white54, size: 14),
                const SizedBox(width: 6),
                Text(
                  duration,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
        ),

        Positioned(
          top: 0,
          right: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                price,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 14,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.star,
                  color: Colors.orangeAccent,
                  size: 18,
                ),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
