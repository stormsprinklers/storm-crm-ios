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

| Where you run the app | `API_BASE_URL` value |
|----------------------|----------------------|
| Simulator, API on same Mac | `http://localhost:3000` |
| Physical iPhone, API on your Mac | `http://192.168.x.x:3000` (your Mac's LAN IP) |
| Staging / production | `https://crm.stormsprinklers.com` |

If you use XcodeGen, `project.yml` seeds this to `http://localhost:3000` — change it there and run `xcodegen generate`, or override it in **Edit Scheme** (scheme edits win at launch).

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

**"Project file is damaged"**

Do not use an old committed `.xcodeproj`. Remove it and regenerate:

```bash
rm -rf StormCRM.xcodeproj
xcodegen generate
```
