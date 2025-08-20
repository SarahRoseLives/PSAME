import 'dart:async';
import 'dart:typed_data';
import '../models/aprs_packet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'protocol/protocol.dart';
import 'dart:convert';

import 'audio_controller.dart';

class RadioController extends ChangeNotifier {
  final BluetoothDevice device;
  BluetoothConnection? _commandConnection;

  AudioController? _audioController;

  final StreamController<Message> _messageStreamController = StreamController<
      Message>.broadcast();
  StreamSubscription? _btStreamSubscription;
  Uint8List _rxBuffer = Uint8List(0);

  // Buffer for reassembling fragmented APRS packets
  final BytesBuilder _aprsReassemblyBuffer = BytesBuilder();

  // --- State Properties ---
  DeviceInfo? deviceInfo;
  StatusExt? status;
  Settings? settings;
  Position? gps;
  Channel? currentChannel;
  Channel? channelA;
  Channel? channelB;
  double? batteryVoltage;
  int? batteryLevelAsPercentage;

  List<AprsPacket> aprsPackets = [];
  AprsPacket? latestAprsPacket;

  bool get isReady =>
      deviceInfo != null && status != null && settings != null &&
          channelA != null && channelB != null;

  bool get isPowerOn => status?.isPowerOn ?? true;

  bool get isInTx => status?.isInTx ?? false;

  bool get isInRx => status?.isInRx ?? false;

  double get rssi => status?.rssi ?? 0.0;

  bool get isSq => status?.isSq ?? false;

  bool get isScan => status?.isScan ?? false;

  int get currentChannelId => status?.currentChannelId ?? 0;

  String get currentChannelName => currentChannel?.name ?? 'Loading...';

  double get currentRxFreq => currentChannel?.rxFreq ?? 0.0;

  bool get isGpsLocked => status?.isGpsLocked ?? false;

  bool get supportsVfo => deviceInfo?.supportsVfo ?? false;

  bool isAudioMonitoring = false;
  bool isVfoScanning = false;
  double _vfoScanStartFreq = 0.0;
  double _vfoScanEndFreq = 0.0;
  num _vfoScanStepKhz = 25;
  double currentVfoFrequencyMhz = 0.0;
  Timer? _vfoScanTimer;

  RadioController({required this.device});

  Future<void> connect() async {
    if (_commandConnection?.isConnected ?? false) return;
    _commandConnection = await BluetoothConnection.toAddress(device.address);
    _btStreamSubscription = _commandConnection!.input!.listen(_onDataReceived);

    _initializeRadioState();

    _audioController =
        AudioController(deviceAddress: device.address, rfcommChannel: 4);
    notifyListeners();
  }

  void _onDataReceived(Uint8List data) {
    if (kDebugMode) {
      print("RAW RX: $data");
    }
    _rxBuffer = Uint8List.fromList([..._rxBuffer, ...data]);
    while (true) {
      final result = _parseGaiaFrameFromBuffer();
      if (result == null) break;

      _rxBuffer = result.remainingBuffer;
      try {
        final message = Message.fromBytes(result.frame.messageBytes);

        if (message.command == BasicCommand.EVENT_NOTIFICATION &&
            message.body is EventNotificationBody) {
          _handleEvent(message.body as EventNotificationBody);
        } else {
          _messageStreamController.add(message);
        }
      } catch (e, s) {
        if (kDebugMode) {
          print('Error parsing message: $e');
          print('Stack trace: $s');
        }
      }
    }
  }

