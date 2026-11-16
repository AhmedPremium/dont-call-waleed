# Don't Call Waleed at 3 AM

An original first-person horror prototype for iPad (iPadOS 17+) and iPhone, in landscape. Built with Apple's SceneKit and UIKit. No network access, ads, accounts, tracking, or in-app purchases.

Explore six rooms, collect three cyan fuses, restore power at the red fuse box, and escape through the green door. Waleed patrols and investigates your ringing phone and running footsteps. Break his line of sight, then use a gold-handled cupboard to hide. The flashlight recharges when switched off. Hold RUN to sprint; release it to recover stamina.

Left joystick moves. Drag the right side to look. USE collects, hides, operates the fuse box, or opens the exit. SILENCE declines an incoming call. Pause stops the game; switching apps pauses automatically. Sound can be disabled from the menu.

This is a first playable alpha, with original procedural geometry, app icon and synthesized audio. Contains jumpscares. Rendering and touch feel require real iPad testing. Cloud compilation and map validation do not establish device performance or a completed playthrough.

## Build and installation

The existing iOS Build workflow compiles on a GitHub macOS runner and uploads an unsigned IPA. Download it from the completed run's Artifacts. It must be signed by your sideloading tool before installation; it is not an App Store or TestFlight build.

The build runs main.swift against the actual House.swift rules before compiling the app, verifying objective reachability, patrol routes, collision and line of sight. Swift Testing tests are also included for simulator runs.

The template's original MIT license is retained in LICENSE.

## Menu and audio update

The menu uses an empty haunted hallway (no female figure), the user-supplied VCR OSD Mono font, and a red 3 AM subtitle. Three original synthesized burp variants play at random room positions every 10–24 seconds, starting after 9 seconds. They pause and mute with the game. Positional playback uses the camera as the audio listener. Real-device audio and rendering remain unverified.
