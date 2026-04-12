import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env for any custom secrets
  await dotenv.load(fileName: ".env");

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IgnisGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const Dashboard(),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  // Firebase Database reference
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

  // Sensor data
  double gasLevel = 0.0;
  double temperature = 0.0;
  double humidity = 0.0;
  String? imageUrl;
  String? imageBase64;
  DateTime lastUpdate = DateTime.now();
  DateTime lastImageTime = DateTime.now();

  // Stream subscriptions
  StreamSubscription? _gasSubscription;
  StreamSubscription? _tempSubscription;
  StreamSubscription? _humiditySubscription;
  StreamSubscription? _imageSubscription;
  StreamSubscription? _timestampSubscription;

  @override
  void initState() {
    super.initState();
    _listenToSensorData();
  }

  void _listenToSensorData() {
    // Listen to timestamp updates
    _timestampSubscription = _databaseRef.child('timestamp').onValue.listen((
      event,
    ) {
      final value = event.snapshot.value;
      if (value != null && mounted) {
        setState(() {
          // Firebase timestamp is in milliseconds
          lastUpdate = DateTime.fromMillisecondsSinceEpoch(value as int);
        });
      }
    });

    // Listen to gas level updates
    _gasSubscription = _databaseRef.child('esp32/gas').onValue.listen((event) {
      final value = event.snapshot.value;
      if (value != null && mounted) {
        setState(() {
          gasLevel = (value as num).toDouble();
        });
      }
    });

    // Listen to temperature updates
    _tempSubscription = _databaseRef.child('esp32/temperature').onValue.listen((
      event,
    ) {
      final value = event.snapshot.value;
      if (value != null && mounted) {
        setState(() {
          temperature = (value as num).toDouble();
        });
      }
    });

    // Listen to humidity updates
    _humiditySubscription = _databaseRef.child('esp32/humidity').onValue.listen(
      (event) {
        final value = event.snapshot.value;
        if (value != null && mounted) {
          setState(() {
            humidity = (value as num).toDouble();
          });
        }
      },
    );

    // Listen to image updates
    _imageSubscription = _databaseRef.child('image').onValue.listen((event) {
      final value = event.snapshot.value;
      if (value != null && mounted) {
        setState(() {
          if (value is String && value.isNotEmpty) {
            // It's a direct base64 string or URL
            if (value.startsWith('http')) {
              // It's a URL
              imageUrl = value;
              imageBase64 = null;
            } else {
              // It's base64 data (with or without data:image prefix)
              imageBase64 = value;
              imageUrl = null;
            }
            lastImageTime = DateTime.now();
          } else if (value is Map) {
            // Legacy support: nested object with data/url fields
            final imageData =
                value['data'] as String? ?? value['url'] as String?;
            if (imageData != null && imageData.isNotEmpty) {
              if (imageData.startsWith('http')) {
                imageUrl = imageData;
                imageBase64 = null;
              } else {
                imageBase64 = imageData;
                imageUrl = null;
              }
            }
            if (value['timestamp'] != null) {
              lastImageTime = DateTime.fromMillisecondsSinceEpoch(
                value['timestamp'] as int,
              );
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _gasSubscription?.cancel();
    _tempSubscription?.cancel();
    _humiditySubscription?.cancel();
    _imageSubscription?.cancel();
    _timestampSubscription?.cancel();
    super.dispose();
  }

  Color _getGasColor() {
    if (gasLevel < 50) return Colors.green;
    if (gasLevel < 75) return Colors.orange;
    return Colors.red;
  }

  Color _getTemperatureColor() {
    if (temperature < 28) return Colors.green;
    if (temperature < 32) return Colors.orange;
    return Colors.red;
  }

  String _getGasStatus() {
    if (gasLevel < 50) return 'Normal';
    if (gasLevel < 75) return 'Elevated';
    return 'Alert!';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'IgnisGuard Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () {
              // Force re-read from Firebase
              _listenToSensorData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing sensor data...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
            Text(
              'Last Updated: ${lastUpdate.hour.toString().padLeft(2, '0')}:${lastUpdate.minute.toString().padLeft(2, '0')}:${lastUpdate.second.toString().padLeft(2, '0')}',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Camera View
            _buildCameraCard(),
            const SizedBox(height: 16),

            // Sensor Cards Row
            Row(
              children: [
                Expanded(
                  child: _buildSensorCard(
                    title: 'Gas Level',
                    value: '${gasLevel.toStringAsFixed(1)} ppm',
                    icon: Icons.air,
                    color: _getGasColor(),
                    status: _getGasStatus(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSensorCard(
                    title: 'Temperature',
                    value: '${temperature.toStringAsFixed(1)}°C',
                    icon: Icons.thermostat,
                    color: _getTemperatureColor(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Humidity Card (Full Width)
            _buildSensorCard(
              title: 'Humidity',
              value: '${humidity.toStringAsFixed(1)}%',
              icon: Icons.water_drop,
              color: Colors.blue,
              fullWidth: true,
            ),
            const SizedBox(height: 16),

            // Alert Section
            if (gasLevel >= 75 || temperature >= 32) _buildAlertCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.photo_camera, color: Colors.deepOrange),
                const SizedBox(width: 8),
                const Text(
                  'Last Captured Image',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () {
                    if ((imageBase64 != null && imageBase64!.isNotEmpty) ||
                        (imageUrl != null && imageUrl!.isNotEmpty)) {
                      _showFullscreenImage(context);
                    }
                  },
                ),
              ],
            ),
          ),
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Display image from Firebase or placeholder
                if (imageBase64 != null && imageBase64!.isNotEmpty)
                  _buildBase64Image()
                else if (imageUrl != null && imageUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    child: Image.network(
                      imageUrl!,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.broken_image,
                          size: 64,
                          color: Colors.grey[400],
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                    ),
                  )
                else
                  Icon(Icons.image, size: 64, color: Colors.grey[400]),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${lastImageTime.hour.toString().padLeft(2, '0')}:${lastImageTime.minute.toString().padLeft(2, '0')}:${lastImageTime.second.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBase64Image() {
    try {
      // Remove the data:image/jpeg;base64, prefix if present
      String base64String = imageBase64!;
      if (base64String.contains(',')) {
        base64String = base64String.split(',')[1];
      }

      // Decode base64 string to bytes
      Uint8List imageBytes = base64Decode(base64String);

      return ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        child: Image.memory(
          imageBytes,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Icon(Icons.broken_image, size: 64, color: Colors.grey[400]);
          },
        ),
      );
    } catch (e) {
      // If decoding fails, show error icon
      return Icon(Icons.broken_image, size: 64, color: Colors.grey[400]);
    }
  }

  void _showFullscreenImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: imageBase64 != null && imageBase64!.isNotEmpty
                    ? _buildFullscreenBase64Image()
                    : (imageUrl != null && imageUrl!.isNotEmpty
                          ? Image.network(
                              imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.broken_image,
                                  size: 100,
                                  color: Colors.white,
                                );
                              },
                            )
                          : const Icon(
                              Icons.image,
                              size: 100,
                              color: Colors.white,
                            )),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Captured: ${lastImageTime.day}/${lastImageTime.month}/${lastImageTime.year} ${lastImageTime.hour.toString().padLeft(2, '0')}:${lastImageTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenBase64Image() {
    try {
      String base64String = imageBase64!;
      if (base64String.contains(',')) {
        base64String = base64String.split(',')[1];
      }

      Uint8List imageBytes = base64Decode(base64String);

      return Image.memory(
        imageBytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.broken_image, size: 100, color: Colors.white);
        },
      );
    } catch (e) {
      return const Icon(Icons.broken_image, size: 100, color: Colors.white);
    }
  }

  Widget _buildSensorCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? status,
    bool fullWidth = false,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            if (status != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard() {
    return Card(
      elevation: 4,
      color: Colors.red[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alert',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gasLevel >= 75
                        ? 'High gas levels detected!'
                        : 'High temperature detected!',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
