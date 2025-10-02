// lib/services/transmitter_controller.dart

import 'dart:typed_data';
import 'package:hackrf_flutter/hackrf_flutter.dart';
import '../sdr/fm_transmitter.dart';
import '../sdr/same_protocol.dart';

/// Manages the state and coordinates the SDR components for transmission.
class FmTransmitterController {
  late final HackrfFlutter _hackrf;
  late final FmTransmitter _transmitter;
  bool _isTransmitting = false;

  Future<void> init() async {
    _hackrf = HackrfFlutter();
    await _hackrf.init();
    _transmitter = FmTransmitter(_hackrf);
  }

  /// Generates and transmits a SAME alert.
  Future<void> transmitSameAlert({
    double frequencyMhz = 162.550,
    int txVgaGain = 30,
    double sampleRateMhz = 2.0,
    double deviation = 5000,
    Duration interval = const Duration(seconds: 30),
  }) async {
    if (_isTransmitting) return;
    _isTransmitting = true;

    _transmitter.sampleRate = sampleRateMhz * 1e6;
    _transmitter.freqDeviation = deviation;

    await _transmitter.configure(frequencyMhz: frequencyMhz, txVgaGain: txVgaGain);

    // --- Orchestration Logic ---
    // 1. Build the SAME message string.
    final message = SameProtocol.buildMessage();
    // 2. Generate the full data payload (preamble + message).
    final payload = SameProtocol.generatePayload(message: message, repeat: 3);
    // 3. Encode the payload into AFSK audio.
    final audio = SameProtocol.generateAfskAudio(data: payload, sampleRate: _transmitter.sampleRate);
    // 4. Modulate the AFSK audio into FM I/Q samples.
    final iqData = _transmitter.modulateFm(audio).buffer.asUint8List();

    await _transmitter.startTx();

    while (_isTransmitting) {
      const chunkSize = 262144; // HackRF's preferred chunk size
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

  /// Transmits a continuous test tone.
  Future<void> transmitTone({
    double frequencyMhz = 162.550,
    int txVgaGain = 30,
    double sampleRateMhz = 2.0,
    double toneFreq = 1000,
    double deviation = 2000,
  }) async {
    if (_isTransmitting) return;
    _isTransmitting = true;

    _transmitter.sampleRate = sampleRateMhz * 1e6;
    _transmitter.freqDeviation = deviation;

    await _transmitter.configure(frequencyMhz: frequencyMhz, txVgaGain: txVgaGain);
    await _transmitter.startTx();

    while (_isTransmitting) {
      // The tone buffer maintains continuous phase internally
      final toneBuffer = _transmitter.generateToneBuffer(toneFreq, 0.1);
      await _transmitter.sendData(toneBuffer);
    }
    await _transmitter.stopTx();
  }

  void stop() {
    _isTransmitting = false;
  }
}