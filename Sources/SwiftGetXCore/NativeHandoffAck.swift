import Foundation
import Network

public struct NativeHandoffAck: Codable, Equatable, Sendable {
    public var requestID: String
    public var token: String
    public var port: UInt16
    public var expiresAt: Date?

    public init(requestID: String, token: String, port: UInt16, expiresAt: Date? = nil) {
        self.requestID = requestID
        self.token = token
        self.port = port
        self.expiresAt = expiresAt
    }

    public func isExpired(now: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}

public struct NativeHandoffAckDecision: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var queued: Bool
    public var requiresUserConfirmation: Bool
    public var rejectedReason: String?
    public var message: String?

    public init(
        accepted: Bool,
        queued: Bool,
        requiresUserConfirmation: Bool,
        rejectedReason: String? = nil,
        message: String? = nil
    ) {
        self.accepted = accepted
        self.queued = queued
        self.requiresUserConfirmation = requiresUserConfirmation
        self.rejectedReason = rejectedReason
        self.message = message
    }

    public static func accepted(
        queued: Bool,
        requiresUserConfirmation: Bool,
        message: String? = nil
    ) -> NativeHandoffAckDecision {
        NativeHandoffAckDecision(
            accepted: true,
            queued: queued,
            requiresUserConfirmation: requiresUserConfirmation,
            message: message
        )
    }

    public static func rejected(
        reason: String,
        requiresUserConfirmation: Bool,
        message: String? = nil
    ) -> NativeHandoffAckDecision {
        NativeHandoffAckDecision(
            accepted: false,
            queued: false,
            requiresUserConfirmation: requiresUserConfirmation,
            rejectedReason: reason,
            message: message
        )
    }

    public static func timedOut() -> NativeHandoffAckDecision {
        NativeHandoffAckDecision.rejected(
            reason: "timeout",
            requiresUserConfirmation: false,
            message: "SwiftGetX did not acknowledge the download request before the native host timed out"
        )
    }
}

public enum NativeHandoffAckClient {
    public static func acknowledge(
        _ decision: NativeHandoffAckDecision,
        handoff: NativeHandoffAck,
        timeout: TimeInterval = 2
    ) async throws {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(handoff.port)
        components.path = "/ack"
        components.queryItems = [
            URLQueryItem(name: "requestID", value: handoff.requestID),
            URLQueryItem(name: "token", value: handoff.token),
            URLQueryItem(name: "accepted", value: decision.accepted ? "true" : "false"),
            URLQueryItem(name: "queued", value: decision.queued ? "true" : "false"),
            URLQueryItem(
                name: "requiresUserConfirmation",
                value: decision.requiresUserConfirmation ? "true" : "false"
            )
        ]
        appendQueryItem("rejectedReason", value: decision.rejectedReason, to: &components)
        appendQueryItem("message", value: decision.message, to: &components)

        guard let url = components.url else {
            throw NativeHandoffAckError.invalidAckURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NativeHandoffAckError.invalidAckResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NativeHandoffAckError.ackRejected(statusCode: httpResponse.statusCode)
        }
    }

    private static func appendQueryItem(_ name: String, value: String?, to components: inout URLComponents) {
        guard let value, !value.isEmpty else { return }
        components.queryItems?.append(URLQueryItem(name: name, value: value))
    }
}

public enum NativeHandoffPayloadClient {
    public static func fetchContext(
        handoff: NativeHandoffAck,
        timeout: TimeInterval = 2
    ) async throws -> BrowserDownloadContext {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(handoff.port)
        components.path = "/payload"
        components.queryItems = [
            URLQueryItem(name: "requestID", value: handoff.requestID),
            URLQueryItem(name: "token", value: handoff.token)
        ]

        guard let url = components.url else {
            throw NativeHandoffAckError.invalidAckURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NativeHandoffAckError.invalidAckResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NativeHandoffAckError.ackRejected(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(BrowserDownloadContext.self, from: data)
    }
}

public final class NativeHandoffAckServer: @unchecked Sendable {
    public private(set) var handoff: NativeHandoffAck

    private let listener: NWListener
    private let payload: Data?
    private let queue = DispatchQueue(label: "SwiftGetX.NativeHandoffAckServer")
    private let resultSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: NativeHandoffAckDecision?
    private var completed = false

    private init(listener: NWListener, handoff: NativeHandoffAck, payload: Data?) {
        self.listener = listener
        self.handoff = handoff
        self.payload = payload
    }

    public static func start(
        payload: Data? = nil,
        expiresAt: Date? = nil,
        startupTimeout: TimeInterval = 2
    ) throws -> NativeHandoffAckServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)

        let listener = try NWListener(using: parameters)
        let server = NativeHandoffAckServer(
            listener: listener,
            handoff: NativeHandoffAck(
                requestID: UUID().uuidString,
                token: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                port: 0,
                expiresAt: expiresAt
            ),
            payload: payload
        )

        let readySemaphore = DispatchSemaphore(value: 0)
        let startupState = NativeHandoffAckStartupState()
        listener.newConnectionHandler = { [weak server] connection in
            server?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                readySemaphore.signal()
            case .failed(let error):
                startupState.set(error)
                readySemaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: server.queue)

        guard readySemaphore.wait(timeout: .now() + startupTimeout) == .success else {
            listener.cancel()
            throw NativeHandoffAckError.listenerTimedOut
        }

        if let error = startupState.error {
            listener.cancel()
            throw error
        }

        guard let port = listener.port?.rawValue else {
            listener.cancel()
            throw NativeHandoffAckError.missingListenerPort
        }

        server.handoff.port = port
        return server
    }

