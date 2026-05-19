import Foundation

public enum NativeMessageHost {
    public static func decodeMessages(from data: Data) throws -> [BrowserDownloadMessage] {
        var offset = 0
        var messages: [BrowserDownloadMessage] = []

        while offset < data.count {
            guard data.count - offset >= 4 else {
                throw NativeMessageError.incompleteLengthPrefix
            }

            let length = data[offset..<(offset + 4)].withUnsafeBytes { pointer in
                pointer.load(as: UInt32.self).littleEndian
            }
            offset += 4

            let end = offset + Int(length)
            guard end <= data.count else {
                throw NativeMessageError.incompletePayload
            }

            let payload = data[offset..<end]
            messages.append(try JSONDecoder().decode(BrowserDownloadMessage.self, from: payload))
            offset = end
        }

        return messages
    }

    public static func encodeResponse(_ response: NativeMessageResponse) throws -> Data {
        let payload = try JSONEncoder().encode(response)
        var length = UInt32(payload.count).littleEndian
        var data = Data(bytes: &length, count: 4)
        data.append(payload)
        return data
    }
}

public struct NativeMessageResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}

public enum NativeMessageError: Error, Equatable {
    case incompleteLengthPrefix
    case incompletePayload
}
