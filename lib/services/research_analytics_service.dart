import 'dart:math' as math;
import '../local_database.dart';
import '../data_model.dart';

/// سرویس تجزیه و تحلیل پژوهشی
///
/// فراهم می‌کند:
/// - حالت cross-validation K‑fold برای داده‌های fingerprint
/// - ارزیابی آفلاین داده‌های تاریخچه و لاگ تخمین
/// - محاسبه ماتریس سردرگمی برای طبقه‌بندی زونی
/// - محاسبه MAE، RMSE
class ResearchAnalyticsService {
  final LocalDatabase _db;

  ResearchAnalyticsService(this._db);

  /// انجام k-fold cross validation روی مجموعه اثرانگشت
  /// بازمی‌گرداند لیست خطاهای برای هر fold
  Future<List<double>> crossValidateFingerprints(int k) async {
    final fps = await _db.getAllFingerprints();
    if (fps.length < k || k < 2) return [];
    final errors = <double>[];

    final foldSize = (fps.length / k).floor();
    for (int i = 0; i < k; i++) {
      final test = fps.skip(i * foldSize).take(foldSize).toList();
      final train = fps.where((fp) => !test.contains(fp)).toList();
      // for simplicity compute naive error as average distance between test point and nearest train
      double totalErr = 0;
      for (final fp in test) {
        double minDist = double.infinity;
        for (final tfp in train) {
          final d = _euclidean(fp.latitude, fp.longitude, tfp.latitude, tfp.longitude);
          if (d < minDist) minDist = d;
        }
        totalErr += minDist;
      }
      errors.add(totalErr / test.length);
    }
    return errors;
  }

  /// محاسبه خطاهای MAE و RMSE برای لیست خطاها
  Map<String, double> computeErrorStats(List<double> errors) {
    if (errors.isEmpty) return {'mae': 0.0, 'rmse': 0.0};
    final mae = errors.reduce((a, b) => a + b) / errors.length;
    final rmse = math.sqrt(errors.map((e) => e * e).reduce((a, b) => a + b) / errors.length);
    return {'mae': mae, 'rmse': rmse};
  }

  /// تولید ماتریس سردرگمی از تاریخچه موقعیت بر اساس zoneLabel
  Future<Map<String, Map<String, int>>> buildConfusionMatrix() async {
    final history = await _db.getAllLocationHistory();
    final matrix = <String, Map<String, int>>{};
    history.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    String? prev;
    for (final entry in history) {
      final z = entry.zoneLabel ?? 'UNKNOWN';
      if (prev != null) {
        matrix.putIfAbsent(prev, () => {})[z] = (matrix[prev]?[z] ?? 0) + 1;
      }
      prev = z;
    }
    return matrix;
  }

  double _euclidean(double lat1, double lon1, double lat2, double lon2) {
    final dx = lat1 - lat2;
    final dy = lon1 - lon2;
    return math.sqrt(dx * dx + dy * dy);
  }
}
