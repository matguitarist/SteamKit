import Foundation

/// An app Steam installed, from its `steamapps/appmanifest_<id>.acf`.
public struct SteamApp: Sendable, Equatable, Identifiable {
    /// The app ID ("413150").
    public var id: String
    /// Its name in Steam; the install folder's name when the manifest has none.
    public var name: String
    /// The folder's name under `steamapps/common`.
    public var installDir: String
    /// Steam's StateFlags; nil when the manifest has none.
    public var stateFlags: Int?
    public var buildID: String?
    /// The build Steam will update to; "0" or the same as `buildID` when none is waiting.
    public var targetBuildID: String?
    /// Bytes on disk, as Steam counts them.
    public var sizeOnDisk: Int64?
    public var lastUpdated: Date?
    public var lastPlayed: Date?
    /// The library folder (holding `steamapps`).
    public var library: URL
    /// The whole manifest, for anything else in it.
    public var manifest: KeyValues

    public init(id: String, name: String, installDir: String, stateFlags: Int? = 4, buildID: String? = nil,
                targetBuildID: String? = nil, sizeOnDisk: Int64? = nil, lastUpdated: Date? = nil, lastPlayed: Date? = nil,
                library: URL, manifest: KeyValues = .block([])) {
        self.id = id
        self.name = name
        self.installDir = installDir
        self.stateFlags = stateFlags
        self.buildID = buildID
        self.targetBuildID = targetBuildID
        self.sizeOnDisk = sizeOnDisk
        self.lastUpdated = lastUpdated
        self.lastPlayed = lastPlayed
        self.library = library
        self.manifest = manifest
    }

    /// The app a manifest's text describes; nil without an `appid` and an `installdir`.
    public init?(manifest text: String, library: URL) {
        self.init(KeyValues.parse(text), library: library)
    }

    init?(_ file: KeyValues, library: URL) {
        guard let state = file["AppState"],
              let id = state["appid"]?.string?.trimmingCharacters(in: .whitespaces), !id.isEmpty,
              let installDir = state["installdir"]?.string, !installDir.isEmpty else { return nil }
        func date(_ key: String) -> Date? {
            state[key]?.int64.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        }
        let name = state["name"]?.string ?? ""
        self.init(id: id, name: name.isEmpty ? installDir : name, installDir: installDir,
                  stateFlags: state["StateFlags"]?.int, buildID: state["buildid"]?.string,
                  targetBuildID: state["TargetBuildID"]?.string, sizeOnDisk: state["SizeOnDisk"]?.int64,
                  lastUpdated: date("LastUpdated"), lastPlayed: date("LastPlayed"), library: library, manifest: file)
    }

    static func read(_ url: URL, library: URL) -> SteamApp? {
        KeyValues.read(url).flatMap { SteamApp($0, library: library) }
    }

    /// `steamapps/common/<installDir>` in its library.
    public var folder: URL {
        library.appending(path: "steamapps/common", directoryHint: .isDirectory)
            .appending(path: installDir, directoryHint: .isDirectory)
    }

    /// Its manifest file.
    public var manifestFile: URL {
        library.appending(path: "steamapps/appmanifest_\(id).acf")
    }

    /// Steam finished installing it (StateFlags bit 4). Still downloading for the first time, or
    /// uninstalled, is false. A manifest without StateFlags counts as installed.
    public var isFullyInstalled: Bool { stateFlags.map { $0 & 4 != 0 } ?? true }

    /// Steam has a newer build to download: StateFlags bit 2 ("update required"), or a target build
    /// that isn't the installed one. Steam updates it the next time it runs or the game starts.
    public var isUpdatePending: Bool {
        if let flags = stateFlags, flags & 2 != 0 { return true }
        guard let target = targetBuildID, !target.isEmpty, target != "0" else { return false }
        return target != buildID
    }

    /// One of Steam's own tools that sit in steamapps like games: the redistributables, Proton,
    /// the Linux runtimes.
    public var isSteamTool: Bool {
        Self.toolIDs.contains(id) || Self.toolPrefixes.contains { name.hasPrefix($0) }
    }

    static let toolIDs: Set<String> = ["228980", "1070560", "1391110", "1628350", "1493710", "961940", "1826330", "2180100"]
    static let toolPrefixes = ["Steamworks", "Proton", "Steam Linux Runtime"]

    /// The Mac app in its install folder: the folder itself when it holds `Contents/MacOS`
    /// (Stardew Valley's does), else the shallowest `.app` up to three folders down, first by name.
    /// Nil for a Windows-only build. Reads the disk.
    public func macApp() -> URL? { Self.macApp(in: folder) }

    /// The Mac app in a folder, as `macApp()`.
    public static func macApp(in folder: URL) -> URL? {
        let fileManager = FileManager.default
        if Steam.exists(folder.appending(path: "Contents/MacOS")) { return folder }
        var level = [folder]
        for _ in 0..<3 {
            var next: [URL] = []
            for dir in level {
                let names = ((try? fileManager.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? [])
                    .filter { !$0.hasPrefix(".") }.sorted()
                if let app = names.first(where: { $0.lowercased().hasSuffix(".app") }) {
                    return dir.appending(path: app, directoryHint: .isDirectory)
                }
                for name in names {
                    let url = dir.appending(path: name, directoryHint: .isDirectory)
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue {
                        next.append(url)
                    }
                }
            }
            if next.isEmpty { break }
            level = next
        }
        return nil
    }

    /// The `steam://` link that has Steam start it.
    public var runURL: URL { SteamLink.run(appID: id) }
}
