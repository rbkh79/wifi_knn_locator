import 'package:flutter/material.dart';
import '../data_model.dart';
import '../local_database.dart';

/// صفحه نمایش تاریخچه موقعیت‌های ذخیره‌شده
class LocationHistoryScreen extends StatefulWidget {
  const LocationHistoryScreen({Key? key}) : super(key: key);

  @override
  State<LocationHistoryScreen> createState() => _LocationHistoryScreenState();
}

class _LocationHistoryScreenState extends State<LocationHistoryScreen> {
  List<LocationHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final db = LocalDatabase.instance;
    final list = await db.getLocationHistory(deviceId: 'user-device', limit: 100, ascending: false);
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تاریخچه موقعیت‌ها'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('هیچ موقعیتی ذخیره نشده'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    final time = e.timestamp.toLocal();
                    return ListTile(
                      title: Text(
                          '${e.latitude.toStringAsFixed(6)}, ${e.longitude.toStringAsFixed(6)}'),
                      subtitle: Text(
                          '${e.zoneLabel ?? ''}  •  ${e.confidence.toStringAsFixed(2)}  •  ${time.year}/${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2,'0')}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.check_circle_outline),
                        tooltip: 'بارگذاری روی نقشه',
                        onPressed: () {
                          Navigator.of(context).pop(e);
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
