# AGENTS.md

A native macOS desktop-pet app: a borderless floating panel with a pixel-art
dino that chats over the OpenCode Go API. SwiftPM executable, no Xcode project,
no SwiftUI `App`/`Scene`, no test target. `README.md` (in Portuguese) documents
the product; this file covers what an agent gets wrong.

## Build and run

```sh
./build-app.sh                  # release build into build/Dino.app
./build-app.sh release --run    # build, bundle, relaunch
```

- **`swift build` does NOT update `build/Dino.app`.** SwiftPM emits a bare
  binary; the `.app` (Info.plist, sprites, icon, codesign) is hand-assembled by
  `build-app.sh`. Editing code and re-running `open build/Dino.app` silently
  runs the old binary. Always `./build-app.sh` before launching.
- Run the bundled binary directly to keep the bundle and see stderr:
  `DINO_DEBUG=1 ./build/Dino.app/Contents/MacOS/Dino`
- `swift run` works for a quick compile check only: there is no bundle, so it
  falls back to the repo's `Resources/sprites`.

## Verifying changes (there is no test suite)

Use the headless flags instead of guessing:

```sh
./build/Dino.app/Contents/MacOS/Dino --selftest        # models + stream + one-shot (real API calls)
./build/Dino.app/Contents/MacOS/Dino --prompt          # prints the exact system prompt
./build/Dino.app/Contents/MacOS/Dino --render /tmp/out # widget + balloons + frames as PNGs
```

- `--render` **cannot draw `NSViewRepresentable` or text fields** (the frosted
  glass, the inputs): ImageRenderer emits yellow no-entry placeholders there.
  The transcript also renders empty because of its `GeometryReader`/`ScrollView`.
  Those are not bugs. Check layout/balloon geometry with `--render`, and glass
  and text on screen.
- `--selftest` spends a little of the user's OpenCode Go credits; don't loop it.
- `DINO_DEBUG=1` logs window chrome geometry and hit-testing (`verifyChrome`).

## You cannot click this app

`orca computer click/drag` returns `"ok": false` for this bundle — synthetic
input is never delivered. **Do not burn turns trying.** Verify interaction
deterministically instead:

- `DINO_DEBUG=1` hit-test logs prove the drag strip and resize grip are
  reachable *and* that they do not cover the header buttons.
- Verify the settings path through the menu, which calls the same
  `AppCommands.openSettings()` the gear button does:
  `osascript -e 'tell application "System Events" to tell process "Dino" to click menu item "Preferências…" of menu 1 of menu bar item "Dino" of menu bar 1'`
- Window geometry via System Events uses a **top-left origin**; AppKit frames
  are bottom-left. A saved `y` will look "wrong" by `screenHeight - y - height`.
- Anything that needs a real mouse or the microphone goes back to the user.

## Architecture traps

- **No SwiftUI `App`/`Scene`.** Entry point is `@main enum Main` calling
  `NSApplication.run()`. A SwiftUI `Settings` scene was removed: macOS opened it
  by itself at launch, and it could only be summoned through the private
  `showSettingsWindow:` selector. Settings is now a plain `NSWindow`
  (`SettingsWindow.swift`) that is opened directly. Don't bring the scene back.
- **Window chrome must be a sibling of the hosting view, not a subview.** The
  drag handle and resize grip live in a `WindowChromeLayer` next to
  `NSHostingView` inside a plain `NSView` container. Nested inside the hosting
  view they never receive clicks.
- **`NSView.hitTest` takes the point in the *superview's* coordinates.**
  Converting it again makes the chrome unreachable — that bug is why drag and
  resize did nothing for a long time.
- **`NSHostingView` is flipped** (origin top-left). `WindowChromeLayer`
  deliberately is not, so its positioning math stays bottom-left.
- The panel is a **`.nonactivatingPanel`**, so the app is not active. macOS
  dictation only targets the active app, so the app activates when the text
  field gains focus (`@FocusState` in `PetRootView`). Don't remove that.
- The panel floats above its own windows; `SettingsWindowController` raises
  itself with a higher window level.

## Sprites

`Resources/sprites/` is generated, not hand-edited. The source sheets are not
kept in the repo; the user holds them. Regenerate with:

```sh
python3 tools/slice_sprites.py ~/Downloads/dino-breathing.png Resources/sprites --report --preview
```

- `idle_1..idle_N.png` is **one whole breath, in sheet order**: first and last
  are the same resting pose, the fullest frame is in the middle. The app ramps
  the sheet up and back down and loops it. A new sheet must keep that shape.
- Frames are split on **blank columns**, not by aspect ratio (a 5-frame and a
  3-frame sheet can be the same width). Frames are re-anchored on the **feet**
  because ChatGPT drifts each frame sideways; verify anchoring by checking every
  frame's lowest ink row is identical.
- `blink.png` is generated too (largest compact dark blob in the head = the eye,
  covered with skin colour plus a painted lid). It is drawn only during the
  empty-lung pause, where the pose is still and the overlay lines up.
- **Never cross-fade the frames.** They are independent drawings, so blending
  ghosts. Swap them dry, as pixel art expects.
- Don't drive the breath with `scaleEffect`/`offset`: the frames already inflate
  from planted feet, and moving the sprite lifts its feet off the ground.
- `tools/` is deliberately dependency-free (no Pillow, no ImageMagick);
  `tools/pngtool.py` is a hand-rolled PNG codec. Don't add deps.

## Conventions

- Code and comments are **English**; all user-facing strings and the personality
  prompt are **pt-BR**.
- Toolchain is `swift-tools-version: 6.0` but **Swift 5 language mode**
  (`swiftLanguageModes: [.v5]`) on purpose. Don't "fix" concurrency warnings by
  moving to v6. macOS 15 only because of `NSCursor.frameResize`.
- The system prompt is **fixed** in `Sources/Dino/Personality.swift`; there is
  deliberately no UI to edit it. Verify with `--prompt`, don't re-add a setting.
- API key lives in `~/Library/Application Support/Dino/secrets.json` (`0600`),
  not Keychain: ad-hoc signing gives a new identity every rebuild, so Keychain
  would re-prompt each time. The app was once called DinoWidget;
  `LegacyCleanup.swift` removes those leftovers — don't reintroduce the name.
- `OpenCodeGo.swift` must keep its custom `User-Agent` and the per-conversation
  `x-opencode-session` header; the Go endpoint rejects requests without them.

## Editing UserDefaults

`defaults write` while the app is running gets clobbered when it exits
(cfprefsd caching), and writing the plist with `plistlib` is ignored for the
same reason. Kill the app first, then use `defaults`. The frame reader in
`PetWindow.swift` tolerates strings as well as numbers, because `defaults write`
with an old-style plist stores numbers as strings.
