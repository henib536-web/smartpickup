import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../env.dart';
import 'track_ride.dart';
import 'incident_rapport.dart';

class Scheduled extends StatefulWidget {
  const Scheduled({super.key});

  @override
  State<Scheduled> createState() => _ScheduledState();
}

class _ScheduledState extends State<Scheduled> {
  late Future<List<Map<String, dynamic>>> _ridesFuture;

  @override
  void initState() {
    super.initState();
    _ridesFuture = _fetchUserRides();
  }

  Future<List<Map<String, dynamic>>> _fetchUserRides() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null) {
      return [];
    }

    final uri = Uri.parse('${Env.baseUrl}/rides/user/$userId');
    final res = await http.get(uri, headers: Env.defaultHeaders);

    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body);
      final now = DateTime.now();
      
      // Filter only future rides (or recurring ones) that are not completed/cancelled
      return data.where((ride) {
        final status = (ride['status'] ?? '').toString().toUpperCase();
        if (status == 'COMPLETED' || status == 'CANCELLED') return false;

        // Keep the recurring schedule templates themselves in upcoming list
        if (ride['item_type'] == 'recurring_schedule') return true;

        if (ride['scheduled_for'] == null) return true; // Urgent rides
        try {
          final schedDate = DateTime.parse(ride['scheduled_for']);
          return schedDate.isAfter(now);
        } catch (_) {
          return true;
        }
      }).map((e) => e as Map<String, dynamic>).toList();
    } else {
      debugPrint('Error fetching rides: ${res.body}');
      return [];
    }
  }

  Future<void> _cancelRide(int requestId) async {
    try {
      final uri = Uri.parse('${Env.baseUrl}/rides/$requestId/cancel');
      final res = await http.post(uri, headers: Env.defaultHeaders);
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ride cancelled successfully'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _ridesFuture = _fetchUserRides();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to cancel ride'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection error while cancelling ride'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelSchedule(int scheduleId) async {
    try {
      final uri = Uri.parse('${Env.baseUrl}/rides/schedules/$scheduleId/cancel');
      final res = await http.post(uri, headers: Env.defaultHeaders);
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule cancelled successfully'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _ridesFuture = _fetchUserRides();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to cancel schedule'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection error while cancelling schedule'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showRatingDialog(int requestId) async {
    int rating = 5;
    final TextEditingController commentController = TextEditingController();
    
    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Rate your ride', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: Colors.orangeAccent,
                    ),
                    onPressed: () {
                      setDialogState(() => rating = index + 1);
                    },
                  );
                }),
              ),
              TextField(
                controller: commentController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Add a comment (optional)',
                  hintStyle: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final userId = prefs.getInt('user_id');
                
                final res = await http.post(
                  Uri.parse('${Env.baseUrl}/rides/$requestId/rate'),
                  headers: {
                    ...Env.defaultHeaders,
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'rating': rating,
                    'comment': commentController.text,
                    'user_id': userId,
                  }),
                );
                
                if (context.mounted) {
                  Navigator.pop(context);
                  if (res.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Thank you for your rating!')),
                    );
                  }
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('yyyy-MM-dd – HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  int _getOccurrences(String startIso, String endIso, String dayName) {
    try {
      final start = DateTime.parse(startIso);
      final end = DateTime.parse(endIso);
      int targetWeekday;
      switch (dayName.toUpperCase()) {
        case 'MONDAY': targetWeekday = DateTime.monday; break;
        case 'TUESDAY': targetWeekday = DateTime.tuesday; break;
        case 'WEDNESDAY': targetWeekday = DateTime.wednesday; break;
        case 'THURSDAY': targetWeekday = DateTime.thursday; break;
        case 'FRIDAY': targetWeekday = DateTime.friday; break;
        case 'SATURDAY': targetWeekday = DateTime.saturday; break;
        case 'SUNDAY': targetWeekday = DateTime.sunday; break;
        default: return 0;
      }
      int count = 0;
      for (var d = start; d.isBefore(end.add(const Duration(days: 1))); d = d.add(const Duration(days: 1))) {
        if (d.weekday == targetWeekday) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return const Color(0xFFFFCC00);
      case 'ACCEPTED':
        return Colors.greenAccent;
      case 'CANCELLED':
        return Colors.redAccent;
      case 'COMPLETED':
        return Colors.blueAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scheduled Rides',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                    ],
                  ),
                  
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Manage your recurring and upcoming rides',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _ridesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFFCC00),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'Error loading rides',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }
                    final rides = snapshot.data ?? [];
                    if (rides.isEmpty) {
                      return const Center(
                        child: Text(
                          'No scheduled rides yet',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: rides.length,
                      itemBuilder: (context, index) {
                        final ride = rides[index];
                        final itemType =
                            (ride['item_type'] ?? 'ride_request').toString();
                        final status = (ride['status'] ?? '').toString();
                        final isRecurring = ride['is_recurring'] == true;
                        final bool isAccepted = status.toUpperCase() == 'ACCEPTED';
                        final dynamic itemId = itemType == 'recurring_schedule'
                            ? ride['schedule_id']
                            : ride['request_id'];
                        final String scheduleLabel = ride['recurring_day'] != null
                            ? 'Every ${ride['recurring_day']}'
                            : (isRecurring
                                ? 'Recurring schedule'
                                : 'Single ride');
                        
                        String priceText = '';
                        String totalPriceText = '';
                        if (ride['estimated_price'] != null) {
                          double priceDT = (ride['estimated_price'] as num) / 1000;
                          priceText = '${priceDT.toStringAsFixed(1)} DT / course';
                          
                          if (itemType == 'recurring_schedule') {
                            final startRaw = ride['start_date'];
                            final endRaw = ride['end_date'];
                            final dayRaw = ride['recurring_day']?.toString() ?? '';
                            // Le backend renvoie parfois "DayOfWeek.MONDAY" → on extrait le jour
                            final dayName = dayRaw.contains('.') ? dayRaw.split('.').last : dayRaw;

                            if (startRaw != null && endRaw != null && dayName.isNotEmpty) {
                              int count = _getOccurrences(startRaw.toString(), endRaw.toString(), dayName);
                              if (count > 0) {
                                totalPriceText = 'Total période: ${(priceDT * count).toStringAsFixed(1)} DT ($count courses)';
                              }
                            }
                          }
                        }

                        return buildScheduleCard(
                          context,
                          'REF-${itemId.toString().padLeft(4, '0')}',
                          'Status: $status',
                          ride['pickup_location'] ?? 'Unknown pickup',
                          ride['dropoff_location'] ?? 'Unknown dropoff',
                          ride['scheduled_for'] != null
                              ? _formatDateTime(
                                  ride['scheduled_for']?.toString() ?? '')
                              : 'Recurring plan',
                          scheduleLabel,
                          isRecurring,
                          isAccepted || status.toUpperCase() == 'ACTIVE',
                          price: priceText,
                          totalPrice: totalPriceText,
                          onCancel: itemType == 'recurring_schedule'
                              ? (status.toUpperCase() == 'ACTIVE'
                                  ? () => _cancelSchedule(
                                      ride['schedule_id'] as int)
                                  : null)
                              : (status.toUpperCase() == 'PENDING'
                                  ? () =>
                                      _cancelRide(ride['request_id'] as int)
                                  : null),
                          onTrack: itemType == 'ride_request' && isAccepted
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TrackRidePage(rideData: ride),
                                    ),
                                  );
                                }
                              : null,
                          onRate: (itemType == 'ride_request' && status.toUpperCase() == 'COMPLETED' && ride['request_id'] != null)
                              ? () => _showRatingDialog(ride['request_id'] as int)
                              : null,
                          onReport: (itemType == 'ride_request' && ride['request_id'] != null)
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReportIncidentPage(
                                        rideId: ride['request_id'].toString(),
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          statusColor: _statusColor(status),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CARD WIDGET
Widget buildScheduledDashboard(
  String title,
  String subtitle,
  Color titleColor,
) {
  return Container(
    width: double.infinity,
    height: 90,
    margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
      ],
    ),
  );
}

Widget buildScheduleCard(
  BuildContext context,
  String title,
  String subtitle,
  String pickup,
  String dropoff,
  String time,
  String days,
  bool isRecurring,
  bool isActive, {
  String? price,
  String? totalPrice,
  VoidCallback? onCancel,
  VoidCallback? onTrack,
  VoidCallback? onRate,
  VoidCallback? onReport,
  Color statusColor = Colors.white,
}) {
  return GestureDetector(
    onLongPress: onCancel != null ? () {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Cancel Reservation?', style: TextStyle(color: Colors.white)),
          content: const Text('Are you sure you want to cancel this reservation?', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('No', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onCancel();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } : null,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(
      children: [
        /// 🔥 CONTENT
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// TITLE + BADGES
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

                if (isRecurring)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Recurring',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 10,
                      ),
                    ),
                  ),

                const SizedBox(width: 6),

                if (isActive)
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

            /// DRIVER
            Text(
              subtitle,
              style: TextStyle(color: statusColor, fontSize: 13),
            ),
            const SizedBox(height: 10),

            /// PICKUP
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
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            /// DROPOFF
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
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),

            /// TIME + DAYS
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  color: Colors.orangeAccent,
                  size: 14,
                ),
                const SizedBox(width: 5),
                Text(
                  time,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),

                const SizedBox(width: 15),

                const Icon(
                  Icons.calendar_today,
                  color: Colors.orangeAccent,
                  size: 14,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    days,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ),
              ],
            ),
            
            if (price != null && price.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.attach_money, color: Colors.greenAccent, size: 14),
                  const SizedBox(width: 5),
                  Text("Prix Estimé: $price", style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
            
            if (totalPrice != null && totalPrice.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet, color: Colors.orangeAccent, size: 14),
                  const SizedBox(width: 5),
                  Text(totalPrice, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                ],
              ),
            ],
          ],
        ),

        /// 🔥 ACTIONS TOP RIGHT
        Positioned(
          top: 0,
          right: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onTrack != null)
                IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFFFFCC00),
                    size: 18,
                  ),
                  onPressed: onTrack,
                ),
              if (onReport != null)
                IconButton(
                  icon: const Icon(
                    Icons.report_problem,
                    color: Colors.orange,
                    size: 18,
                  ),
                  onPressed: onReport,
                ),
              if (onRate != null)
                IconButton(
                  icon: const Icon(
                    Icons.star_rate,
                    color: Colors.amber,
                    size: 18,
                  ),
                  onPressed: onRate,
                ),
              IconButton(
                icon: const Icon(Icons.info, color: Colors.white, size: 18),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
    ),
   ),
  );
}
