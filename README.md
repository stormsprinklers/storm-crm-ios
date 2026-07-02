# StormCRM iOS

## Setup

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen). **`project.yml` is the source of truth** for the Xcode project. The `.xcodeproj` is not committed — generate it locally after cloning.

```bash
brew install xcodegen   # once
xcodegen generate       # after clone, or whenever project.yml changes
open StormCRM.xcodeproj
```

## After pulling changes

```bash
git pull
xcodegen generate
```

Then in Xcode: **Product → Clean Build Folder** (Shift+Cmd+K), then build.

## API URL (required for login)

The app reads the backend URL from the **`API_BASE_URL` environment variable** in the Xcode scheme. See `StormCRM/Core/AppConfig.swift`.

**Set it in Xcode:**

1. **Product → Scheme → Edit Scheme…**
2. Select **Run** on the left
3. Open the **Arguments** tab
4. Under **Environment Variables**, set:
   - **Name:** `API_BASE_URL`
   - **Value:** your backend URL (no trailing slash)

Examples:

| Scenario | `API_BASE_URL` value |
|----------|----------------------|
| Production (default) | `https://crm.stormsprinklers.com` |
| Local API on your Mac (simulator) | `http://localhost:3000` |
| Local API on your Mac (physical device) | `http://192.168.x.x:3000` |

The default is `https://crm.stormsprinklers.com` in `AppConfig.swift` and `project.yml`. After changing `project.yml`, run `xcodegen generate`. You can also override in **Edit Scheme** (scheme values win at launch).

**Also make sure:**

- Your Storm CRM API server is actually running and reachable at that URL
- For a real device, `localhost` will **not** work — it points at the phone, not your Mac
- Use `http://` only for local dev; production should use `https://`

## Troubleshooting

**"Cannot find InboxHubView in scope"**

Inbox lives under `StormCRM/Features/Inbox/`. Run `xcodegen generate` and clean build after pulling.

**Tabs load but show no data / "Invalid response"**

The CRM API returns **camelCase** JSON (`startAt`, `accessToken`, …). If you see decoding errors on Visits, pull the latest code — older builds used snake_case decoding and failed on every response.

After updating:

```bash
git pull
xcodegen generate
```

Then **Product → Clean Build Folder** and rebuild.

Also check:

- **Schedule empty** — The schedule loads roughly two weeks before and three weeks after the selected week. Tap another day in the week strip or use the arrows to change weeks. Field techs only see visits assigned to them; admins see the full company schedule.
- **Customers empty** — Open the **Customers** tab (search loads all active customers; use `status=ALL` to include archived). Pull to refresh.
- **Inbox empty** — Use the **Customers** or **Team** segment at the top. Customer SMS uses `scope=external`; team SMS uses `scope=internal`. Field techs default to Team.
- **401 / session errors** — Confirm `API_BASE_URL` points at a server with the mobile auth endpoints deployed (`/api/mobile/auth/login`).

**"Build input file cannot be found" (e.g. `MeView.swift`)**

Your `.xcodeproj` is stale. Recent updates removed `MeView.swift` (replaced by **More** tab → `MoreView.swift`) and added many new files. Regenerate the project:

```bash
git pull origin main
rm -rf StormCRM.xcodeproj
xcodegen generate
open StormCRM.xcodeproj
```

Then **Product → Clean Build Folder** and build again.

**"Project file is damaged"**

Do not use an old committed `.xcodeproj`. Remove it and regenerate:

```bash
rm -rf StormCRM.xcodeproj
xcodegen generate
```

## Twilio Voice (in-app calling)

Calls use the **Twilio Voice iOS SDK** over VoIP — the same `/api/inbox/voice/token` endpoint as the web CRM softphone.

After pulling:

```bash
xcodegen generate   # links TwilioVoice SPM package from project.yml
```

**Requirements on the CRM server** (see `crm/.env.example`):

- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_API_KEY`, `TWILIO_API_SECRET`
- `TWILIO_TWIML_APP_SID` with Voice URL → `{APP_URL}/api/twilio/voice/client`
- Company `twilioPhone` configured in Settings → Voice

**On device:**

- Grant **Microphone** permission when prompted
- Test on a **physical iPhone/iPad** — the Simulator has limited VoIP/audio support
- A call bar appears at the top while connected (mute / end)

If the SDK is not linked, the app falls back to opening the native Phone app (`tel:`).

## Dashboard

The **Dashboard** tab (first tab) is the home screen:

- **Shift clock** — clock in/out and today’s hours (`GET/POST /api/time-clock`)
- **Next job** — preview of your current or next scheduled visit (tap to open visit detail)
- **This week** — your personal stats for the current calendar week: average job value, 5-star reviews, and total revenue (KPI dashboard API, filtered to your user)

Pull to refresh reloads the clock, schedule preview, and weekly stats.

## More

The **More** tab (last tab) holds account actions and future settings:

- Account name, email, and role
- **Sign out**

Mobile login is available to **Admin, Manager, CSR, Sales, Tech, and Installer** roles.

## SMS Inbox

The **Inbox** tab is a full SMS/MMS client wired to the same APIs as the web CRM:

- **Customers** — external customer conversations (`GET/POST /api/inbox/sms/conversations?scope=external`)
- **Team** — internal employee SMS (`scope=internal`)
- Message bubbles show **timestamp**, **sender name** on outbound messages, and **delivery status**
- **MMS** — inbound images/videos display via authenticated blob URLs; outbound attachments upload through `POST /api/inbox/media/upload?channel=sms` (camera or photo library)
- **Compose** — search customers or team members and start a new thread
- Threads **poll every 5 seconds** while open (same as web)

## Push notifications (new SMS alerts)

When a customer or team member texts your Twilio number, the CRM sends an **APNs push** to registered iOS devices.

**CRM server env** (see `crm/.env.example`):

- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (contents of your `.p8` key)
- `APNS_BUNDLE_ID=com.stormsprinklers.stormcrm`
- `APNS_USE_SANDBOX=true` for Xcode debug builds; `false` for TestFlight/App Store

**Database:** run `npx prisma db push` (or apply `crm/prisma/patches/mobile_push_device.sql`) to create the `MobilePushDevice` table.

**Xcode setup:**

1. Enable **Push Notifications** capability on the StormCRM target (Signing & Capabilities).
2. `StormCRM.entitlements` includes `aps-environment` — use `development` for local debug, `production` for release builds.
3. Test on a **physical device** (Simulator push delivery is unreliable).
4. Sign in once; the app registers the device token via `POST /api/mobile/push/register`.

Tapping a notification opens the conversation in the Inbox tab. Deep link format: `stormcrm://inbox?conversationId={id}`.

