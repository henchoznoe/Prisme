import Foundation

extension ConversionEngine {
    func table(_ action: ConversionAction, file: URL, options: ConversionOptions) async throws -> [URL] {
        let ext = action.outputExtension ?? "csv"
        let inputExt = file.pathExtension.lowercased()
        let rows: [[String]]
        if inputExt == "json" {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            guard let objects = value as? [[String: Any]] else { throw ConversionError.unsupported("Le JSON doit contenir un tableau d’objets.") }
            let headers = Array(Set(objects.flatMap { $0.keys })).sorted()
            rows = [headers] + objects.map { object in headers.map { key in jsonCell(object[key]) } }
        } else { rows = try parseDelimited(readText(file), separator: inputExt == "tsv" ? "\t" : ",") }
        guard !rows.isEmpty else { throw ConversionError.invalid("Le tableau est vide.") }
        return [try await stagedOutput(source: file, suffix: "-converti", ext: ext, options: options) { output in
            if ext == "json" {
                var used = Set<String>()
                let headers = rows[0].enumerated().map { index, value -> String in
                    let base = value.isEmpty ? "colonne_\(index + 1)" : value
                    var candidate = base; var duplicate = 2
                    while used.contains(candidate) { candidate = "\(base)_\(duplicate)"; duplicate += 1 }
                    used.insert(candidate); return candidate
                }
                guard rows.dropFirst().allSatisfy({ $0.count == headers.count }) else { throw ConversionError.invalid("Les lignes n’ont pas toutes le même nombre de colonnes.") }
                let objects = rows.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(headers, $0)) }
                try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]).write(to: output)
            } else {
                let separator: Character = ext == "tsv" ? "\t" : ","
                let text = rows.map { $0.map { quoteCell($0, separator: separator) }.joined(separator: String(separator)) }.joined(separator: "\r\n") + "\r\n"
                try text.write(to: output, atomically: true, encoding: .utf8)
            }
        }]
    }

    func subtitle(_ action: ConversionAction, file: URL, options: ConversionOptions) async throws -> [URL] {
        let ext = action.outputExtension ?? "srt"
        let cues = try parseSubtitles(readText(file))
        guard !cues.isEmpty else { throw ConversionError.invalid("Aucun sous-titre avec minutage n’a été trouvé.") }
        return [try await stagedOutput(source: file, suffix: "-converti", ext: ext, options: options) { output in
            let text: String
            if ext == "txt" { text = cues.map(\.text).joined(separator: "\n\n") + "\n" }
            else if ext == "vtt" {
                text = "WEBVTT\n\n" + cues.map { "\(timestamp($0.start, vtt: true)) --> \(timestamp($0.end, vtt: true))\n\($0.text)\n" }.joined(separator: "\n")
            } else {
                text = cues.enumerated().map { index, cue in "\(index + 1)\n\(timestamp(cue.start, vtt: false)) --> \(timestamp(cue.end, vtt: false))\n\(cue.text)\n" }.joined(separator: "\n")
            }
            try text.write(to: output, atomically: true, encoding: .utf8)
        }]
    }
}

// State-machine parsing preserves quoted delimiters, escaped quotes, and embedded line breaks.
func parseDelimited(_ text: String, separator: Character) throws -> [[String]] {
    let characters = Array(text)
    var rows: [[String]] = []; var row: [String] = []; var field = ""
    var quoted = false; var closedQuote = false; var index = 0
    while index < characters.count {
        let char = characters[index]
        if quoted {
            if char == "\"" {
                if index + 1 < characters.count, characters[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted = false; closedQuote = true }
            } else { field.append(char) }
        } else if char == separator {
            row.append(field); field = ""; closedQuote = false
        } else if char == "\n" || char == "\r" || char == "\r\n" {
            row.append(field); rows.append(row); row = []; field = ""; closedQuote = false
            if char == "\r", index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
        } else if char == "\"", field.isEmpty, !closedQuote { quoted = true }
        else {
            if closedQuote || char == "\"" { throw ConversionError.invalid("Guillemets mal formés dans le tableau.") }
            field.append(char)
        }
        index += 1
    }
    guard !quoted else { throw ConversionError.invalid("Un champ entre guillemets n’est pas fermé.") }
    if !field.isEmpty || !row.isEmpty || closedQuote { row.append(field); rows.append(row) }
    return rows
}

private func quoteCell(_ value: String, separator: Character) -> String {
    if value.contains(separator) || value.contains("\"") || value.contains("\n") || value.contains("\r") {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return value
}

private func jsonCell(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "" }
    if let value = value as? String { return value }
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) { return String(decoding: data, as: UTF8.self) }
    return String(describing: value)
}

struct SubtitleCue { let start: Double; let end: Double; let text: String }

func parseSubtitles(_ text: String) throws -> [SubtitleCue] {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let blocks = normalized.components(separatedBy: "\n\n")
    var cues: [SubtitleCue] = []
    for block in blocks {
        let lines = block.components(separatedBy: "\n")
        if let first = lines.first?.trimmingCharacters(in: .whitespaces), first == "NOTE" || first.hasPrefix("NOTE ") || first == "STYLE" || first == "REGION" { continue }
        guard let index = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
        let sides = lines[index].components(separatedBy: "-->")
        guard sides.count == 2,
              let start = parseTimestamp(sides[0].trimmingCharacters(in: .whitespaces)),
              let endToken = sides[1].split(whereSeparator: \.isWhitespace).first,
              let end = parseTimestamp(String(endToken)), end >= start else { throw ConversionError.invalid("Minutage de sous-titre invalide.") }
        let content = lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)
        cues.append(.init(start: start, end: end, text: content))
    }
    return cues
}

private func parseTimestamp(_ value: String) -> Double? {
    let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":")
    guard (2...3).contains(parts.count), let seconds = Double(parts[parts.count - 1]), seconds.isFinite, (0..<60).contains(seconds), let minutes = Double(parts[parts.count - 2]), minutes.isFinite, minutes.rounded() == minutes, (0..<60).contains(minutes) else { return nil }
    let hours = parts.count == 3 ? Double(parts[0]) : 0
    guard let hours, hours.isFinite, hours.rounded() == hours, hours >= 0, hours <= 100_000 else { return nil }
    return hours * 3600 + minutes * 60 + seconds
}

private func timestamp(_ seconds: Double, vtt: Bool) -> String {
    let value = Int((seconds * 1000).rounded())
    return String(format: "%02d:%02d:%02d%@%03d", value / 3_600_000, (value / 60_000) % 60, (value / 1000) % 60, vtt ? "." : ",", value % 1000)
}
