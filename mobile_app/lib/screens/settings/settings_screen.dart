import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/connection_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final conn = context.read<ConnectionService>();
    _hostCtrl.text = conn.host;
    _portCtrl.text = conn.port.toString();
  }

  @override
  void dispose() { _hostCtrl.dispose(); _portCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Server Configuration', style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
          const SizedBox(height: 16),
          TextField(controller: _hostCtrl, decoration: const InputDecoration(labelText: 'Server Host / IP', prefixIcon: Icon(Icons.dns_rounded))),
          const SizedBox(height: 12),
          TextField(controller: _portCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port', prefixIcon: Icon(Icons.tag_rounded))),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save'),
            onPressed: () async {
              final host = _hostCtrl.text.trim();
              final port = int.tryParse(_portCtrl.text.trim()) ?? 5000;
              await context.read<ConnectionService>().saveSettings(host, port);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Connection Tips', style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
                const SizedBox(height: 8),
                _tip('Android Emulator → PC', '10.0.2.2'),
                _tip('Same WiFi network', 'Your PC\'s local IP'),
                _tip('Default port', '5000'),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tip(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Text('$label: ', style: const TextStyle(fontSize: 13)),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
    ]),
  );
}
