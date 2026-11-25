import Foundation
import Testing
@testable import SteamKit

/// A fake Steam folder and a second library on a drive.
struct FakeSteam {
    let scratch: Scratch
    let fixture: SteamFixture
    var steam: Steam { fixture.steam }
    var root: URL { fixture.root }
    var drive: URL { scratch.url("Drive/SteamLibrary") }

    init(_ name: String = #function) throws {
        scratch = try Scratch(name)
        fixture = try SteamFixture(root: scratch.url("Steam"))
    }
}

struct SteamLibraryTests {
    @Test func defaultRootIsInApplicationSupport() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(Steam.defaultRoot(home: home).path == "/Users/someone/Library/Application Support/Steam")
        #expect(Steam.defaultRoot.path.hasSuffix("/Library/Application Support/Steam"))
    }

    @Test func listsEveryLibraryOnceAndKeepsUnpluggedOnes() throws {
        let fake = try FakeSteam()
        defer { fake.scratch.clean() }
        try fake.fixture.addLibrary(fake.drive, label: "Games")
        try fake.fixture.addLibrary(URL(fileURLWithPath: "/Volumes/SteamKitAbsentDrive/SteamLibrary"), connected: false)
        try fake.fixture.addLibrary(fake.root) // listed twice
        try fake.fixture.install(appID: "413150", name: "Stardew Valley", in: fake.drive)
        let libraries = fake.steam.libraries()
        #expect(libraries.map(\.folder.lastPathComponent) == ["Steam", "SteamLibrary", "SteamLibrary"])
        #expect(libraries.map(\.isReachable) == [true, true, false])
        #expect(libraries[1].label == "Games")
        #expect(libraries[1].apps == ["413150": 1_000])
    }

    @Test func steamsOwnFolderComesFirstWhenTheFileLeavesItOut() throws {
        let scratch = try Scratch()
        defer { scratch.clean() }
        try scratch.folder("Steam/steamapps")
        try scratch.folder("Drive/steamapps")
        try scratch.write("Steam/steamapps/libraryfolders.vdf", """
        "libraryfolders" { "1" { "path" "\(scratch.url("Drive").path)" } }
        """)
        #expect(Steam(root: scratch.url("Steam")).libraries().map(\.folder.lastPathComponent) == ["Steam", "Drive"])
    }

    @Test func readsTheOldLibraryFoldersFormat() throws {
        let scratch = try Scratch()
        defer { scratch.clean() }
        try scratch.folder("Steam/steamapps")
        try scratch.write("Steam/steamapps/libraryfolders.vdf", """
        "LibraryFolders"
        {
        \t"TimeNextStatsReport"\t\t"1234"
        \t"ContentStatsID"\t\t"-1"
        \t"1"\t\t"\(scratch.url("Old").path)"
        }
        """)
        #expect(Steam(root: scratch.url("Steam")).libraries().map(\.folder.lastPathComponent) == ["Steam", "Old"])
    }

    @Test func withoutLibraryFoldersSteamsOwnFolderIfItHasOne() throws {
        let scratch = try Scratch()
        defer { scratch.clean() }
        let steam = Steam(root: scratch.url("Steam"))
        #expect(steam.libraries().isEmpty)
        #expect(!steam.isInstalled)
        try scratch.folder("Steam/steamapps")
        #expect(steam.libraries().map(\.folder) == [scratch.url("Steam")])
        #expect(steam.isInstalled)
    }

    @Test func mapsWindowsPathsWithTheAppsRule() throws {
        let scratch = try Scratch()
        defer { scratch.clean() }
        let bottle = scratch.url("Bottle")
        try scratch.folder("Bottle/drive_c/Steam/steamapps")
        try scratch.folder("Bottle/drive_c/Games/steamapps")
        try scratch.write("Bottle/drive_c/Steam/steamapps/libraryfolders.vdf", #"""
        "libraryfolders" { "0" { "path" "C:\\Steam" } "1" { "path" "C:\\Games" } "2" { "path" "Q:\\Nope" } }
        """#)
        let steam = Steam(root: bottle.appending(path: "drive_c/Steam")) { path in
            guard path.hasPrefix(#"C:\"#) else { return nil }
            return bottle.appending(path: "drive_c/" + path.dropFirst(3).replacingOccurrences(of: #"\"#, with: "/"))
        }
        #expect(steam.libraries().map(\.folder.lastPathComponent) == ["Steam", "Games"])
    }
}

struct SteamAppTests {
    @Test func readsAManifest() throws {
        let library = URL(fileURLWithPath: "/L")
        let app = try #require(SteamApp(manifest: """
        "AppState"
        {
        \t"appid"\t\t"1086940"
        \t"name"\t\t"Baldur's Gate 3"
        \t"StateFlags"\t\t"4"
        \t"installdir"\t\t"Baldurs Gate 3"
        \t"LastUpdated"\t\t"1764000000"
        \t"LastPlayed"\t\t"0"
        \t"SizeOnDisk"\t\t"152438221313"
        \t"buildid"\t\t"20516337"
        \t"TargetBuildID"\t\t"0"
        \t"InstalledDepots" { "1419657" { "manifest" "123" "size" "456" } }
        }
        """, library: library))
        #expect(app.id == "1086940")
        #expect(app.name == "Baldur's Gate 3")
        #expect(app.installDir == "Baldurs Gate 3")
        #expect(app.sizeOnDisk == 152_438_221_313)
        #expect(app.lastUpdated == Date(timeIntervalSince1970: 1_764_000_000))
        #expect(app.lastPlayed == nil)
        #expect(app.isFullyInstalled && !app.isUpdatePending && !app.isSteamTool)
        #expect(app.folder.path == "/L/steamapps/common/Baldurs Gate 3")
        #expect(app.manifestFile.path == "/L/steamapps/appmanifest_1086940.acf")
        #expect(app.manifest["AppState"]?["InstalledDepots"]?["1419657"]?["size"]?.string == "456")
        #expect(app.runURL.absoluteString == "steam://rungameid/1086940")
    }

    @Test func needsAnIDAndAFolderAndFallsBackToTheFolderName() {
        let library = URL(fileURLWithPath: "/L")
        #expect(SteamApp(manifest: #""AppState" { "appid" "1" }"#, library: library) == nil)
        #expect(SteamApp(manifest: #""AppState" { "installdir" "X" }"#, library: library) == nil)
        #expect(SteamApp(manifest: "junk", library: library) == nil)
        let app = SteamApp(manifest: #""AppState" { "appid" "1" "installdir" "Folder" }"#, library: library)
        #expect(app?.name == "Folder")
        // No StateFlags: counted as installed.
        #expect(app?.isFullyInstalled == true)
    }

    @Test func statesAndUpdates() {
        func app(_ flags: Int, build: String = "1", target: String = "1") -> SteamApp {
            SteamApp(id: "1", name: "A", installDir: "A", stateFlags: flags, buildID: build, targetBuildID: target, library: URL(fileURLWithPath: "/"))
        }
        #expect(app(4).isFullyInstalled)
        #expect(!app(1026).isFullyInstalled) // still downloading
        #expect(app(6).isFullyInstalled && app(6).isUpdatePending) // installed, update queued
        #expect(app(4, build: "1", target: "2").isUpdatePending)
        #expect(!app(4, build: "1", target: "0").isUpdatePending)
        #expect(!app(4, build: "1", target: "").isUpdatePending)
    }

    @Test func knowsSteamsOwnTools() {
        func app(_ id: String, _ name: String) -> SteamApp { SteamApp(id: id, name: name, installDir: name, library: URL(fileURLWithPath: "/")) }
        #expect(app("228980", "Steamworks Common Redistributables").isSteamTool)
        #expect(app("1", "Proton 9.0").isSteamTool)
        #expect(app("1628350", "Steam Linux Runtime 3.0 (sniper)").isSteamTool)
        #expect(!app("367520", "Hollow Knight").isSteamTool)
    }
}

struct InstalledGamesTests {
    @Test func gamesAreFullyInstalledAndNotTools() throws {
        let fake = try FakeSteam()
        defer { fake.scratch.clean() }
        try fake.fixture.install(appID: "367520", name: "Hollow Knight")
        try fake.fixture.install(appID: "228980", name: "Steamworks Common Redistributables", installDir: "Steamworks Shared", macApp: false)
        try fake.fixture.install(appID: "1086940", name: "Baldur's Gate 3", installDir: "Baldurs Gate 3", stateFlags: 1026)
        try fake.fixture.install(appID: "1569580", name: "Blue Prince", stateFlags: 6)
        #expect(fake.steam.apps().map(\.id) == ["1086940", "1569580", "367520", "228980"])
        #expect(fake.steam.games().map(\.id) == ["1569580", "367520"])
    }

    @Test func findsGamesInEveryConnectedLibraryOnce() throws {
        let fake = try FakeSteam()
        defer { fake.scratch.clean() }
        try fake.fixture.addLibrary(fake.drive)
        try fake.fixture.install(appID: "413150", name: "Stardew Valley", in: fake.drive)
        try fake.fixture.install(appID: "367520", name: "Hollow Knight")
        // A stale copy of the same manifest on the drive.
        try fake.fixture.install(appID: "367520", name: "Hollow Knight", in: fake.drive)
        let games = fake.steam.games()
        #expect(games.map(\.id) == ["367520", "413150"])
        #expect(games[0].library == fake.root)
        #expect(games[1].library.standardizedFileURL == fake.drive.standardizedFileURL)
    }

    @Test func findsAnAppAndItsFolder() throws {
        let fake = try FakeSteam()
        defer { fake.scratch.clean() }
        try fake.fixture.addLibrary(fake.drive)
        let folder = try fake.fixture.install(appID: "413150", name: "Stardew Valley", in: fake.drive)
        #expect(fake.steam.app(id: "413150")?.name == "Stardew Valley")
        #expect(fake.steam.app(id: "1") == nil)
        #expect(fake.steam.app(installDir: "stardew valley")?.id == "413150")
        #expect(fake.steam.installFolder(appID: "413150") == folder)
        #expect(fake.steam.installFolder(named: "Stardew Valley") == folder)
        #expect(fake.steam.installFolder(named: "Nothing") == nil)
        // The folder gone, the manifest left: no folder.
        try FileManager.default.removeItem(at: folder)
        #expect(fake.steam.installFolder(appID: "413150") == nil)
    }

    @Test func aFolderCopiedInWithoutAManifestIsFoundByName() throws {
        let fake = try FakeSteam()
        defer { fake.scratch.clean() }
        let folder = fake.root.appending(path: "steamapps/common/Stardew Valley", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(fake.steam.installFolder(named: "Stardew Valley") == folder)
        #expect(fake.steam.app(installDir: "Stardew Valley") == nil)
    }

    @Test func findsTheAppAFolderIsIn() throws {
        let fake = try FakeSteam()
        defer { fake.scratch.clean() }
        let folder = try fake.fixture.install(appID: "413150", name: "Stardew Valley", buildID: "7", targetBuildID: "8")
        let inside = folder.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let app = try #require(Steam.app(containing: inside))
        #expect(app.id == "413150" && app.buildID == "7" && app.isUpdatePending)
        #expect(Steam.app(containing: folder)?.id == "413150")
        #expect(Steam.app(containing: fake.root) == nil)
        #expect(Steam.app(containing: fake.root.appending(path: "steamapps/common/Other")) == nil)
    }

    @Test func findsTheMacApp() throws {
        let scratch = try Scratch()
        defer { scratch.clean() }
        // Windows build: none.
        try scratch.write("Win/Game.exe", "MZ")
        #expect(SteamApp.macApp(in: scratch.url("Win")) == nil)
        // The folder is the app (Stardew Valley).
        try scratch.folder("Stardew/Contents/MacOS")
        #expect(SteamApp.macApp(in: scratch.url("Stardew")) == scratch.url("Stardew"))
        // Top level wins over deeper, first by name.
        try scratch.folder("Game/B.app/Contents")
        try scratch.folder("Game/A.app/Contents")
        try scratch.folder("Game/Deep/Z.app/Contents")
        #expect(SteamApp.macApp(in: scratch.url("Game"))?.lastPathComponent == "A.app")
        // Up to three folders down.
        try scratch.folder("Nested/one/two/Game.app/Contents")
        #expect(SteamApp.macApp(in: scratch.url("Nested"))?.lastPathComponent == "Game.app")
        try scratch.folder("TooDeep/a/b/c/Game.app/Contents")
        #expect(SteamApp.macApp(in: scratch.url("TooDeep")) == nil)
    }
}

struct SteamUserTests {
    @Test func readsAccountsMostRecentFirst() throws {
        let fake = try FakeSteam()
        defer { fake.scratch.clean() }
        try fake.fixture.signIn(steamID: "76561198000000001", accountName: "first", personaName: "First")
        try fake.fixture.signIn(steamID: "76561198032678845", accountName: "second", personaName: "Second", remembersPassword: false)
        let users = fake.steam.users()
        #expect(users.map(\.accountName) == ["second", "first"])
        #expect(users[0].isMostRecent && !users[1].isMostRecent)
        #expect(users[1].remembersPassword && !users[0].remembersPassword)
        #expect(users[0].accountID == 72_413_117)
        #expect(users[0].lastSignIn == Date(timeIntervalSince1970: 1_764_000_000))
        #expect(fake.steam.userdataFolders().map(\.lastPathComponent) == ["39734273", "72413117"])
        #expect(fake.steam.userdataFolder(accountID: 72_413_117).path.hasSuffix("/Steam/userdata/72413117"))
        #expect(SteamUser(id: "12").accountID == nil)
    }

    @Test func signedInNeedsARememberedAccountAndASessionThatDidntEndSignedOut() throws {
        let fake = try FakeSteam()
        defer { fake.scratch.clean() }
        #expect(!fake.steam.isSignedIn)
        try fake.fixture.signIn(remembersPassword: false)
        #expect(!fake.steam.isSignedIn)
        try fake.fixture.signIn(steamID: "76561198000000002")
        #expect(fake.steam.isSignedIn)
        try fake.fixture.signOut()
        #expect(!fake.steam.isSignedIn)
    }

    @Test func readsHowTheLastSessionEnded() {
        let replaced = """
        [2026-11-24 06:00:56] [Logged On, 4, 15] [U:1:72413117] RecvMsgClientLogOnResponse() : processing complete
        [2026-11-24 08:56:29] [Logged On, 4, 15] [U:1:72413117] RecvMsgClientLoggedOff('Session Replaced')
        [2026-11-24 08:57:16] [Logged Off, 0, 0] [U:1:72413117] Log session ended
        """
        #expect(!Steam.lastSessionSignedOut(replaced))
        #expect(Steam.lastSessionSignedOut(replaced + "\n[2026-11-24 09:01:00] [Connecting, 0, 0] [U:1:0] Log session ended\n"))
        #expect(!Steam.lastSessionSignedOut(""))
    }
}

struct SteamLinkTests {
    @Test func links() {
        #expect(SteamLink.run(appID: "413150").absoluteString == "steam://rungameid/413150")
        #expect(SteamLink.libraryPage(appID: "413150").absoluteString == "steam://nav/games/details/413150")
        #expect(SteamLink.install(appID: "1").absoluteString == "steam://install/1")
        #expect(SteamLink.storePage(appID: "1").absoluteString == "steam://store/1")
        #expect(SteamLink.webStorePage(appID: "367520")?.absoluteString == "https://store.steampowered.com/app/367520/")
        #expect(SteamLink.webStorePage(appID: "abc") == nil)
        #expect(SteamLink.webStorePage(appID: "") == nil)
    }
}
