import Foundation

/// Registro en fichero de texto, una línea por mensaje:
/// `2026-11-17 18:03:12.345 [gps] mensaje`.
///
/// Sin Xcode no hay consola, así que este fichero es la única forma de ver
/// qué pasa dentro de la app. Cuando supera `maxBytes` se queda con la mitad
/// más reciente.
public final class FileLog: @unchecked Sendable {
    public let fileURL: URL
    public let maxBytes: Int

    private let queue = DispatchQueue(label: "MetroCore.FileLog")
    private let formatter: DateFormatter
    private let now: () -> Date

    public init(
        fileURL: URL,
        maxBytes: Int = 1_000_000,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.now = now

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.formatter = formatter
    }

    /// Añade una línea al fichero y la devuelve ya formateada.
    @discardableResult
    public func write(_ message: String, category: String = "app") -> String {
        queue.sync { () -> String in
            let singleLine = message
                .split(whereSeparator: { $0.isNewline })
                .joined(separator: " | ")
            let line = "\(formatter.string(from: now())) [\(category)] \(singleLine)"
            append(line)
            return line
        }
    }

    public func readAll() -> String {
        queue.sync { () -> String in
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
    }

    /// Las últimas `count` líneas, de la más antigua a la más reciente.
    public func tail(lines count: Int) -> [String] {
        readAll()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(max(count, 0))
            .map { String($0) }
    }

    public func clear() {
        queue.sync {
            _ = try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Privado (siempre dentro de `queue`)

    private func append(_ line: String) {
        let data = Data((line + "\n").utf8)
        let manager = FileManager.default

        if !manager.fileExists(atPath: fileURL.path) {
            _ = try? manager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = manager.createFile(atPath: fileURL.path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
        _ = try? handle.close()

        trimIfNeeded()
    }

    private func trimIfNeeded() {
        guard maxBytes > 0,
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size > maxBytes,
              let data = try? Data(contentsOf: fileURL)
        else {
            return
        }

        // Conserva la mitad final, empezando en un principio de línea.
        let keepFrom = max(data.count - maxBytes / 2, 0)
        var start = keepFrom
        if let newline = data[keepFrom...].firstIndex(of: 0x0A) {
            start = newline + 1
        }
        let trimmed = data.subdata(in: start..<data.count)
        _ = try? trimmed.write(to: fileURL, options: .atomic)
    }
}
