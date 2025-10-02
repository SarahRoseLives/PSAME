// lib/sdr/fm_transmitter.dart

import 'dart:math';
import 'dart:typed_data';
import 'package:hackrf_flutter/hackrf_flutter.dart';

/// Handles generic FM modulation and interfacing with the HackRF device.
class FmTransmitter {
  final HackrfFlutter _hackrf;

  // Transmission parameters
  double sampleRate;
  double freqDeviation;
  double carrierOffset;

  // State for continuous phase generation
  double _audioPhase = 0.0;
  double _fmPhase = 0.0;

  FmTransmitter(
    this._hackrf, {
    this.sampleRate = 2e6,
    this.freqDeviation = 2500,
    this.carrierOffset = 0,
  });

  /// FM modulates an audio signal into I/Q samples.
  Int8List modulateFm(Float32List audio) {
    final samples = Int8List(audio.length * 2);
    // Reset phase for each distinct modulation job
    double phase = 0.0;

    for (int i = 0; i < audio.length; i++) {
      final audioSample = audio[i];

      final instantaneousFreq = carrierOffset + (freqDeviation * audioSample);
      final phaseIncrement = 2.0 * pi * instantaneousFreq / sampleRate;
      phase += phaseIncrement;
      if (phase >= 2.0 * pi) phase -= 2.0 * pi;

      final iSample = (127.0 * cos(phase)).round().clamp(-128, 127);
      final qSample = (127.0 * sin(phase)).round().clamp(-128, 127);

      samples[i * 2] = iSample;
      samples[i * 2 + 1] = qSample;
    }
    return samples;
  }

  /// Generates a continuous tone buffer for testing purposes.
  /// Uses internal state to maintain phase continuity across calls.
  Uint8List generateToneBuffer(double toneFreq, double durationSeconds) {
    final bufferSamples = (sampleRate * durationSeconds).round();
    final buffer = Int8List(bufferSamples * 2);
    final audioPhaseIncr = 2.0 * pi * toneFreq / sampleRate;

    for (int i = 0; i < bufferSamples; i++) {
      final audioSample = sin(_audioPhase);
      _audioPhase += audioPhaseIncr;
      if (_audioPhase >= 2.0 * pi) _audioPhase -= 2.0 * pi;

      final instantaneousFreq = carrierOffset + (freqDeviation * audioSample);
      final phaseIncrement = 2.0 * pi * instantaneousFreq / sampleRate;
      _fmPhase += phaseIncrement;
      if (_fmPhase >= 2.0 * pi) _fmPhase -= 2.0 * pi;

      final iSample = (127.0 * cos(_fmPhase)).round().clamp(-128, 127);
      final qSample = (127.0 * sin(_fmPhase)).round().clamp(-128, 127);

      buffer[i * 2] = iSample;
      buffer[i * 2 + 1] = qSample;
    }
    return buffer.buffer.asUint8List();
  }

  // --- HackRF Control Methods ---

  Future<void> configure({
    required double frequencyMhz,
    required int txVgaGain,
  }) async {
    await _hackrf.setFrequency((frequencyMhz * 1e6).toInt());
    await _hackrf.setSampleRate(sampleRate.toInt());
    await _hackrf.setTxVgaGain(txVgaGain);
  }

  Future<void> startTx() async => _hackrf.startTx();
  Future<void> stopTx() async => _hackrf.stopTx();
  Future<void> sendData(Uint8List data) async => _hackrf.sendData(data);
}