  void _handleEvent(EventNotificationBody eventBody) async {
    bool dataChanged = false;
    switch (eventBody.eventType) {
      case EventType.HT_STATUS_CHANGED:
        final statusReply = eventBody.event as GetHtStatusReplyBody;
        if (statusReply.status != null) {
          status = statusReply.status;
          dataChanged = true;
        }
        break;
      case EventType.HT_SETTINGS_CHANGED:
        final settingsReply = eventBody.event as ReadSettingsReplyBody;
        if (settingsReply.settings != null) {
          settings = settingsReply.settings;
          await _updateVfoChannels();
          dataChanged = true;
        }
        break;
      case EventType.HT_CH_CHANGED:
        final channelReply = eventBody.event as ReadRFChReplyBody;
        if (channelReply.rfCh != null) {
          final updatedChannel = channelReply.rfCh!;
          if (status?.currentChannelId == updatedChannel.channelId) {
            currentChannel = updatedChannel;
          }
          if (updatedChannel.channelId == settings?.channelA) {
            channelA = updatedChannel;
          }
          if (updatedChannel.channelId == settings?.channelB) {
            channelB = updatedChannel;
          }
          dataChanged = true;
        }
        break;
      case EventType.DATA_RXD:
        final dataRxdBody = eventBody.event as DataRxdEventBody;
        final fragment = dataRxdBody.tncDataFragment;

        _aprsReassemblyBuffer.add(fragment.data);

        if (fragment.isFinalFragment) {
          final fullPacketBytes = _aprsReassemblyBuffer.toBytes();
          _aprsReassemblyBuffer.clear();

          try {
            // --- FIX: Removed ascii.decode from this debug line to prevent crashes ---
            if (kDebugMode) {
              print("PARSING APRS PACKET (bytes): $fullPacketBytes");
            }

            final newPacket = AprsPacket.fromAX25Frame(fullPacketBytes);

            if (newPacket != null) {
              latestAprsPacket = newPacket;

              if (newPacket.latitude != null && newPacket.longitude != null) {
                final existingIndex = aprsPackets.indexWhere((p) =>
                p.source == newPacket.source);

                if (existingIndex != -1) {
                  aprsPackets[existingIndex] = newPacket;
                } else {
                  aprsPackets.add(newPacket);
                }

                if (aprsPackets.length > 100) {
                  aprsPackets.removeAt(0);
                }
              }
              dataChanged = true;
            }
          } catch (e) {
            if (kDebugMode) {
              print("Could not decode or parse reassembled APRS packet: $e");
            }
          }
        }
        break;
      default:
        if (kDebugMode) print("Unhandled Event: ${eventBody.eventType}");
    }
    if (dataChanged) {
      notifyListeners();
    }
  }

