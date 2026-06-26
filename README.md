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

**"Cannot find TeamInboxView in scope"**

`TeamInboxView` is defined in `StormCRM/App/MainTabView.swift` (same file as `MainTabView`). If you still see this error:

1. Confirm `git pull` brought in the latest `MainTabView.swift` (search for `struct TeamInboxView` in that file).
2. Delete any stale local copy of `StormCRM/Features/Inbox/TeamInboxView.swift` if it still exists on disk.
3. Run `xcodegen generate` again and clean build.

**Tabs load but show no data / "Invalid response"**

The CRM API returns **camelCase** JSON (`startAt`, `accessToken`, …). If you see decoding errors on Visits, pull the latest code — older builds used snake_case decoding and failed on every response.

After updating:

```bash
git pull
xcodegen generate
```

Then **Product → Clean Build Folder** and rebuild.

Also check:

- **Schedule empty** — Shows jobs from the past 7 days through the next 21 days. Field techs only see visits assigned to them; admins see the full company schedule.
- **Customers empty** — The list loads automatically on open (up to 500). Use search to filter.
- **Inbox empty** — Team inbox only shows **internal** SMS threads. If your team uses external/customer SMS only, this tab will be empty until internal conversations exist.
- **401 / session errors** — Confirm `API_BASE_URL` points at a server with the mobile auth endpoints deployed (`/api/mobile/auth/login`).


Do not use an old committed `.xcodeproj`. Remove it and regenerate:

```bash
rm -rf StormCRM.xcodeproj
xcodegen generate
```
