import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';

List<CameraDescription> _availableCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _availableCameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera initialization error: $e');
  }
  runApp(const SixMWTApp());
}

class SixMWTApp extends StatelessWidget {
  const SixMWTApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '6MWT & Gait Assessment',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PatientIntakeScreen(),
    );
  }
}

// ─── DATABASE HELPER ─────────────────────────────────────────────────────────

class DatabaseHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'sixmwt.db');
    return openDatabase(fullPath, version: 2, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE tests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          mode TEXT,
          name TEXT,
          patient_id TEXT,
          age INTEGER,
          sex TEXT,
          height REAL,
          weight REAL,
          referred_by TEXT,
          indication TEXT,
          date_time TEXT,
          start_latitude REAL,
          start_longitude REAL,
          raw_distance REAL,
          corrected_distance REAL,
          predicted REAL,
          percent_predicted REAL,
          avg_speed REAL,
          avg_accuracy REAL,
          gps_points TEXT,
          video_path TEXT
        )
      ''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute('ALTER TABLE tests ADD COLUMN mode TEXT');
        await db.execute('ALTER TABLE tests ADD COLUMN start_latitude REAL');
        await db.execute('ALTER TABLE tests ADD COLUMN start_longitude REAL');
        await db.execute('ALTER TABLE tests ADD COLUMN video_path TEXT');
      }
    });
  }

  static Future<int> insertTest(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('tests', data);
  }

  static Future<List<Map<String, dynamic>>> getAllTests() async {
    final db = await database;
    return db.query('tests', orderBy: 'id DESC');
  }
}

// ─── PATIENT INTAKE SCREEN ───────────────────────────────────────────────────

class PatientIntakeScreen extends StatefulWidget {
  const PatientIntakeScreen({super.key});
  @override
  State<PatientIntakeScreen> createState() => _PatientIntakeScreenState();
}

