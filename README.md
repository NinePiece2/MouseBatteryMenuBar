# Logitech Mouse Battery

A lightweight macOS menu-bar app for Logitech G mice. It reads HID++ battery status through IOKit, shows a charging-aware SF Symbol in the menu bar, and lets you select which mouse to monitor when multiple compatible devices are connected.

## Build and run

```sh
swift package clean
swift build
swift run
```

The app is an accessory application, so it has no Dock icon. HID++ support depends on the connected mouse exposing the Unified Battery feature (`0x1004`) or the legacy battery feature (`0x1000`).