  Future<void> _initializeRadioState() async {
    try {
      await _registerForEvents();

      final results = await Future.wait([
        getDeviceInfo(),
        getStatus(),
        getSettings(),
        getBatteryPercentage(),
        getBatteryVoltage(),
        getPosition(),
      ]);

      deviceInfo = results[0] as DeviceInfo?;
      status = results[1] as StatusExt?;
      settings = results[2] as Settings?;
      batteryLevelAsPercentage = (results[3] as num?)?.toInt();
      batteryVoltage = (results[4] as num?)?.toDouble();
      gps = results[5] as Position?;

      if (status != null) {
        currentChannel = await getChannel(status!.currentChannelId);
      }

      if (settings != null) {
        await _updateVfoChannels();
      }
    } catch (e) {
      if (kDebugMode) print('Error initializing radio state: $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> _updateVfoChannels() async {
    if (settings == null) return;
    try {
      final results = await Future.wait([
        getChannel(settings!.channelA),
        getChannel(settings!.channelB),
      ]);
      channelA = results[0];
      channelB = results[1];
    } catch (e) {
      if (kDebugMode) print("Error updating VFO channels: $e");
      channelA = null;
      channelB = null;
    } finally {
      notifyListeners();
    }
  }

  GaiaParseResult? _parseGaiaFrameFromBuffer() {
    int frameStart = _rxBuffer.indexOf(GaiaFrame.startByte);
    if (frameStart == -1) {
      _rxBuffer = Uint8List(0);
      return null;
    }
    if (frameStart > 0) _rxBuffer = _rxBuffer.sublist(frameStart);
    if (_rxBuffer.length < 4) return null;
    if (_rxBuffer[1] != GaiaFrame.version) {
      _rxBuffer = _rxBuffer.sublist(1);
      return _parseGaiaFrameFromBuffer();
    }
    final messagePayloadLength = _rxBuffer[3];
    final fullMessageLength = messagePayloadLength + 4;
    final fullFrameLength = 4 + fullMessageLength;
    if (_rxBuffer.length < fullFrameLength) return null;

    final messageBytes = _rxBuffer.sublist(4, fullFrameLength);
    final frame = GaiaFrame(flags: _rxBuffer[2], messageBytes: messageBytes);
    final remainingBuffer = _rxBuffer.sublist(fullFrameLength);

    return GaiaParseResult(frame, remainingBuffer);
  }

  Future<void> _sendCommand(Message command) async {
    final messageBytes = command.toBytes();
    final gaiaFrame = GaiaFrame(messageBytes: messageBytes);
    final bytes = gaiaFrame.toBytes();
    if (kDebugMode) {
      print("RAW TX: $bytes");
    }
    _commandConnection?.output.add(bytes);
    await _commandConnection?.output.allSent;
  }

  Future<T> _sendCommandExpectReply<T extends ReplyBody>({
    required Message command,
    required BasicCommand replyCommand,
    bool Function(T body)? validator,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<T>();
    late StreamSubscription streamSub;

    streamSub = _messageStreamController.stream.listen((message) {
      if (message.command == replyCommand && message.isReply) {
        final body = message.body as T;

        if (validator != null && !validator(body)) {
          return;
        }

        if (!completer.isCompleted) {
          if (body.replyStatus != ReplyStatus.SUCCESS) {
            completer.completeError(
                Exception("Command failed with status: ${body.replyStatus}"));
          } else {
            completer.complete(body);
          }
          streamSub.cancel();
        }
      }
    });

    await _sendCommand(command);

    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(
            'Radio did not reply in time for ${command.command}.'));
        streamSub.cancel();
      }
    });

