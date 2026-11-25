import Foundation

/// The Steam store's public answers, which need no account or key: a game's details
/// (`appdetails`) and its library pictures (`IStoreBrowseService/GetItems`). SteamKit builds the
/// requests and reads the answers; the app fetches them its own way (DownloadKit, URLSession).
public enum SteamStore {
    /// `appdetails` for one game, in Steam's language name ("english", "french").
    public static func detailsURL(appID: String, language: String = "english") -> URL {
        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        components.queryItems = [URLQueryItem(name: "appids", value: appID), URLQueryItem(name: "l", value: language)]
        return components.url!
    }

    /// `GetItems` with the assets: the library pictures, whose file names are content hashes
    /// for newer games, so they can't be guessed.
    public static func assetsURL(appID: String, language: String = "english", country: String = "US") -> URL {
        let request = #"{"ids":[{"appid":\#(appID)}],"context":{"language":"\#(language)","country_code":"\#(country)"},"data_request":{"include_assets":true}}"#
        var components = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1")!
        components.queryItems = [URLQueryItem(name: "input_json", value: request)]
        return components.url!
    }

    /// Older games' portrait cover at its fixed address; check it exists (a HEAD request) first.
    public static func classicCoverURL(appID: String) -> URL {
        URL(string: "https://shared.steamstatic.com/store_item_assets/steam/apps/\(appID)/library_600x900_2x.jpg")!
    }

    /// Older games' logo at its fixed address; a miss downloads nothing.
    public static func classicLogoURL(appID: String) -> URL {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/logo.png")!
    }

    /// Steam's name for a language ("french") from a language code ("fr", "fr-CA"); "english" for
    /// one it doesn't have.
    public static func language(for code: String) -> String {
        let base = code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        if base == "zh" { return code.lowercased().contains("hant") || code.lowercased().hasSuffix("tw") ? "tchinese" : "schinese" }
        if base == "pt", code.lowercased().hasSuffix("br") { return "brazilian" }
        return languages[base] ?? "english"
    }

    static let languages = [
        "en": "english", "fr": "french", "de": "german", "es": "spanish", "it": "italian", "ja": "japanese",
        "pt": "portuguese", "nl": "dutch", "pl": "polish", "ru": "russian", "ko": "koreana", "sv": "swedish",
        "da": "danish", "fi": "finnish", "no": "norwegian", "nb": "norwegian", "tr": "turkish", "uk": "ukrainian",
        "cs": "czech", "hu": "hungarian", "el": "greek", "ro": "romanian", "th": "thai", "vi": "vietnamese",
        "bg": "bulgarian",
    ]

    // MARK: - Answers

    /// A game's details from `appdetails`, as the store gives them: the description is the
    /// store's text, which can hold HTML tags and entities.
    public struct Details: Sendable, Equatable {
        public var name: String?
        public var shortDescription: String?
        public var developers: [String] = []
        public var publishers: [String] = []
        public var genres: [String] = []
        /// The date as the store writes it ("16 Jul, 2026", "Coming soon").
        public var releaseText: String?
        public var comingSoon = false
        /// The wide header picture.
        public var headerImage: URL?
        public var screenshots: [URL] = []
        /// HLS playlists of the trailers, the highlighted ones first.
        public var trailers: [URL] = []
        /// Steam's category numbers (2 single-player, 1 multi-player, 9 co-op…).
        public var categoryIDs: Set<Int> = []
        public var metacriticScore: Int?
        /// Platforms the store sells it for: "mac", "windows", "linux".
        public var platforms: Set<String> = []

        public init() {}

        /// The release date, when `releaseText` is one (`SteamStore.releaseDate`).
        public var releaseDate: Date? { releaseText.flatMap(SteamStore.releaseDate) }

        /// The store sells a macOS version; nil when it didn't say.
        public var hasMacVersion: Bool? { platforms.isEmpty ? nil : platforms.contains("mac") }
    }

    /// `appdetails`' answer for `appID`; nil when the store has no page for it (`success` false).
    public static func details(from data: Data, appID: String) -> Details? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[appID] as? [String: Any], entry["success"] as? Bool == true,
              let game = entry["data"] as? [String: Any] else { return nil }
        func strings(_ key: String) -> [String] {
            (game[key] as? [String] ?? []).filter { !$0.isEmpty }
        }
        var details = Details()
        details.name = game["name"] as? String
        details.shortDescription = (game["short_description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        details.developers = strings("developers")
        details.publishers = strings("publishers")
        details.genres = (game["genres"] as? [[String: Any]] ?? []).compactMap { $0["description"] as? String }
        let release = game["release_date"] as? [String: Any]
        details.releaseText = (release?["date"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        details.comingSoon = release?["coming_soon"] as? Bool ?? false
        details.headerImage = (game["header_image"] as? String).flatMap(URL.init(string:))
        details.screenshots = (game["screenshots"] as? [[String: Any]] ?? []).compactMap { ($0["path_full"] as? String).flatMap(URL.init(string:)) }
        let movies = game["movies"] as? [[String: Any]] ?? []
        let ordered = movies.filter { $0["highlight"] as? Bool == true } + movies.filter { $0["highlight"] as? Bool != true }
        details.trailers = ordered.compactMap { ($0["hls_h264"] as? String).flatMap(URL.init(string:)) }
        details.categoryIDs = Set((game["categories"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? Int })
        details.metacriticScore = (game["metacritic"] as? [String: Any])?["score"] as? Int
        if let platforms = game["platforms"] as? [String: Any] {
            details.platforms = Set(platforms.compactMap { $0.value as? Bool == true ? $0.key : nil })
        }
        return details
    }

    /// The library pictures in `GetItems`' answer: the portrait cover, the wide hero picture
    /// and the logo, twice the size when there is one.
    public struct Assets: Sendable, Equatable {
        public var cover: URL?
        public var hero: URL?
        public var logo: URL?
        public var header: URL?

        public init(cover: URL? = nil, hero: URL? = nil, logo: URL? = nil, header: URL? = nil) {
            self.cover = cover
            self.hero = hero
            self.logo = logo
            self.header = header
        }
    }

    /// `GetItems`' asset file names, put into its URL format.
    public static func assets(from data: Data) -> Assets {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = ((root["response"] as? [String: Any])?["store_items"] as? [[String: Any]])?.first,
              let assets = item["assets"] as? [String: Any],
              let format = assets["asset_url_format"] as? String else { return Assets() }
        func url(_ keys: String...) -> URL? {
            for key in keys {
                guard let name = assets[key] as? String, !name.isEmpty else { continue }
                return URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/"
                    + format.replacingOccurrences(of: "${FILENAME}", with: name))
            }
            return nil
        }
        return Assets(cover: url("library_capsule_2x", "library_capsule"), hero: url("library_hero_2x", "library_hero"),
                      logo: url("library_logo_2x", "library_logo"), header: url("header"))
    }

    /// A date as the store writes it for its English page ("16 Jul, 2026", "Jul 16, 2026",
    /// "16 July, 2026"); nil for just a year, "Coming soon" or "Q3 2026".
    public static func releaseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["d MMM, yyyy", "MMM d, yyyy", "d MMMM, yyyy", "MMMM d, yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespaces)) { return date }
        }
        return nil
    }
}
