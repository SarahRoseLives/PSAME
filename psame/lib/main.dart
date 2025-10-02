import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hackrf_flutter/hackrf_flutter.dart';

// Your existing FmTransmitter class (no changes needed here)
enum TransmitMode { same, tone }

class FmTransmitter {
  final HackrfFlutter _hackrf;

  // SAME Protocol Constants
  static const double baudRate = 520.833333333;
  static const double markFreq = 2083.333333333; // 4 * baudRate
  static const double spaceFreq = 1562.5; // 3 * baudRate
  static const int preambleByte = 0xAB;
  static const int preambleLength = 16;

  // Transmission parameters
  double sampleRate;
  double freqDeviation;
  double carrierOffset;
  TransmitMode mode;

  // State for continuous tone generation
  double _audioPhase = 0.0;
  double _fmPhase = 0.0;

  FmTransmitter(
    this._hackrf, {
    this.sampleRate = 2e6,
    this.freqDeviation = 2500,
    this.carrierOffset = 0,
    this.mode = TransmitMode.tone,
  });

  /// Build SAME message
  String buildSameMessage({
    String org = 'WXR',
    String event = 'RWT',
    String fips = '039007',
    String purgeTime = '0030',
    String issueTime = '2750700',
    String stationId = 'KCLE-NWR',
  }) {
    return 'ZCZC-$org-$event-$fips+$purgeTime-$issueTime-$stationId-';
  }

  /// Generate AFSK audio from data
  Float32List generateAfskAudio(Uint8List data) {
    final samplesPerBit = sampleRate / baudRate;
    final totalSamples = (data.length * 8 * samplesPerBit).ceil();
    final audio = Float32List(totalSamples);

    double phase = 0.0;
    final phaseIncrMark = 2.0 * pi * markFreq / sampleRate;
    final phaseIncrSpace = 2.0 * pi * spaceFreq / sampleRate;

    int bitCounter = -1;
    double currentPhaseIncr = 0.0;

    for (int i = 0; i < totalSamples; i++) {
      final currentBitInStream = (i / samplesPerBit).floor();

      if (bitCounter != currentBitInStream) {
        bitCounter = currentBitInStream;
        final byteCounter = bitCounter ~/ 8;
        final bitInByte = bitCounter % 8;

        if (byteCounter < data.length) {
          final currentByte = data[byteCounter];
          final currentBit = (currentByte >> bitInByte) & 1; // LSB-first

          currentPhaseIncr = (currentBit == 1) ? phaseIncrMark : phaseIncrSpace;
        }
      }

      audio[i] = sin(phase);
      phase += currentPhaseIncr;

      while (phase >= 2.0 * pi) {
        phase -= 2.0 * pi;
      }
      while (phase < 0) {
        phase += 2.0 * pi;
      }
    }

    return audio;
  }

  /// FM modulate audio signal
  Int8List modulateFm(Float32List audio) {
    final samples = Int8List(audio.length * 2);
    double phase = 0.0;

    for (int i = 0; i < audio.length; i++) {
      final audioSample = audio[i];

      // FM modulation: instantaneous frequency = carrier + deviation * audio
      final instantaneousFreq = carrierOffset + (freqDeviation * audioSample);
      final phaseIncrement = 2.0 * pi * instantaneousFreq / sampleRate;

      phase += phaseIncrement;

      while (phase >= 2.0 * pi) {
        phase -= 2.0 * pi;
      }
      while (phase < 0) {
        phase += 2.0 * pi;
      }

      // Generate I/Q samples
      final iSample = (127.0 * cos(phase)).round().clamp(-128, 127);
      final qSample = (127.0 * sin(phase)).round().clamp(-128, 127);

      samples[i * 2] = iSample;
      samples[i * 2 + 1] = qSample;
    }

    return samples;
  }

