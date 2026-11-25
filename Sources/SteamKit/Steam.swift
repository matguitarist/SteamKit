import Foundation

/// The Steam client's folder on this Mac, and what it knows: its libraries, the games installed in
/// them, and the accounts that signed in. Every read goes through `root`, so tests and self-tests
/// point it at a fake Steam folder (`SteamFixture`).
///
/// Reads small files on the caller's thread: call it off the main actor.
public struct Steam: Sendable {
    /// Steam's own folder, holding `steamapps`, `config`, `userdata` and `logs`.
    public let root: URL
    /// Turns a library path from libraryfolders.vdf into a folder on this Mac. Steam in a CrossOver
    /// bottle writes Windows paths ("C:\\Games\\SteamLibrary"); the app maps them into the bottle.
    public let mapPath: @Sendable (String) -> URL?

    public init(root: URL = Steam.defaultRoot, mapPath: (@Sendable (String) -> URL?)? = nil) {
        self.root = root
        self.mapPath = mapPath ?? { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// ~/Library/Application Support/Steam, where Steam for Mac keeps its data and first library.
    public static var defaultRoot: URL { defaultRoot(home: FileManager.default.homeDirectoryForCurrentUser) }

    /// Steam's folder for another home folder (a test's).
    public static func defaultRoot(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Steam", directoryHint: .isDirectory)
    }

    /// Whether Steam has a library here: its `steamapps` folder exists.
    public var isInstalled: Bool { Self.exists(root.appending(path: "steamapps")) }

    // MARK: - Libraries

    /// Every library Steam knows, in libraryfolders.vdf's order, each once, with Steam's own folder
    /// first when the file doesn't list it. Libraries on a drive that isn't connected are kept, with
    /// `isReachable` false, so an app can keep their games. Without the file, Steam's own folder
    /// when it has a `steamapps` folder.
    public func libraries() -> [SteamLibrary] {
        var libraries: [SteamLibrary] = []
        func add(_ folder: URL, label: String = "", apps: [String: Int64] = [:]) {
            let key = folder.standardizedFileURL.path
            if let index = libraries.firstIndex(where: { $0.folder.standardizedFileURL.path == key }) {
                libraries[index].apps.merge(apps) { old, _ in old }
            } else {
                libraries.append(SteamLibrary(folder: folder, label: label, apps: apps))
            }
        }
        if let file = KeyValues.read(root.appending(path: "steamapps/libraryfolders.vdf")) {
            // Older Steam wrote "LibraryFolders" with "1" "<path>" entries next to its settings.
            let list = file["libraryfolders"] ?? file
            for (key, entry) in list.pairs {
                switch entry {
                case .text(let path):
                    guard Int(key) != nil, let folder = mapPath(path) else { continue }
                    add(folder)
                case .block:
                    guard let path = entry["path"]?.string, let folder = mapPath(path) else { continue }
                    var apps: [String: Int64] = [:]
                    for (id, size) in entry["apps"]?.pairs ?? [] { apps[id] = size.int64 ?? 0 }
                    add(folder, label: entry["label"]?.string ?? "", apps: apps)
                }
            }
        }
        let rootKey = root.standardizedFileURL.path
        if !libraries.contains(where: { $0.folder.standardizedFileURL.path == rootKey }), isInstalled {
            libraries.insert(SteamLibrary(folder: root, label: "", apps: [:]), at: 0)
        }
        return libraries
    }

    // MARK: - Installed apps

    /// Every app with a manifest in a connected library, whatever its state (still downloading,
    /// Steam's own tools), each app once (the first library wins), by name.
    public func apps() -> [SteamApp] {
        var seen = Set<String>()
        var apps: [SteamApp] = []
        for library in libraries() where library.isReachable {
            for app in library.manifests() where seen.insert(app.id).inserted {
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The games: fully installed apps that aren't Steam's own tools (redistributables, Proton,
    /// the Linux runtimes), by name.
    public func games() -> [SteamApp] {
        apps().filter { $0.isFullyInstalled && !$0.isSteamTool }
    }

    /// The app with this ID, if a connected library has its manifest (in any state).
    public func app(id: String) -> SteamApp? {
        for library in libraries() where library.isReachable {
            if let app = SteamApp.read(library.steamapps.appending(path: "appmanifest_\(id).acf"), library: library.folder) {
                return app
            }
        }
        return nil
    }

    /// The app installed in `steamapps/common/<installDir>`, ignoring case.
    public func app(installDir: String) -> SteamApp? {
        apps().first { $0.installDir.caseInsensitiveCompare(installDir) == .orderedSame }
    }

    /// The install folder of an app, when its manifest and folder are both there.
    public func installFolder(appID: String) -> URL? {
        app(id: appID).map(\.folder).flatMap { Self.exists($0) ? $0 : nil }
    }

    /// `steamapps/common/<name>` in the first connected library that has it, with or without a
    /// manifest (a game copied in by hand still counts).
    public func installFolder(named name: String) -> URL? {
        for library in libraries() where library.isReachable {
            let folder = library.common.appending(path: name, directoryHint: .isDirectory)
            if Self.exists(folder) { return folder }
        }
        return nil
    }

    /// The app whose install folder holds `folder` (".../steamapps/common/Stardew Valley/Contents/MacOS"),
    /// from the manifest next to it. Nil when the folder isn't inside a Steam library or nothing
    /// there names it.
    public static func app(containing folder: URL) -> SteamApp? {
        let parts = folder.standardizedFileURL.pathComponents
        guard let at = parts.lastIndex(where: { $0.caseInsensitiveCompare("steamapps") == .orderedSame }),
              at + 2 < parts.count, parts[at + 1].caseInsensitiveCompare("common") == .orderedSame else { return nil }
        let installDir = parts[at + 2]
        let library = URL(fileURLWithPath: NSString.path(withComponents: Array(parts[..<at])), isDirectory: true)
        return SteamLibrary(folder: library, label: "", apps: [:]).manifests()
            .first { $0.installDir.caseInsensitiveCompare(installDir) == .orderedSame }
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

/// One Steam library folder: the folder holding `steamapps`.
public struct SteamLibrary: Sendable, Equatable {
    public var folder: URL
    /// The name the person gave it in Steam's storage settings; often empty.
    public var label: String
    /// App IDs libraryfolders.vdf lists in it, with their size in bytes. Known even when the drive
    /// isn't connected.
    public var apps: [String: Int64]

    public init(folder: URL, label: String = "", apps: [String: Int64] = [:]) {
        self.folder = folder
        self.label = label
        self.apps = apps
    }

    public var steamapps: URL { folder.appending(path: "steamapps", directoryHint: .isDirectory) }
    public var common: URL { steamapps.appending(path: "common", directoryHint: .isDirectory) }

    /// Whether its `steamapps` folder is there (false for an unplugged drive). Reads the disk.
    public var isReachable: Bool { Steam.exists(steamapps) }

    /// The apps whose manifest is in this library, in file name order.
    public func manifests() -> [SteamApp] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: steamapps.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("appmanifest_") && $0.hasSuffix(".acf") }.sorted()
            .compactMap { SteamApp.read(steamapps.appending(path: $0), library: folder) }
    }
}
