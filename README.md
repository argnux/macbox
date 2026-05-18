# MacBox

MacBox is a native SwiftUI macOS app for inspecting hardware network ports and managing their network services.

## Version

Current version: `2.2.2`.

## Features

- Hardware interface list refreshed by native SystemConfiguration change notifications and dynamic network state APIs
- Create, rename, delete, DHCP, and manual IPv4 service configuration through native macOS network preferences
- Ping tool backed by `/sbin/ping`
- UDP/TCP packet watcher with raw hex, ASCII, and MAVLink v1/v2 parsing
- GitHub release check and in-app install for compatible macOS zip assets

## Build

Open `macbox.xcodeproj` in Xcode, or build from the terminal. If your active developer directory points at Command Line Tools, keep `DEVELOPER_DIR` on the command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project macbox.xcodeproj \
  -scheme macbox \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/macbox-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The app supports macOS only.

## Release

Publish a GitHub release whose tag matches the app version, for example `v2.2.2`. The release workflow validates the tag against `MacBox/Info.plist`, builds a clean Apple Silicon `MacBox.app`, and uploads:

- `macbox_v2.2.2_arm64.zip` for the in-app updater
- `macbox_v2.2.2_arm64.dmg` for native manual installation

The in-app updater checks the latest GitHub release and installs the compatible macOS zip asset when the release version is newer than the installed app. The manual zip download remains available in Settings as a fallback.

For manual installation, download the DMG, open it, drag `MacBox.app` to Applications, and replace the existing app.

Version `2.1.1` only opens the update zip in a browser and cannot self-install Swift updates. Updating from `2.1.1` requires a one-time manual replacement of `MacBox.app`, preferably from the DMG; newer versions install future updates in app.

The app bundle is named `MacBox.app`, but the executable remains `Contents/MacOS/macbox` so v1.x Wails builds can install the Swift binary through their legacy updater.

When a v1.x app installs only the Swift executable, MacBox repairs the legacy bundle on the next launch by downloading the current release zip, copying the new Info.plist and resources into the installed app, renaming the bundle when possible, refreshing LaunchServices, and relaunching once.
