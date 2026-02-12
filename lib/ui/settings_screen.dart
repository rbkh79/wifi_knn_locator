import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../ui/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _continuousScan = false;
  double _scanInterval = 5.0;
  bool _motionAware = true;

  int _strategy = 1;
  bool _hashMac = true;
  bool _localOnly = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final cont = await SettingsService.getContinuousScan();
      final interval = await SettingsService.getScanIntervalSeconds();
      final motion = await SettingsService.getUseMotionAwareScanning();
      final hash = await SettingsService.getHashDeviceMac();
      final local = await SettingsService.getStoreLocalOnly();
      final strat = await SettingsService.getLocalizationStrategy();
      setState(() {
        _continuousScan = cont;
        _scanInterval = interval.toDouble();
        _motionAware = motion;
        _hashMac = hash;
        _localOnly = local;
        _strategy = strat;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    await SettingsService.setContinuousScan(_continuousScan);
    await SettingsService.setScanIntervalSeconds(_scanInterval.toInt());
    await SettingsService.setUseMotionAwareScanning(_motionAware);
    await SettingsService.setHashDeviceMac(_hashMac);
    await SettingsService.setStoreLocalOnly(_localOnly);
    await SettingsService.setLocalizationStrategy(_strategy);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات'),
        backgroundColor: AppTheme.primary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حالت اسکن', style: TextStyle(fontWeight: FontWeight.bold)),
                  SwitchListTile(
                    value: _continuousScan,
                    title: const Text('اسکن مداوم'),
                    subtitle: const Text('اسکن خودکار در پس‌زمینه'),
                    onChanged: (v) => setState(() => _continuousScan = v),
                  ),
                  const SizedBox(height: 6),
                  Text('فاصله اسکن: ${_scanInterval.toInt()} ثانیه'),
                  Slider(
                    min: 3,
                    max: 15,
                    divisions: 12,
                    value: _scanInterval,
                    onChanged: (v) => setState(() => _scanInterval = v),
                  ),
                  SwitchListTile(
                    value: _motionAware,
                    title: const Text('اسکن هوشمند بر اساس حرکت'),
                    subtitle: const Text('تشخیص ساکن/راه‌رفتن با شتاب‌سنج'),
                    onChanged: (v) => setState(() => _motionAware = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('استراتژی مکان‌یابی', style: TextStyle(fontWeight: FontWeight.bold)),
                  RadioListTile<int>(
                    value: 1,
                    groupValue: _strategy,
                    title: const Text('خارجی: فقط دکل‌های مخابراتی (BTS)'),
                    onChanged: (v) => setState(() => _strategy = v ?? 1),
                  ),
                  RadioListTile<int>(
                    value: 2,
                    groupValue: _strategy,
                    title: const Text('داخلی: ترکیب WiFi و دکل‌های مخابراتی'),
                    onChanged: (v) => setState(() => _strategy = v ?? 2),
                  ),
                  RadioListTile<int>(
                    value: 3,
                    groupValue: _strategy,
                    title: const Text('حالت ترکیبی هوشمند'),
                    onChanged: (v) => setState(() => _strategy = v ?? 3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حریم خصوصی', style: TextStyle(fontWeight: FontWeight.bold)),
                  SwitchListTile(
                    value: _hashMac,
                    title: const Text('هش کردن MAC دستگاه'),
                    onChanged: (v) => setState(() => _hashMac = v),
                  ),
                  SwitchListTile(
                    value: _localOnly,
                    title: const Text('ذخیره داده‌ها فقط در دستگاه'),
                    onChanged: (v) => setState(() => _localOnly = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await _saveSettings();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات ذخیره شد')));
            },
            child: const Text('ذخیره تنظیمات'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}
