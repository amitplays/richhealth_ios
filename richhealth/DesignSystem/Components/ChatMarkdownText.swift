import SwiftUI

/// Lightweight markdown renderer for Richie's AI messages. Mirrors the Android TextFormatter
/// feature set — headings (#/##/###), bullet lists (- / *), numbered lists, **bold**, *italic*,
/// ~~strikethrough~~, and pipe-tables reflowed to "Key: value" lines (NOT a grid).
///
/// Deliberately line/regex based — NOT a full CommonMark engine. Block structure is parsed per line;
/// inline styling is delegated to `AttributedString(markdown:)`. Any inline-parse failure falls back
/// to plain text, so the view never crashes on malformed markdown.
struct ChatMarkdownText: View {
    let text: String
    var fontSize: CGFloat = 14

    // Parsed block model. Kept private — this view is the only consumer.
    private enum Block {
        case heading(String, level: Int)
        case bullet(String)
        case numbered(number: String, String)
        case tableRow(key: String, value: String)
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let content, let level):
            inline(content)
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(Theme.brandTeal)

        case .bullet(let content):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("•")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(Theme.brandTeal)
                inline(content)
                    .font(.system(size: fontSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .numbered(let number, let content):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("\(number).")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(Theme.brandTeal)
                inline(content)
                    .font(.system(size: fontSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .tableRow(let key, let value):
            if value.isEmpty {
                Text(key)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Theme.brandTeal)
            } else {
                Text(key + ": ")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Theme.brandTeal)
                    + inline(value).font(.system(size: fontSize))
            }

        case .paragraph(let content):
            inline(content)
                .font(.system(size: fontSize))
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return fontSize + 6
        case 2:  return fontSize + 4
        default: return fontSize + 2
        }
    }

    /// Inline markdown (**bold**, *italic*, ~~strikethrough~~). Falls back to plain text on failure.
    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(
            markdown: s,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(s)
    }

    // MARK: - Block parsing

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.isEmpty { i += 1; continue }

            // Pipe table — group the contiguous run of table rows, reflow to Key: value lines.
            if isTableRow(line) {
                var tableLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if isTableRow(l) { tableLines.append(l); i += 1 } else { break }
                }
                result.append(contentsOf: reflowTable(tableLines))
                continue
            }

            if let (level, content) = parseHeading(line) {
                result.append(.heading(content, level: level)); i += 1; continue
            }
            if let content = parseBullet(line) {
                result.append(.bullet(content)); i += 1; continue
            }
            if let (number, content) = parseNumbered(line) {
                result.append(.numbered(number: number, content)); i += 1; continue
            }

            result.append(.paragraph(line)); i += 1
        }
        return result
    }

    private func parseHeading(_ line: String) -> (Int, String)? {
        if line.hasPrefix("### ") { return (3, String(line.dropFirst(4))) }
        if line.hasPrefix("## ")  { return (2, String(line.dropFirst(3))) }
        if line.hasPrefix("# ")   { return (1, String(line.dropFirst(2))) }
        return nil
    }

    // "- item" or "* item" (the trailing space rules out *italic* being read as a bullet).
    private func parseBullet(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return String(line.dropFirst(2)) }
        return nil
    }

    // "1. item" or "12) item"
    private func parseNumbered(_ line: String) -> (String, String)? {
        guard let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else { return nil }
        let number = String(line[line.startIndex..<range.upperBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " .)"))
        let content = String(line[range.upperBound...])
        return (number, content)
    }

    // Require a leading pipe or ≥2 pipes, so a stray "a | b" sentence isn't misread as a table.
    private func isTableRow(_ line: String) -> Bool {
        guard line.contains("|") else { return false }
        return line.hasPrefix("|") || line.filter({ $0 == "|" }).count >= 2
    }

    private func tableCells(of line: String) -> [String] {
        var s = line
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // A separator row is all dashes/colons, e.g. "| --- | :--: |".
    private func isSeparatorRow(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private func reflowTable(_ lines: [String]) -> [Block] {
        var out: [Block] = []
        for line in lines {
            let cells = tableCells(of: line)
            if isSeparatorRow(cells) { continue }
            guard let key = cells.first, !key.isEmpty else { continue }
            let value = cells.dropFirst().joined(separator: " · ")
            out.append(.tableRow(key: key, value: value))
        }
        return out
    }
}
