# Moving the apps onto SteamKit

What each app replaces, what it keeps, and the behaviour that changes. One app per commit; run the app's own
tests, self-test and snapshots after. Tests in each app that only checked parsing move here; tests of the app's own
rules stay. Line numbers are from 2026-11-25.

Where to add the package: Attic in `AtticKit/Package.swift` (the AtticEmulation target), Hangar in `Package.swift`
(HangarKit), Starseed in `ModManagerCore/Package.swift` (ModManagerCore), Tadpole in `TadpoleCore/Package.swift` or
`project.yml` (only the app target uses it).

## Where each copy came from

| SteamKit | Attic | Hangar | Starseed |
| --- | --- | --- | --- |
| `KeyValues` | `VDF` (internal) | `KeyValues` | line splitting in `SteamGameState.parse`, `GameLocator.steamLibraries` |
| `Steam.defaultRoot` | `SteamLibrary.defaultSteamFolder` | `LibraryRoots.live` (`support/Steam`) | `GameLocator.steamFolder`, `AppConstants.defaultSteamModsURL` |
| `Steam.libraries()` | `libraryFolders`, private `libraries` | `SteamScanner.libraryFolders(steamRoot:mapPath:)` | `GameLocator.steamLibraries(inVDF:)` |
| `Steam.games()` / `apps()` | `installedGames`, `installedGame(manifest:steamapps:)` | `SteamScanner.manifests(in:)`, `Manifest`, `tools` | |
| `Steam.app(containing:)`, `isUpdatePending` | | | `SteamGameState.read(gameFolder:)`, `parse` |
| `SteamApp.macApp()` | `hasMacApp` | `Launcher.macApp(in:)` | |
| `isSignedIn`, `lastSessionSignedOut` | | `SteamScanner.isSignedIn`, `lastSessionSignedOut` | |
| `SteamLink.run` | `SteamLibrary.runURL` | `Launcher` (`"steam://rungameid/…"`) | `AppModel` (`"steam://rungameid/…"`) |
| `SteamLink.libraryPage` | | | `AppModel+Updates` (`"steam://nav/games/details/…"`) |
| `SteamLink.webStorePage` | | `GameLinks.store(steamID:)` | |
| `SteamStore` | `SteamStore.detailsURL`, `assetsURL`, `assets(from:)`, `releaseDate`, `classicLogoURL`, part of `details(from:)` | `SteamArt.assetsURL`, `assets(from:)`, classic cover URL; `SteamDetails.url`, `language(for:)`, part of `parse` | |

The best of each copy is what SteamKit keeps: Attic's parser that tells a quoted `"}"` from a brace and its
one-game-per-ID rule, Hangar's tolerance of stray braces and non-UTF-8 bytes, its Steam-tool list, its `mapPath`
for bottles and its sign-in check, Starseed's update-waiting rule and its search from a game folder.

## Attic (`AtticKit/Sources/AtticEmulation/`)

**`SteamLibrary.swift`**

| Drop | Use |
| --- | --- |
| `enum VDF` (all of it, lines 176–272) | `KeyValues`: `.object` is `.block`, `.string` stays `.string`, `VDF.parse` is `KeyValues.parse` |
| `defaultSteamFolder` | `Steam.defaultRoot` |
| `libraryFolders(steamFolder:)` | `Steam(root:).libraries().filter(\.isReachable).map(\.folder)` |
| `installedGames(steamFolder:)` | `Steam(root:).games().filter { $0.macApp() != nil }`, mapped to `InstalledGame(appID: $0.id, title: $0.name, folder: $0.folder)` (or make `InstalledGame` a typealias of `SteamApp`) |
| `installedGame(manifest:steamapps:)` | `SteamApp(manifest:library:)` + `isFullyInstalled` |
| `hasMacApp(_:)` | `SteamApp.macApp(in:) != nil` |
| private `Library`, `libraries(steamFolder:)` | `steam.libraries()`; the unreachable app IDs are `libraries().filter { !$0.isReachable }.flatMap(\.apps.keys)` |
| `runURL(appID:)` | `SteamLink.run(appID:)` |

