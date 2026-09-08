# Logitech Mouse Battery

A lightweight macOS menu-bar application for Logitech mice. It reads HID++ battery status through IOKit, dynamically discovers connected devices with hotplug support, displays a combined mouse-and-battery status item with optional text percentage in the menu bar, and features a rich SwiftUI popover dashboard.

## Features

- **Menu Bar Integration**: Displays a composite status icon (`computermouse` + battery symbol) alongside an optional live battery percentage indicator.
- **Dynamic Device Hotplugging**: Automatically detects when compatible mice are connected or disconnected in real-time.
- **Multi-Device Support & Selection**: Seamlessly switches between multiple connected Logitech devices via a clean dropdown picker.
- **Visual Battery Dashboard**: Includes a built-in progress bar, status text (charging/discharging state), and low-battery alerts.
- **Customizable Refresh Intervals**: Choose how frequently the app checks battery levels (1 min, 5 mins, 15 mins, or 30 mins).
- **Persistent Preferences**: Remembers your menu bar text display configurations using `UserDefaults`.
- **HID++ Compatibility**: Supports devices utilizing the Unified Battery feature (`0x1004`) or legacy battery feature (`0x1000`).
- **Background App**: The application runs as a background accessory service with no Dock icon.

## Images



## Build and Run

```sh
swift package clean
swift build
swift run
```

## Package

```sh
swift build -c release
```

```sh
# Create the .app directory hierarchy
mkdir -p LogiMouse.app/Contents/MacOS
mkdir -p LogiMouse.app/Contents/Resources

# Copy the compiled executable into the MacOS folder
cp .build/release/LogiMouseBatteryMenuBar LogiMouse.app/Contents/MacOS/LogiMouse
```

```sh
create-dmg \
  --volname "LogiMouse Installer" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "LogiMouse.app" 175 120 \
  --hide-extension "LogiMouse.app" \
  --app-drop-link 425 120 \
  "LogiMouse-Installer.dmg" \
  "LogiMouse.app"
```

