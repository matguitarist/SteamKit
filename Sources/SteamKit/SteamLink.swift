import Foundation

/// Links that have the Steam client do something. Open them with `NSWorkspace.shared.open`.
public enum SteamLink {
    /// Starts the game through Steam, which keeps it updated and signed in, with its overlay and
    /// cloud saves: `steam://rungameid/<id>`. Steam passes no arguments or environment on.
    public static func run(appID: String) -> URL {
        URL(string: "steam://rungameid/\(appID)")!
    }

    /// The game's page in Steam's library: `steam://nav/games/details/<id>`.
    public static func libraryPage(appID: String) -> URL {
        URL(string: "steam://nav/games/details/\(appID)")!
    }

    /// Asks Steam to install the game: `steam://install/<id>`.
    public static func install(appID: String) -> URL {
        URL(string: "steam://install/\(appID)")!
    }

    /// The game's store page in the Steam client: `steam://store/<id>`.
    public static func storePage(appID: String) -> URL {
        URL(string: "steam://store/\(appID)")!
    }

    /// The game's store page on the web: `https://store.steampowered.com/app/<id>/`. Nil for an ID
    /// that isn't a number (a non-Steam shortcut's).
    public static func webStorePage(appID: String) -> URL? {
        guard !appID.isEmpty, appID.allSatisfy(\.isASCII), appID.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://store.steampowered.com/app/\(appID)/")
    }
}
