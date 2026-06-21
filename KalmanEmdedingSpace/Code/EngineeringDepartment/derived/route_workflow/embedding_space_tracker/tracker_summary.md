# Embedding Space Tracker — خلاصه نتایج

## رویکرد
به‌جای decoder آموزش‌دیده روی Argoverse، از encoder HiVT برای استخراج embedding استفاده شد.
احتمال مسیرها از softmax روی فاصله کسینوسی همسایه‌های Top-K ساخته شد.
آینده از مسیرهای مرجع indoor (G+C) بازیابی شد — نه از decoder.

## معیارها (میانگین کل)

| معیار | مقدار |
|---|---|
| mean Expected ADE (raw) | 44.03 m |
| mean Expected FDE (raw) | 64.65 m |
| mean Expected ADE (snapped) | 44.08 m |
| mean Expected FDE (snapped) | 64.65 m |
| mean Top-1 ADE (snapped) | 36.22 m |
| mean Top-1 FDE (snapped) | 63.32 m |

## مقایسه با روش قبلی (decoder مستقیم)

| روش | mean ADE | mean FDE |
|---|---|---|
| decoder مستقیم HiVT (Argoverse) | 59.57 m | 97.68 m |
| embedding retrieval احتمالاتی (Expected raw) | 44.03 m | 64.65 m |
| embedding retrieval احتمالاتی + snap | 44.08 m | 64.65 m |

## تعداد موارد
144 مورد (48 مسیر × 3 طول مشاهده)
