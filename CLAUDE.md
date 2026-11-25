# SteamKit

Steam on this Mac: libraries, installed games, accounts, `steam://` links, the store's details and pictures, and
Valve's KeyValues text. Shared by Attic, Hangar, Starseed and Tadpole, and the next ones. A change here reaches every
app at its next package update, so keep the API stable and additive. `docs/MOVING.md` says what each app replaces.

Shared rules for how every project is laid out and named:
@~/.claude/project-layout.md

## Layout

- `Sources/SteamKit/` Foundation only, macOS only:
  - `Steam.swift`: `Steam(root:mapPath:)`, `defaultRoot`, `isInstalled`, `libraries`, `apps`, `games`, `app(id:)`,
    `app(installDir:)`, `installFolder(appID:)`, `installFolder(named:)`, `app(containing:)`; `SteamLibrary`.
  - `SteamApp.swift`: one appmanifest: fields, `isFullyInstalled`, `isUpdatePending`, `isSteamTool`, `macApp()`.
  - `SteamUser.swift`: `users`, `isSignedIn`, `lastSessionSignedOut`, `userdataFolder(s)`.
  - `SteamLink.swift`: `run`, `libraryPage`, `install`, `storePage`, `webStorePage`.
  - `SteamStore.swift`: `detailsURL`, `assetsURL`, `classicCoverURL`, `classicLogoURL`, `language(for:)`,
    `details(from:)`, `assets(from:)`, `releaseDate`.
  - `KeyValues.swift`: `parse`, `read`, subscript, `string`, `int`, `int64`, `pairs`, `setting`, `formatted`.
  - `SteamFixture.swift`: a fake Steam folder (`addLibrary`, `install`, `signIn`, `signOut`).
- `Tests/SteamKitTests/` Swift Testing, on fake Steam folders under `FileManager.default.temporaryDirectory`
  (`Scratch`, `FakeSteam`).
- `docs/MOVING.md` what each app drops and the behaviour to watch.

## Rules

- Every read goes through `Steam.root`; nothing reads ~/Library/Application Support/Steam unless asked to. Tests
  never touch the real Steam folder.
- Read only. SteamKit never writes into Steam's folders; `SteamFixture` writes only where it is told.
- Tolerant: a broken or half-written file gives what could be read, never a crash or a throw.
- No network and no strings shown to people: the app fetches and words things in its own languages.
- Reads happen on the caller's thread; the README says to call them off the main actor.
- Add a test for every change. `swift build && swift test` pass with no warnings, then CI on macOS.
- Release: tag `x.y.z` and push the tag; apps use `from:`.

## Git

Commit after each working change, with a message that says what an app can now do.