    return completer.future;
  }


  Future<void> _registerForEvents() async {
    final eventsToRegister = [
      EventType.HT_STATUS_CHANGED,
      EventType.HT_SETTINGS_CHANGED,
      EventType.HT_CH_CHANGED,
      EventType.DATA_RXD,
    ];
    for (var eventType in eventsToRegister) {
      final command = Message(
          commandGroup: CommandGroup.BASIC,
          command: BasicCommand.REGISTER_NOTIFICATION,
          isReply: false,
          body: RegisterNotificationBody(eventType: eventType)
      );
      await _sendCommand(command);
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> setVfoFrequency(double frequencyMhz) async {
    const vfoScanChannelId = 252;
    final Channel vfoChannel;
    try {
      vfoChannel = await getChannel(vfoScanChannelId);
    } catch (e) {
      if (kDebugMode) print(
          "Could not read VFO channel $vfoScanChannelId to update it: $e");
      return;
    }

    final updatedVfoChannel = vfoChannel.copyWith(
      rxFreq: frequencyMhz,
      txFreq: frequencyMhz,
    );

    await writeChannel(updatedVfoChannel);

    currentVfoFrequencyMhz = frequencyMhz;
    notifyListeners();
  }

  Future<void> startVfoScan(
      {required double startFreqMhz, required double endFreqMhz, required num stepKhz}) async {
    if (isVfoScanning) return;
    const vfoScanChannelId = 252;

    if (settings == null) await getSettings();
    if (settings == null) return;

    final newSettings = settings!.copyWith(vfoX: 1, channelA: vfoScanChannelId);
    await writeSettings(newSettings);
    await Future.delayed(const Duration(milliseconds: 100));

    isVfoScanning = true;
    _vfoScanStartFreq = startFreqMhz;
    _vfoScanEndFreq = endFreqMhz;
    _vfoScanStepKhz = stepKhz;
    currentVfoFrequencyMhz = startFreqMhz;

    await setVfoFrequency(currentVfoFrequencyMhz);

    _vfoScanTimer?.cancel();
    _vfoScanTimer =
        Timer.periodic(const Duration(milliseconds: 250), (timer) async {
          if (!isVfoScanning || (status?.isSq ?? false)) {
            return;
          }

          currentVfoFrequencyMhz += (_vfoScanStepKhz / 1000.0);
          if (currentVfoFrequencyMhz > _vfoScanEndFreq) {
            currentVfoFrequencyMhz = _vfoScanStartFreq;
          }

          await setVfoFrequency(currentVfoFrequencyMhz);
        });

    notifyListeners();
  }

  void stopVfoScan() {
    isVfoScanning = false;
    _vfoScanTimer?.cancel();
    _vfoScanTimer = null;
    notifyListeners();
  }

  Future<void> writeChannel(Channel channel) async {
    final reply = await _sendCommandExpectReply<WriteRFChReplyBody>(
      command: Message(
          commandGroup: CommandGroup.BASIC,
          command: BasicCommand.WRITE_RF_CH,
          isReply: false,
          body: WriteRFChBody(rfCh: channel)
      ),
      replyCommand: BasicCommand.WRITE_RF_CH,
      timeout: const Duration(seconds: 3),
    );
    if (kDebugMode) {
      print('Successfully wrote channel ${reply.channelId}');
    }
  }

  Future<void> writeSettings(Settings newSettings) async {
    final reply = await _sendCommandExpectReply<WriteSettingsReplyBody>(
      command: Message(
        commandGroup: CommandGroup.BASIC,
        command: BasicCommand.WRITE_SETTINGS,
        isReply: false,
        body: WriteSettingsBody(settings: newSettings),
      ),
      replyCommand: BasicCommand.WRITE_SETTINGS,
    );

    if (reply.replyStatus == ReplyStatus.SUCCESS) {
      if (kDebugMode) print("Successfully sent WRITE_SETTINGS.");
      // Update local state and notify listeners.
      // The caller is responsible for polling getStatus() if it needs to confirm a state change.
      settings = newSettings;
      await _updateVfoChannels();
      notifyListeners();
    } else {
      throw Exception(
          "Failed to write settings. Radio replied with status: ${reply
              .replyStatus}");
    }
  }


  Future<DeviceInfo?> getDeviceInfo() async {
    final reply = await _sendCommandExpectReply<GetDevInfoReplyBody>(
      command: Message(commandGroup: CommandGroup.BASIC,
          command: BasicCommand.GET_DEV_INFO,
          isReply: false,
          body: GetDevInfoBody()),
      replyCommand: BasicCommand.GET_DEV_INFO,
    );
    deviceInfo = reply.devInfo;
    notifyListeners();
    return reply.devInfo;
  }

  Future<Settings?> getSettings() async {
    final reply = await _sendCommandExpectReply<ReadSettingsReplyBody>(
      command: Message(commandGroup: CommandGroup.BASIC,
          command: BasicCommand.READ_SETTINGS,
          isReply: false,
          body: ReadSettingsBody()),
      replyCommand: BasicCommand.READ_SETTINGS,
    );
    settings = reply.settings;
    notifyListeners();
    return reply.settings;
  }

  Future<StatusExt?> getStatus() async {
    final reply = await _sendCommandExpectReply<GetHtStatusReplyBody>(
      command: Message(commandGroup: CommandGroup.BASIC,
          command: BasicCommand.GET_HT_STATUS,
          isReply: false,
          body: GetHtStatusBody()),
      replyCommand: BasicCommand.GET_HT_STATUS,
    );
    status = reply.status;
    notifyListeners();
    return reply.status;
  }

  Future<num?> getBatteryVoltage() async {
    final reply = await _sendCommandExpectReply<ReadPowerStatusReplyBody>(
      command: Message(commandGroup: CommandGroup.BASIC,
          command: BasicCommand.READ_STATUS,
          isReply: false,
          body: ReadPowerStatusBody(
              statusType: PowerStatusType.BATTERY_VOLTAGE)),
      replyCommand: BasicCommand.READ_STATUS,
    );
    batteryVoltage = reply.value?.toDouble();
    notifyListeners();
    return reply.value;
  }

  Future<num?> getBatteryPercentage() async {
    final reply = await _sendCommandExpectReply<ReadPowerStatusReplyBody>(
      command: Message(commandGroup: CommandGroup.BASIC,
          command: BasicCommand.READ_STATUS,
          isReply: false,
          body: ReadPowerStatusBody(
              statusType: PowerStatusType.BATTERY_LEVEL_AS_PERCENTAGE)),
      replyCommand: BasicCommand.READ_STATUS,
    );
    batteryLevelAsPercentage = reply.value?.toInt();
    notifyListeners();
    return reply.value;
  }

  Future<Position?> getPosition() async {
    try {
      final reply = await _sendCommandExpectReply<GetPositionReplyBody>(
        command: Message(commandGroup: CommandGroup.BASIC,
            command: BasicCommand.GET_POSITION,
            isReply: false,
            body: GetPositionBody()),
        replyCommand: BasicCommand.GET_POSITION,
      );
      gps = reply.position;
      notifyListeners();
      return reply.position;
    } catch (e) {
      if (kDebugMode) print("Could not get position: $e");
      return null;
    }
  }

  Future<Channel> getChannel(int channelId) async {
    final reply = await _sendCommandExpectReply<ReadRFChReplyBody>(
      command: Message(commandGroup: CommandGroup.BASIC,
          command: BasicCommand.READ_RF_CH,
          isReply: false,
          body: ReadRFChBody(channelId: channelId)),
      replyCommand: BasicCommand.READ_RF_CH,
      validator: (body) => body.rfCh?.channelId == channelId,
    );
    if (reply.rfCh == null) throw Exception(
        'Failed to get channel $channelId.');
    if (status?.currentChannelId == channelId) {
      currentChannel = reply.rfCh;
      notifyListeners();
    }
    return reply.rfCh!;
  }

  Future<List<Channel>> getAllChannels() async {
    if (deviceInfo == null) await getDeviceInfo();
    if (deviceInfo == null) return [];

    final channels = <Channel>[];
    for (int i = 0; i < (deviceInfo?.channelCount ?? 0); i++) {
      try {
        final channel = await getChannel(i);
        channels.add(channel);
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        if (kDebugMode) print('Failed to get channel $i: $e');
      }
    }
    return channels;
  }

  Future<void> setRadioScan(bool enable) async {
    if (settings == null) await getSettings();
    if (settings == null) {
      throw Exception("Could not load radio settings to modify them.");
    }

    // If enabling scan, also disable dual watch as it can interfere.
    final Settings newSettings;
    if (enable) {
      newSettings = settings!.copyWith(scan: true, doubleChannel: ChannelType.OFF.value);
    } else {
      newSettings = settings!.copyWith(scan: false);
    }


    // 1. Write the new settings object to the radio.
    await writeSettings(newSettings);

    // 2. Wait for a moment to allow the radio to process the command and update its internal state.
    await Future.delayed(const Duration(milliseconds: 250));

    // 3. Poll the radio's status again to get the definitive, updated state.
    // This will update the `isScan` property and notify all listeners, including the ScanScreen UI.
    await getStatus();
  }

  Future<void> startAudioMonitor() async {
    if (_audioController == null) return;
    await _audioController!.startMonitoring();
    isAudioMonitoring = _audioController!.isMonitoring;
    notifyListeners();
  }

  Future<void> stopAudioMonitor() async {
    if (_audioController == null) return;
    await _audioController!.stopMonitoring();
    isAudioMonitoring = _audioController!.isMonitoring;
    notifyListeners();
  }

  Future<void> toggleAudioMonitor() async {
    if (isAudioMonitoring) {
      await stopAudioMonitor();
    } else {
      await startAudioMonitor();
    }
  }

  @override
  void dispose() {
    stopVfoScan();
    _btStreamSubscription?.cancel();
    _commandConnection?.close();
    _messageStreamController.close();
    _audioController?.dispose();
    super.dispose();
  }
}