Keeps (Attic's own): `shortcutExtension`, `appID(shortcut:)`, `installedGame(shortcut:steamFolder:)`,
`syncShortcuts`, `fileName`. Keep the `steamFolder:` parameters but pass a `Steam` (or its root) through.

**`SteamStore.swift`**: drop `detailsURL`, `assetsURL`, `assets(from:)`, `releaseDate`, `classicLogoURL`; use
`SteamStore.detailsURL(appID:language: "english")`, `SteamStore.assetsURL(appID:)`, `SteamStore.assets(from:)`
(`.cover`, `.hero`, `.logo`), `SteamStore.releaseDate`, `SteamStore.classicLogoURL`. Attic's `details(from:)`
becomes a mapping from `SteamStore.Details`: `plainText(shortDescription)`, developers and publishers joined with
", ", `genres` joined, `releaseDate`, `players(categoryIDs:)`, `metacriticScore / 100`, `headerImage` as cover,
`screenshots.first`, `trailers.first`. Name clash: Attic's `public enum SteamStore` hides SteamKit's inside
AtticEmulation; rename Attic's to `SteamStoreInfoReader` or call `SteamKit.SteamStore`.
Keeps: `SteamStoreInfo`, `info(appID:fetch:)`, `appInfo` and `libraryLogo` (steamcmd.net), `genreNames`,
`players`, `plainText`; `SteamGridDB.swift` and `SteamTrailer.swift` stay.

Callers in the app (`Attic/App/LaunchCoordinator.swift:185`, `SteamImport.swift`, `ScanCoordinator.swift:79`,
`ScrapeCoordinator.swift:402`) keep calling Attic's `SteamLibrary`; only `runURL` moves to `SteamLink.run`.

Tests (`Tests/AtticEmulationTests/SteamLibraryTests.swift`): drop `parsesKeyValuesWithEscapesAndComments`; the
fake Steam setup (`init`, `install`) can become `SteamFixture`. Keep the shortcut tests and the Mac-app filter
test. `SteamStoreTests.readsAppDetails` stays (it checks Attic's mapping), `buildsAssetURLsFromTheirFormat` and
`readsBothDateOrders` move here.

Behaviour to watch:
- A manifest without `StateFlags` now counts as installed (Attic skipped it). Steam always writes it.
- A manifest with bytes that aren't UTF-8 is now read (Attic skipped the game).
- `macApp` looks for the shallowest `.app`, first by name; Attic took the first one the enumerator met, at any of
  the first three levels. Only "is there one" matters to Attic.
- `games()` leaves out Steam's own tools even when they hold a Mac app.
- Libraries: libraryfolders.vdf's order with Steam's own folder first when missing; Attic always put Steam's own
  folder first. Steam writes its own folder as entry "0", so it's the same on a real Mac.
- A backslash that isn't an escape now stays (`"C:\Games"` was `C:Games`).

## Hangar (`Sources/HangarKit/`)

| Drop | Use |
| --- | --- |
| `KeyValues.swift` (whole file) | SteamKit's `KeyValues`: same cases (`.text`, `.block`), `string`, subscript, `pairs` (now labelled `(key:value:)`; `for (_, entry) in` still works), `parse`, `read` |
| `SteamScanner.tools`, the `Steamworks`/`Proton`/`Steam Linux Runtime` name checks | `SteamApp.isSteamTool` |
| `SteamScanner.libraryFolders(steamRoot:mapPath:)` | `Steam(root:mapPath:).libraries().map(\.folder)` |
| `SteamScanner.Manifest`, `manifests(in:)` | `SteamLibrary(folder:).manifests().filter { $0.isFullyInstalled && !$0.isSteamTool }` (`id`, `name`, `installDir`) |
| `SteamScanner.scan(steamRoot:)` body | `for library in Steam(root:).libraries()`: `!library.isReachable` gives `.libraryMissing(path: library.folder.path)`, else its manifests become `Game`s |
| `SteamScanner.isSignedIn(steamRoot:)` | `Steam(root:).isSignedIn` (`AppModel.swift:295`) |
| `SteamScanner.lastSessionSignedOut` | `Steam.lastSessionSignedOut` |
| `Launcher.swift:62` `"steam://rungameid/\(id)"` | `SteamLink.run(appID: id).absoluteString` |
| `Launcher.macApp(in:)` | `SteamApp.macApp(in:)` (see below) |
| `Covers.swift` `SteamArt.assetsURL`, `assets(from:)`, the classic URL | `SteamStore.assetsURL`, `SteamStore.assets(from:)` (`.cover`, `.hero`), `SteamStore.classicCoverURL` |
| `GameDetails.swift` `SteamDetails.url`, `language(for:)` | `SteamStore.detailsURL(appID:language:)`, `SteamStore.language(for:)` |
| `SteamDetails.parse` JSON reading | `SteamStore.details(from:appID:)`, then `PlainText` on `shortDescription`, developers and publishers; `releaseText`, `genres`, `hasMacVersion` |
| `GameLinks.swift:38` store URL | `SteamLink.webStorePage(appID:)` |

Keeps (Hangar's own): `LibraryRoots`, `ScanNote`, `ScanResult`, `Game` building, `CrossOverScanner` with
`macPath` (passed as `mapPath`), `steamFolder(bottle:)`, `steamWindowsFolder`, `BinaryKeyValues` and
`SteamAchievements` (binary format, only Hangar), `SteamGridDB`, `CoverCache`, `TheGamesDB`, `PlainText`.
`CrossOverScanner.steamGames` becomes `Steam(root: steamFolder(bottle:), mapPath: { macPath($0, bottle: bottle) })`.

Tests: `LibraryTests.keyValuesReadsNestedBlocksAndEscapes` and `SignInTests.aSessionThatEndedSignedOutNeedsASignIn`
move here. Keep `readsEverySteamLibraryAndSkipsMissingOnes`, the bottle tests and `aSignedOutLogOverridesRememberedUsers`
(they check Hangar's wiring on its fixture). `Tests/Fixtures/Steam` stays for the self-test and snapshots.

Behaviour to watch:
- Each app is listed once even when two libraries hold its manifest (Hangar listed both, with the same
  `steam:<id>` id). If Hangar keeps its own per-library loop, dedupe by ID there.
- A quoted `"}"` value is now text; Hangar's parser closed the block on it.
- A manifest without `name` now gives the folder name (Hangar dropped the game).
- `libraries()` puts Steam's own folder first when the file doesn't list it and it has a `steamapps` folder; with
  an empty library list and no `steamapps` it gives nothing (Hangar gave the root, then a "library missing" note).
- `SteamApp.macApp(in:)` also finds the folder itself (`Contents/MacOS`) and `.app`s up to three folders down;
  Hangar's looked only at the top level. A Steam game with launch options now opens a deeper app instead of failing.
- `SteamStore.language(for:)` knows more languages, reads `fr-CA`, and gives `brazilian` for `pt-BR`,
  `tchinese` for `zh-Hant`/`zh-TW` (Hangar gave `portuguese` and `schinese`).
- `SteamStore.assets` also reads `.logo` and `.header`; Hangar ignores them.
- A backslash that isn't an escape now stays.

## Starseed (`ModManagerCore/Sources/ModManagerCore/`)

| Drop | Use |
| --- | --- |
| `SteamGame.swift` `SteamGameState.read(gameFolder:)` | `Steam.app(containing: gameFolder)` → `buildID`, `isUpdatePending` (keep `SteamGameState` as a two-field value built from it, or use `SteamApp` in `AppModel.steamGame`) |
| `SteamGameState.parse` (line splitting) | `SteamApp(manifest:library:)` |
| `GameLocator.steamFolder` | `Steam.defaultRoot(home: home)` |
| `GameLocator.steamLibraries(inVDF:)` | `Steam(root: Steam.defaultRoot(home: home)).libraries().map(\.folder)` |
| `installs()` Steam part | `libraries().map { $0.common.appending(path: "Stardew Valley/Contents/MacOS") }`, still filtered by `SMAPIInstaller.isGameFolder` |
| `App/AppModel.swift:583` `"steam://rungameid/\(AppConstants.steamAppID)"` | `SteamLink.run(appID: AppConstants.steamAppID)` |
| `App/AppModel+Updates.swift:33` `"steam://nav/games/details/\(SteamGameState.appID)"` | `SteamLink.libraryPage(appID: AppConstants.steamAppID)` |

Keeps (Starseed's own): `GameLocator` (GOG and App Store folders, `gameFolder(fromPicked:)`), `GameStore.detect`
(the `/steamapps/` path test needs no manifest, so it stays), `AppConstants.steamAppID`, `defaultSteamModsURL`
(can be built from `Steam.defaultRoot`). `SteamGameState.appID` (an `Int`) goes; the app ID is the string in
`AppConstants`.

Tests: `SteamGameTests.readsAnUpToDateGame` and `noticesAWaitingUpdate` move here
(`SteamAppTests.statesAndUpdates`); `findsTheManifestFromTheGameFolder` becomes a test of the wrapper or goes
(`InstalledGamesTests.findsTheAppAFolderIsIn`). `GameLocatorTests.readsSteamLibraryPaths` goes;
`findsSteamLibrariesAndApps` and `normalizesWhatTheUserPicked` stay.

Behaviour to watch:
- `Steam.app(containing:)` finds the manifest whose `installdir` is the folder under `steamapps/common`, not
  `appmanifest_413150.acf` by name. Same answer for Stardew Valley; a renamed install folder no longer matches.
- Starseed's parser took the first `"key" "value"` line anywhere (a nested `buildid` could win) and only
  unescaped `\\`; SteamKit reads the real structure, all escapes, one-line files and CRLF.
- No `StateFlags`: Starseed read 0 (no update); SteamKit reads nil, `isUpdatePending` then looks only at the build.
- `libraries()` lists Steam's own folder only when it has `steamapps`; Starseed always tried it. No change in
  practice: `installs()` keeps only folders that hold the game.
- The library list keeps every library, connected or not; `isGameFolder` already drops the unplugged ones.

## Tadpole (optional)

Tadpole finds Baldur's Gate 3 through Launch Services (`AppModel.gameApp`:
`NSWorkspace.urlForApplication(withBundleIdentifier: "com.larian.bg3")`, `App/AppModel.swift:481`) and starts it with
`"steam://rungameid/\(GamePaths.steamAppID)"` (`App/AppModel.swift:474`). It reads no Steam files.

SteamKit helps a little:
- `SteamLink.run(appID: GamePaths.steamAppID)` in `launchGame()`.
- A fallback for `gameApp` when Launch Services doesn't know the app yet (installed on another drive and never
  opened): `Steam().app(id: GamePaths.steamAppID)?.macApp()`. Call it off the main actor.
- `Steam().app(id:)?.isUpdatePending` and `buildID` could say "Steam will update the game first" and notice a game
  update before the Script Extender check compares files; `isFullyInstalled` tells "still downloading" from "not
  installed".
- `isSignedIn` before Play, as Hangar does, if a launch that never opens comes up.

Nothing to drop. Worth doing when that code changes anyway; not on its own.
