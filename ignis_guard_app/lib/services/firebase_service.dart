import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

  factory FirebaseService() {
    return _instance;
  }

  FirebaseService._internal();

  // Sensor Data Streams
  Stream<double> getGasLevelStream() {
    return _databaseRef.child('esp32/gas').onValue.map((event) {
      final value = event.snapshot.value;
      return value != null ? (value as num).toDouble() : 0.0;
    });
  }

  Stream<double> getTemperatureStream() {
    return _databaseRef.child('esp32/temperature').onValue.map((event) {
      final value = event.snapshot.value;
      return value != null ? (value as num).toDouble() : 0.0;
    });
  }

  Stream<double> getHumidityStream() {
    return _databaseRef.child('esp32/humidity').onValue.map((event) {
      final value = event.snapshot.value;
      return value != null ? (value as num).toDouble() : 0.0;
    });
  }

  Stream<String?> getImageStream() {
    return _databaseRef.child('image').onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return null;

      if (value is String) {
        return value.isNotEmpty ? value : null;
      } else if (value is Map) {
        return (value['data'] as String?) ?? (value['url'] as String?);
      }
      return null;
    });
  }

  Stream<DateTime> getTimestampStream() {
    return _databaseRef.child('timestamp').onValue.map((event) {
      final value = event.snapshot.value;
      return value != null
          ? DateTime.fromMillisecondsSinceEpoch(value as int)
          : DateTime.now();
    });
  }

  // Alert Stream - returns alert from firebase/alerts
  Stream<AlertSeverity?> getAlertStream() {
    return _databaseRef.child('alerts').onValue.map((event) {
      if (!event.snapshot.exists) return null;
      final value = event.snapshot.value;
      if (value is String) {
        return _parseSeverity(value);
      }
      return null;
    });
  }

  // Set alert
  Future<void> setAlert(AlertSeverity severity) async {
    try {
      await _databaseRef.child('alerts').set(severity.name);
    } catch (e) {
      throw Exception('Failed to set alert: $e');
    }
  }

  // Clear alert
  Future<void> clearAlert() async {
    try {
      await _databaseRef.child('alerts').remove();
    } catch (e) {
      throw Exception('Failed to clear alert: $e');
    }
  }

  static AlertSeverity _parseSeverity(String severity) {
    return AlertSeverity.values.firstWhere(
      (e) => e.name.toLowerCase() == severity.toLowerCase(),
      orElse: () => AlertSeverity.Warning,
    );
  }
}

enum AlertSeverity { Good, Warning, Danger }
