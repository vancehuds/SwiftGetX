import Foundation

struct HTTPPartialDataStore: Sendable {
    static let maxSegmentCount = 128

    let savePath: String

    var singlePartURL: URL {
        URL(fileURLWithPath: savePath + ".part")
    }

    var manifestURL: URL {
        URL(fileURLWithPath: savePath + ".segments")
    }

    var mergeURL: URL {
        URL(fileURLWithPath: savePath + ".merge")
    }

    func segmentURL(index: Int) -> URL {
        URL(fileURLWithPath: savePath + ".part\(index)")
    }

    var existingDataURLs: [URL] {
        dataURLPairs(to: self)
            .map(\.source)
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && !isDirectory.boolValue
            }
    }

    var hasData: Bool {
        !existingDataURLs.isEmpty
    }

    var preferredDataURL: URL? {
        existingDataURLs
            .map { ($0, Self.localSize(at: $0)) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.path < rhs.0.path
            }
            .first?
            .0
    }

    var downloadedBytes: Int64 {
        max(Self.localSize(at: singlePartURL), segmentBytes)
    }

    func removeData() {
        for url in existingDataURLs {
            _ = try? FileSystemSafety.removeSafely(
                url,
                allowedRoot: URL(fileURLWithPath: savePath).deletingLastPathComponent(),
                allowsDirectories: false
            )
        }
    }

    func moveData(to newSavePath: String) throws {
        let targetStore = HTTPPartialDataStore(savePath: newSavePath)
        let pairs = dataURLPairs(to: targetStore)
            .filter { FileManager.default.fileExists(atPath: $0.source.path) }
        guard !pairs.isEmpty else { return }

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: newSavePath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        for pair in pairs {
            if FileManager.default.fileExists(atPath: pair.destination.path) {
                try FileSystemSafety.removeSafely(
                    pair.destination,
                    allowedRoot: URL(fileURLWithPath: newSavePath).deletingLastPathComponent(),
                    allowsDirectories: false
                )
            }
            try FileManager.default.moveItem(at: pair.source, to: pair.destination)
        }
    }

    private var segmentBytes: Int64 {
        (0..<Self.maxSegmentCount).reduce(Int64(0)) { partialResult, index in
            partialResult + Self.localSize(at: segmentURL(index: index))
        }
    }

    private func dataURLPairs(to destinationStore: HTTPPartialDataStore) -> [(source: URL, destination: URL)] {
        var pairs = [
            (singlePartURL, destinationStore.singlePartURL),
            (manifestURL, destinationStore.manifestURL),
            (mergeURL, destinationStore.mergeURL)
        ]
        pairs.append(contentsOf: (0..<Self.maxSegmentCount).map { index in
            (segmentURL(index: index), destinationStore.segmentURL(index: index))
        })
        return pairs
    }

    static func localSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
