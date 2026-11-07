# location UI component preview

This isolated app renders the **actual production SwiftUI components** listed in
`project.yml`, including `Theme`, map search, status, toolbar, pin, pending-target
card, pinned actions, bottom controls, route controls, joystick, connection-guide
policy and guide sheet. It uses an explicitly fictional map drawn by a
deterministic Canvas and small state doubles; it never links idevice or writes a
location. It is excluded from the production app because the main XcodeGen
configuration includes only the `Locus` source tree.

The preview is evidence for component appearance and layout on an iOS Simulator.
It is **not** evidence for the full app's navigation, live MapKit tiles, pairing,
VPN behavior, system location restoration, MapKit camera behavior, or real-device
compatibility. The synthetic target is placed at the center of the space between
the measured top and bottom controls to illustrate the layout only.

The `Render location UI preview` workflow builds with Xcode 26 and captures seven
Simplified Chinese scenarios on an available iPhone and iPad running iOS 26
(14 images total):

- `idle`: a named pending target with a demonstration address and normal controls.
- `active-route`: synthetic active route at 38% progress; the active coordinates
  deliberately differ from those in the pending-target card.
- `large-type`: active route with the accessibility 2 text size.
- `reduced-transparency`: active route with solid accessibility surfaces.
- `guide-pairing`: the real guide sheet in its missing-pairing state.
- `guide-restoration`: the real guide sheet in its unconfirmed-restoration state.
- `compact-height`: real map chrome at accessibility 2 text size in a
  **320-point-high container**, exercising the pinned-Stop fallback and explicitly
  labeled as a constrained component preview. It is not a landscape device or
  keyboard interaction test.

Guide actions are explicit no-op callbacks. Other fixture interactions only
change in-memory fake UI state; they never start pairing, request a connection,
write a device location, or save real favorites. The production state controller
and native transport are excluded from this target.

All scenarios enable the simulator's reduced-motion preference for deterministic rendering. The simulator
system appearance is set to **dark** while the app specifies **light**, so the
screenshots also expose failures of the app's light appearance policy. The
large text size is injected into the SwiftUI environment. Reduce Transparency
and Reduce Motion are set through the simulator's Accessibility preferences and
the script verifies the actual values observed by the app before each screenshot.
It waits up to 90 seconds for readiness, including nonzero chrome measurements
for map scenarios, then waits three seconds and re-reads the settled environment.
It also checks guide topics, the separation of active and pending coordinates,
and positive remaining map height in the constrained scenario.
An ignored preference, wrong language, or dark app appearance fails the run.
Hardware accessibility behavior remains a separate acceptance item.

The artifact contains PNG screenshots, Xcode build/render logs, and a JSON
manifest with the exact commit, simulator runtime/device, scenario, dimensions,
and image SHA-256. Review the pixels as well as the build result; successful
compilation alone does not establish visual quality.

On a Mac with Xcode 26, XcodeGen, and iOS 26 Simulator runtimes installed:

```sh
mkdir -p outputs/ui-preview
(cd DesignPreview && xcodegen generate)
xcodebuild -project DesignPreview/LocationDesignPreview.xcodeproj \
  -scheme LocationDesignPreview -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath outputs/preview-build CODE_SIGNING_ALLOWED=NO build
python3 DesignPreview/render_simulator.py \
  --app outputs/preview-build/Build/Products/Debug-iphonesimulator/LocationDesignPreview.app \
  --output outputs/ui-preview
```
