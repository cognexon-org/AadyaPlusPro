# aadya_plus_professional (Professional App) — Completion Checklist

**Stack:** Flutter · Riverpod (state) · go_router · Dio · fl_chart · webview_flutter
**Role:** For doctors, pharmacies, pathology labs and physiotherapists — dashboards, appointments, earnings, stock, orders, onboarding approval.
**Current state:** Rich role-based screens with charts and a pending-approval gate. Biggest gap: there is **no notifications surface at all**, and no push.

Legend: 🔴 P0 (launch blocker) · 🟠 P1 (strongly recommended) · 🔵 P2 (fast-follow)

---

## 1. Notifications (currently completely missing)
- [ ] 🔴 Add a **notifications screen** (none exists in this app) + unread badge in the dashboard shell.
- [ ] 🔴 Add `firebase_messaging` + `flutter_local_notifications`; request permission; register FCM token to backend.
- [ ] 🔴 Push + in-app alerts for: new booking, new chat message, cancellation/reschedule, new order / prescription in queue, payout processed.
- [ ] 🟠 Sound/priority alert for time-sensitive events (new pharmacy order, urgent consult).
- [ ] 🔵 Per-category notification preferences.

## 2. Doctor Module
- [ ] 🔴 Digital e-prescription pad: structured Rx with drug list, dosage templates, auto-send to patient + pharmacy.
- [ ] 🔴 Patient history timeline (past visits, prescriptions, reports) — EMR-lite.
- [ ] 🟠 Availability/schedule: block slots, per-consult-type fees, recurring schedules, leave.
- [ ] 🟠 Ratings dashboard: view & respond to reviews.
- [ ] 🔵 Follow-up / recall automation; publish to Health Feed.

## 3. Pharmacy Module
- [ ] 🔴 Real-time incoming-order + prescription-queue alerts (don't miss a sale).
- [ ] 🔴 Prescription-to-order fulfilment: read Rx, match SKUs, accept/reject, pack, dispatch.
- [ ] 🔴 Barcode scanning for fast billing & stock-in (backend has barcode/QR libs).
- [ ] 🔴 Batch & expiry management with near-expiry alerts; `screens/pharmacy/stock_alert.dart` has a placeholder — implement real low-stock logic.
- [ ] 🟠 Auto-reorder / purchase orders to suppliers; supplier ledger.
- [ ] 🟠 Delivery-partner assignment + live tracking.
- [ ] 🟠 Sales analytics & GST reports.
- [ ] 🔵 Generic/substitute suggestions.

## 4. Pathology & Physio Modules
- [ ] 🔴 Pathology: accept order → sample collected → upload report → patient notified (close the loop).
- [ ] 🟠 Physio: home-visit scheduling with service-area logic; session notes/exercise plans to patient.
- [ ] 🟠 Report/document upload flow (image_picker present).

## 5. Earnings & Payments
- [ ] 🟠 Verify earnings figures come from real transactions (screens read `professionalEarning`/`platformCommission`); show settlement dates & downloadable statements.
- [ ] 🟠 Instant/faster payout status + history.

## 6. Onboarding & Verification
- [ ] 🟠 Strengthen the pending-approval flow: document/license upload, status tracking, resubmission on rejection.
- [ ] 🔵 ABHA/HPR registration prompt for professionals (trust signal).

## 7. Polish & Store Readiness
- [ ] 🟠 Consistent loading (shimmer present), empty and error states; offline handling.
- [ ] 🟠 Crash reporting + analytics.
- [ ] 🔴 App icons, splash, store listing, permissions; test release build.
- [ ] 🔵 Tests for critical flows (none today).

> Note: this app uses Riverpod + Dio + go_router, while the patient app uses Provider + http — keep integrations (FCM, payments) implemented per-app; they don't share code.
