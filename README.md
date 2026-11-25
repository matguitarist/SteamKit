# SteamKit

Steam on this Mac, for my apps. It gathers what each app wrote on its own: Attic's and Hangar's library scans,
Starseed's search for Stardew Valley in every library and its "update waiting" check, Hangar's sign-in check, three
`steam://rungameid` links, and the store details and pictures Attic and Hangar read.

- **Steam**: Steam's folder, its libraries (`libraryfolders.vdf`, unplugged drives kept), the apps installed in them
  (`appmanifest_<id>.acf`), an app or its folder by ID or folder name, the app a folder is in.
- **SteamApp**: one manifest: ID, name, folder, state, build, size, dates; fully installed, update waiting, Steam's own
  tools, the Mac app inside.
- **SteamUser**: the accounts in `loginusers.vdf`, their `userdata` folders, and whether Steam is signed in.
- **SteamLink**: `steam://` links that start a game, show it in Steam's library, install it.
- **SteamStore**: the store's `appdetails` and library pictures (`GetItems`): the requests and how to read the answers.
- **KeyValues**: Valve's text format, read tolerantly and written back.
- **SteamFixture**: a fake Steam folder for tests, self-tests and snapshots.

macOS 14 or later. No SwiftUI, no network: an app fetches the store's answers its own way.

## Add it to an app

SwiftPM (`Package.swift`):

```swift
.package(url: "https://github.com/matguitarist/SteamKit", from: "0.1.0"),
// in the app or Kit target:
.product(name: "SteamKit", package: "SteamKit"),
```

XcodeGen (`project.yml`):

```yaml
packages:
  SteamKit:
    url: https://github.com/matguitarist/SteamKit
    from: 0.1.0
targets:
  App:
    dependencies:
      - package: SteamKit
```

## Libraries and games

```swift
import SteamKit

let steam = Steam()                       // ~/Library/Application Support/Steam
let test = Steam(root: tempFolder)        // a fake one (see SteamFixture)

steam.isInstalled                         // it has a steamapps folder
for library in steam.libraries() {        // libraryfolders.vdf, in order, each once
    library.folder; library.label; library.apps   // app IDs and sizes, known even when unplugged
    library.isReachable                   // false for a drive that isn't connected
}

let games = steam.games()                 // fully installed, not Steam's own tools, by name
let everything = steam.apps()             // every manifest, any state
let bg3 = steam.app(id: "1086940")
let folder = steam.installFolder(appID: "413150")          // only when the folder is there
let byName = steam.installFolder(named: "Stardew Valley")  // even without a manifest
let mine = Steam.app(containing: gameFolder)               // the app a folder is inside
```

Every read is a few small files: call these off the main actor. Each app appears once (the first library wins); a
library that isn't connected is listed but not read, so an app can keep the games on it. Steam's own folder comes
first when the file leaves it out; the old `"1" "<path>"` format still reads.

Steam in a CrossOver bottle writes Windows paths; pass the app's own mapping:

```swift
let bottled = Steam(root: bottleSteam) { windowsPath in macPath(windowsPath, bottle: bottle) }
```

### One app

```swift
app.id; app.name; app.installDir; app.folder; app.library; app.manifestFile
app.stateFlags; app.buildID; app.targetBuildID; app.sizeOnDisk; app.lastUpdated; app.lastPlayed
app.isFullyInstalled      // StateFlags bit 4; no StateFlags counts as installed
app.isUpdatePending       // bit 2, or a target build that isn't the installed one
app.isSteamTool           // redistributables, Proton, Steam Linux Runtime
app.macApp()              // the folder itself (Contents/MacOS), else the shallowest .app; nil for a Windows build
app.manifest["AppState"]?["InstalledDepots"]   // anything else in the file
```

## Accounts

```swift
steam.users()             // loginusers.vdf, the most recent first: id, accountName, personaName, accountID
steam.isSignedIn          // a remembered account, and the last session didn't end signed out
steam.userdataFolders()   // userdata/<account ID>, one per account
steam.userdataFolder(accountID: user.accountID!)
```

A game started through Steam while Steam waits for a sign-in never opens: check `isSignedIn` first and ask the
person to open Steam.

## Links

```swift
NSWorkspace.shared.open(SteamLink.run(appID: "413150"))   // steam://rungameid/413150
SteamLink.libraryPage(appID:)    // steam://nav/games/details/<id>
SteamLink.install(appID:)        // steam://install/<id>
SteamLink.storePage(appID:)      // steam://store/<id>
SteamLink.webStorePage(appID:)   // https://store.steampowered.com/app/<id>/
```

Steam passes no arguments or environment to a game it starts: an app that needs them opens `app.macApp()` itself.

## The store

```swift
let data = try await fetch(SteamStore.detailsURL(appID: id, language: SteamStore.language(for: "fr")))
if let details = SteamStore.details(from: data, appID: id) {
    details.shortDescription   // the store's text: HTML tags and entities are the app's to clean
    details.developers; details.publishers; details.genres; details.releaseText; details.releaseDate
    details.headerImage; details.screenshots; details.trailers   // highlighted trailers first
    details.categoryIDs; details.metacriticScore; details.hasMacVersion
}
let assets = SteamStore.assets(from: try await fetch(SteamStore.assetsURL(appID: id)))
assets.cover; assets.hero; assets.logo; assets.header      // twice the size when there is one
SteamStore.classicCoverURL(appID:)   // older games' fixed portrait cover: check it with a HEAD request
```

## KeyValues

```swift
let file = KeyValues.read(url)                 // nil only when the file can't be read
let vdf = KeyValues.parse(text)                // never fails
vdf["AppState"]?["StateFlags"]?.int            // keys ignore case; the first of two wins
for (key, value) in vdf["users"]?.pairs ?? [] { … }
let changed = vdf.setting("name", to: .text("New"))
try Data(changed.formatted.utf8).write(to: url)
```

Read as Steam reads them: `//` comments, bare words, conditions (`[$OSX]`), a byte order mark, CRLF, braces inside
quotes, stray braces, files cut short, bytes that aren't UTF-8. `\n`, `\t`, `\r`, `\\` and `\"` are escapes; any
other backslash stays, so a Windows path written by hand keeps it. Binary KeyValues (`appinfo.vdf`, stats) aren't read.

## Tests and self-tests

```swift
let fixture = try SteamFixture(root: tmp.appending(path: "Steam"))
try fixture.addLibrary(tmp.appending(path: "Drive"), label: "Games")
try fixture.addLibrary(URL(fileURLWithPath: "/Volumes/Gone/SteamLibrary"), connected: false)
try fixture.install(appID: "413150", name: "Stardew Valley", in: tmp.appending(path: "Drive"))
try fixture.install(appID: "1086940", name: "Baldur's Gate 3", stateFlags: 1026)    // still downloading
try fixture.signIn(accountName: "player")
let steam = fixture.steam
```

It writes only under its root and the libraries it is given, in the files Steam itself writes.

## License

MIT
