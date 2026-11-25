import Foundation

/// An account that signed in to Steam on this Mac, from `config/loginusers.vdf`.
public struct SteamUser: Sendable, Equatable, Identifiable {
    /// The 64-bit Steam ID ("76561198032678845").
    public var id: String
    public var accountName: String
    /// The name others see.
    public var personaName: String
    /// Steam keeps it signed in.
    public var remembersPassword: Bool
    /// The account Steam signed in last.
    public var isMostRecent: Bool
    public var lastSignIn: Date?

    public init(id: String, accountName: String = "", personaName: String = "", remembersPassword: Bool = false,
                isMostRecent: Bool = false, lastSignIn: Date? = nil) {
        self.id = id
        self.accountName = accountName
        self.personaName = personaName
        self.remembersPassword = remembersPassword
        self.isMostRecent = isMostRecent
        self.lastSignIn = lastSignIn
    }

    /// The 32-bit account ID, which names its `userdata` folder; nil for an ID that isn't a
    /// personal account's.
    public var accountID: UInt32? {
        guard let steamID = UInt64(id), steamID > Self.individualBase else { return nil }
        return UInt32(exactly: steamID - Self.individualBase)
    }

    static let individualBase: UInt64 = 76_561_197_960_265_728
}

extension Steam {
    /// The accounts in config/loginusers.vdf, the most recent first.
    public func users() -> [SteamUser] {
        guard let users = KeyValues.read(root.appending(path: "config/loginusers.vdf"))?["users"] else { return [] }
        let list = users.pairs.map { id, entry in
            SteamUser(id: id, accountName: entry["AccountName"]?.string ?? "", personaName: entry["PersonaName"]?.string ?? "",
                      remembersPassword: entry["RememberPassword"]?.string == "1", isMostRecent: entry["MostRecent"]?.string == "1",
                      lastSignIn: entry["Timestamp"]?.int64.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil })
        }
        return list.filter(\.isMostRecent) + list.filter { !$0.isMostRecent }
    }

    /// Steam remembers a signed-in account and its last session didn't end signed out
    /// (logs/connection_log.txt). A game started through Steam while it waits for a sign-in never
    /// opens, so an app asks the person to sign in first.
    public var isSignedIn: Bool {
        guard users().contains(where: \.remembersPassword) else { return false }
        let log = try? String(contentsOf: root.appending(path: "logs/connection_log.txt"), encoding: .utf8)
        return !(log.map(Self.lastSessionSignedOut) ?? false)
    }

    /// The connection log's last account is [U:1:0]: Steam ended its last session with nobody
    /// signed in. A session replaced or disconnected keeps its account and signs in again by itself.
    public static func lastSessionSignedOut(_ log: String) -> Bool {
        for line in log.split(whereSeparator: \.isNewline).reversed() {
            guard let start = line.range(of: "[U:1:") else { continue }
            return line[start.upperBound...].prefix { $0 != "]" } == "0"
        }
        return false
    }

    /// `userdata/<account ID>`: an account's settings, screenshots, and the cloud saves of games
    /// that keep them there.
    public func userdataFolder(accountID: UInt32) -> URL {
        root.appending(path: "userdata/\(accountID)", directoryHint: .isDirectory)
    }

    /// The `userdata` folders there are, one per account that signed in, by account ID.
    public func userdataFolders() -> [URL] {
        let userdata = root.appending(path: "userdata", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: userdata.path(percentEncoded: false))) ?? []
        return names.compactMap(UInt32.init).filter { $0 != 0 }.sorted()
            .map { userdata.appending(path: String($0), directoryHint: .isDirectory) }
    }
}
