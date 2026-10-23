# location UI component preview

This isolated app renders the **actual production SwiftUI components** listed in
`project.yml`, including `Theme`, map search, status, toolbar, pin, bottom controls,
route controls, and joystick. It uses an explicitly fictional map drawn by a
deterministic Canvas and small state doubles; it never links idevice or writes a
location. It is excluded from the production app because the main XcodeGen
configuration includes only the `Locus` source tree.

The preview is evidence for component appearance and layout on an iOS Simulator.
It is **not** evidence for the full app's navigation, live MapKit tiles, pairing,
VPN behavior, system location restoration, or real-device compatibility.

The `Render location UI preview` workflow builds with Xcode 26 and captures four
Simplified Chinese scenarios on an available iPhone and iPad running iOS 26:

- `idle`: selected pin and normal controls.
- `active-route`: synthetic active route at 38% progress.
- `large-type`: active route with the accessibility 2 text size.
- `reduced-transparency`: active route with solid accessibility surfaces.

All scenarios enable the simulator's reduced-motion preference for deterministic rendering. The simulator
system appearance is set to **dark** while the app specifies **light**, so the
screenshots also expose failures of the app's light appearance policy. The
large text size is injected into the SwiftUI environment. Reduce Transparency
and Reduce Motion are set through the simulator's Accessibility preferences and
the script verifies the actual values observed by the app before each screenshot.
An ignored preference, wrong language, or dark app appearance fails the run.
Hardware accessibility behavior remains a separate acceptance item.

The artifact contains PNG screenshots, Xcode build/render logs, and a JSON
manifest with the exact commit, simulator runtime/device, scenario, dimensions,
and image SHA-256. Review the pixels as well as the build result; successful
compilation alone does not establish visual quality.

On a Mac with Xcode 26, XcodeGen, and iOS 26 Simulator runtimes installed:

```sh
mkdir -p outputs/preview-project outputs/ui-preview
xcodegen generate --spec DesignPreview/project.yml --project outputs/preview-project
xcodebuild -project outputs/preview-project/LocationDesignPreview.xcodeproj \
  -scheme LocationDesignPreview -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath outputs/preview-build CODE_SIGNING_ALLOWED=NO build
python3 DesignPreview/render_simulator.py \
  --app outputs/preview-build/Build/Products/Debug-iphonesimulator/LocationDesignPreview.app \
  --output outputs/ui-preview
```
