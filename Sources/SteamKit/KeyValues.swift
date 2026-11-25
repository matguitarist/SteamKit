import Foundation

/// Valve's KeyValues text format, which Steam keeps its files in (libraryfolders.vdf,
/// appmanifest_<id>.acf, loginusers.vdf, config.vdf): quoted keys, each followed by a quoted
/// value or a `{ … }` block.
///
/// The parser never fails. Comments (`//`), bare words, conditions (`[$OSX]`), a byte order
/// mark, CRLF lines and stray braces are skipped or read as Steam reads them; anything cut short
/// keeps what came before.
public indirect enum KeyValues: Sendable, Equatable {
    case text(String)
    case block([(key: String, value: KeyValues)])

    public static func == (a: KeyValues, b: KeyValues) -> Bool {
        switch (a, b) {
        case let (.text(x), .text(y)): x == y
        case let (.block(x), .block(y)): x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    /// The value of the first `key`, ignoring case as Steam does.
    public subscript(_ key: String) -> KeyValues? {
        guard case let .block(pairs) = self else { return nil }
        return pairs.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    /// The text of a value; nil for a block.
    public var string: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    /// The text as a whole number ("4", " 1026 "); nil when it isn't one.
    public var int: Int? { string.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }

    /// The text as a 64-bit number (sizes, Steam IDs).
    public var int64: Int64? { string.flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) } }

    /// The pairs of a block, in file order; empty for a text.
    public var pairs: [(key: String, value: KeyValues)] {
        if case let .block(pairs) = self { return pairs }
        return []
    }

    /// A copy of this block with `key` set: the first pair with that key (any case) replaced,
    /// else a pair added at the end. A text becomes a block.
    public func setting(_ key: String, to value: KeyValues) -> KeyValues {
        var pairs = pairs
        if let index = pairs.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            pairs[index].value = value
        } else {
            pairs.append((key, value))
        }
        return .block(pairs)
    }

    // MARK: - Reading

    /// The whole text as one block.
    public static func parse(_ text: String) -> KeyValues {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        return .block(parser.block(depth: 0))
    }

    /// A file's contents as one block; nil when it can't be read. Bytes that aren't UTF-8 become
    /// U+FFFD rather than losing the file.
    public static func read(_ url: URL) -> KeyValues? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Writing

    /// The text Steam would write: tab-indented, quoted, with `\\`, `\"`, `\n` and `\t` escaped.
    /// A `.block` at the top writes its pairs; parse(formatted) gives the same value back.
    public var formatted: String {
        var out = ""
        Self.write(pairs, depth: 0, into: &out)
        return out
    }

    private static func write(_ pairs: [(key: String, value: KeyValues)], depth: Int, into out: inout String) {
        let indent = String(repeating: "\t", count: depth)
        for (key, value) in pairs {
            switch value {
            case let .text(text):
                out += "\(indent)\"\(escaped(key))\"\t\t\"\(escaped(text))\"\n"
            case let .block(inner):
                out += "\(indent)\"\(escaped(key))\"\n\(indent){\n"
                write(inner, depth: depth + 1, into: &out)
                out += "\(indent)}\n"
            }
        }
    }

    private static func escaped(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: - Parser

    private struct Parser {
        enum Token { case text(String), open, close }

        let scalars: [Unicode.Scalar]
        var index = 0

        /// Deeper blocks than this are read as empty, so a hostile file can't exhaust the stack.
        static let maxDepth = 200

        mutating func block(depth: Int) -> [(key: String, value: KeyValues)] {
            var pairs: [(key: String, value: KeyValues)] = []
            while let token = next() {
                switch token {
                case .close:
                    if depth > 0 { return pairs }
                    // A stray brace at the top: skip it and keep reading.
                case .open:
                    // A block with no key: read past it.
                    _ = block(depth: depth + 1)
                case .text(let key):
                    switch next() {
                    case .text(let value)?:
                        pairs.append((key, .text(value)))
                    case .open?:
                        if depth >= Self.maxDepth {
                            skipBlock()
                            pairs.append((key, .block([])))
                        } else {
                            pairs.append((key, .block(block(depth: depth + 1))))
                        }
                    case .close?:
                        // A key with no value ends its block.
                        if depth > 0 { return pairs }
                    case nil:
                        return pairs
                    }
                }
            }
            return pairs
        }

        mutating func skipBlock() {
            var level = 1
            while level > 0, let token = next() {
                if case .open = token { level += 1 }
                if case .close = token { level -= 1 }
            }
        }

        mutating func next() -> Token? {
            while index < scalars.count {
                let scalar = scalars[index]
                if scalar.properties.isWhitespace || scalar == "\u{FEFF}" {
                    index += 1
                } else if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "/" {
                    while index < scalars.count, scalars[index] != "\n" { index += 1 }
                } else if scalar == "{" {
                    index += 1
                    return .open
                } else if scalar == "}" {
                    index += 1
                    return .close
                } else if scalar == "\"" {
                    return .text(quoted())
                } else {
                    let word = bare()
                    // A condition such as [$OSX] or [!$WIN32] belongs to the pair before it.
                    if word.hasPrefix("["), word.hasSuffix("]") { continue }
                    return .text(word)
                }
            }
            return nil
        }

        /// A quoted string; \n, \t, \r, \\ and \" are escapes, and any other backslash is kept
        /// as it is (a Windows path written without escapes keeps its backslashes).
        mutating func quoted() -> String {
            index += 1
            var text = String.UnicodeScalarView()
            while index < scalars.count, scalars[index] != "\"" {
                if scalars[index] == "\\", index + 1 < scalars.count {
                    let escape = scalars[index + 1]
                    switch escape {
                    case "n": text.append("\n")
                    case "t": text.append("\t")
                    case "r": text.append("\r")
                    case "\\", "\"": text.append(escape)
                    default:
                        text.append("\\")
                        text.append(escape)
                    }
                    index += 2
                } else {
                    text.append(scalars[index])
                    index += 1
                }
            }
            index += 1 // the closing quote, or past the end
            return String(text)
        }

        /// An unquoted word, up to white space, a brace or a quote.
        mutating func bare() -> String {
            var text = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                if scalar.properties.isWhitespace || scalar == "{" || scalar == "}" || scalar == "\"" { break }
                if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "/" { break }
                text.append(scalar)
                index += 1
            }
            return String(text)
        }
    }
}
