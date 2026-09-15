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
system HUD and animate around the camera housing. Bluetooth and AirPods
connections, output-device changes, and timers surface the same way, with
priority and coalescing so two events never fight over the island.

**Battery** - Plugging in plays a charging animation: the battery fills to the
real charge level with a highlight travelling along it, a pulsing bolt, and a
green bloom, alongside the time to full. Below a threshold you choose
(default 20 %) the island warns with an amber, breathing battery and the time
remaining, then once more in red at a quarter of that level. Hysteresis keeps a
battery hovering on the line from warning twice.

**Gestures** - Two-finger swipe across the open island pages between sections,
with the content sliding in from the direction of travel; swipe on the resting
island to change track, scroll down to open, up to close.

**File shelf** - Drag anything onto the notch: files, images, selected text,
links. Items are copied into the app's own storage, so they keep working after
the original moves; drag them back out one at a time or as a stack, AirDrop
them, Quick Look them, or convert them (image formats, PDF, audio extraction,
video transcode) without leaving the island.

**Running apps** - Every app with its live CPU and memory, sorted by weight,
with hung apps flagged as *Not responding*. Quitting is graceful by default, so
macOS still offers to save your work; **Force quit** is a separate action that
always confirms and warns harder when the target is healthy, because killing a
working app is how data gets lost. System-critical processes can never be
force-quit, any app can be shielded from bulk actions, **Quit All** is staggered
so fifty apps do not throw fifty save dialogs at once, and idle apps can be
quit automatically after a period you choose - always by the graceful path.

**Clipboard history**, **calendar**, **weather**, **camera mirror**,
**Shortcuts runner**, and **timers** each get a section.

**Notifications and calls** - With Accessibility access granted, banners are
mirrored into the island, and incoming calls take it over with working
Accept/Decline buttons driven through the banner's own controls.

## Themes

Three looks, switchable live in Settings → Appearance:

- **Dark** - black chrome that is indistinguishable from the bezel, so the
  island vanishes when idle.
- **Light** - bright chrome with dark text for light desktops.
- **Glass** - the Dock's own material: a behind-window blur of the desktop and
  windows underneath, a scrim for density, and a single hair of light around
  the edge. Nothing is added on top, which is why it reads as a pane rather
  than a glowing panel - the island simply takes on whatever is behind it.

At rest the island is flat black on every theme, so it still disappears into
the bezel instead of outlining an empty notch.

## Build

```sh
./Scripts/make-signing-identity.sh   # once: stable signature keeps TCC grants
./Scripts/build.sh release run       # build, bundle, sign, launch
```

Requires the Xcode Command Line Tools and macOS 15 or later. The result is
`build/DynamicArch.app`.

Note: the macOS 27 Command Line Tools declare SwiftUI's `@State` and friends as
macros whose plugin ships only inside Xcode. `build.sh` detects that and falls
back to the newest installed SDK that still has a working macro plugin, so a
CLT-only machine keeps building.

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
