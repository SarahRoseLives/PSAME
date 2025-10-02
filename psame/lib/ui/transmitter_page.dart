// lib/ui/transmitter_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/transmitter_controller.dart';
import '../sdr/same_protocol.dart';
import 'widgets/eas_codes.dart';

class TransmitterPage extends StatefulWidget {
  const TransmitterPage({super.key});

  @override
  State<TransmitterPage> createState() => _TransmitterPageState();
}

class _TransmitterPageState extends State<TransmitterPage> {
  final _controller = FmTransmitterController();
  final _formKey = GlobalKey<FormState>();

  // UI State
  bool _isInitialized = false;
  bool _isTransmitting = false;
  String _status = "Not Initialized";

  // Form Values
  double _selectedFrequency = 162.550;
  double _txVgaGain = 20;
  MapEntry<String, String> _selectedEvent = const MapEntry('RWT', 'Required Weekly Test');
  String _selectedOriginator = 'WXR';
  String _selectedPurgeTime = '0030';
  final _fipsController = TextEditingController(text: '039007');
  final _stationIdController = TextEditingController(text: 'KCLE-NWR');

  // Constants for UI
  final List<double> _wxFrequencies = const [162.400, 162.425, 162.450, 162.475, 162.500, 162.525, 162.550];
  final Map<String, String> _purgeTimes = const {
    '15 Mins': '0015', '30 Mins': '0030', '45 Mins': '0045',
    '1 Hour': '0100', '2 Hours': '0200', '6 Hours': '0600',
  };
  final List<String> _originators = const ['WXR', 'EAS', 'CIV'];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _fipsController.dispose();
    _stationIdController.dispose();
    super.dispose();
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
    if (!_formKey.currentState!.validate() || !_isInitialized || _isTransmitting) return;

    setState(() {
      _isTransmitting = true;
      _status = "Transmitting SAME: ${_selectedEvent.key}...";
    });

    _controller.transmitSameAlert(
      frequencyMhz: _selectedFrequency,
      txVgaGain: _txVgaGain.toInt(),
      org: _selectedOriginator,
      event: _selectedEvent.key,
      fips: _fipsController.text,
      purgeTime: _selectedPurgeTime,
      issueTime: SameProtocol.generateIssueTime(),
      stationId: _stationIdController.text
    ).catchError(_handleError);
  }

  void _startTone() {
    if (!_isInitialized || _isTransmitting) return;
    setState(() {
      _isTransmitting = true;
      _status = "Transmitting 1kHz Tone...";
    });
    _controller.transmitTone(
      frequencyMhz: _selectedFrequency,
      txVgaGain: _txVgaGain.toInt()
    ).catchError(_handleError);
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
        title: const Text('SAME/FM Transmitter'),
      ),
      body: Form(
        key: _formKey,
        child: IgnorePointer(
          ignoring: _isTransmitting,
          child: Opacity(
            opacity: _isTransmitting ? 0.5 : 1.0,
            child: ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                _buildStatusCard(),
                _buildRadioSettingsCard(),
                _buildMessageCard(),
                _buildTimingAndIdCard(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildActionButtons(),
    );
  }

  Widget _buildStatusCard() => Card(
    elevation: 2,
    child: ListTile(
      leading: Icon(
        _isTransmitting ? Icons.cell_tower : (_isInitialized ? Icons.check_circle : Icons.hourglass_top),
        color: _isTransmitting ? Colors.red : (_isInitialized ? Colors.green : Colors.grey),
      ),
      title: const Text("Status"),
      subtitle: Text(_status),
    ),
  );

  Widget _buildRadioSettingsCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Radio Settings", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<double>(
            value: _selectedFrequency,
            decoration: const InputDecoration(labelText: 'WX Frequency (MHz)', border: OutlineInputBorder()),
            items: _wxFrequencies.map((freq) => DropdownMenuItem(value: freq, child: Text(freq.toStringAsFixed(3)))).toList(),
            onChanged: (value) => setState(() => _selectedFrequency = value!),
          ),
          const SizedBox(height: 16),
          Text("TX VGA Gain: ${_txVgaGain.toInt()} dB"),
          Slider(
            value: _txVgaGain,
            min: 0, max: 47, divisions: 47,
            label: _txVgaGain.round().toString(),
            onChanged: (value) => setState(() => _txVgaGain = value),
          ),
        ],
      ),
    ),
  );

  Widget _buildMessageCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SAME Message", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ListTile(
            title: Text(_selectedEvent.key),
            subtitle: Text(_selectedEvent.value),
            trailing: const Icon(Icons.edit),
            onTap: _showEventPicker,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Theme.of(context).colorScheme.outline)
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _fipsController,
                  decoration: const InputDecoration(labelText: 'FIPS Code', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) => (value?.length != 6) ? 'Must be 6 digits' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _selectedOriginator,
                  decoration: const InputDecoration(labelText: 'Originator', border: OutlineInputBorder()),
                  items: _originators.map((org) => DropdownMenuItem(value: org, child: Text(org))).toList(),
                  onChanged: (value) => setState(() => _selectedOriginator = value!),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildTimingAndIdCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Timing & ID", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedPurgeTime,
                  decoration: const InputDecoration(labelText: 'Expiration', border: OutlineInputBorder()),
                  items: _purgeTimes.entries.map((entry) => DropdownMenuItem(value: entry.value, child: Text(entry.key))).toList(),
                  onChanged: (value) => setState(() => _selectedPurgeTime = value!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _stationIdController,
                  decoration: const InputDecoration(labelText: 'Station ID', border: OutlineInputBorder()),
                  validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildActionButtons() => Padding(
    padding: const EdgeInsets.all(8.0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.warning_amber),
          label: const Text('Transmit SAME Alert'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _isInitialized && !_isTransmitting ? _startSame : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                child: const Text('Transmit Tone'),
                onPressed: _isInitialized && !_isTransmitting ? _startTone : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Stop'),
                onPressed: _isTransmitting ? _stop : null,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  void _showEventPicker() async {
    final result = await showDialog<MapEntry<String, String>>(
      context: context,
      builder: (context) => _EventPickerDialog(),
    );
    if (result != null) {
      setState(() => _selectedEvent = result);
    }
  }
}


class _EventPickerDialog extends StatefulWidget {
  @override
  __EventPickerDialogState createState() => __EventPickerDialogState();
}

class __EventPickerDialogState extends State<_EventPickerDialog> {
  String _searchText = '';

  @override
  Widget build(BuildContext context) {
    final filteredEvents = easEventCodes.entries.where((entry) {
      final query = _searchText.toLowerCase();
      return entry.key.toLowerCase().contains(query) || entry.value.toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      title: const Text('Select Event Code'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (value) => setState(() => _searchText = value),
              decoration: const InputDecoration(
                labelText: 'Search...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filteredEvents.length,
                itemBuilder: (context, index) {
                  final event = filteredEvents[index];
                  return ListTile(
                    title: Text(event.key),
                    subtitle: Text(event.value),
                    onTap: () => Navigator.of(context).pop(event),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}