  /// Generate SAME message I/Q data
  Uint8List generateSameIq({
    required String org,
    required String event,
    required String fips,
    required String purgeTime,
    required String issueTime,
    required String stationId,
    int repeat = 3,
  }) {
    final message = buildSameMessage(
      org: org,
      event: event,
      fips: fips,
      purgeTime: purgeTime,
      issueTime: issueTime,
      stationId: stationId,
    );

    // Build payload: preamble + message, repeated
    final preamble = Uint8List(preambleLength)..fillRange(0, preambleLength, preambleByte);
    final messageBytes = Uint8List.fromList(message.codeUnits);

    final payload = <int>[];
    for (int i = 0; i < repeat; i++) {
      payload.addAll(preamble);
      payload.addAll(messageBytes);
    }

    final fullPayload = Uint8List.fromList(payload);

    // Generate AFSK audio
    final audio = generateAfskAudio(fullPayload);

    // FM modulate
    final iqData = modulateFm(audio);

    return iqData.buffer.asUint8List();
  }

  /// Generate a continuous tone buffer (for testing)
  Uint8List generateToneBuffer(double toneFreq, double durationSeconds) {
    final bufferSamples = (sampleRate * durationSeconds).round();
    final buffer = Int8List(bufferSamples * 2);

    final audioPhaseIncr = 2.0 * pi * toneFreq / sampleRate;

    for (int i = 0; i < bufferSamples; i++) {
      // Generate audio sample
      final audioSample = sin(_audioPhase);
      _audioPhase += audioPhaseIncr;
      if (_audioPhase >= 2.0 * pi) {
        _audioPhase -= 2.0 * pi;
      }

      // FM modulate
      final instantaneousFreq = carrierOffset + (freqDeviation * audioSample);
      final phaseIncrement = 2.0 * pi * instantaneousFreq / sampleRate;
      _fmPhase += phaseIncrement;

      if (_fmPhase >= 2.0 * pi) {
        _fmPhase -= 2.0 * pi;
      }
      if (_fmPhase < 0) {
        _fmPhase += 2.0 * pi;
      }

      // Generate I/Q samples
      final iSample = (127.0 * cos(_fmPhase)).round().clamp(-128, 127);
      final qSample = (127.0 * sin(_fmPhase)).round().clamp(-128, 127);

      buffer[i * 2] = iSample;
      buffer[i * 2 + 1] = qSample;
    }

    return buffer.buffer.asUint8List();
  }

  /// Configure HackRF for transmission
  Future<void> configure({
    required double frequencyMhz,
    required int txVgaGain,
  }) async {
    await _hackrf.setFrequency((frequencyMhz * 1e6).toInt());
    await _hackrf.setSampleRate(sampleRate.toInt());
    await _hackrf.setTxVgaGain(txVgaGain);
  }

  /// Start transmitting (call this before sending data)
  Future<void> startTx() async {
    await _hackrf.startTx();
  }

  /// Stop transmission
  Future<void> stopTx() async {
    await _hackrf.stopTx();
  }

  /// Send data buffer
  Future<void> sendData(Uint8List data) async {
    await _hackrf.sendData(data);
  }
}

// ---- MODIFIED CLASS ----
/// Example usage class
class FmTransmitterController {
  // Change 1: Declare _hackrf but do not initialize it here.
  // We use 'late' to promise Dart that it will be initialized before use.
  late final HackrfFlutter _hackrf;
  late final FmTransmitter _transmitter;
  bool _isTransmitting = false;

  // Change 2: Create an async init method for setup.
  Future<void> init() async {
    // Initialize the plugin and transmitter here, safely.
    _hackrf = HackrfFlutter();
    await _hackrf.init();
    _transmitter = FmTransmitter(_hackrf);
  }

