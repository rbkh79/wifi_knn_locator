/// سرویس مکان‌یابی خارجی (Outdoor Localization Service)
/// 
/// این سرویس برای مکان‌یابی در محیط‌های باز (Outdoor) طراحی شده است
/// و به صورت کاملاً GPS-Free عمل می‌کند.
/// 
/// روش کار:
/// - از اطلاعات دکل‌های مخابراتی (Cell Towers) استفاده می‌کند
/// - Cell ID، LAC/TAC، MCC، MNC و قدرت سیگنال را استخراج می‌کند
/// - الگوریتم KNN برای تخمین موقعیت به کار می‌رود
/// - پایگاه داده آفلاین SQLite برای ذخیره اثرانگشت‌های سلولی
/// 
/// چرا GPS-Free؟
/// - در برخی شرایط، GPS در دسترس نیست یا دقت پایینی دارد
/// - Cell-based localization می‌تواند به عنوان جایگزین یا مکمل عمل کند
/// - نیازی به دسترسی به سرویس‌های خارجی نیست (حریم خصوصی بهتر)
/// - برای محیط‌های شهری که دکل‌های مخابراتی فراوان هستند مناسب است
/// 
/// محدودیت‌ها:
/// - دقت در حد ناحیه‌ای (Coarse-Grained) است (معمولاً 50-500 متر)
/// - نیاز به جمع‌آوری اثرانگشت‌های سلولی در مرحله آموزش دارد
/// - در مناطق روستایی با دکل‌های کم، دقت کاهش می‌یابد
import 'package:flutter/foundation.dart';
import '../data_model.dart';
import '../local_database.dart';
import '../knn_localization.dart';
import '../cell_scanner.dart';

/// نتیجه مکان‌یابی خارجی
class OutdoorLocalizationResult {
  final LocationEstimate? estimate;
  final bool isOutdoor;
  final int cellTowerCount; // تعداد دکل‌های شناسایی شده
  final double averageSignalStrength; // میانگین قدرت سیگنال

  OutdoorLocalizationResult({
    this.estimate,
    required this.isOutdoor,
    required this.cellTowerCount,
    required this.averageSignalStrength,
  });

  /// بررسی اینکه آیا نتیجه قابل اعتماد است
  bool get isReliable =>
      estimate != null &&
      estimate!.confidence >= 0.2 && // آستانه پایین‌تر برای Outdoor
      cellTowerCount >= 1;
}

/// سرویس مکان‌یابی خارجی
class OutdoorLocalizationService {
  final LocalDatabase _database;
  final KnnLocalization _knnLocalization;

  OutdoorLocalizationService(this._database)
      : _knnLocalization = KnnLocalization(_database);

  /// انجام مکان‌یابی خارجی بر اساس اسکن دکل‌های مخابراتی
  /// 
  /// این متد:
  /// 1. اسکن دکل‌های مخابراتی را انجام می‌دهد
  /// 2. اطلاعات دکل متصل (Serving Cell) و همسایه‌ها را جمع‌آوری می‌کند
  /// 3. با استفاده از KNN موقعیت را تخمین می‌زند
  /// 4. نتیجه را با ضریب اطمینان برمی‌گرداند
  /// 
  /// [k]: تعداد همسایه‌های نزدیک برای الگوریتم KNN (پیش‌فرض: 3)
  /// 
  /// Returns: OutdoorLocalizationResult شامل تخمین موقعیت و اطلاعات محیط
  Future<OutdoorLocalizationResult> performOutdoorLocalization({
    int k = 3,
  }) async {
    try {
      // بررسی اینکه آیا Cell Scanner در دسترس است
      final isAvailable = await CellScanner.isAvailable();
      if (!isAvailable) {
        debugPrint('Outdoor localization: Cell scanner not available');
        return OutdoorLocalizationResult(
          isOutdoor: false,
          cellTowerCount: 0,
          averageSignalStrength: 0.0,
        );
      }

      // انجام اسکن دکل‌های مخابراتی
      final cellScan = await CellScanner.performScan();

      // جمع‌آوری تمام دکل‌ها (متصل + همسایه)
      final allCells = cellScan.allCells;

      if (allCells.isEmpty) {
        debugPrint('Outdoor localization: No cell towers detected');
        return OutdoorLocalizationResult(
          isOutdoor: false,
          cellTowerCount: 0,
          averageSignalStrength: 0.0,
        );
      }

      // محاسبه میانگین قدرت سیگنال
      final avgSignal = _calculateAverageSignalStrength(allCells);
      final cellTowerCount = allCells.length;

      // بررسی اینکه آیا محیط Outdoor است یا نه
      // معیار: حداقل یک دکل شناسایی شده
      final isOutdoor = cellTowerCount >= 1;

      if (!isOutdoor) {
        debugPrint('Outdoor localization: Not enough cell towers for outdoor localization');
        return OutdoorLocalizationResult(
          isOutdoor: false,
          cellTowerCount: cellTowerCount,
          averageSignalStrength: avgSignal,
        );
      }

      // تخمین موقعیت با استفاده از KNN (فقط Cell)
      final estimate = await _knnLocalization.estimateLocationFromCell(
        cellScan,
        k: k,
      );

      debugPrint(
        'Outdoor localization completed: '
        'Cells=${cellTowerCount}, '
        'AvgSignal=${avgSignal.toStringAsFixed(1)} dBm, '
        'Confidence=${estimate?.confidence.toStringAsFixed(2) ?? "N/A"}',
      );

      return OutdoorLocalizationResult(
        estimate: estimate,
        isOutdoor: true,
        cellTowerCount: cellTowerCount,
        averageSignalStrength: avgSignal,
      );
    } catch (e) {
      debugPrint('Error in outdoor localization: $e');
      return OutdoorLocalizationResult(
        isOutdoor: false,
        cellTowerCount: 0,
        averageSignalStrength: 0.0,
      );
    }
  }

  /// محاسبه میانگین قدرت سیگنال دکل‌ها
  double _calculateAverageSignalStrength(List<CellTowerInfo> cells) {
    if (cells.isEmpty) return 0.0;

    final signals = cells
        .where((cell) => cell.signalStrength != null)
        .map((cell) => cell.signalStrength!.toDouble())
        .toList();

    if (signals.isEmpty) return 0.0;

    return signals.reduce((a, b) => a + b) / signals.length;
  }

  /// بررسی اینکه آیا محیط Outdoor است یا نه
  /// 
  /// این متد بر اساس تعداد و قدرت سیگنال دکل‌های مخابراتی تصمیم می‌گیرد
  /// که آیا کاربر در محیط باز (Outdoor) است یا نه.
  Future<bool> isOutdoorEnvironment() async {
    try {
      final isAvailable = await CellScanner.isAvailable();
      if (!isAvailable) return false;

      final cellScan = await CellScanner.performScan();
      return cellScan.allCells.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking outdoor environment: $e');
      return false;
    }
  }
}

