import Foundation
import Testing
@testable import SteamKit

struct SteamStoreTests {
    @Test func readsAppDetails() throws {
        let json = """
        {"3808690":{"success":true,"data":{
          "name":"Spore Thing",
          "short_description":"You are a disease. Infect &amp;amp; evolve.",
          "developers":["Aberrant Labs"],"publishers":["Slug Disco",""],
          "genres":[{"id":"1","description":"Action"},{"id":"23","description":"Indie"}],
          "release_date":{"coming_soon":false,"date":"16 Jul, 2026"},
          "header_image":"https://example.com/header.jpg",
          "platforms":{"windows":true,"mac":true,"linux":false},
          "categories":[{"id":2,"description":"Single-player"},{"id":39,"description":"Shared/Split Screen Co-op"}],
          "metacritic":{"score":89},
          "screenshots":[{"id":0,"path_full":"https://example.com/ss1.jpg"},{"id":1,"path_full":"https://example.com/ss2.jpg"}],
          "movies":[{"id":1,"hls_h264":"https://example.com/1/master.m3u8"},
                    {"id":2,"hls_h264":"https://example.com/2/master.m3u8","highlight":true}]
        }}}
        """
        let details = try #require(SteamStore.details(from: Data(json.utf8), appID: "3808690"))
        #expect(details.name == "Spore Thing")
        // The store's own text: the app turns HTML and entities into plain text.
        #expect(details.shortDescription == "You are a disease. Infect &amp;amp; evolve.")
        #expect(details.developers == ["Aberrant Labs"])
        #expect(details.publishers == ["Slug Disco"])
        #expect(details.genres == ["Action", "Indie"])
        #expect(details.releaseText == "16 Jul, 2026" && !details.comingSoon)
        #expect(details.headerImage?.absoluteString == "https://example.com/header.jpg")
        #expect(details.screenshots.count == 2)
        // The highlighted trailer first.
        #expect(details.trailers.map(\.absoluteString) == ["https://example.com/2/master.m3u8", "https://example.com/1/master.m3u8"])
        #expect(details.categoryIDs == [2, 39])
        #expect(details.metacriticScore == 89)
        #expect(details.platforms == ["windows", "mac"])
        #expect(details.hasMacVersion == true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = try #require(details.releaseDate)
        #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2026, month: 7, day: 16))
    }

    @Test func failedOrOtherDetailsGiveNothing() {
        #expect(SteamStore.details(from: Data(#"{"1":{"success":false}}"#.utf8), appID: "1") == nil)
        #expect(SteamStore.details(from: Data(#"{"2":{"success":true,"data":{}}}"#.utf8), appID: "1") == nil)
        #expect(SteamStore.details(from: Data("not json".utf8), appID: "1") == nil)
        #expect(SteamStore.details(from: Data(#"{"1":{"success":true,"data":{}}}"#.utf8), appID: "1")?.hasMacVersion == nil)
    }

    @Test func buildsAssetURLsFromTheirFormat() {
        let json = """
        {"response":{"store_items":[{"assets":{
          "asset_url_format":"steam/apps/3808690/${FILENAME}?t=1",
          "library_capsule":"aa/library_capsule.jpg","library_capsule_2x":"bb/library_capsule_2x.jpg",
          "library_hero":"cc/library_hero.jpg","header":"header.jpg"
        }}]}}
        """
        let assets = SteamStore.assets(from: Data(json.utf8))
        let base = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/3808690/"
        #expect(assets.cover?.absoluteString == base + "bb/library_capsule_2x.jpg?t=1")
        #expect(assets.hero?.absoluteString == base + "cc/library_hero.jpg?t=1")
        #expect(assets.header?.absoluteString == base + "header.jpg?t=1")
        #expect(assets.logo == nil)
        #expect(SteamStore.assets(from: Data("{}".utf8)) == SteamStore.Assets())
    }

    @Test func requestURLs() {
        #expect(SteamStore.detailsURL(appID: "367520", language: "french").query()?.contains("l=french") == true)
        #expect(SteamStore.detailsURL(appID: "367520").query()?.contains("appids=367520") == true)
        let assets = SteamStore.assetsURL(appID: "367520").absoluteString
        #expect(assets.hasPrefix("https://api.steampowered.com/IStoreBrowseService/GetItems/v1?input_json="))
        #expect(assets.removingPercentEncoding?.contains(#""appid":367520"#) == true)
        #expect(SteamStore.classicCoverURL(appID: "1").absoluteString.hasSuffix("/steam/apps/1/library_600x900_2x.jpg"))
        #expect(SteamStore.classicLogoURL(appID: "1").absoluteString.hasSuffix("/steam/apps/1/logo.png"))
    }

    @Test func languages() {
        #expect(SteamStore.language(for: "fr") == "french")
        #expect(SteamStore.language(for: "fr-CA") == "french")
        #expect(SteamStore.language(for: "en") == "english")
        #expect(SteamStore.language(for: "pt-BR") == "brazilian")
        #expect(SteamStore.language(for: "zh-Hant") == "tchinese")
        #expect(SteamStore.language(for: "zh-Hans") == "schinese")
        #expect(SteamStore.language(for: "xx") == "english")
    }

    @Test func readsBothDateOrders() {
        #expect(SteamStore.releaseDate("Feb 24, 2017") != nil)
        #expect(SteamStore.releaseDate("24 Feb, 2017") != nil)
        #expect(SteamStore.releaseDate("24 February, 2017") != nil)
        #expect(SteamStore.releaseDate("Coming soon") == nil)
        #expect(SteamStore.releaseDate("2017") == nil)
    }
}