  /// Transmit SAME alert
  Future<void> transmitSameAlert({
    double frequencyMhz = 162.550,
    int txVgaGain = 30,
    double sampleRateMhz = 2.0,
    double deviation = 5000,
    Duration interval = const Duration(seconds: 30),
  }) async {
    if (_isTransmitting) return; // Prevent multiple transmissions
    _isTransmitting = true;

    _transmitter.sampleRate = sampleRateMhz * 1e6;
    _transmitter.freqDeviation = deviation;
    _transmitter.mode = TransmitMode.same;

    await _transmitter.configure(
      frequencyMhz: frequencyMhz,
      txVgaGain: txVgaGain,
    );

    final iqData = _transmitter.generateSameIq(
      org: 'WXR',
      event: 'RWT',
      fips: '039007', // Ashtabula County, Ohio
      purgeTime: '0030',
      issueTime: '2750700', // Day 275, 07:00 UTC
      stationId: 'KCLE-NWR',
      repeat: 3,
    );

    await _transmitter.startTx();

    // Transmission loop
    while (_isTransmitting) {
      // Send burst
      const chunkSize = 262144;
      for (int i = 0; i < iqData.length; i += chunkSize) {
        if (!_isTransmitting) break;

        final end = (i + chunkSize < iqData.length) ? i + chunkSize : iqData.length;
        final chunk = iqData.sublist(i, end);

        if (chunk.length < chunkSize) {
          final padded = Uint8List(chunkSize)..setRange(0, chunk.length, chunk);
          await _transmitter.sendData(padded);
        } else {
          await _transmitter.sendData(chunk);
        }
      }

      if (!_isTransmitting) break;
      await Future.delayed(interval);
    }

    await _transmitter.stopTx();
  }

  /// Transmit continuous tone
  Future<void> transmitTone({
    double frequencyMhz = 162.550,
    int txVgaGain = 30,
    double sampleRateMhz = 2.0,
    double toneFreq = 1000,
    double deviation = 2000,
  }) async {
    if (_isTransmitting) return; // Prevent multiple transmissions
    _isTransmitting = true;

    _transmitter.sampleRate = sampleRateMhz * 1e6;
    _transmitter.freqDeviation = deviation;
    _transmitter.mode = TransmitMode.tone;

    await _transmitter.configure(
      frequencyMhz: frequencyMhz,
      txVgaGain: txVgaGain,
    );

    await _transmitter.startTx();

    final toneBuffer = _transmitter.generateToneBuffer(toneFreq, 0.1);

    while (_isTransmitting) {
      await _transmitter.sendData(toneBuffer);
    }

    await _transmitter.stopTx();
  }

  void stop() {
    _isTransmitting = false;
  }
}


// ---- NEW CODE: main() and UI ----

Future<void> main() async {
  // This line is CRUCIAL. It ensures the Flutter binding is initialized
  // before any platform channel calls are made.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HackRF FM Transmitter',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const TransmitterPage(),
    );
  }
}

class TransmitterPage extends StatefulWidget {
  const TransmitterPage({super.key});

  @override
  State<TransmitterPage> createState() => _TransmitterPageState();
}

class _TransmitterPageState extends State<TransmitterPage> {
  final FmTransmitterController _controller = FmTransmitterController();
  bool _isInitialized = false;
  bool _isTransmitting = false;
  String _status = "Not Initialized";

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _status = "Initializing...";
      });
      await _controller.init();
      setState(() {
        _isInitialized = true;
        _status = "Ready. Plug in HackRF.";
      });
    } catch (e) {
      setState(() {
        _status = "Error initializing: $e";
      });
    }
  }

  void _startSame() {
    if (!_isInitialized || _isTransmitting) return;
    setState(() {
      _isTransmitting = true;
      _status = "Transmitting SAME Alert...";
    });
    // We don't await this call so the UI remains responsive
    _controller.transmitSameAlert().catchError((e) {
      if(mounted) {
        setState(() {
          _status = "Error: $e";
          _isTransmitting = false;
        });
      }
    });
  }

  void _startTone() {
    if (!_isInitialized || _isTransmitting) return;
    setState(() {
      _isTransmitting = true;
      _status = "Transmitting 1kHz Tone...";
    });
    // We don't await this call so the UI remains responsive
    _controller.transmitTone().catchError((e) {
      if(mounted) {
        setState(() {
          _status = "Error: $e";
          _isTransmitting = false;
        });
      }
    });
  }

  void _stop() {
    if (!_isTransmitting) return;
    _controller.stop();
    setState(() {
      _isTransmitting = false;
      _status = "Stopped. Ready to transmit.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HackRF Transmitter'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Status: $_status',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_isInitialized && !_isTransmitting) ? _startSame : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                child: const Text('Transmit SAME Alert (RWT)'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: (_isInitialized && !_isTransmitting) ? _startTone : null,
                child: const Text('Transmit 1kHz Test Tone'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isTransmitting ? _stop : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Stop Transmitting'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}