import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/auth_service.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final FirebaseService _firebaseService = FirebaseService();
  final AuthService _authService = AuthService();
  DateTime lastImageTime = DateTime.now();

  Color _getGasColor(double gasLevel) {
    if (gasLevel < 400) return Colors.green;
    if (gasLevel < 800) return Colors.orange;
    return Colors.red;
  }

  Color _getTemperatureColor(double temperature) {
    if (temperature < 28) return Colors.green;
    if (temperature < 32) return Colors.orange;
    return Colors.red;
  }

  String _getGasStatus(double gasLevel) {
    if (gasLevel < 400) return 'Normal';
    if (gasLevel < 800) return 'Elevated';
    return 'Alert!';
  }

  Color _getAlertColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.Good:
        return Colors.green;
      case AlertSeverity.Warning:
        return Colors.orange;
      case AlertSeverity.Danger:
        return Colors.red;
    }
  }

  IconData _getAlertIcon(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.Good:
        return Icons.check_circle;
      case AlertSeverity.Warning:
        return Icons.warning_amber;
      case AlertSeverity.Danger:
        return Icons.dangerous;
    }
  }

  Future<void> _logout() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/auth');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      }
    }
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
            icon: const Icon(Icons.person),
            tooltip: 'Profile',
            onPressed: () {
              _showProfileDialog();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Last Updated - StreamBuilder
            StreamBuilder<DateTime>(
              stream: _firebaseService.getTimestampStream(),
              builder: (context, snapshot) {
                final time = snapshot.data ?? DateTime.now();
                return Text(
                  'Last Updated: ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                );
              },
            ),
            const SizedBox(height: 20),

            // Camera View
            _buildCameraCard(),
            const SizedBox(height: 16),

            // Sensor Cards Row - Each with StreamBuilder
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<double>(
                    stream: _firebaseService.getGasLevelStream(),
                    builder: (context, snapshot) {
                      final gasLevel = snapshot.data ?? 0.0;
                      return _buildSensorCard(
                        title: 'Gas Level',
                        value: '${gasLevel.toStringAsFixed(1)} ppm',
                        icon: Icons.air,
                        color: _getGasColor(gasLevel),
                        status: _getGasStatus(gasLevel),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: StreamBuilder<double>(
                    stream: _firebaseService.getTemperatureStream(),
                    builder: (context, snapshot) {
                      final temperature = snapshot.data ?? 0.0;
                      return _buildSensorCard(
                        title: 'Temperature',
                        value: '${temperature.toStringAsFixed(1)}°C',
                        icon: Icons.thermostat,
                        color: _getTemperatureColor(temperature),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Humidity Card - StreamBuilder
            StreamBuilder<double>(
              stream: _firebaseService.getHumidityStream(),
              builder: (context, snapshot) {
                final humidity = snapshot.data ?? 0.0;
                return _buildSensorCard(
                  title: 'Humidity',
                  value: '${humidity.toStringAsFixed(1)}%',
                  icon: Icons.water_drop,
                  color: Colors.blue,
                  fullWidth: true,
                );
              },
            ),
            const SizedBox(height: 16),

            // Alerts Section - StreamBuilder
            StreamBuilder<AlertSeverity?>(
              stream: _firebaseService.getAlertStream(),
              builder: (context, snapshot) {
                final alertSeverity = snapshot.data;

                if (alertSeverity == null) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      border: Border.all(color: Colors.green[300]!),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'All systems normal',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return _buildAlertCard(alertSeverity);
              },
            ),
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
                StreamBuilder<String?>(
                  stream: _firebaseService.getImageStream(),
                  builder: (context, snapshot) {
                    final image = snapshot.data;
                    return IconButton(
                      icon: const Icon(Icons.fullscreen),
                      onPressed: (image != null && image.isNotEmpty)
                          ? () => _showFullscreenImage(context, image)
                          : null,
                    );
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
            child: StreamBuilder<String?>(
              stream: _firebaseService.getImageStream(),
              builder: (context, snapshot) {
                final image = snapshot.data;

                if (image == null || image.isEmpty) {
                  return Icon(Icons.image, size: 64, color: Colors.grey[400]);
                }

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (image.startsWith('http'))
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                        child: Image.network(
                          image,
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
                                value:
                                    loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                        ),
                      )
                    else
                      _buildBase64Image(image),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBase64Image(String base64String) {
    try {
      String cleanBase64 = base64String;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',')[1];
      }

      Uint8List imageBytes = base64Decode(cleanBase64);

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
      return Icon(Icons.broken_image, size: 64, color: Colors.grey[400]);
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

  Widget _buildAlertCard(AlertSeverity severity) {
    return Card(
      // elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _getAlertColor(severity).withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getAlertIcon(severity),
              color: _getAlertColor(severity),
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(
              severity.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _getAlertColor(severity),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullscreenImage(BuildContext context, String imageData) {
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
                child: imageData.startsWith('http')
                    ? Image.network(
                        imageData,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.broken_image,
                            size: 100,
                            color: Colors.white,
                          );
                        },
                      )
                    : _buildFullscreenBase64Image(imageData),
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

  Widget _buildFullscreenBase64Image(String base64String) {
    try {
      String cleanBase64 = base64String;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',')[1];
      }

      Uint8List imageBytes = base64Decode(cleanBase64);

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

  void _showProfileDialog() {
    final user = _authService.currentUser;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('Email: ${user?.email ?? 'N/A'}')],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
