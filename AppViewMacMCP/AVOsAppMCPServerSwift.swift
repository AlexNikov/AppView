import Foundation
import Network

/// Swift Network.framework MCP listener. Routes are handled by `AVOsAppMCPHandler`.
@objc(AVOsAppMCPServer)
public final class AVOsAppMCPServerSwift: NSObject {
    @objc public static let shared = AVOsAppMCPServerSwift()

    private let queue = DispatchQueue(label: "appview.osapp.mcp.swift")
    private let requestQueue = DispatchQueue(
        label: "appview.osapp.mcp.requests",
        attributes: .concurrent
    )
    private var listener: NWListener?
    private let handler = AVOsAppMCPHandler()

    private override init() {
        super.init()
    }

    @objc(startOnPort:dataSource:)
    public func start(onPort port: UInt16, dataSource: NSObject) {
        guard let swiftSource = dataSource as? AppViewMacMCPDataSource else {
            NSLog("[AppViewMCP] dataSource must conform to AppViewMacMCPDataSource")
            return
        }
        start(port: port, swiftDataSource: swiftSource)
    }

    public func start(port: UInt16, swiftDataSource: AppViewMacMCPDataSource) {
        beginListening(on: port, dataSource: swiftDataSource)
    }

    private func beginListening(on port: UInt16, dataSource: AppViewMacMCPDataSource) {
        queue.sync {
            guard listener == nil else { return }

            handler.dataSource = dataSource

            let params = NWParameters.tcp
            guard let nwPort = NWEndpoint.Port(rawValue: port),
                  let listener = try? NWListener(using: params, on: nwPort) else {
                NSLog("[AppViewMCP] failed to create listener on port %u", port)
                return
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection: connection)
            }
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    NSLog("[AppViewMCP] listening on port %u", port)
                } else if case .failed(let error) = state {
                    NSLog("[AppViewMCP] listener failed: %@", error.localizedDescription)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        }
    }

    @objc public func stop() {
        queue.async { [self] in
            self.listener?.cancel()
            self.listener = nil
            self.handler.dataSource = nil
        }
    }

    private func accept(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            guard let data, error == nil,
                  let requestStr = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            // Handle on the concurrent request queue so long-running requests (select-inspect-target,
            // refresh-launch-targets) don't block fast queries like /status.
            self.requestQueue.async {
                self.handleRequestString(requestStr, connection: connection)
            }
        }
    }

    private func handleRequestString(_ requestStr: String, connection: NWConnection) {
        guard let parsed = AVOsAppMCPHTTPParser.parseRequest(requestStr) else {
            send(AVOsAppMCPHTTPResponse.error("Bad request", statusCode: 400), on: connection)
            return
        }

        let reply = handler.handle(method: parsed.method, path: parsed.path, body: parsed.body)
        let response = AVOsAppMCPHTTPResponse(statusCode: reply.statusCode > 0 ? reply.statusCode : 500, body: reply.body)
        send(response, on: connection)
    }

    private func send(_ response: AVOsAppMCPHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.httpData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
