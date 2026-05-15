import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/notification.dart';

class DriverLayout extends StatefulWidget {
  final Widget child;
  final String title;
  final int currentIndex;

  const DriverLayout({Key? key, required this.child, required this.title, this.currentIndex = 0}) : super(key: key);

  @override
  _DriverLayoutState createState() => _DriverLayoutState();
}

class _DriverLayoutState extends State<DriverLayout> {
  late int _selectedIndex;
  int? userId;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.currentIndex;
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userId = prefs.getInt('user_id');
    });
  }

  final List<Map<String, dynamic>> _navItems = [
    {'icon': Icons.dashboard, 'label': 'Dashboard', 'route': '/driver'},
    {'icon': Icons.access_time, 'label': 'Ride Requests', 'route': '/driver/requests'},
    {'icon': Icons.directions_car, 'label': 'Active Ride', 'route': '/driver/active'},
    {'icon': Icons.person, 'label': 'Profile', 'route': '/driver/profile'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFCC00), Color(0xFFFF9900)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFCC00).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: const Icon(Icons.directions_car, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SmartPickup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white), overflow: TextOverflow.ellipsis),
                  const Text('Driver Portal', style: TextStyle(fontSize: 12, color: Color(0xFFA0A0A0)), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0A0A0A).withValues(alpha: 0.9),
        elevation: 0,
        actions: [
          if (userId != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: NotificationsWidget(userId: userId!),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Color(0xFFFFCC00), strokeWidth: 2),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF0F0F0F),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFFFCC00),
          unselectedItemColor: const Color(0xFFA0A0A0),
          currentIndex: _selectedIndex,
          onTap: (index) {
            final item = _navItems[index];
            if (item['route'] != null && _selectedIndex != index) {
              Navigator.pushReplacementNamed(context, item['route']);
            }
          },
          items: _navItems.map((item) {
            return BottomNavigationBarItem(
              icon: Icon(item['icon']),
              label: item['label'],
            );
          }).toList(),
        ),
      ),
      body: widget.child,
    );
  }
}