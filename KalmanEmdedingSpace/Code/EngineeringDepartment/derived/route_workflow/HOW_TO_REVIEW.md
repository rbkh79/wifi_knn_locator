# How to Review Stage-1 Route Proposals

This folder now supports a one-by-one review flow.

## Where to look

- One-image-per-route preview images:
  - `route_images/`
- Clean article gallery without rejected routes:
  - `article_gallery/clean/`
- Long-route article gallery and contact sheet:
  - `article_gallery/long_routes/`
  - `article_gallery/long_routes_contact_sheet.png`
- Rejected-route archive:
  - `article_gallery/rejected/`
- Original all-in-one preview:
  - `route_proposals_stage1_preview.png`
- Compact summary:
  - `route_proposals_stage1_summary.md`
- Full proposal data:
  - `route_proposals_stage1.json`
  - `route_proposals_stage1.csv`
- Persistent database with full review history:
  - `routes_workflow.db`

## Recommended review method

Use the interactive menu:

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/route_proposal_workflow.py --action review
```

اگر route غلط است و نمی‌خواهید اصلا در دیتابیس بماند:

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/route_proposal_workflow.py --action purge-wrong --delete-images
```

برای حذف کامل routeهای مشخص:

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/route_proposal_workflow.py --action purge-routes --route-ids R036,R037,R038 --delete-images
```

## Manual Pen Workflow (recommended)

برای رسم دستی مسیر با قلم نوری/ماوس و تایید مرحله‌ای:

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/manual_route_draw_tool.py
```

رفتار ابزار رسم:
- کلیک چپ: افزودن checkpoint
- کلیک راست: حذف آخرین checkpoint
- دکمه `Approve and Next`: ذخیره مسیر تاییدشده و شروع مسیر بعدی
- دکمه `Clear`: پاک کردن مسیر فعلی
- دکمه `Finish`: اتمام جلسه رسم

خروجی مسیرهای دستی:
- جدول‌های `manual_routes`, `manual_route_checkpoints`, `manual_route_points` در `routes_workflow.db`
- تصویر هر مسیر در `derived/route_workflow/manual_drawn/route_images/`

For each route, the script prints:
- route id
- route type
- floor level(s)
- whether a floor transition is required
- the image path for that specific route

Then choose one of these actions:
- `A` = approve
- `R` = reject
- `C` = add comment
- `S` = skip for now
- `Q` = cancel the review session

Recommended next routes to inspect for the longer cases:
- `R036` = long multi-floor / multi-corridor route across levels `0-1-2`
- `R037` = long multi-floor / multi-corridor route across levels `0-1-2.5`
- `R038` = long multi-floor / multi-corridor route across levels `1-2-2.5`

## Important behavior

- Every action is saved in `routes_workflow.db`.
- Approvals are preserved in `approved_routes`.
- Rejections are preserved in `rejected_routes`.
- Comments and skips are stored in `route_reviews`, so all attempts remain recorded.
- You can stop anytime and resume later without losing prior history.

## Approve a route directly

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/route_proposal_workflow.py --action decide --route-id R004 --decision approve --comment "good corridor path"
```

## Reject a route directly

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/route_proposal_workflow.py --action decide --route-id R016 --decision reject --comment "needs better corridor connector"
```

## Check current status

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/route_proposal_workflow.py --action status
```

## List approved routes

```powershell
h:/HadiEnv/KalmanEmdedingSpace/Scripts/python.exe Code/EngineeringDepartment/route_proposal_workflow.py --action list-approved
```
