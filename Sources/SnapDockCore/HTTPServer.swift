import Foundation
import Network

public actor HTTPServer {
  private var listener: NWListener?
  private var startup: CheckedContinuation<Void, any Error>?
  private var generation = UUID()
  private var connections: [UUID: NWConnection] = [:]
  private let store: ImageStore

  public init(store: ImageStore) { self.store = store }

  public func start(
    configuration: ReceiverConfiguration,
    onReceive: @escaping @Sendable (ReceivedImage) async -> Void,
    onFailure: @escaping @Sendable (String) async -> Void
  ) async throws {
    stop()
    guard configuration.port >= 1024, !configuration.token.isEmpty,
      let port = NWEndpoint.Port(rawValue: configuration.port)
    else { throw HTTPFailure(400, "Invalid Configuration") }
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = false
    let next = try NWListener(using: parameters, on: port)
    listener = next
    let current = generation
    next.newConnectionHandler = { [weak self] connection in
      Task {
        await self?.accept(
          connection, generation: current, configuration: configuration, onReceive: onReceive)
      }
    }
    try await withCheckedThrowingContinuation { continuation in
      startup = continuation
      next.stateUpdateHandler = { [weak self] state in
        Task { await self?.stateChanged(state, generation: current, onFailure: onFailure) }
      }
      next.start(queue: .global(qos: .userInitiated))
    }
  }

  public func stop() {
    generation = UUID()
    startup?.resume(throwing: CancellationError())
    startup = nil
    listener?.cancel()
    listener = nil
    for connection in connections.values { connection.cancel() }
    connections.removeAll()
  }

  private func stateChanged(
    _ state: NWListener.State, generation current: UUID, onFailure: @Sendable (String) async -> Void
  ) async {
    guard current == generation else { return }
    switch state {
    case .ready:
      startup?.resume()
      startup = nil
    case .failed(let error), .waiting(let error):
      let wasStarting = startup != nil
      startup?.resume(throwing: error)
      startup = nil
      stop()
      if !wasStarting { await onFailure(error.localizedDescription) }
    case .cancelled:
      startup?.resume(throwing: CancellationError())
      startup = nil
    default:
      break
    }
  }

  private func accept(
    _ connection: NWConnection, generation current: UUID, configuration: ReceiverConfiguration,
    onReceive: @escaping @Sendable (ReceivedImage) async -> Void
  ) {
    guard current == generation, connections.count < 4 else {
      connection.cancel()
      return
    }
    let id = UUID()
    connections[id] = connection
    connection.start(queue: .global(qos: .userInitiated))
    Task { await serve(connection, id: id, configuration: configuration, onReceive: onReceive) }
  }

  private func serve(
    _ connection: NWConnection, id: UUID, configuration: ReceiverConfiguration,
    onReceive: @Sendable (ReceivedImage) async -> Void
  ) async {
    let timeout = Task {
      try await Task.sleep(for: .seconds(45))
      connection.cancel()
    }
    defer {
      timeout.cancel()
      connection.cancel()
      connections[id] = nil
    }
    do {
      var decoder = HTTPRequestDecoder(token: configuration.token)
      var continued = false
      while true {
        let data = try await Self.receive(connection)
        guard !data.isEmpty else { throw HTTPFailure(400, "Incomplete Request") }
        if let request = try decoder.append(data) {
          let image = try await store.save(request.body, in: configuration.directory)
          await onReceive(image)
          try await Self.send(
            connection, status: 201, reason: "Created", body: "{\"ok\":true,\"status\":\"saved\"}")
          return
        }
        if decoder.expectsContinue && !continued {
          try await Self.sendRaw(connection, Data("HTTP/1.1 100 Continue\r\n\r\n".utf8))
          continued = true
        }
      }
    } catch let error as HTTPFailure {
      try? await Self.send(
        connection, status: error.status, reason: error.reason,
        body: "{\"ok\":false,\"status\":\"error\",\"error\":\(error.status)}")
    } catch {
      try? await Self.send(
        connection, status: 500, reason: "Internal Server Error",
        body: "{\"ok\":false,\"status\":\"error\",\"error\":500}")
    }
  }

  private static func receive(_ connection: NWConnection) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
        data, _, _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: data ?? Data())
        }
      }
    }
  }

  private static func send(_ connection: NWConnection, status: Int, reason: String, body: String)
    async throws
  {
    let bytes = Data(body.utf8)
    var response = Data(
      "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        .utf8)
    response.append(bytes)
    try await sendRaw(connection, response)
  }

  private static func sendRaw(_ connection: NWConnection, _ data: Data) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      connection.send(
        content: data,
        completion: .contentProcessed { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        })
    }
  }
}
