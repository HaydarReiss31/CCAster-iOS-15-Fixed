![CCAster](assets/banner.png)

# CCAster

CCAster is an iOS 18-inspired, editable Control Center experience for jailbroken iOS 15 through 17 devices.

The project focuses on bringing a modern, paged and customizable Control Center experience to older iOS versions.

## ✨ Features

- Editable module layout
- Paged Control Center
- Custom add-control sheet
- Resizable modules
- Custom module footprints
- iOS 16 compatibility improvements for `ControlCenterUIKit` and `ControlCenterServices`
- Rootless jailbreak support

## 📱 Compatibility

| iOS Version | Status |
|-------------|--------|
| iOS 15 | ✅ Tested |
| iOS 16 | ✅ Tested |
| iOS 17 | ⚠️ Testing needed |
| iOS 11–14 | ❓ Unknown |

### Tested Devices

- iPhone 6s — iOS 15.8.8
- iPhone 7 Plus — iOS 15.8.3
- iPhone X — iOS 16.7.15

Support for iOS 11–14 is currently unknown. If you test CCAster on these versions, please report your results.

## 🔨 Building

CCAster is a rootless Theos project.

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=/tmp/swift-module-cache \
make clean package FINALPACKAGE=1
Package Information
Package ID: com.futur3sn0w.ccaster
Firmware: >= 11.0, << 17.0
Injection Target: SpringBoard
Dependencies: ElleKit, PreferenceLoader
📁 Project Structure
Tweak.xm — SpringBoard hooks, Control Center logic, layout engine, edit mode, add sheet and module presentation
prefs/ — PreferenceLoader bundle
scripts/ — Development and testing helpers
🧩 COSMIC Kit
CCAster can work with COSMIC Kit⁠�, a companion package providing optional Control Center modules.
The projects have separate responsibilities:
CCAster — Control Center UI, layout, editing, paging, resizing and runtime integration
COSMIC Kit — Optional Control Center module bundles
This separation allows additional modules to be developed and installed independently from the CCAster core.
⚠️ Status
CCAster is still under active development.
Because the tweak relies on Apple's private Control Center frameworks, behavior may vary between iOS versions and devices.
If you encounter a problem, please include:
Device model
iOS version
Jailbreak used
Relevant logs or crash reports
Steps to reproduce the issue
🤝 Contributing
Compatibility testing, bug reports and pull requests are welcome.
If you test CCAster on an unsupported iOS version or device, please share your results.
⭐ Support
If CCAster is useful to you, consider giving the repository a star.
It helps other jailbreak users discover the project.
🤖 Development Note
CCAster was developed entirely using AI assistance.
