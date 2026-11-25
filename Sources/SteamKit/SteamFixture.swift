import Foundation

/// Writes a fake Steam folder for tests, self-tests and snapshots: libraries, installed games and
/// signed-in accounts, in the files Steam itself writes. Point `Steam(root:)` at `root`.
/// It writes only under `root` and the library folders it is given.
public struct SteamFixture: Sendable {
    public let root: URL

    /// Makes `root/steamapps` and a libraryfolders.vdf listing `root` as library "0".
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appending(path: "steamapps/common"), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: libraryFile.path(percentEncoded: false)) {
            try write(.block([("libraryfolders", .block([]))]), to: libraryFile)
            try addLibrary(root)
        }
    }

    public var steam: Steam { Steam(root: root) }

    var libraryFile: URL { root.appending(path: "steamapps/libraryfolders.vdf") }

    /// Lists another library in libraryfolders.vdf, and makes its `steamapps` folder unless
    /// `connected` is false (an unplugged drive).
    public func addLibrary(_ folder: URL, label: String = "", connected: Bool = true) throws {
        if connected {
            try FileManager.default.createDirectory(at: folder.appending(path: "steamapps/common"), withIntermediateDirectories: true)
        }
        try updateLibraries { list in
            let index = list.pairs.count
            return list.setting(String(index), to: .block([("path", .text(folder.path(percentEncoded: false))), ("label", .text(label)),
                                                           ("contentid", .text("0")), ("totalsize", .text("0")), ("apps", .block([]))]))
        }
    }

    /// Writes `appmanifest_<id>.acf` in a library (Steam's own by default), lists the app in
    /// libraryfolders.vdf, and makes its install folder, with an empty Mac app in it when
    /// `macApp` is true or a Windows .exe when false. Returns the install folder.
    @discardableResult
    public func install(appID: String, name: String, installDir: String? = nil, stateFlags: Int = 4,
                        buildID: String = "1", targetBuildID: String? = nil, sizeOnDisk: Int64 = 1_000,
                        lastPlayed: Date? = nil, in library: URL? = nil, macApp: Bool = true) throws -> URL {
        let library = library ?? root
        let dir = installDir ?? name
        let steamapps = library.appending(path: "steamapps", directoryHint: .isDirectory)
        let manifest: KeyValues = .block([("AppState", .block([
            ("appid", .text(appID)), ("universe", .text("1")), ("name", .text(name)), ("StateFlags", .text(String(stateFlags))),
            ("installdir", .text(dir)), ("LastUpdated", .text("1764000000")), ("SizeOnDisk", .text(String(sizeOnDisk))),
            ("buildid", .text(buildID)), ("TargetBuildID", .text(targetBuildID ?? buildID)),
            ("LastPlayed", .text(String(Int(lastPlayed?.timeIntervalSince1970 ?? 0)))),
        ]))])
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try write(manifest, to: steamapps.appending(path: "appmanifest_\(appID).acf"))
        let folder = steamapps.appending(path: "common/\(dir)", directoryHint: .isDirectory)
        if macApp {
            try FileManager.default.createDirectory(at: folder.appending(path: "\(dir).app/Contents/MacOS"), withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: folder.appending(path: "\(dir).exe"))
        }
        let libraryPath = library.standardizedFileURL.path(percentEncoded: false)
        try updateLibraries { list in
            var list = list
            for (key, entry) in list.pairs where (entry["path"]?.string).map({ URL(fileURLWithPath: $0).standardizedFileURL.path(percentEncoded: false) }) == libraryPath {
                let apps = (entry["apps"] ?? .block([])).setting(appID, to: .text(String(sizeOnDisk)))
                list = list.setting(key, to: entry.setting("apps", to: apps))
            }
            return list
        }
        return folder
    }

    /// Adds an account to config/loginusers.vdf, as the most recent, and makes its userdata folder.
    public func signIn(steamID: String = "76561198000000001", accountName: String = "player", personaName: String = "Player",
                       remembersPassword: Bool = true) throws {
        let file = root.appending(path: "config/loginusers.vdf")
        var users = KeyValues.read(file)?["users"] ?? .block([])
        users = .block(users.pairs.map { ($0.key, $0.value.setting("MostRecent", to: .text("0"))) })
        users = users.setting(steamID, to: .block([
            ("AccountName", .text(accountName)), ("PersonaName", .text(personaName)),
            ("RememberPassword", .text(remembersPassword ? "1" : "0")), ("WantsOfflineMode", .text("0")),
            ("SkipOfflineModeWarning", .text("0")), ("AllowAutoLogin", .text("1")), ("MostRecent", .text("1")),
            ("Timestamp", .text("1764000000")),
        ]))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(.block([("users", users)]), to: file)
        if let accountID = SteamUser(id: steamID).accountID {
            try FileManager.default.createDirectory(at: steam.userdataFolder(accountID: accountID).appending(path: "config"), withIntermediateDirectories: true)
        }
    }

    /// Ends the connection log with a session that closed signed out.
    public func signOut() throws {
        let logs = root.appending(path: "logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("[2026-11-25 10:00:00] [Logged Off, 0, 0] [U:1:0] Log session ended\n".utf8)
            .write(to: logs.appending(path: "connection_log.txt"))
    }

    private func updateLibraries(_ change: (KeyValues) -> KeyValues) throws {
        let file = KeyValues.read(libraryFile) ?? .block([])
        try write(file.setting("libraryfolders", to: change(file["libraryfolders"] ?? .block([]))), to: libraryFile)
    }

    private func write(_ value: KeyValues, to url: URL) throws {
        try Data(value.formatted.utf8).write(to: url, options: .atomic)
    }
}
