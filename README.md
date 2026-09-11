# DynamicArch

A dynamic island for macOS. The notch stops being dead space and becomes the
place where media, system state, files, and your schedule live.

Built natively in Swift and SwiftUI, no Xcode required: the whole app, its
helper, its icon, and its signature are produced by `Scripts/build.sh`.

## Features

**Media** - Now Playing from *any* app (Music, Spotify, Safari, Chrome, VLC,
IINA, QuickTime), with artwork, an artwork-derived accent, a scrubbable
progress bar, shuffle/repeat, and a live waveform. Swipe across the notch to
change track, scroll down to open.

**Live activities** - Volume, brightness, and keyboard backlight replace the
system HUD and animate around the camera housing. Charger connect/disconnect,
low-battery thresholds, Bluetooth and AirPods connections, output-device
changes, and timers all surface the same way, with priority and coalescing so
two events never fight over the island.

**File shelf** - Drag anything onto the notch: files, images, selected text,
links. Items are copied into the app's own storage, so they keep working after
the original moves; drag them back out one at a time or as a stack, AirDrop
them, Quick Look them, or convert them (image formats, PDF, audio extraction,
video transcode) without leaving the island.

**Clipboard history**, **calendar**, **weather**, **camera mirror**,
**Shortcuts runner**, and **timers** each get a tab.

**Notifications and calls** - With Accessibility access granted, banners are
mirrored into the island, and incoming calls take it over with working
Accept/Decline buttons driven through the banner's own controls.

## Build

```sh
./Scripts/make-signing-identity.sh   # once: stable signature keeps TCC grants
./Scripts/build.sh release run       # build, bundle, sign, launch
```

Requires the Xcode Command Line Tools and macOS 15 or later. The result is
`build/DynamicArch.app`.

## How it works

**Window.** One `NSPanel` per active display, `.nonactivatingPanel` at level
`.mainMenu + 3`, joining all spaces and full-screen auxiliary. The panel is
*fixed size* for the lifetime of the display and the island animates inside it;
resizing a window per frame is what makes notch apps stutter, because every
resize recreates the window-server backing store. Hit testing is explicit: the
stage view returns `nil` for every point outside the island's current shape, so
menu-bar clicks fall straight through.

**Geometry.** The cutout is measured from `NSScreen.auxiliaryTopLeftArea` and
`auxiliaryTopRightArea` rather than guessed, so the resting island matches the
hardware exactly and is invisible when idle. Displays without a notch get a
synthesised pill of the same proportions.

**Media.** macOS 15.4 restricted `MediaRemote.framework` to Apple platform
binaries. `Helper/archmedia.pl` is loaded by `/usr/bin/perl` - which *is* a
platform binary - and pulls in `ArchMediaBridge.dylib`, which streams
newline-delimited JSON to the app and accepts commands on stdin. Unlike the
one-shot helpers other apps use, the bridge is long-lived and bidirectional, so
a play/pause tap costs a pipe write instead of a process spawn. If the route
ever closes, the app falls back to AppleScript for Music and Spotify.

**Motion.** Every transition draws from one spring vocabulary in
`Design/Motion.swift`, tuned for 120 Hz: expand bounces slightly, collapse does
not, content crossfades faster than the shell moves. The island silhouette is a
single animatable `Shape` with inverted top corners and continuous-curvature
bottom corners, so the morph is one interpolated path rather than a stack of
overlapping views.

**Permissions.** Nothing is requested at launch. Calendar, location, camera,
and Accessibility are asked for at the moment you turn the matching feature on,
and every one of them degrades to a visible "off" state rather than failing
silently.

## Layout

```
Sources/DynamicArch
  App/          entry point, services lifecycle, menu bar, launch at login
  Core/         screen geometry, panel + stage view, pointer and event input
  Design/       motion, palette, island shape, haptics
  State/        island state machine, activity queue, preferences
  Features/     media, shelf, HUD, power, bluetooth, clipboard, calendar,
                weather, timer, camera, shortcuts, notifications
  UI/           island views and components
  Settings/     settings window
Helper/         MediaRemote bridge (perl loader + Objective-C dylib)
Scripts/        build, signing identity, icon generation
```
