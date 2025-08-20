import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';

void main() => runApp(const SAMETransmitterApp());

class SAMETransmitterApp extends StatelessWidget {
  const SAMETransmitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAME Transmitter',
      home: Scaffold(
        appBar: AppBar(title: const Text('SAME Transmitter')),
        body: const Center(child: TransmitButton()),
      ),
    );
  }
}

class TransmitButton extends StatefulWidget {
  const TransmitButton({super.key});

  @override
  State<TransmitButton> createState() => _TransmitButtonState();
}

class _TransmitButtonState extends State<TransmitButton> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.openPlayer();
  }

  @override
  void dispose() {
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _transmit() async {
    if (_isPlaying) return;
    setState(() => _isPlaying = true);

    // Generate SAME message audio
    final Uint8List wavBytes = await SAMEMessageGenerator.generateSAMEWav();

    // Play through phone speaker
    await _player.startPlayer(
      fromDataBuffer: wavBytes,
      codec: Codec.pcm16WAV,
      whenFinished: () => setState(() => _isPlaying = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isPlaying ? null : _transmit,
      child: Text(_isPlaying ? 'Transmitting...' : 'Transmit SAME Message'),
    );
  }
}

class SAMEMessageGenerator {
  // ========== SAME Parameters ==========
  // Mark = 2083.33 Hz, Space = 1562.5 Hz, bit duration = 1.92 ms, 8 bits/byte, 520.83 bps
  static const double sampleRate = 44100.0;
  static const double bitDuration = 0.00192;
  static const double markFreq = 2083.33;
  static const double spaceFreq = 1562.5;
  static const int preambleByte = 0xAB;
  static const int preambleRepeat = 16;

  // Header fields for test message
  static String get _header =>
      'ZCZC-EAS-RWT-012057-012081-012101-012103-012115+0030-2780415-WTSP/TV-';

  static String get _eom => 'NNNN';

  // Text message content
  static String get _voiceMessage =>
      'An EAS Participant has issued a Required Weekly Test for the following counties/areas: Hillsborough FL, Manatee FL, Pasco FL, Pinellas FL, and Sarasota FL at 12:15 am EDT on October 5 effective until 12:45 am EDT. Message from WTSP-TV.';

  // ========== Public API ==========
  static Future<Uint8List> generateSAMEWav() async {
    // Compose the full message sequence:
    // [header x3] [1 sec silence] [attention signal] [1 sec silence]
    // [voice message (TTS)] [1 sec silence] [EOM x3]
    List<_AudioChunk> chunks = [];

    // Header x3
    for (int i = 0; i < 3; ++i) {
      chunks.add(_AudioChunk(await _generateSAMEBurst(_header), 1.0));
      chunks.add(_AudioChunk(_silence(1.0), 1.0));
    }

    // Attention: 853 Hz + 960 Hz combined for 8 sec (broadcast style)
    chunks.add(_AudioChunk(_dualTone([853.0, 960.0], 8.0), 8.0));
    chunks.add(_AudioChunk(_silence(1.0), 1.0));

    // Message (TTS is not available in Dart, so use 1050Hz for 5 sec as placeholder)
    chunks.add(_AudioChunk(_singleTone(1050.0, 5.0), 5.0));
    chunks.add(_AudioChunk(_silence(1.0), 1.0));

    // EOM x3
    for (int i = 0; i < 3; ++i) {
      chunks.add(_AudioChunk(await _generateSAMEBurst(_eom), 1.0));
      chunks.add(_AudioChunk(_silence(1.0), 1.0));
    }

    // Concatenate all PCM samples
    List<int> pcm = [];
    for (var chunk in chunks) {
      pcm.addAll(chunk.samples);
    }
    // Compose WAV file
    return _encodeWAV(Int16List.fromList(pcm), sampleRate.toInt());
  }

  // ========== Core ==========

  // Generate SAME burst for a string (header or EOM)
  static Future<List<int>> _generateSAMEBurst(String data) async {
    // Format: 16x preamble bytes + ASCII bytes, each byte 8 bits LSB first, mark = 2083.33 Hz, space = 1562.5 Hz
    List<int> bits = [];

    // Preamble
    for (int i = 0; i < preambleRepeat; ++i) {
      bits.addAll(_byteToBits(preambleByte));
    }
    // Data
    for (int i = 0; i < data.length; ++i) {
      bits.addAll(_byteToBits(data.codeUnitAt(i) & 0x7F)); // ASCII, MSB zero
    }

    // Convert bits to PCM
    List<int> pcm = [];
    for (int b in bits) {
      double freq = b == 1 ? markFreq : spaceFreq;
      pcm.addAll(_sineWave(freq, bitDuration, sampleRate));
    }
    return pcm;
  }

  // Convert a byte to bits (LSB first)
  static List<int> _byteToBits(int byte) {
    List<int> bits = [];
    for (int i = 0; i < 8; ++i) {
      bits.add((byte >> i) & 1);
    }
    return bits;
  }

  // Generate silence (PCM)
  static List<int> _silence(double durationSec) {
    int samples = (sampleRate * durationSec).round();
    return List<int>.filled(samples, 0);
  }

  // Dual-tone for EAS attention
  static List<int> _dualTone(List<double> freqs, double durationSec) {
    int samples = (sampleRate * durationSec).round();
    List<int> pcm = [];
    for (int i = 0; i < samples; ++i) {
      double t = i / sampleRate;
      double val = 0.0;
      for (double f in freqs) {
        val += sin(2 * pi * f * t);
      }
      val = (val / freqs.length) * 0.6; // scale
      pcm.add((val * 32767).toInt());
    }
    return pcm;
  }

  // Single tone (1050 Hz for placeholder message)
  static List<int> _singleTone(double freq, double durationSec) {
    int samples = (sampleRate * durationSec).round();
    List<int> pcm = [];
    for (int i = 0; i < samples; ++i) {
      double t = i / sampleRate;
      double val = sin(2 * pi * freq * t) * 0.6;
      pcm.add((val * 32767).toInt());
    }
    return pcm;
  }

  // Sine wave for bit
  static List<int> _sineWave(double freq, double durationSec, double rate) {
    int samples = (rate * durationSec).round();
    List<int> pcm = [];
    for (int i = 0; i < samples; ++i) {
      double t = i / rate;
      double val = sin(2 * pi * freq * t) * 0.35;
      pcm.add((val * 32767).toInt());
    }
    return pcm;
  }

  // WAV encoding
  static Uint8List _encodeWAV(Int16List pcm, int sampleRate) {
    int byteRate = sampleRate * 2;
    int blockAlign = 2;
    int subchunk2Size = pcm.length * 2;
    int chunkSize = 36 + subchunk2Size;
    ByteData header = ByteData(44);

    header.setUint8(0, 0x52); // "RIFF"
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57); // "WAVE"
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66); // "fmt "
    header.setUint8(13, 0x6d);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little); // PCM chunk size
    header.setUint16(20, 1, Endian.little); // Audio format (PCM)
    header.setUint16(22, 1, Endian.little); // Num channels
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, 16, Endian.little); // Bits per sample
    header.setUint8(36, 0x64); // "data"
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, subchunk2Size, Endian.little);

    Uint8List wav = Uint8List(44 + subchunk2Size);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + subchunk2Size, pcm.buffer.asUint8List());
    return wav;
  }
}

// Helper to track chunks
class _AudioChunk {
  final List<int> samples;
  final double durationSec;
  _AudioChunk(this.samples, this.durationSec);
}