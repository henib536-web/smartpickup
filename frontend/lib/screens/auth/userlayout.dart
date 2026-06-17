import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/notification.dart';

class UserLayout extends StatefulWidget {
  final Widget child;
  const UserLayout({super.key, required this.child});

  @override
  State<UserLayout> createState() => _UserLayoutState();
}

class _UserLayoutState extends State<UserLayout> {
  int? userId;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  // Récupération de l'ID de l'utilisateur connecté depuis le stockage local
  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // On récupère l'ID enregistré avec la clé 'user_id' lors du login
      userId = prefs.getInt('user_id'); 
    });
  }

  Future<void> handleLogout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushReplacementNamed(context, "/");
  }

  void navigate(BuildContext context, int index) {
    final routes = [
      "/user", 
      "/user/bookride", 
      "/user/scheduled", 
            "/user/profile", 

    ];
    if (index < routes.length) {
      Navigator.pushReplacementNamed(context, routes[index]);
    }
  }

  int getCurrentIndex(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    switch (route) {
      case "/user": return 0;
      case "/user/bookride": return 1;
      case "/user/profile": return 3;
      case "/user/scheduled": return 2;
  
      default: return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = getCurrentIndex(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 20.0,
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFCC00), Color(0xFFFF9900)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.directions_car, color: Colors.black),
            ),
            const SizedBox(width: 10),
            const Text(
              "SmartPickup", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
            ),
          ],
        ),
        actions: [
          // Affiche le widget de notification seulement quand le userId est prêt
          if (userId != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
              child: NotificationsWidget(userId: userId!),
            )
          else
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(
                  color: Color(0xFFFFCC00), 
                  strokeWidth: 2
                )
              ),
            ),
        ],
      ),
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F0F0F),
        selectedItemColor: const Color(0xFFFFCC00),
        unselectedItemColor: Colors.grey,
        currentIndex: currentIndex,
        onTap: (index) => navigate(context, index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.directions_car), label: "Book"),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: "Scheduled"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),


        ],
      ),
    );
  }
}