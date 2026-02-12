import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

/// Helpers for requesting and guiding users for permissions
class PermissionUtils {
  /// Request location + phone permissions and return true if both granted.
  /// If any permission is permanently denied, it returns false.
  static Future<bool> requestLocationAndPhonePermissions() async {
    try {
      final loc = await Permission.location.request();
      final phone = await Permission.phone.request();

      if (loc.isPermanentlyDenied || phone.isPermanentlyDenied) {
        debugPrint('PermissionUtils: one or more permissions permanently denied');
        return false;
      }

      return loc.isGranted && phone.isGranted;
    } catch (e) {
      debugPrint('PermissionUtils: error requesting permissions: $e');
      return false;
    }
  }

  /// Open app settings so user can manually enable permissions
  static Future<bool> openAppSettingsIfNeeded(BuildContext context) async {
    try {
      final opened = await openAppSettings();
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot open app settings. Please enable permissions manually.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return opened;
    } catch (e) {
      debugPrint('PermissionUtils: error opening app settings: $e');
      return false;
    }
  }
}
