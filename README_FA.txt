به روزرسانی محدود Outdoor GPS+BTS
=================================

هدف این بسته فقط افزودن اطلاعات پژوهشی ارزشمند BTS است.
Wi-Fi، IMU، روش دانلود فعلی و سایر قسمت های برنامه تغییر نمی کنند.
هیچ APK، AAB، build، keystore یا فایل امضایی در این بسته وجود ندارد.

فیلدهای افزوده شده به CSV:
GpsQuality, ENodeBID, LocalCellID, PSC, PCI, EARFCN,
RSRP, RSRQ, SINR, CQI, TimingAdvance, ASULevel,
SignalLevel, CellBandwidth, Band, Registered,
ServingCellWasFallback, NeighborCellCount, NeighborCellsJSON

روش استفاده:
1) محتویات این ZIP را در ریشه مخزن wifi_knn_locator کپی کنید؛ همان پوشه ای که pubspec.yaml در آن است.
2) فایل APPLY_BTS_UPDATE.bat را اجرا کنید.
3) در GitHub Desktop تغییرات را بررسی کنید.
4) Commit و Push کنید.
5) در Codemagic Build بگیرید.

روش Export عوض نشده است. همان دکمه موجود فایل را باز/دانلود می کند،
ولی CSV جدید ستون های پژوهشی بیشتری خواهد داشت.

نکته:
بعضی گوشی ها همه فیلدها مانند SINR یا Timing Advance را در اختیار Android نمی گذارند.
در این حالت ستون مربوطه خالی می ماند و برنامه نباید Crash کند.
