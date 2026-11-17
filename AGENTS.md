# Don't Call Waleed at 3 AM

Brother Studios' first-person horror game for landscape iPad and iPhone. The app runs on iOS/iPadOS 17 or later. SwiftUI hosts a UIKit view controller, and SceneKit renders the house. Gameplay is offline.

## Start here

- The active gameplay branch is `gameplay-ipa-update`. Check it out before working on the game.
- `project.yml` defines the `DontCallWaleed` app and test targets. XcodeGen generates the project from that file. Keep edits to target membership, bundled assets, and build settings in the YAML.
- The baseline for this handoff is **0.5.0 (build 15)**. Check `VERSION` and the version settings in `project.yml` when packaging a new release.

## Code map

| File | Where to work |
| --- | --- |
| [AppNameApp.swift](AppNameApp.swift), [ContentView.swift](ContentView.swift) | App entry point and bridge to the UIKit game controller. |
| [GameController.swift](GameController.swift) | Menu and HUD, controls, scene construction, interactable objects, chase AI, dialogue and sound, and cutscene playback. |
| [House.swift](House.swift) | Seeded house layout, wall-aligned cupboard locations, navigation and collision, opening and garden coordinates, story progression, and escape timing. |
| [OpeningScene.swift](OpeningScene.swift) | Bedroom, stairs, foyer, front door and bolt, and the rainy garden. Coordinate changes here also affect `OpeningLayout` in `House.swift`. |
| [IntroPhoneView.swift](IntroPhoneView.swift), [DocumentReader.swift](DocumentReader.swift) | Phone graphics and the in-game note reader. |
| [HouseMaterials.swift](HouseMaterials.swift), [WaleedMesh.swift](WaleedMesh.swift) | Procedural materials and Waleed's mesh geometry. |
| [main.swift](main.swift), [HouseTests.swift](HouseTests.swift) | Standalone logic checks run during the iOS build, plus Swift Testing tests for the simulator. |

## Current gameplay

1. Yamen calls Waleed at 3 AM and answers the knock at the front door. The garden is empty and raining. Yamen closes the door, then the house lights go out.
2. The player reopens the front door and resets the outdoor service breaker. Yamen spots Waleed in the garden, then must sprint inside and bolt the door.
3. The lounge TV plays a voiced, captioned emergency bulletin. Three of the nine wall-aligned cupboards contain fuses. The locations and utility doorways can vary by layout seed.
4. Install the fuses at the red security panel, take the service key from the study, reset both the kitchen and laundry relays, then use the study console to unlock the back exit.
5. The ending plays after Yamen leaves the house. **The End** becomes **The End?**, followed by **Yamen and Waleed will be returning**.

Crouching reduces movement noise and detection range. Waleed can still spot and catch a crouched player at close range. If changing the opening, preserve the handoff back to player control. If moving a prop, keep its visual geometry and collision footprint aligned, and check the paths across layout seeds.

## Build and verify

On macOS with Xcode and XcodeGen installed, run these from the repo root:

```sh
xcodegen generate
xcodebuild -project DontCallWaleed.xcodeproj -scheme DontCallWaleed -showdestinations
```

Select an installed iPad simulator from the destination list and use its ID:

```sh
xcodebuild test -project DontCallWaleed.xcodeproj -scheme DontCallWaleed \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' CODE_SIGNING_ALLOWED=NO
```

To run the layout and story checks independently of the iOS simulator:

```sh
check_dir="$(mktemp -d)"
xcrun --sdk macosx swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  House.swift main.swift -o "$check_dir/house-check"
"$check_dir/house-check"
```

[iOS Build (Unsigned IPA)](.github/workflows/ios-build.yml) produces an IPA artifact for sideloading. Download the artifact for the commit you tested and sign the IPA with the sideloading tool before installing. [Unit Tests (Simulator)](.github/workflows/tests.yml) runs the simulator checks. Use the exact commit SHA when checking results.

The 0.5.0 IPA build and simulator suite passed. The automated checks cover reachability, story order, both relay requirements, crouch detection, and scene construction. An iPad playthrough is still pending for touch controls, visual polish, speech, and audio balance.
