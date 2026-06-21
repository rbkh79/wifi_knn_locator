# Contrastive + Decoder Prediction Summary

این خروجی با یک روش جدید مستقل تولید شده و فایل های قبلی را تغییر نمی دهد.

## Training setup
- train routes: 38
- test routes: 10
- train samples: 114
- test samples: 30
- adapter epochs: 8
- decoder epochs: 20

- hybrid alpha: 0.35
- retrieval top-k: 6
- retrieval tau: 0.05

## Mean metrics on held-out test routes

| Metric | Value (m) |
|---|---:|
| mean ADE raw | 41.099 |
| mean FDE raw | 62.925 |
| mean ADE decoder-snapped | 38.619 |
| mean FDE decoder-snapped | 61.127 |
| mean ADE hybrid-snapped | 35.184 |
| mean FDE hybrid-snapped | 58.593 |

## Best 10 by hybrid snapped FDE

- G014 obs=12 | ADE_hyb=2.88 | FDE_hyb=3.18
- G014 obs=16 | ADE_hyb=2.87 | FDE_hyb=3.18
- G014 obs=20 | ADE_hyb=2.85 | FDE_hyb=5.24
- G018 obs=12 | ADE_hyb=7.16 | FDE_hyb=12.22
- G018 obs=16 | ADE_hyb=7.12 | FDE_hyb=12.22
- G018 obs=20 | ADE_hyb=7.70 | FDE_hyb=14.68
- C015 obs=20 | ADE_hyb=26.41 | FDE_hyb=17.44
- C008 obs=20 | ADE_hyb=13.39 | FDE_hyb=21.58
- C008 obs=16 | ADE_hyb=13.36 | FDE_hyb=21.80
- C008 obs=12 | ADE_hyb=13.41 | FDE_hyb=22.04

## Worst 10 by hybrid snapped FDE

- G008 obs=12 | ADE_hyb=71.01 | FDE_hyb=126.30
- G008 obs=20 | ADE_hyb=70.92 | FDE_hyb=125.35
- G008 obs=16 | ADE_hyb=70.20 | FDE_hyb=123.57
- C021 obs=12 | ADE_hyb=48.62 | FDE_hyb=110.15
- C021 obs=16 | ADE_hyb=48.56 | FDE_hyb=110.15
- G012 obs=12 | ADE_hyb=93.64 | FDE_hyb=103.29
- G012 obs=16 | ADE_hyb=93.63 | FDE_hyb=103.29
- G012 obs=20 | ADE_hyb=93.62 | FDE_hyb=103.29
- C021 obs=20 | ADE_hyb=46.82 | FDE_hyb=102.17
- C015 obs=12 | ADE_hyb=45.31 | FDE_hyb=66.83

## Output files

- CSV: contrastive_decoder_cases.csv
- Summary: contrastive_decoder_summary.md
- Images: images/
- Contact sheet: predictions_contact_sheet.png
- Adapter weights: contrastive_adapter.pt
- Decoder weights: contrastive_decoder.pt
