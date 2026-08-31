![CCAster](assets/banner.png)

# CCAster

CCAster is an iOS 18-inspired, editable Control Center experience for rootless iOS 15 through 17. (11 through 14 compatibility not known)

The project currently focuses on SpringBoard-side Control Center behavior:

- editable module layout
- CCAster's custom add-control sheet
- paged module placement
- resize chrome and custom module footprints
- iOS 16 compatibility around `ControlCenterUIKit` and `ControlCenterServices`

This source repository is intentionally separate from the public package feed. Pushing here does not publish a package to the live APT repo or GitHub Pages.

## Building

CCAster is a rootless Theos project.

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFT_MODULE_CACHE_PATH=/tmp/swift-module-cache make clean package FINALPACKAGE=1
```

The package is configured for iOS 11 through 17 (though support will vary):

- package id: `com.futur3sn0w.ccaster`
- firmware: `>= 11.0, << 17.0`
- injection target: SpringBoard
- dependencies: ElleKit and PreferenceLoader

## Project Layout

This is a horribly AI coded sloppy mess and I am only here to add support for iOS 15 through 17. Support for iOS 11 through 14 is not known yet, therefore you are encouraged to test.
What's so hard about adding support for iOS 15 anyway? I managed to do it just by changing the target firmware.
Tested on iPhone X running iOS 16.7.15, iPhone 7 Plus running iOS 15.8.3 as well as iPhone 6s running iOS 15.8.8
- `Tweak.xm` contains 13 thousand fucking lines of AI coded SpringBoard hooks, layout engine, edit mode, add sheet, and module presentation logic that could either crash or horribly lag out devices. 
- `prefs/` contains the PreferenceLoader bundle.
- `scripts/` contains local device/testing helpers.

Generated build output, package artifacts, screenshots, and diagnostics are intentionally ignored by git.

## COSMIC Kit

CCAster can work with [COSMIC Kit](https://github.com/MoarTweaks/COSMICKit), a companion package for optional Control Center modules.

The split is intentional:

- CCAster owns the Control Center experience: layout, editing, add sheet, paging, resize behavior, and runtime integration.
- COSMIC Kit owns optional module bundles that can be installed independently from the CCAster core.

The first COSMIC Kit split moved the extra connectivity module bundles out of the CCAster package while preserving their existing bundle identifiers. This keeps current CCAster runtime handling and saved layouts stable while giving future modules a cleaner home.

Future work can make the CCAster add sheet COSMIC-aware, including support for module families, duplicate-capable modules, and dynamically generated module instances with unique Apple-facing identifiers.
