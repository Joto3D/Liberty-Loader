# Liberty Loader

A native macOS launcher for **Helldivers 2** running through **CrossOver**. One window to:

- **Launch** the game through Steam in your CrossOver bottle (auto-detected).
- **Install mods** by dragging in a `.zip`, `.7z` or `.rar` (Nexus Mods downloads work as-is,
  including mods made for HD2 Mod Manager with `manifest.json` variants).
- **Tune performance** with presets matched to your Mac, plus CrossOver bottle settings
  (D3DMetal/DXVK, MSync/ESync, Metal FPS overlay).

Also included:

- **Nexus Mods integration**: the "Mod Manager Download" button installs mods directly, and
  mod updates are checked against Nexus (needs your personal API key, set in Settings).
- **Mod profiles**: save and switch between mod setups ("Cosmetics only", "Everything").
- **Mod previews**: icons from `manifest.json` or the Nexus preview picture.
- **Custom performance presets** and a **High Resolution (Retina) Mode** switch.
- **Menu bar icon** with launch, force quit and profile switching.
- **Playtime tracking** and a **stuck-launch helper** that offers to force quit and retry.
- **In-app updates** from GitHub Releases.
- **Mod browser**: trending, new and updated Helldivers 2 mods from Nexus Mods, with search.
- **Galactic War**: live Major Order and planet liberation from the community API (api.helldivers2.dev).
- **Setup assistant** for first launch, a **crash helper** with one-click fixes, and a **Discord status**
  (Liberty Loader's Discord application is built in; it can be overridden in Settings).
- A custom app icon, drawn by `scripts/make_icon.swift` at build time.

The interface uses a dark Helldivers-style theme and is available in **English and German**
(it follows your Mac's language).

**Website:** https://joto3d.github.io/Liberty-Loader/

## Requirements

- macOS 14 Sonoma or newer (Apple Silicon recommended)
- CrossOver 24 or newer, with Steam installed in a bottle and Helldivers 2 downloaded

## Build & run

```sh
swift run LibertyLoader          # run from source
swift test                       # unit tests for the core library
scripts/bundle.sh --dmg          # build "build/Liberty Loader.app" and a .dmg
```

Or open `Package.swift` in Xcode and run the `LibertyLoader` scheme.

## How it works

### Finding the game
Bottles are scanned in `~/Library/Application Support/CrossOver/Bottles`. Each bottle's Steam
install (`drive_c/Program Files (x86)/Steam`) and any extra libraries listed in
`steamapps/libraryfolders.vdf` are checked for `steamapps/common/Helldivers 2`.

### Launching
```
CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine --bottle <bottle> \
  "C:\Program Files (x86)\Steam\steam.exe" -applaunch 553850 [launch options]
```
Going through Steam keeps login and anti-cheat working. Mods are synced to the game folder
right before launch. **Force Quit Bottle** runs `wineboot --kill` for stuck sessions.

### Mods
Helldivers 2 mods are patch files in `Helldivers 2/data`: `<hash>.patch_<n>` plus optional
`.gpu_resources` / `.stream` files. Higher numbers override lower ones.

- Mods are kept in `~/Library/Application Support/LibertyLoader/mods`, never edited in place.
- On sync, every enabled mod gets the next free `patch_<n>` per hash in **load order**
  (lower in the list = higher priority), with its sibling files kept on the same number.
  Two mods changing the same file are flagged as overlapping.
- Liberty Loader records the files it deploys and only ever removes those. Patches from other
  tools are left alone and keep their slots.
- When Steam updates the game (build id changes), you're warned and can disable all mods in one
  click — game updates frequently break mods.

### Performance
- **Presets** (Max Performance / Balanced / Quality) edit `user_settings.config` in the bottle's
  `AppData/Roaming/Arrowhead/Helldivers2`. Only keys already in your file are changed and the
  rest of the file is preserved byte-for-byte; keys that aren't present are skipped and listed.
  Every key in the file is also editable under **All Game Settings**.
- **Bottle settings** are written to the bottle's `cxbottle.conf` `[EnvironmentVariables]`:
  `CX_GRAPHICS_BACKEND`, `WINEMSYNC`, `WINEESYNC`, `MTL_HUD_ENABLED`.
- A backup is taken before every change. The first backup of each file is kept forever, so
  **Restore Original Settings** always returns to how things were before Liberty Loader.

### Releases & updates
Push a tag such as `v0.2.0` (or run the Release workflow from the Actions tab with a version); it builds and publishes `LibertyLoader.dmg`
(new installs) and `LibertyLoader.zip` (used by the built-in updater). The app checks
`releases/latest` on launch and can replace itself and relaunch. Builds are ad-hoc signed, so
macOS shows a Gatekeeper prompt on first launch (System Settings → Privacy & Security → Open Anyway).

### Translations
UI text lives in `Localization/{en,de}.lproj/Localizable.strings`. After changing text in the
code, run `scripts/gen_strings.py` (add German text to `scripts/de_translations.py` for anything
it reports). CI runs `scripts/check_strings.py` to catch missing translations.

### Website
`site/` is a static page (HTML/CSS/JS, English + German) deployed to GitHub Pages by
`.github/workflows/pages.yml` on every push to `main` that touches it. Pages: home, `mods.html`
(gallery from `site/data/mods.json`, refreshed daily by `.github/workflows/mods-data.yml` when the
`NEXUS_API_KEY` repository secret is set) and `news.html` (release notes from the GitHub API). Preview locally with
`python3 -m http.server -d site`.

### Mods don't show up in game?
Open **Mods → Diagnose**. It checks every mod against the game folder and explains, per mod, if
files were never copied (start the game from Liberty Loader or press **Apply Now**), if the mod is
outdated (the game archive it patches no longer exists), if its variant is empty, if a later mod
overrides it, or if it needs another Nexus mod (shown as **Needs …**, installable with one click).

## Project layout

```
Sources/LibertyCore      platform-independent logic (bottles, launching, mods, configs, backups)
Sources/LibertyLoader    SwiftUI app (Play, Mods, Performance, Settings; Theme/ holds the design system)
Localization             English and German UI text
site                     GitHub Pages website
Tests/LibertyCoreTests   unit tests using fake bottle trees
scripts/bundle.sh        .app / .dmg packaging
```

## Notes

- The preset key names in `Sources/LibertyCore/Performance/Presets.swift` must match the keys
  Helldivers 2 writes; if a game update renames them, they show up as "skipped" in the app.
- Mods are used at your own risk. Arrowhead tolerates cosmetic mods, but anything that changes
  gameplay can get you kicked or banned.
