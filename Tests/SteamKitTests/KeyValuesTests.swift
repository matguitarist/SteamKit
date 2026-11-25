import Foundation
import Testing
@testable import SteamKit

struct KeyValuesTests {
    @Test func readsNestedBlocksIgnoringCase() {
        let vdf = KeyValues.parse(#""a" { "path" "C:\\Games" "apps" { "1" "2" } } // comment"#)
        #expect(vdf["a"]?["path"]?.string == #"C:\Games"#)
        #expect(vdf["A"]?["APPS"]?["1"]?.string == "2")
        #expect(vdf["a"]?["apps"]?.string == nil)
        #expect(vdf["missing"] == nil)
    }

    @Test func readsEscapesCommentsAndBareWords() {
        let vdf = KeyValues.parse("""
        // a comment
        "AppState"
        {
            "name"  "Say \\"Hi\\"\\tthere\\nnow" // trailing comment
            "NoQuotes" 12
            Bare word
            "Nested" { "a" "b" }
        }
        """)
        #expect(vdf["appstate"]?["name"]?.string == "Say \"Hi\"\tthere\nnow")
        #expect(vdf["AppState"]?["noquotes"]?.int == 12)
        #expect(vdf["AppState"]?["bare"]?.string == "word")
        #expect(vdf["AppState"]?["Nested"]?["a"]?.string == "b")
    }

    @Test func keepsABackslashThatIsntAnEscape() {
        // Written by hand, without escapes.
        #expect(KeyValues.parse(#""path" "C:\Program Files\Steam""#)["path"]?.string == #"C:\Program Files\Steam"#)
    }

    @Test func aBraceInsideQuotesIsText() {
        let vdf = KeyValues.parse(#""a" { "close" "}" "open" "{" } "b" "c""#)
        #expect(vdf["a"]?["close"]?.string == "}")
        #expect(vdf["a"]?["open"]?.string == "{")
        #expect(vdf["b"]?.string == "c")
    }

    @Test func skipsConditionsBOMAndCRLF() {
        let vdf = KeyValues.parse("\u{FEFF}\"root\"\r\n{\r\n\t\"mac\"\t\"1\" [$OSX]\r\n\t\"win\"\t\"2\" [$WIN32]\r\n}\r\n")
        #expect(vdf["root"]?["mac"]?.string == "1")
        #expect(vdf["root"]?["win"]?.string == "2")
        #expect(vdf["root"]?.pairs.count == 2)
    }

    @Test func survivesBrokenFiles() {
        // Cut short inside a block, inside a string, after a key.
        #expect(KeyValues.parse(#""a" { "b" "c" "d" {"#)["a"]?["b"]?.string == "c")
        #expect(KeyValues.parse(#""a" "unterminated"#)["a"]?.string == "unterminated")
        #expect(KeyValues.parse(#""a" { "b" }"#)["a"] == .block([]))
        // A stray closing brace at the top, and a block without a key.
        let vdf = KeyValues.parse(#"} "a" "1" { "x" "y" } "b" "2""#)
        #expect(vdf["a"]?.string == "1")
        #expect(vdf["b"]?.string == "2")
        #expect(KeyValues.parse("") == .block([]))
        // Very deep nesting doesn't exhaust the stack.
        let deep = String(repeating: "\"k\" {", count: 5_000) + String(repeating: "}", count: 5_000) + #" "after" "yes""#
        #expect(KeyValues.parse(deep)["after"]?.string == "yes")
    }

    @Test func theFirstOfTwoKeysWins() {
        let vdf = KeyValues.parse(#""a" "1" "A" "2""#)
        #expect(vdf["a"]?.string == "1")
        #expect(vdf.pairs.map(\.key) == ["a", "A"])
    }

    @Test func readsAFileWithBytesThatArentUTF8() throws {
        let scratch = try Scratch()
        defer { scratch.clean() }
        let url = scratch.root.appending(path: "bad.vdf")
        try (Data(#""name" "Caf"#.utf8) + Data([0xE9]) + Data(#"" "ok" "1""#.utf8)).write(to: url)
        let vdf = try #require(KeyValues.read(url))
        #expect(vdf["name"]?.string == "Caf\u{FFFD}")
        #expect(vdf["ok"]?.string == "1")
        #expect(KeyValues.read(scratch.root.appending(path: "none.vdf")) == nil)
    }

    @Test func formattedTextReadsBackTheSame() {
        let value: KeyValues = .block([
            ("root", .block([("path", .text(#"C:\Games "quoted""#)), ("lines", .text("a\nb\tc")), ("empty", .block([]))])),
            ("top", .text("1")),
        ])
        #expect(KeyValues.parse(value.formatted) == value)
        #expect(value.formatted.contains("\"path\"\t\t\"C:\\\\Games \\\"quoted\\\"\""))
    }

    @Test func settingReplacesOrAdds() {
        let value = KeyValues.parse(#""a" "1" "b" "2""#)
        #expect(value.setting("A", to: .text("9"))["a"]?.string == "9")
        #expect(value.setting("c", to: .text("3")).pairs.map(\.key) == ["a", "b", "c"])
        #expect(KeyValues.text("x").setting("k", to: .text("v")) == .block([("k", .text("v"))]))
    }

    @Test func numbers() {
        #expect(KeyValues.text(" 1026 ").int == 1026)
        #expect(KeyValues.text("76561198000000001").int64 == 76_561_198_000_000_001)
        #expect(KeyValues.text("x").int == nil)
        #expect(KeyValues.block([]).int == nil)
    }
}
