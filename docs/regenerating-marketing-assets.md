# Regenerating screenshots and the demo video

Both are produced by driving the app under XCUITest on a simulator, where
`FixtureSleepStore` stands in for HealthKit. Re-run them after UI changes that
alter what a reviewer sees.

Budget **about 15 minutes** for both, most of it waiting on builds. The first
time these were built took far longer, entirely in working out the constraints
below — they are written down so nobody has to rediscover them.

## The two commands

```bash
./Scripts/capture-screenshots.sh
```

App Store screenshots at the exact pixel sizes App Store Connect requires, into
`fastlane/screenshots/en-US/`. Three device sizes, roughly 3 minutes each.

Pass `-skip-testing:SleepDaddyScreenshots/DemoWalkthrough` to its `xcodebuild
test` invocation if it isn't there already — otherwise this pass also runs the
75-second demo walkthrough once per device for nothing.

```bash
./Scripts/record-demo.sh
```

The App Review demo video, into `web/demo/sleepdaddy-demo.mp4`. Around 5 minutes.
Prints the detected walkthrough bounds; expect roughly 70 seconds of content.

Then refresh the poster frame, which is just a frame of the new video:

```bash
ffmpeg -y -i web/demo/sleepdaddy-demo.mp4 -ss 3.5 -frames:v 1 -map_metadata -1 -q:v 3 web/demo/poster.jpg
```

## Checking the result

The walkthrough asserts on every control it touches, so a renamed accessibility
label fails the run rather than quietly dropping a section. What it cannot catch
is the recording looking wrong. Check that with a contact sheet:

```bash
ffmpeg -y -i web/demo/sleepdaddy-demo.mp4 -vf "fps=1/3,scale=-2:340,tile=7x4" -frames:v 1 /tmp/contact.png
```

Every numbered section of `SleepDaddyScreenshots/DemoWalkthrough.swift` should be
visible, and neither end should show the home screen.

Also confirm the video is constant frame rate and a sane length:

```bash
ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate,width,height -show_entries format=duration -of default=nw=1 web/demo/sleepdaddy-demo.mp4
```

Expect `30/1`, `588x1280`, and roughly 70 seconds.

## Constraints worth knowing before changing anything

**`simctl io recordVideo` writes a frame only when the screen changes.** Twenty
seconds of an idle simulator records as a single frame. Three things follow, and
`Scripts/record-demo.sh` is shaped around all of them:

- The capture is variable frame rate and stutters until resampled, hence
  `-vf fps=30 -fps_mode cfr`.
- Its duration is not elapsed time, so the springboard cannot be trimmed off
  either end by the clock. The script finds the app by picture instead: mean
  saturation via `signalstats` separates the home-screen wallpaper (~12.5) from
  every screen of the app (~2.9) and its white loading screen (~0.05).
- Wall-clock marks taken during the run cannot be mapped onto video time. This
  was tried anchored to both the start and the stop of the recording; both
  drifted non-linearly, up to four seconds. **The video has no chapter marks and
  should not grow any** without solving that first.

**The demo is portrait only.** A device recording keeps the display's native
orientation, so rotating mid-run produces a sideways segment. Landscape is a
still on the demo page instead.

**`sips --rotate` writes an EXIF orientation tag as well as rotating pixels.**
Decoders that honour it — browsers, ffmpeg — then rotate a second time and show
landscape captures as portrait, while `sips -g pixelWidth` and `ffprobe` report
the correct dimensions and hide the problem. Strip the PNG's `eXIf` chunk before
converting anything for the web.

**Keep the demo page in step.** The numbered list in `web/demo.html` mirrors the
numbered sections of `DemoWalkthrough.swift` and is the only navigation a viewer
gets. Reorder or add a step in the test and the page has to follow.

## Environment gotchas

The iOS Simulator MCP tools cannot attach under Xcode 27 — they look for
`SimulatorKit.framework` at a path that no longer exists — so there is no live
panel and no MCP tap/swipe. Drive the simulator with XCUITest, which is what both
scripts already do.

The ffmpeg installed here has no `drawtext`, `subtitles`, or `ass` filter, so
burned-in captions are not an option. `signalstats`, `blackframe`, `freezedetect`
and `scdet` are available.
