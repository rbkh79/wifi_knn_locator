# HiVT Domain Adaptation (Simple Adapter)

این خروجی با افزودن یک adapter سبک روی embedding های frozen HiVT تولید شده است.

## Setup
- Routes: 48
- Obs lengths: [12, 16, 20]
- Epochs: 2
- Margin: 0.25
- Reg lambda: 0.05

## Mean Metrics (Snapped)

| Metric | Baseline | Adapted | Delta (Adapted-Baseline) |
|---|---:|---:|---:|
| ADE (m) | 37.251 | 36.763 | -0.488 |
| FDE (m) | 57.360 | 57.933 | 0.573 |

## Case-level Improvement Count

- ADE improved in 5/144 cases
- FDE improved in 4/144 cases

## Output Files

- CSV: adapter_comparison_cases.csv
- Report: adapter_summary.md
- Adapter weights: adapter_weights.pt
