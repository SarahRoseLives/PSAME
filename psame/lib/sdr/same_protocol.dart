// lib/sdr/same_protocol.dart

import 'dart:math';
import 'dart:typed_data';

/// Handles the logic for generating SAME protocol messages and AFSK audio.
class SameProtocol {
  // SAME Protocol Constants
  static const double baudRate = 520.833333333;
  static const double markFreq = 2083.333333333; // 4 * baudRate
  static const double spaceFreq = 1562.5; // 3 * baudRate
  static const int preambleByte = 0xAB;
  static const int preambleLength = 16;
  static const int endOfMessageLength = 3;

  /// Builds the full SAME message string.
  static String buildMessage({
    String org = 'WXR',
    String event = 'RWT',
    String fips = '039007', // Ashtabula County, OH (where Jefferson is)
    String purgeTime = '0030',
    String issueTime = '2750800', // Day 275 (Oct 2), 08:00 UTC
    String stationId = 'KCLE-NWR',
  }) {
    return 'ZCZC-$org-$event-$fips+$purgeTime-$issueTime-$stationId-';
  }

  /// Creates the full data payload including preamble and repeated messages.
  static Uint8List generatePayload({
    required String message,
    int repeat = 3,
  }) {
    final preamble = Uint8List(preambleLength)..fillRange(0, preambleLength, preambleByte);
    final messageBytes = Uint8List.fromList(message.codeUnits);
    // The EOM (End of Message) is just three NUL bytes after the main message
    final eom = Uint8List(endOfMessageLength);

    final payload = <int>[];
    for (int i = 0; i < repeat; i++) {
      payload.addAll(preamble);
      payload.addAll(messageBytes);
      if (i < (repeat -1)) { // Add EOM between messages
          payload.addAll(eom);
      }
    }

    return Uint8List.fromList(payload);
  }

  /// Generates AFSK audio from a data payload.
  /// This translates the 1s and 0s of the data into sine waves of different frequencies.
  static Float32List generateAfskAudio({
    required Uint8List data,
    required double sampleRate,
  }) {
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
      if (phase >= 2.0 * pi) phase -= 2.0 * pi;
    }
    return audio;
  }
}