## Customers tab

Browse and manage customers from the **Customers** tab (between Visits and Reports/Inbox):

- **Search** — name, phone, or address (debounced live search)
- **List** — phone, city, property/visit counts, Do Not Service and archived badges
- **Detail** — contact info, summary stats, and for each property inline: **street view**, map embed, property info (zones, shutoff, controller), **irrigation zone map + program guide**, visit history, estimates, and notes
- **Actions** — CRM text (opens inbox compose), Twilio voice call, email
- **Edit** — office roles (CSR, Manager, Admin, Sales) can update contact/address fields; **Tags** and **Do not service** are editable inline on the customer profile for Tech, Installer (tags only), CSR, Sales, Manager, and Admin
- **Create** — office roles can add customers via **+** in the toolbar

## Service plans (lite)

See whether a customer is on a maintenance/service plan and enroll them in the field:

- **Customer detail** — Service plans section lists all enrollments (active, draft, cancelled) with status badges
- **Visit detail** — Service plan card shows active plans, link visit to plan visits, or **Sell plan**
- **Enroll flow** — pick property, plan template, billing frequency, start date, optional add-ons → creates a **DRAFT** enrollment
- **Activate** — **Accept & activate plan** on the enrollment detail after the customer agrees (same as web CRM)

**Who can sell:** CSR, Manager, Admin, Tech, and Sales (`canManageEnrollments`). All field/office roles except Installer can **view** plan status.

Plans are configured on the web CRM under **Maintenance Plans**. Stripe billing runs server-side when you activate an enrollment.

## Field payments and invoices

Technicians can collect payment and send invoices from the visit detail screen:

- **Payment card** — shows balance due, **Collect payment** (Stripe Checkout in Safari, returns via `stormcrm://payment-return`), **Send invoice to customer** (email/SMS via CRM templates), and **Share pay link**
- **After Finish** — if the visit has line items and an outstanding balance, you'll be prompted to collect payment or send an invoice
- Invoice is synced from visit line items automatically (`POST /api/visits/{id}/invoice`)

Requires `STRIPE_SECRET_KEY` on the CRM server for card checkout. Invoice send requires customer email or phone and configured notification templates.

## Branding

The app uses Storm Sprinklers colors (navy, sky, coral) and loads your company **email logo** from `GET /api/settings/company` after sign-in. Upload the logo in CRM → Settings → Company → Email branding.

## Visit page parity

The visit detail screen is laid out top-to-bottom: a thin **street view** header (content scrolls over it), visit title with **Pay** when balance is due, time-tracking actions, **summary of work**, checklist launcher, **customer** block (contact, property map, collapsible programming guide), **schedule** (date, time, window, technician), timestamped **notes** with author photos, then attachments, estimates, line items, and tags. It also includes maintenance plans, customer history, profit (managers), and admin delete where applicable.

**Summary of work:** Saved on the visit (`workSummary` field). Requires running a Prisma migration after pulling backend changes (`npx prisma migrate dev` in `crm/`).

**Line items:** All roles can add items from the price book, edit quantity/price, remove items, and manage discounts (same APIs as web).

**Schedule:** A **week strip** (Sun–Sat) at the top lets you pick one day at a time; the list below shows only that day’s jobs. Use the chevrons to move between weeks, or **Today** when you’re not on the current day. Office roles (CSR, Manager, Admin) can edit start/end time and assigned technician from the **Schedule** tab (swipe or long-press a job) or visit detail. The schedule is **color-coded** by technician, service area, crew, or division (palette menu). Field techs see a read-only color-coded view of their assigned jobs.

**Delete visit:** Admins see a delete button at the bottom of the visit page (`DELETE /api/visits/{id}`).

## Reporting

The **Reports** tab (Admin, Manager, CSR, Sales, Tech) loads live data from `GET /api/reporting/{type}`:

- Business insights, **KPI dashboard** with editable date range (YTD, MTD, last 30 days, or custom start/end)
- Tech performance, CSR calls, voice summary
- Estimates, leads
- Financial trends, AR aging, payments by method
- Service plan churn

Pull to refresh on any report screen.

**Irrigation map:** Full map editor on visit and customer property screens — capture aerial satellite image, draw zone polygons (tap-to-place corners), place markers (POC, timer, valve, filter, backflow), edit zone attributes (vegetation, shade, slope, soil, nozzles, GPM), save draft or publish to portal, and adjust controller program settings (grass season, drought mode, cycle & soak, ETo override). Private blob images load with Bearer auth.

**Still web-only:** design zone viewer (estimate snapshots).
