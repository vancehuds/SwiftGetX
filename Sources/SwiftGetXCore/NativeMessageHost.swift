import Foundation

public enum NativeMessageHost {
    public static func decodeMessages(from data: Data) throws -> [BrowserDownloadMessage] {
        var offset = 0
        var messages: [BrowserDownloadMessage] = []

        while offset < data.count {
            guard data.count - offset >= 4 else {
                throw NativeMessageError.incompleteLengthPrefix
            }

            let length = decodeLength(data[offset..<(offset + 4)])
            offset += 4

            let end = offset + length
            guard end <= data.count else {
                throw NativeMessageError.incompletePayload
            }

            let payload = data[offset..<end]
            messages.append(try JSONDecoder().decode(BrowserDownloadMessage.self, from: payload))
            offset = end
        }

        return messages
    }

    public static func readMessage(from input: FileHandle = .standardInput) throws -> BrowserDownloadMessage? {
        let lengthData = input.readData(ofLength: 4)
        guard !lengthData.isEmpty else { return nil }
        guard lengthData.count == 4 else {
            throw NativeMessageError.incompleteLengthPrefix
        }

        let length = decodeLength(lengthData)
        let payload = input.readData(ofLength: length)
        guard payload.count == length else {
            throw NativeMessageError.incompletePayload
        }

        return try JSONDecoder().decode(BrowserDownloadMessage.self, from: payload)
    }

    public static func encodeResponse(_ response: NativeMessageResponse) throws -> Data {
        let payload = try JSONEncoder().encode(response)
        var length = UInt32(payload.count).littleEndian
        var data = Data(bytes: &length, count: 4)
        data.append(payload)
        return data
    }

    private static func decodeLength(_ data: Data) -> Int {
        let bytes = Array(data)
        let value = UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
        return Int(value)
    }
}

public struct NativeMessageResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var message: String
    public var version: String?

    public init(ok: Bool, message: String, version: String? = nil) {
        self.ok = ok
        self.message = message
        self.version = version
    }
}

public enum NativeMessageError: Error, Equatable {
    case incompleteLengthPrefix
    case incompletePayload
}
