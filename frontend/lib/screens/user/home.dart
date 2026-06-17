import 'package:flutter/material.dart';
import '../../services/user_api_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Model classes
class RideData {
  final int id;
  final String pickup;
  final String dropoff;
  final String date;
  final String time;
  final String passenger;
  final String type;
  final String driver;
  final String status;

  RideData({
    required this.id,
    required this.pickup,
    required this.dropoff,
    required this.date,
    required this.time,
    required this.passenger,
    required this.type,
    required this.driver,
    required this.status,
  });
}

class NewsItem {
  final int id;
  final String title;
  final String description;
  final String time;
  final String type;

  NewsItem({
    required this.id,
    required this.title,
    required this.description,
    required this.time,
    required this.type,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final UserApiService _apiService = UserApiService();
  
  List<RideData> upcomingRides = [];
  bool _isLoading = true;
  int _totalRides = 0;
  String _userName = "User";

  final List<NewsItem> news = [
   NewsItem(
  id: 1,
  title: "New Safety Features Will Be Available",
  description: "You will soon be able to share your live location with up to 5 emergency contacts",
  time: "Coming soon",
  type: "feature",
),

NewsItem(
  id: 2,
  title: "Your Driver Will Be Able to Receive Ratings",
  description: "You will be able to rate your driver after each ride",
  time: "Next update",
  type: "rating",
),

NewsItem(
  id: 3,
  title: "Monthly Report Will Be Available",
  description: "Your transportation report will be ready for download at the end of the month",
  time: "End of month",
  type: "report",
),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userName = prefs.getString('user_name') ?? "User";
      });

      final ridesData = await _apiService.getUserRides();
      
      setState(() {
        _totalRides = ridesData.length;
        
        // Filter and map to RideData
        // Only show PENDING or ACCEPTED rides as "Upcoming" and strictly filter out expired dates
        final now = DateTime.now();
        upcomingRides = ridesData.where((e) {
          final status = e['status'];
          bool validStatus = status == 'PENDING' || status == 'ACCEPTED' || status == 'ACTIVE';
          
          bool isFuture = true;
          if (e['scheduled_for'] != null) {
            try {
              final sched = DateTime.parse(e['scheduled_for']);
              // On n'affiche jamais une course dont la date est strictement dépassée
              if (sched.isBefore(now)) {
                isFuture = false;
              }
            } catch (_) {}
          } else if (e['requested_at'] != null) {
            try {
              final reqAt = DateTime.parse(e['requested_at']);
              // Les courses ASAP expirent après 15 minutes (comme côté backend)
              if (reqAt.add(const Duration(minutes: 15)).isBefore(now)) {
                isFuture = false;
              }
            } catch (_) {}
          }
          
          return validStatus && isFuture;
        }).take(3).map((e) {
          DateTime? sched;
          if (e['scheduled_for'] != null) {
            sched = DateTime.parse(e['scheduled_for']);
          }
          
          return RideData(
            id: e['request_id'] ?? e['schedule_id'] ?? 0,
            pickup: e['pickup_location'] ?? 'N/A',
            dropoff: e['dropoff_location'] ?? 'N/A',
            date: sched != null ? DateFormat('MMM d, yyyy').format(sched) : (e['item_type'] == 'recurring_schedule' ? 'Recurring' : 'Today'),
            time: sched != null ? DateFormat('HH:mm').format(sched) : (e['recurring_day'] ?? 'NOW'),
            passenger: "You", // Backend doesn't always return passenger name for list
            type: e['item_type'] == 'recurring_schedule' ? 'Recurring' : 'One-time',
            driver: "Pending", // Backend doesn't return driver in list
            status: e['status'] ?? 'N/A',
          );
        }).toList();
        
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading dashboard data: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 768;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFFCC00))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome Hero Section
              _buildHeroSection(context),
              
              const SizedBox(height: 32),
              
              // User Dashboard Stats
              _buildStatsSection(isDesktop),
              
              const SizedBox(height: 32),
              
              // Upcoming Rides Section
              _buildUpcomingRidesSection(context),
              
              const SizedBox(height: 32),
              
              // News & Updates Section
              _buildNewsSection(),
              
              const SizedBox(height: 32),
              
              // Quick Actions
              _buildQuickActionsSection(context, isDesktop),
              
              const SizedBox(height: 32),
              
              // Features Grid
              _buildFeaturesSection(isDesktop),
              
              const SizedBox(height: 32),
              
              // Stats Section
              _buildWhyChooseSection(isDesktop),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // Build Hero Section
  Widget _buildHeroSection(BuildContext context) {
    return FadeTransition(
      opacity: _animationController,
      child: Column(
        children: [
          const SizedBox(height: 48),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              children: [
                const TextSpan(text: "Welcome, "),
                TextSpan(
                  text: _userName,
                  style: const TextStyle(color: Color(0xFFFFCC00)),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          const Text(
            "🚀  Safe, Reliable, Smart Transportation at Your Fingertips",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFFa0a0a0),
            ),
          ),
          
          const SizedBox(height: 32),
          
          ElevatedButton(
            onPressed: () {
              Navigator.pushNamed(context, '/user/bookride');
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: const Color(0xFFFFCC00),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
              shadowColor: const Color(0xFFFFCC00).withOpacity(0.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.directions_car, size: 24),
                SizedBox(width: 12),
                Text(
                  "Book a Ride Now",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build Stats Section
  Widget _buildStatsSection(bool isDesktop) {
    final stats = {
      "Total Rides": _totalRides.toString(),
      "Avg Wait Time": "4.2 min",
      "Time Saved": "${(_totalRides * 0.25).toStringAsFixed(1)} hrs",
      "Upcoming Rides": upcomingRides.length.toString(),
    };

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1a1a1a), Color(0xFF0f0f0f)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.trending_up, color: Color(0xFFFFCC00), size: 24),
              SizedBox(width: 8),
              Text(
                "Your Activity",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isDesktop ? 4 : 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: isDesktop ? 1.5 : 1.2,
            children: stats.entries.map((entry) {
              return _buildStatCard(entry.value, entry.key);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String value, String label) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a0a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFFFCC00),
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFa0a0a0),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Build Upcoming Rides Section
  Widget _buildUpcomingRidesSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.calendar_today, color: Color(0xFFFFCC00), size: 24),
                  SizedBox(width: 8),
                  Text(
                    "Upcoming Rides",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/user/scheduled');
                },
                icon: const Icon(Icons.arrow_forward, size: 15, color: Color(0xFFFFCC00)),
                label: const Text(
                  "View All",
                  style: TextStyle(
                    color: Color(0xFFFFCC00),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          if (upcomingRides.isEmpty)
            _buildEmptyRidesState(context)
          else
            Column(
              children: upcomingRides.map((ride) => _buildRideCard(ride)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildRideCard(RideData ride) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0f0f0f),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Navigate to ride details
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type and Status Badges
                Row(
                  children: [
                    _buildBadge(
                      ride.type,
                      ride.type == "Recurring"
                          ? Colors.purple
                          : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    _buildBadge(
                      ride.status,
                      ride.status == "Confirmed"
                          ? Colors.green
                          : Colors.yellow,
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Pickup and Dropoff
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFFFFCC00), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ride.pickup,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(Icons.arrow_forward, color: Color(0xFFa0a0a0), size: 16),
                    ),
                    Expanded(
                      child: Text(
                        ride.dropoff,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Additional Info
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(Icons.access_time, "${ride.date} at ${ride.time}"),
                    _buildInfoChip(Icons.person, ride.passenger),
                    if (ride.driver != "Pending")
                      _buildInfoChip(Icons.directions_car, ride.driver),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
color: Colors.blue.shade400,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFa0a0a0), size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFa0a0a0),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyRidesState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.calendar_today,
            size: 48,
            color: const Color(0xFFa0a0a0).withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            "No upcoming rides scheduled",
            style: TextStyle(color: Color(0xFFa0a0a0)),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              Navigator.pushNamed(context, '/user/bookride');
            },
            child: const Text(
              "Book your first ride",
              style: TextStyle(
                color: Color(0xFFFFCC00),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build News Section
  Widget _buildNewsSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.notifications, color: Color(0xFFFFCC00), size: 24),
              SizedBox(width: 8),
              Text(
                "News & Updates",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Column(
            children: news.map((item) => _buildNewsCard(item)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(NewsItem item) {
    IconData iconData;
    Color iconColor;
    Color bgColor;

    switch (item.type) {
      case "feature":
        iconData = Icons.shield;
        iconColor = Colors.blue.shade400;
        bgColor = Colors.blue.withOpacity(0.2);
        break;
      case "rating":
        iconData = Icons.trending_up;
        iconColor = Colors.green.shade400;
        bgColor = Colors.green.withOpacity(0.2);
        break;
      case "report":
        iconData = Icons.calendar_today;
        iconColor = Colors.purple.shade400;
        bgColor = Colors.purple.withOpacity(0.2);
        break;
      default:
        iconData = Icons.info;
        iconColor = Colors.grey;
        bgColor = Colors.grey.withOpacity(0.2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0f0f0f),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(iconData, color: iconColor, size: 20),
                ),
                
                const SizedBox(width: 12),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        style: const TextStyle(
                          color: Color(0xFFa0a0a0),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.time,
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build Quick Actions Section
  Widget _buildQuickActionsSection(BuildContext context, bool isDesktop) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isDesktop ? 3 : 1,
      mainAxisSpacing: 24,
      crossAxisSpacing: 24,
      childAspectRatio: isDesktop ? 1.3 : 2.5,
      children: [
       
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String description,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.colors.first.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: icon == Icons.directions_car ? Colors.black : Colors.white,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFFa0a0a0),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build Features Section
  Widget _buildFeaturesSection(bool isDesktop) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isDesktop ? 2 : 1,
      mainAxisSpacing: 24,
      crossAxisSpacing: 24,
      childAspectRatio: isDesktop ? 1.5 : 0.9,
      children: [
        _buildFeatureCard(
          icon: Icons.shield,
          title: "Safety First",
          description:
              "Complete safety features including real-time tracking, driver verification, and 24/7 incident reporting system.",
          features: [
            "Verified drivers with background checks",
            "Real-time GPS tracking",
            "Emergency contact features",
          ],
        ),
        _buildFeatureCard(
          icon: Icons.access_time,
          title: "Flexible Scheduling",
          description:
              "Book rides instantly or schedule in advance. Set up recurring trips for daily routines like school pickups.",
          features: [
            "On-demand and scheduled rides",
            "Recurring trip management",
            "Predictive scheduling",
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required List<String> features,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1a1a1a), Color(0xFF0f0f0f)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFFCC00), size: 48),
          
          const SizedBox(height: 16),
          
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 12),
          
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFFa0a0a0),
              fontSize: 14,
            ),
          ),
          
          const SizedBox(height: 16),
          
          Column(
            children: features.map((feature) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFCC00),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(
                          color: Color(0xFFa0a0a0),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Build Why Choose Section
  Widget _buildWhyChooseSection(bool isDesktop) {
    final stats = [
      {"value": "", "label": "Happy Users"},
      {"value": "", "label": "Verified Drivers"},
      {"value": "4.9", "label": "Average Rating"},
      {"value": "24/7", "label": "Support"},
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFCC00), Color(0xFFff9900)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Text(
            "Why Choose SmartPickup?",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 32),
          
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isDesktop ? 4 : 2,
            mainAxisSpacing: 24,
            crossAxisSpacing: 24,
            childAspectRatio: 1.5,
            children: stats.map((stat) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    stat["value"]!,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stat["label"]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
