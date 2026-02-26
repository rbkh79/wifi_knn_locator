import 'dart:io';

/// ساده‌ترین پروفایلر داخلی که زمان اجرای یک بلوک را اندازه‌گیری می‌کند
/// و در صورت نیاز می‌تواند مصرف حافظه را ثبت کند.
class Profiler {
  static int elapsedMilliseconds({required void Function() block}) {
    final sw = Stopwatch()..start();
    block();
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  /// اجرای بلوک ناسینکرون و بازگرداندن مدت زمان (ms)
  static Future<int> elapsedMillisecondsAsync({required Future<void> Function() block}) async {
    final sw = Stopwatch()..start();
    await block();
    sw.stop();
    return sw.elapsedMilliseconds;
  }

  /// مصرف حافظه فعلی (RSS) را به کیلوبایت برمی‌گرداند.
  /// ممکن است روی برخی پلتفرم‌ها ناکارآمد باشد یا همیشه در دسترس نباشد.
  static int currentMemoryUsageKb() {
    try {
      final bytes = ProcessInfo.currentRss;
      return (bytes / 1024).round();
    } catch (_) {
      return 0;
    }
  }
}
