# OpenTab

A free, open-source, MIT-licensed **AltTab-style window switcher for macOS**.
Hold <kbd>⌥ Option</kbd> and press <kbd>⇥ Tab</kbd> to cycle through your open
windows; release Option to focus the highlighted one.

> Status: **v0.1** — core switching, a settings window, view modes and a
> rebindable shortcut work. Live thumbnails and the remaining scopes are on the
> roadmap below.

## Features

Working now:
- Global window cycling — default <kbd>⌥</kbd>+<kbd>⇥</kbd> forward, <kbd>⌥⇧</kbd>+<kbd>⇥</kbd> backward
- Raises the exact window (not just the app) via the Accessibility API
- HUD panel with app icon + window title per entry
- **Settings window** (menu bar → Settings…, or <kbd>⌘</kbd>+<kbd>,</kbd>):
  - **View mode** — app grid, list, or one entry per app
  - **Scope** — all screens or active screen
  - **Rebindable shortcut** — record any modifier + key combo
- Menu-bar item, no Dock icon

Roadmap:
- Live window thumbnails
- `activeSpace` scope + `appOnly` collapsing
- Minimized / hidden-window inclusion
- Fuzzy search while the switcher is open

## Build from source

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

```bash
git clone https://github.com/socraft/opentab.git
cd opentab
make run          # builds OpenTab.app and launches it
```

Other targets: `make build` (SPM only), `make app` (assemble the bundle),
`make clean`.

On first launch macOS will ask for **Accessibility** permission
(System Settings → Privacy & Security → Accessibility). Grant it, then relaunch.

## Install with Homebrew

Once a signed release is published:

```bash
brew install --cask socraft/tap/opentab
```

The cask lives in `Casks/opentab.rb`. To ship it: zip `OpenTab.app`, attach it
to a GitHub Release, then set `version` and `sha256` in the cask and push it to
a `homebrew-tap` repository.

## Architecture

| File | Responsibility |
|------|----------------|
| `main.swift` | App entry point, accessory (agent) activation policy |
| `AppDelegate.swift` | Permission check, hot-key + modifier-release wiring, menu bar |
| `HotKeyManager.swift` | Global hot keys via Carbon `RegisterEventHotKey` |
| `WindowManager.swift` | Enumerate windows (`CGWindowList`) and raise them (Accessibility) |
| `SwitcherController.swift` | Session state: build list, track selection, commit |
| `SwitcherPanel.swift` | The borderless HUD panel and its cells |
| `Preferences.swift` | Persisted settings: layout, scope, keybindings |

## License

MIT — see [LICENSE](LICENSE).
