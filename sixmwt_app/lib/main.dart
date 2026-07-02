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

void main() {
  runApp(const SixMWTApp());
}

class SixMWTApp extends StatelessWidget {
  const SixMWTApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '6 Minute Walk Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PatientIntakeScreen(),
    );
  }
}

// ─── DATABASE ───────────────────────────────────────────────────────────────

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
    return openDatabase(fullPath, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE tests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          patient_id TEXT,
          age INTEGER,
          sex TEXT,
          height REAL,
          weight REAL,
          referred_by TEXT,
          indication TEXT,
          date_time TEXT,
          raw_distance REAL,
          corrected_distance REAL,
          predicted REAL,
          percent_predicted REAL,
          avg_speed REAL,
          avg_accuracy REAL,
          gps_points TEXT
        )
      ''');
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

  final List<String> _sexOptions = ['Male', 'Female', 'Other'];
  final List<String> _indicationOptions = [
    'Spine', 'Cardiac', 'Pulmonary', 'Geriatric', 'Other'
  ];

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

  void _startTest() {
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('6 Minute Walk Test'),
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
              const Text('Patient Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Patient Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idCtrl,
                decoration: const InputDecoration(
                  labelText: 'Patient ID *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Age (years) *',
                  border: OutlineInputBorder(),
                ),
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
                decoration: const InputDecoration(
                  labelText: 'Sex *',
                  border: OutlineInputBorder(),
                ),
                items: _sexOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _sex = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _heightCtrl,
                decoration: const InputDecoration(
                  labelText: 'Height (cm) *',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                decoration: const InputDecoration(
                  labelText: 'Weight (kg) *',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                decoration: const InputDecoration(
                  labelText: 'Referred By *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _indication,
                decoration: const InputDecoration(
                  labelText: 'Clinical Indication *',
                  border: OutlineInputBorder(),
                ),
                items: _indicationOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _indication = v!),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _startTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('START TEST',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen())),
                child: const Text('VIEW PAST TESTS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── TEST SCREEN ─────────────────────────────────────────────────────────────

class TestScreen extends StatefulWidget {
  final String name, patientId, sex, referredBy, indication;
  final int age;
  final double height, weight;

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
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  static const int testDuration = 360;

  int _secondsLeft = testDuration;
  double _rawDistance = 0;
  double _currentAccuracy = 0;
  bool _testStarted = false;
  bool _testDone = false;
  String _statusMessage = 'Checking GPS...';

  Timer? _countdownTimer;
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;
  final List<Position> _positions = [];
  final List<double> _accuracyReadings = [];

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
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'GPS is turned off. Please enable location services in your phone settings.');
      return;
    }

    var status = await Permission.location.status;
    if (status.isDenied) {
      status = await Permission.location.request();
    }

    if (status.isPermanentlyDenied) {
      setState(() => _statusMessage = 'Location permission permanently denied. Please enable it from Device Settings.');
      openAppSettings();
      return;
    }

    if (!status.isGranted) {
      setState(() => _statusMessage = 'Location permission denied. Cannot run test.');
      return;
    }

    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      setState(() {
        _currentAccuracy = pos.accuracy;
        if (pos.accuracy <= 15.0) {
          _statusMessage = 'GPS ready. Accuracy: ${pos.accuracy.toStringAsFixed(1)}m\nPress START when patient is ready.';
        } else {
          _statusMessage = 'Weak GPS signal (${pos.accuracy.toStringAsFixed(1)}m). Move to an open outdoor area for better accuracy.';
        }
      });
    } catch (e) {
      setState(() => _statusMessage = 'GPS processing error: $e');
    }
  }

  void _startTest() {
    setState(() {
      _testStarted = true;
      _statusMessage = 'Test running...';
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _stopTest();
        }
      });
    });

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 2,
      ),
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

  void _stopTest() {
    _countdownTimer?.cancel();
    _positionSub?.cancel();

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
        .map((p) => {
              'lat': p.latitude,
              'lng': p.longitude,
              'acc': p.accuracy,
              'ts': p.timestamp.toIso8601String(),
            })
        .toList());

    final testData = {
      'name': widget.name,
      'patient_id': widget.patientId,
      'age': widget.age,
      'sex': widget.sex,
      'height': widget.height,
      'weight': widget.weight,
      'referred_by': widget.referredBy,
      'indication': widget.indication,
      'date_time': DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      'raw_distance': _rawDistance,
      'corrected_distance': corrected,
      'predicted': predicted,
      'percent_predicted': percentPredicted,
      'avg_speed': avgSpeed,
      'avg_accuracy': avgAccuracy,
      'gps_points': gpsJson,
    };

    DatabaseHelper.insertTest(testData);

    setState(() => _testDone = true);

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

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('6MWT Running'),
        backgroundColor: _testStarted ? Colors.green : Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'ID: ${widget.patientId}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    _formatTime(_secondsLeft),
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: _secondsLeft < 30 ? Colors.red : Colors.blue,
                    ),
                  ),
                  const Text('Time Remaining', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${_rawDistance.toStringAsFixed(1)} m',
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                  ),
                  const Text('Distance', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'GPS Accuracy: ${_currentAccuracy.toStringAsFixed(1)}m',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _currentAccuracy > 15 ? Colors.orange : Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            if (!_testStarted)
              ElevatedButton(
                onPressed: (_statusMessage.contains('denied') || _statusMessage.contains('off')) ? null : _startTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_statusMessage.contains('denied') || _statusMessage.contains('off')) ? Colors.grey : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
                child: const Text('START TEST', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            if (_testStarted && !_testDone)
              ElevatedButton(
                onPressed: _stopTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
                child: const Text('STOP EARLY', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
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
    final slowWarning = avgSpeed < 2.0;
    final accuracyWarning = avgAccuracy > 10.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Results'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _resultCard('Patient', testData['name'], Icons.person),
            _resultCard('Date', testData['date_time'], Icons.calendar_today),
            _resultCard('Raw Distance', '${(testData['raw_distance'] as double).toStringAsFixed(1)} m', Icons.straighten),
            _resultCard('Corrected Distance', '${corrected.toStringAsFixed(1)} m', Icons.straighten),
            _resultCard('Predicted Normal', '${predicted.toStringAsFixed(1)} m', Icons.trending_up),
            _resultCard('% Predicted', '${percent.toStringAsFixed(1)}%', Icons.percent,
                color: percent < 70
                    ? Colors.red.shade50
                    : percent < 85
                        ? Colors.orange.shade50
                        : Colors.green.shade50),
            _resultCard('Avg Speed', '${avgSpeed.toStringAsFixed(2)} km/h', Icons.speed),
            _resultCard('Avg GPS Accuracy', '${avgAccuracy.toStringAsFixed(1)} m', Icons.gps_fixed),
            if (slowWarning)
              _warningCard('⚠️ Speed Warning', 'Average speed was below 2 km/h. GPS accuracy is reduced at slow speeds. Result may be underestimated.'),
            if (accuracyWarning)
              _warningCard('⚠️ GPS Warning', 'Average GPS accuracy was ${avgAccuracy.toStringAsFixed(1)}m. Results may be less reliable. Recommend open outdoor environment.'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const PatientIntakeScreen()),
                (route) => false,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('NEW TEST', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
              child: const Text('VIEW ALL TESTS'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(String label, String value, IconData icon, {Color? color}) {
    return Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        subtitle: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
      ),
    );
  }

  Widget _warningCard(String title, String message) {
    return Card(
      color: Colors.orange.shade50,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(fontSize: 13)),
          ],
        ),
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
        'Test ID', 'Patient Name', 'Patient ID', 'Age', 'Sex', 'Height (cm)', 
        'Weight (kg)', 'Referred By', 'Indication', 'Date Time', 
        'Raw Distance (m)', 'Corrected Distance (m)', 'Predicted Normal (m)', 
        '% Predicted', 'Avg Speed (km/h)', 'Avg Accuracy (m)'
      ]
    ];

    for (var row in rows) {
      csvData.add([
        row['id'], row['name'], row['patient_id'], row['age'], row['sex'],
        row['height'], row['weight'], row['referred_by'], row['indication'],
        row['date_time'], row['raw_distance'], row['corrected_distance'],
        row['predicted'], row['percent_predicted'], row['avg_speed'], row['avg_accuracy'],
      ]);
    }

    String csvString = ListToCsvConverter().convert(csvData);
    final directory = await getTemporaryDirectory();
    final String filePath = '${directory.path}/6MWT_Patient_Data.csv';
    final File file = File(filePath);
    await file.writeAsString(csvString);

    await Share.shareXFiles([XFile(filePath)], text: '6MWT Exported Patient Records');
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
        title: const Text('Past Tests'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export data to Excel/CSV',
            onPressed: () async {
              await exportTestsToCSV();
            },
          ),
        ],
      ),
      body: _tests.isEmpty
          ? const Center(child: Text('No tests recorded yet.'))
          : ListView.builder(
              itemCount: _tests.length,
              itemBuilder: (_, i) {
                final t = _tests[i];
                final pct = (t['percent_predicted'] as double).toStringAsFixed(1);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(t['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${t['date_time']} • ${t['indication']}\n'
                        'Distance: ${(t['corrected_distance'] as double).toStringAsFixed(1)}m • $pct% predicted'),
                    isThreeLine: true,
                    leading: CircleAvatar(
                      backgroundColor: double.parse(pct) < 70 ? Colors.red : Colors.green,
                      child: Text(
                        '$pct%',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}