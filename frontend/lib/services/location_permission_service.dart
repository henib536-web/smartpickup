import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service to request location permission with a custom dialog on Android.
class LocationPermissionService {
  /// Shows a rationale dialog, then requests the permission.
  /// Returns true if permission is granted.
  static Future<bool> requestWithDialog(BuildContext context) async {
    // Check current status
    PermissionStatus status = await Permission.locationWhenInUse.status;

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      // Already permanently denied — open settings
      await _showPermanentlyDeniedDialog(context);
      return false;
    }

    // Show our custom rationale popup before asking
    final confirmed = await _showRationaleDialog(context);
    if (!confirmed) return false;

    // Request the permission
    status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  static Future<bool> _showRationaleDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFFFCC00), width: 1.5),
            ),
            title: Row(
              children: const [
                Text('🚕', style: TextStyle(fontSize: 28)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Autorisation de localisation',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon illustration
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFCC00).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Color(0xFFFFCC00),
                    size: 42,
                  ),
                ),
                const Text(
                  'SmartPickup a besoin d\'accéder à votre localisation pour :',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _featureRow(Icons.my_location, 'Afficher votre position sur la carte'),
                const SizedBox(height: 8),
                _featureRow(Icons.route, 'Calculer l\'itinéraire vers le passager'),
                const SizedBox(height: 8),
                _featureRow(Icons.directions_car, 'Navigation en temps réel'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Refuser',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFCC00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Autoriser',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<void> _showPermanentlyDeniedDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFF87171), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Color(0xFFF87171), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Localisation désactivée',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'La localisation est refusée de façon permanente. Veuillez l\'activer dans les Paramètres de votre téléphone pour utiliser SmartPickup.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFCC00),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Ouvrir Paramètres', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Widget _featureRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFCC00), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
