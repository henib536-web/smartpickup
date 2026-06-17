import 'package:flutter/material.dart';
import 'package:test_windows/screens/auth/login.dart';
import 'package:test_windows/screens/auth/signup.dart';
import 'package:test_windows/screens/auth/forgot_password.dart';
import 'package:test_windows/screens/user/Book.dart';
import 'package:test_windows/screens/user/scheduled.dart';
import 'package:test_windows/screens/user/schedule.dart';
import 'package:test_windows/screens/user/profile_page.dart';
import 'package:test_windows/screens/user/track_ride.dart';
import 'package:test_windows/screens/user/incident_rapport.dart';
import 'package:test_windows/screens/user/Ride_History.dart';
import 'package:test_windows/screens/auth/userlayout.dart';
import 'package:test_windows/screens/auth/driver_layout.dart';
import 'package:test_windows/screens/user/home.dart';
import 'package:test_windows/screens/driver/driver_dashboard.dart';
import 'package:test_windows/screens/driver/driver_requests.dart';
import 'package:test_windows/screens/driver/driver_active_ride.dart';
import 'package:test_windows/screens/driver/driver_history.dart';
import 'package:test_windows/screens/driver/driver_profile.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:test_windows/services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    await FCMService().init();
  } catch (e) {
    print("Erreur d'initialisation de Firebase: $e");
  }
  
  runApp(MyApp());
}
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'SmartPickup',
      initialRoute: '/',
      routes: {
        '/': (context) => Login(),
        '/signup': (context) => Signup(),
        '/forgot-password': (context) => const ForgotPassword(),
        // Tous les écrans utilisateurs passent par UserLayout
        '/user': (context) => const UserLayout(child: Center(child: HomePage())),
        '/user/bookride': (context) => const UserLayout(child: BookRide()),
        '/user/scheduled': (context) => const UserLayout(child: Scheduled()),
        '/user/track_ride': (context) => const UserLayout(child: TrackRidePage()),
        '/user/schedule': (context) => UserLayout(child: NewSchedule()),
        '/user/incident_rapport': (context) => UserLayout(child: ReportIncidentPage()),
        '/user/profile': (context) => const UserLayout(child: ProfilePage()),
        '/user/history': (context) => const UserLayout(child: RideHistory()),
        '/userlayout': (context) => UserLayout(child: Center(child: HomePage()), ),
        //driver 
        // Routes pour l'interface Chauffeur (Driver)
        '/driver': (context) => const DriverDashboard(),
        '/driver/dashboard': (context) => const DriverDashboard(),
        '/driver/requests': (context) => const DriverRequests(),
        '/driver/active': (context) => const DriverActiveRide(),
        '/driver/active_ride': (context) => const DriverActiveRide(),
        '/driver/history': (context) => const DriverHistory(),
        '/driver/profile': (context) => const DriverProfile(),

        // Route par défaut
        '/driverlayout': (context) => const DriverDashboard(),
      },
    );
  }
}