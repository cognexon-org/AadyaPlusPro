import 'package:geolocator/geolocator.dart';

class FieldLocationService {
  static Future<Map<String, dynamic>> currentPayload() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError(
        'Location services are disabled. Turn on GPS and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is required for field attendance and DCR check-in.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return {
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