    public func waitForResult(timeout: TimeInterval) -> NativeHandoffAckDecision {
        let deadline = DispatchTime.now() + timeout
        let waitResult = resultSemaphore.wait(timeout: deadline)
        listener.cancel()

        guard waitResult == .success else {
            return .timedOut()
        }

        lock.lock()
        let result = self.result
        lock.unlock()
        return result ?? .timedOut()
    }

    public func cancel() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(from: connection, data: Data())
    }

    private func receiveRequest(from connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if error != nil {
                connection.cancel()
                return
            }

            var nextData = data
            if let content {
                nextData.append(content)
            }

            guard nextData.count <= 16_384 else {
                self.sendHTTPResponse(statusCode: 413, body: #"{"ok":false}"#, on: connection)
                return
            }

            if nextData.containsHeaderTerminator {
                self.handleRequest(nextData, connection: connection)
            } else {
                self.receiveRequest(from: connection, data: nextData)
            }
        }
    }

    private func handleRequest(_ data: Data, connection: NWConnection) {
        guard let text = String(data: data, encoding: .utf8),
              let requestLine = text.components(separatedBy: "\r\n").first
        else {
            sendHTTPResponse(statusCode: 400, body: #"{"ok":false}"#, on: connection)
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2, parts[0] == "GET" else {
            sendHTTPResponse(statusCode: 405, body: #"{"ok":false}"#, on: connection)
            return
        }

        guard let url = URL(string: "http://127.0.0.1\(parts[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path == "/ack" || components.path == "/payload"
        else {
            sendHTTPResponse(statusCode: 404, body: #"{"ok":false}"#, on: connection)
            return
        }

        let requestID = queryValue("requestID", in: components)
        let token = queryValue("token", in: components)
        guard requestID == handoff.requestID, token == handoff.token else {
            sendHTTPResponse(statusCode: 403, body: #"{"ok":false}"#, on: connection)
            return
        }

        if components.path == "/payload" {
            guard let payload else {
                sendHTTPResponse(statusCode: 404, body: #"{"ok":false}"#, on: connection)
                return
            }

            sendHTTPResponse(statusCode: 200, body: payload, on: connection)
            return
        }

        let decision = NativeHandoffAckDecision(
            accepted: boolValue("accepted", in: components),
            queued: boolValue("queued", in: components),
            requiresUserConfirmation: boolValue("requiresUserConfirmation", in: components),
            rejectedReason: queryValue("rejectedReason", in: components),
            message: queryValue("message", in: components)
        )

        sendHTTPResponse(statusCode: 200, body: #"{"ok":true}"#, on: connection) { [weak self] in
            self?.complete(with: decision)
        }
    }

    private func complete(with decision: NativeHandoffAckDecision) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        result = decision
        lock.unlock()
        resultSemaphore.signal()
    }

    private func sendHTTPResponse(
        statusCode: Int,
        body: String,
        on connection: NWConnection,
        completion: (@Sendable () -> Void)? = nil
    ) {
        sendHTTPResponse(
            statusCode: statusCode,
            body: Data(body.utf8),
            on: connection,
            completion: completion
        )
    }

    private func sendHTTPResponse(
        statusCode: Int,
        body: Data,
        on connection: NWConnection,
        completion: (@Sendable () -> Void)? = nil
    ) {
        let statusText: String
        switch statusCode {
        case 200:
            statusText = "OK"
        case 400:
            statusText = "Bad Request"
        case 403:
            statusText = "Forbidden"
        case 404:
            statusText = "Not Found"
        case 405:
            statusText = "Method Not Allowed"
        case 413:
            statusText = "Payload Too Large"
        default:
            statusText = "Error"
        }

        var response = Data()
        response.append(Data("HTTP/1.1 \(statusCode) \(statusText)\r\n".utf8))
        response.append(Data("Content-Type: application/json\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            completion?()
            connection.cancel()
        })
    }

    private func queryValue(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func boolValue(_ name: String, in components: URLComponents) -> Bool {
        queryValue(name, in: components) == "true"
    }
}

private final class NativeHandoffAckStartupState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    func set(_ error: Error) {
        lock.lock()
        storedError = error
        lock.unlock()
    }
}

public enum NativeHandoffAckError: Error, Equatable, LocalizedError {
    case invalidAckURL
    case invalidAckResponse
    case ackRejected(statusCode: Int)
    case listenerTimedOut
    case missingListenerPort

    public var errorDescription: String? {
        switch self {
        case .invalidAckURL:
            return "Unable to build SwiftGetX handoff acknowledgement URL"
        case .invalidAckResponse:
            return "SwiftGetX handoff acknowledgement returned an invalid response"
        case .ackRejected(let statusCode):
            return "SwiftGetX handoff acknowledgement was rejected with HTTP \(statusCode)"
        case .listenerTimedOut:
            return "Timed out while starting the SwiftGetX handoff acknowledgement listener"
        case .missingListenerPort:
            return "SwiftGetX handoff acknowledgement listener did not report a local port"
        }
    }
}

private extension Data {
    var containsHeaderTerminator: Bool {
        guard count >= 4 else { return false }
        return withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return false
            }
            for index in 0...(count - 4) {
                if bytes[index] == 13,
                   bytes[index + 1] == 10,
                   bytes[index + 2] == 13,
                   bytes[index + 3] == 10 {
                    return true
                }
            }
            return false
        }
    }
}
