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

  /// [MODIFIED] Generates and transmits a SAME alert using parameters from the UI.
  Future<void> transmitSameAlert({
    // Radio parameters
    required double frequencyMhz,
    required int txVgaGain,
    // SAME message parameters
    required String org,
    required String event,
    required String fips,
    required String purgeTime,
    required String issueTime,
    required String stationId,
    // Other parameters
    double sampleRateMhz = 2.0,
    Duration interval = const Duration(seconds: 30),
  }) async {
    if (_isTransmitting) return;
    _isTransmitting = true;

    _transmitter.sampleRate = sampleRateMhz * 1e6;
    _transmitter.freqDeviation = 5000; // SAME deviation is typically fixed at 5kHz

    await _transmitter.configure(frequencyMhz: frequencyMhz, txVgaGain: txVgaGain);

    final message = SameProtocol.buildMessage(
      org: org,
      event: event,
      fips: fips,
      purgeTime: purgeTime,
      issueTime: issueTime,
      stationId: stationId
    );
    final payload = SameProtocol.generatePayload(message: message, repeat: 3);
    final audio = SameProtocol.generateAfskAudio(data: payload, sampleRate: _transmitter.sampleRate);
    final iqData = _transmitter.modulateFm(audio).buffer.asUint8List();

    await _transmitter.startTx();

    while (_isTransmitting) {
      const chunkSize = 262144;
      for (int i = 0; i < iqData.length; i += chunkSize) {
        if (!_isTransmitting) break;
        final end = (i + chunkSize > iqData.length) ? iqData.length : i + chunkSize;
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

  /// [MODIFIED] Transmits a continuous test tone using parameters from the UI.
  Future<void> transmitTone({
    required double frequencyMhz,
    required int txVgaGain,
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
      final toneBuffer = _transmitter.generateToneBuffer(toneFreq, 0.1);
      await _transmitter.sendData(toneBuffer);
    }
    await _transmitter.stopTx();
  }

  void stop() {
    _isTransmitting = false;
  }
}