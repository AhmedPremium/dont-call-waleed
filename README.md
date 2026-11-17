# Don't Call Waleed at 3 AM

An original first-person horror prototype for iPad (iPadOS 17+) and iPhone, in landscape. Built with Apple's SceneKit and UIKit. No network access, ads, accounts, tracking, or in-app purchases.

The opening follows Yamen through his lit house, lock screen, Phone app, recents, and the 3 AM call that cuts the power. You can skip it. The larger house has an east wing with a dining room, guest room, and sunroom. Each attempt varies the wing doorways and fuse locations.

Explore the Bedroom, Kitchen, Lounge, Study, Laundry and Workshop. Collect three cyan fuses, restore power at the red fuse box, and escape through the green door. Waleed patrols, gives chase on sight or sound, and searches the area around your last known position. His eyes glow red up close. Break his line of sight, then use a gold-handled cupboard to hide.

Move with the left joystick and drag the right side to look. Tap RUN above the movement stick to toggle sprint. USE interacts with nearby objects. The flashlight has a wide beam and recharges when switched off. Pause stops play, including when the app goes into the background.

CALL WALEED makes his phone ring in a nearby room and draws him toward it. HANG UP within four seconds to avoid being traced. SILENCE declines incoming calls before they draw him closer. The room name appears even with sound muted.

Collect optional notes to learn what happened before the call. Loose floorboards can bring Waleed to you, while cupboards and the steel shelter offer cover. Unpredictable pipe sounds play in nearby rooms. Contains a 3D jumpscare with Waleed’s burp, sudden sounds and haptics. Sound can be disabled from the menu. Real-device rendering, touch feel, audio balance and a completed playthrough still need iPad testing.

## Build and installation

The existing iOS Build workflow compiles on a GitHub macOS runner and uploads an unsigned IPA. Download it from the completed run's Artifacts. It must be signed by your sideloading tool before installation; it is not an App Store or TestFlight build.

The build runs main.swift against the actual House.swift rules before compiling the app, verifying objective reachability, patrol routes, collision and line of sight. Swift Testing tests are also included for simulator runs.

The template's original MIT license is retained in LICENSE.

## Atmosphere

The VHS menu uses the empty hallway artwork and the supplied VCR OSD Mono font. The kitchen fridge hums, the lounge television flickers, and occasional positional burps come from either Waleed or another room. Use headphones to hear the direction.