class _PatientIntakeScreenState extends State<PatientIntakeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _referredCtrl = TextEditingController();
  
  String _sex = 'Male';
  String _indication = 'Spine';
  
  double? _startLat;
  double? _startLng;
  String _locationStatus = 'Fetching initial GPS coordinates...';

  final List<String> _sexOptions = ['Male', 'Female', 'Other'];
  final List<String> _indicationOptions = ['Spine', 'Cardiac', 'Pulmonary', 'Geriatric', 'Other'];

  @override
  void initState() {
    super.initState();
    _fetchInitialCoordinates();
  }

  Future<void> _fetchInitialCoordinates() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationStatus = 'GPS Disabled');
        return;
      }
      var status = await Permission.location.status;
      if (status.isDenied) status = await Permission.location.request();

      if (status.isGranted) {
        Position pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        setState(() {
          _startLat = pos.latitude;
          _startLng = pos.longitude;
          _locationStatus = 'Lat: ${pos.latitude.toStringAsFixed(5)}, Lng: ${pos.longitude.toStringAsFixed(5)}';
        });
      } else {
        setState(() => _locationStatus = 'Location Permission Denied');
      }
    } catch (e) {
      setState(() => _locationStatus = 'Loc Error: $e');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _referredCtrl.dispose();
    super.dispose();
  }

  void _launch6MWT() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TestScreen(
          name: _nameCtrl.text.trim(),
          patientId: _idCtrl.text.trim(),
          age: int.parse(_ageCtrl.text.trim()),
          sex: _sex,
          height: double.parse(_heightCtrl.text.trim()),
          weight: double.parse(_weightCtrl.text.trim()),
          referredBy: _referredCtrl.text.trim(),
          indication: _indication,
          startLat: _startLat,
          startLng: _startLng,
        ),
      ),
    );
  }

  void _launchGaitVideo() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GaitVideoScreen(
          name: _nameCtrl.text.trim(),
          patientId: _idCtrl.text.trim(),
          age: int.parse(_ageCtrl.text.trim()),
          sex: _sex,
          height: double.parse(_heightCtrl.text.trim()),
          weight: double.parse(_weightCtrl.text.trim()),
          referredBy: _referredCtrl.text.trim(),
          indication: _indication,
          startLat: _startLat,
          startLng: _startLng,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Intake & Assessment'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _locationStatus,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: _fetchInitialCoordinates,
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Patient Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Patient Name *', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idCtrl,
                decoration: const InputDecoration(labelText: 'Patient ID *', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ageCtrl,
                decoration: const InputDecoration(labelText: 'Age (years) *', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final age = int.tryParse(v.trim());
                  if (age == null || age < 1 || age > 120) return 'Invalid age';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _sex,
                decoration: const InputDecoration(labelText: 'Sex *', border: OutlineInputBorder()),
                items: _sexOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _sex = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _heightCtrl,
                decoration: const InputDecoration(labelText: 'Height (cm) *', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final h = double.tryParse(v.trim());
                  if (h == null || h < 50 || h > 250) return 'Invalid height';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _weightCtrl,
                decoration: const InputDecoration(labelText: 'Weight (kg) *', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final w = double.tryParse(v.trim());
                  if (w == null || w < 10 || w > 300) return 'Invalid weight';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referredCtrl,
                decoration: const InputDecoration(labelText: 'Referred By *', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _indication,
                decoration: const InputDecoration(labelText: 'Clinical Indication *', border: OutlineInputBorder()),
                items: _indicationOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _indication = v!),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _launch6MWT,
                icon: const Icon(Icons.directions_walk),
                label: const Text('START 6 MINUTE WALK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _launchGaitVideo,
                icon: const Icon(Icons.videocam),
                label: const Text('START RECORDING VIDEO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                child: const Text('VIEW PAST RECORDS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 6MWT TEST SCREEN (STRICT FULL 6 MINUTE DURATION) ───────────────────────

class TestScreen extends StatefulWidget {
  final String name, patientId, sex, referredBy, indication;
  final int age;
  final double height, weight;
  final double? startLat, startLng;

  const TestScreen({
    super.key,
    required this.name,
    required this.patientId,
    required this.age,
    required this.sex,
    required this.height,
    required this.weight,
    required this.referredBy,
    required this.indication,
    this.startLat,
    this.startLng,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  static const int testDuration = 360; // 6 Minutes

  int _secondsLeft = testDuration;
  double _rawDistance = 0;
  double _currentAccuracy = 0;
  bool _testStarted = false;
  bool _testDone = false;
  String _statusMessage = 'Checking GPS status...';

  Timer? _countdownTimer;
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;
  final List<Position> _positions = [];
  final List<double> _accuracyReadings = [];
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initGPS();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _positionSub?.cancel();
    _audioPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _playCompletionSound() async {
    try {
      await _audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/alarms/beep_short.ogg'));
    } catch (e) {
      debugPrint('Audio play error: $e');
    }
  }

  Future<void> _initGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'GPS is turned off. Please enable location services.');
      return;
    }

    var status = await Permission.location.status;
    if (status.isDenied) status = await Permission.location.request();

    if (!status.isGranted) {
      setState(() => _statusMessage = 'Location permission denied.');
      return;
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      setState(() {
        _currentAccuracy = pos.accuracy;
        _statusMessage = 'GPS ready (${pos.accuracy.toStringAsFixed(1)}m). Press START when ready.';
      });
    } catch (e) {
      setState(() => _statusMessage = 'GPS error: $e');
    }
  }

  void _startTest() {
    setState(() {
      _testStarted = true;
      _statusMessage = '6MWT Running... (Must complete full 6 minutes)';
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _completeTest();
        }
      });
    });

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2),
    ).listen((Position pos) {
      setState(() {
        _currentAccuracy = pos.accuracy;
        _accuracyReadings.add(pos.accuracy);

        if (_lastPosition != null) {
          double segment = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          if (segment < 20.0) {
            _rawDistance += segment;
          }
        }
        _lastPosition = pos;
        _positions.add(pos);
      });
    });
  }

  void _completeTest() async {
    _countdownTimer?.cancel();
    _positionSub?.cancel();

    await _playCompletionSound();

    final avgSpeed = (_rawDistance / 1000) / (testDuration / 3600);
    final avgAccuracy = _accuracyReadings.isEmpty
        ? 0.0
        : _accuracyReadings.reduce((a, b) => a + b) / _accuracyReadings.length;

    double corrected = _rawDistance;
    if (avgSpeed < 3.5) {
      final deficit = 3.5 - avgSpeed;
      corrected = _rawDistance * (1 + deficit * 0.02);
    }

    double predicted;
    if (widget.sex == 'Male') {
      predicted = (7.57 * widget.height) - (5.02 * widget.age) - (1.76 * widget.weight) - 309;
    } else {
      predicted = (2.11 * widget.height) - (2.29 * widget.weight) - (5.78 * widget.age) + 667;
    }
    predicted = predicted.clamp(100, 1000);
    final percentPredicted = (corrected / predicted) * 100;

    final gpsJson = jsonEncode(_positions
        .map((p) => {'lat': p.latitude, 'lng': p.longitude, 'acc': p.accuracy, 'ts': p.timestamp.toIso8601String()})
        .toList());

    final testData = {
      'mode': '6MWT',
      'name': widget.name,
      'patient_id': widget.patientId,
      'age': widget.age,
      'sex': widget.sex,
      'height': widget.height,
      'weight': widget.weight,
      'referred_by': widget.referredBy,
      'indication': widget.indication,
      'date_time': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      'start_latitude': widget.startLat,
      'start_longitude': widget.startLng,
      'raw_distance': _rawDistance,
      'corrected_distance': corrected,
      'predicted': predicted,
      'percent_predicted': percentPredicted,
      'avg_speed': avgSpeed,
      'avg_accuracy': avgAccuracy,
      'gps_points': gpsJson,
      'video_path': null,
    };

    await DatabaseHelper.insertTest(testData);

    setState(() => _testDone = true);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            testData: testData,
            avgAccuracy: avgAccuracy,
            avgSpeed: avgSpeed,
          ),
        ),
      );
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_testStarted || _testDone,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('6MWT Active Tracking'),
          backgroundColor: _testStarted ? Colors.green : Colors.blue,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: !_testStarted,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text('ID: ${widget.patientId}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Text(_formatTime(_secondsLeft), style: TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: _secondsLeft < 30 ? Colors.red : Colors.blue)),
                    const Text('Time Remaining', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Text('${_rawDistance.toStringAsFixed(1)} m', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                    const Text('Distance', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 24),
              if (!_testStarted)
                ElevatedButton(
                  onPressed: _startTest,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18)),
                  child: const Text('START 6-MINUTE TEST', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              if (_testStarted && !_testDone)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                    '🔒 Test running. Patient must walk full 6 minutes to complete test.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── GAIT VIDEO RECORDING SCREEN (MAX 6 MIN, WITH EARLY STOP) ───────────────

class GaitVideoScreen extends StatefulWidget {
  final String name, patientId, sex, referredBy, indication;
  final int age;
  final double height, weight;
  final double? startLat, startLng;

  const GaitVideoScreen({
    super.key,
    required this.name,
    required this.patientId,
    required this.age,
    required this.sex,
    required this.height,
    required this.weight,
    required this.referredBy,
    required this.indication,
    this.startLat,
    this.startLng,
  });

  @override
  State<GaitVideoScreen> createState() => _GaitVideoScreenState();
}

class _GaitVideoScreenState extends State<GaitVideoScreen> {
  CameraController? _cameraCtrl;
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isSaving = false;
  int _secondsRecorded = 0;
  static const int maxGaitVideoDuration = 360; // Max 6 Minutes Limit
  Timer? _videoTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initCamera();
  }

  @override
  void dispose() {
    _videoTimer?.cancel();
    _cameraCtrl?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initCamera() async {
    var cameraStatus = await Permission.camera.request();
    var micStatus = await Permission.microphone.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera & Microphone permissions are required.')),
        );
      }
      return;
    }

    if (_availableCameras.isEmpty) {
      try {
        _availableCameras = await availableCameras();
      } catch (_) {}
    }

    if (_availableCameras.isNotEmpty) {
      _cameraCtrl = CameraController(_availableCameras.first, ResolutionPreset.medium);
      await _cameraCtrl!.initialize();
    }

    if (mounted) setState(() => _isInitializing = false);
  }

  void _startRecording() async {
    if (_cameraCtrl == null || !_cameraCtrl!.value.isInitialized) return;

    try {
      await _cameraCtrl!.startVideoRecording();
      setState(() => _isRecording = true);

      _videoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _secondsRecorded++;
          if (_secondsRecorded >= maxGaitVideoDuration) {
            _stopRecording();
          }
        });
      });
    } catch (e) {
      debugPrint('Error starting video: $e');
    }
  }

  void _stopRecording() async {
    if (_cameraCtrl == null || !_isRecording || _isSaving) return;

    setState(() => _isSaving = true);
    _videoTimer?.cancel();

    try {
      XFile videoFile = await _cameraCtrl!.stopVideoRecording();

      final appDir = await getApplicationDocumentsDirectory();
      final cleanName = widget.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final cleanID = widget.patientId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final timeStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      
      // File naming convention: Gait_[PatientID]_[PatientName]_[Timestamp].mp4
      final String newPath = path.join(appDir.path, 'Gait_${cleanID}_${cleanName}_$timeStr.mp4');

      await File(videoFile.path).copy(newPath);

      final recordData = {
        'mode': 'Gait Video',
        'name': widget.name,
        'patient_id': widget.patientId,
        'age': widget.age,
        'sex': widget.sex,
        'height': widget.height,
        'weight': widget.weight,
        'referred_by': widget.referredBy,
        'indication': widget.indication,
        'date_time': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
        'start_latitude': widget.startLat,
        'start_longitude': widget.startLng,
        'raw_distance': 0.0,
        'corrected_distance': 0.0,
        'predicted': 0.0,
        'percent_predicted': 0.0,
        'avg_speed': 0.0,
        'avg_accuracy': 0.0,
        'gps_points': '[]',
        'video_path': newPath,
      };

      await DatabaseHelper.insertTest(recordData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video saved: Gait_${cleanID}_$cleanName.mp4')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        );
      }
    } catch (e) {
      debugPrint('Error stopping video: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_cameraCtrl == null || !_cameraCtrl!.value.isInitialized) {
      return const Scaffold(body: Center(child: Text('Camera Hardware Unavailable')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Gait Video (${widget.name})'),
        backgroundColor: _isRecording ? Colors.red : Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          CameraPreview(_cameraCtrl!),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'Patient: ${widget.name} (ID: ${widget.patientId})\nRec Time: ${_formatTime(_secondsRecorded)} (Max 06:00)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: _isSaving
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _isRecording
                    ? ElevatedButton.icon(
                        onPressed: _stopRecording,
                        icon: const Icon(Icons.stop, color: Colors.white),
                        label: const Text('STOP & SAVE VIDEO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                      )
                    : ElevatedButton.icon(
                        onPressed: _startRecording,
                        icon: const Icon(Icons.videocam, color: Colors.white),
                        label: const Text('START GAIT RECORDING', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
          )
        ],
      ),
    );
  }
}

// ─── RESULTS SCREEN ──────────────────────────────────────────────────────────

class ResultsScreen extends StatelessWidget {
  final Map<String, dynamic> testData;
  final double avgAccuracy;
  final double avgSpeed;

  const ResultsScreen({
    super.key,
    required this.testData,
    required this.avgAccuracy,
    required this.avgSpeed,
  });

  @override
  Widget build(BuildContext context) {
    final corrected = testData['corrected_distance'] as double;
    final predicted = testData['predicted'] as double;
    final percent = testData['percent_predicted'] as double;

    return Scaffold(
      appBar: AppBar(
        title: const Text('6MWT Test Results'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _card('Patient Name', testData['name'], Icons.person),
            _card('Start Lat/Long', '${testData['start_latitude'] ?? 'N/A'}, ${testData['start_longitude'] ?? 'N/A'}', Icons.map),
            _card('Corrected Distance', '${corrected.toStringAsFixed(1)} m', Icons.straighten),
            _card('Predicted Normal', '${predicted.toStringAsFixed(1)} m', Icons.trending_up),
            _card('% Predicted', '${percent.toStringAsFixed(1)}%', Icons.percent,
                color: percent < 70 ? Colors.red.shade50 : percent < 85 ? Colors.orange.shade50 : Colors.green.shade50),
            _card('Avg Speed', '${avgSpeed.toStringAsFixed(2)} km/h', Icons.speed),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const PatientIntakeScreen()),
                (route) => false,
              ),
              child: const Text('NEW ASSESSMENT'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String label, String value, IconData icon, {Color? color}) {
    return Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        subtitle: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─── HISTORY SCREEN ──────────────────────────────────────────────────────────

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _tests = [];

  Future<void> exportTestsToCSV() async {
    final List<Map<String, dynamic>> rows = await DatabaseHelper.getAllTests();
    if (rows.isEmpty) return;

    List<List<dynamic>> csvData = [
      [
        'Test ID', 'Mode', 'Patient Name', 'Patient ID', 'Age', 'Sex', 'Height (cm)', 
        'Weight (kg)', 'Referred By', 'Indication', 'Date Time', 'Start Lat', 'Start Lng',
        'Raw Distance (m)', 'Corrected Distance (m)', 'Predicted Normal (m)', 
        '% Predicted', 'Avg Speed (km/h)', 'Avg Accuracy (m)', 'Saved Video Path'
      ]
    ];

    for (var row in rows) {
      csvData.add([
        row['id'], row['mode'] ?? '6MWT', row['name'], row['patient_id'], row['age'], row['sex'],
        row['height'], row['weight'], row['referred_by'], row['indication'],
        row['date_time'], row['start_latitude'], row['start_longitude'],
        row['raw_distance'], row['corrected_distance'], row['predicted'], 
        row['percent_predicted'], row['avg_speed'], row['avg_accuracy'], row['video_path'] ?? 'N/A'
      ]);
    }

    String csvString = const ListToCsvConverter().convert(csvData);
    final directory = await getTemporaryDirectory();
    final String filePath = '${directory.path}/Clinical_Assessment_Data.csv';
    final File file = File(filePath);
    await file.writeAsString(csvString);

    await Share.shareXFiles([XFile(filePath)], text: 'Exported Clinical Patient Records & Gait Logs');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tests = await DatabaseHelper.getAllTests();
    setState(() => _tests = tests);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Past Records'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: exportTestsToCSV,
          ),
        ],
      ),
      body: _tests.isEmpty
          ? const Center(child: Text('No records logged yet.'))
          : ListView.builder(
              itemCount: _tests.length,
              itemBuilder: (_, i) {
                final t = _tests[i];
                final isVideo = (t['mode'] ?? '') == 'Gait Video';
                final pct = ((t['percent_predicted'] ?? 0.0) as double).toStringAsFixed(1);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isVideo ? Colors.purple : Colors.blue,
                      child: Icon(isVideo ? Icons.videocam : Icons.directions_walk, color: Colors.white),
                    ),
                    title: Text('${t['name']} (ID: ${t['patient_id']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      isVideo
                          ? 'Mode: Gait Video | Date: ${t['date_time']}\nSaved File: ${t['video_path'] != null ? path.basename(t['video_path']) : 'N/A'}'
                          : 'Mode: 6MWT | Date: ${t['date_time']}\nDist: ${(t['corrected_distance'] as double).toStringAsFixed(1)}m ($pct% predicted)',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}