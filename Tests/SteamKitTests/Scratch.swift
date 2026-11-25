import Foundation

/// A folder under the temporary directory, removed by `clean()`. Tests never touch anything else.
struct Scratch {
    let root: URL

    init(_ name: String = #function) throws {
        let safe = name.filter { $0.isLetter || $0.isNumber }
        root = FileManager.default.temporaryDirectory
            .appending(path: "SteamKitTests-\(safe)-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func url(_ path: String) -> URL { root.appending(path: path, directoryHint: .isDirectory) }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func folder(_ path: String) throws {
        try FileManager.default.createDirectory(at: url(path), withIntermediateDirectories: true)
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
}
