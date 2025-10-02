// lib/ui/transmitter_page.dart

import 'package:flutter/material.dart';
import '../services/transmitter_controller.dart';

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
      setState(() => _status = "Initializing...");
      await _controller.init();
      setState(() {
        _isInitialized = true;
        _status = "Ready. Plug in HackRF.";
      });
    } catch (e) {
      setState(() => _status = "Error initializing: $e");
    }
  }

  void _startSame() {
    if (!_isInitialized || _isTransmitting) return;
    setState(() {
      _isTransmitting = true;
      _status = "Transmitting SAME Alert...";
    });
    _controller.transmitSameAlert().catchError(_handleError);
  }

  void _startTone() {
    if (!_isInitialized || _isTransmitting) return;
    setState(() {
      _isTransmitting = true;
      _status = "Transmitting 1kHz Tone...";
    });
    _controller.transmitTone().catchError(_handleError);
  }

  void _stop() {
    if (!_isTransmitting) return;
    _controller.stop();
    setState(() {
      _isTransmitting = false;
      _status = "Stopped. Ready to transmit.";
    });
  }

  void _handleError(Object e) {
    if (mounted) {
      setState(() {
        _status = "Error: $e";
        _isTransmitting = false;
      });
    }
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