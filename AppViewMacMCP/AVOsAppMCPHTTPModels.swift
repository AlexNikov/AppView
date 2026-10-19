import Foundation

struct AVOsAppMCPHTTPResponse {
    let statusCode: Int
    let body: Data

    static func ok(json: Any) -> AVOsAppMCPHTTPResponse {
        let payload: [String: Any] = ["success": true, "data": json]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return AVOsAppMCPHTTPResponse(statusCode: 200, body: body)
    }

    static func error(_ message: String, statusCode: Int) -> AVOsAppMCPHTTPResponse {
        let payload: [String: Any] = ["success": false, "error": message]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return AVOsAppMCPHTTPResponse(statusCode: statusCode, body: body)
    }

    var httpData: Data {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        case 501: statusText = "Not Implemented"
        case 503: statusText = "Service Unavailable"
        case 504: statusText = "Gateway Timeout"
        default: statusText = "Error"
        }
        var header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }
}

enum AVOsAppMCPHTTPParser {
    static func parseRequest(_ raw: String) -> (method: String, path: String, body: Data?)? {
        guard let headerEnd = raw.range(of: "\r\n\r\n") else { return nil }
        let headerPart = String(raw[..<headerEnd.lowerBound])
        let bodyPart = String(raw[headerEnd.upperBound...])
        let lines = headerPart.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])
        let body = bodyPart.isEmpty ? nil : bodyPart.data(using: .utf8)
        return (method, path, body)
    }

    static func queryInt(_ query: String?, key: String, default defaultValue: Int) -> Int {
        guard let query, !query.isEmpty else { return defaultValue }
        for part in query.split(separator: "&") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == key, let value = Int(kv[1]) {
                return value
            }
        }
        return defaultValue
    }

    static func splitPath(_ path: String) -> (pathOnly: String, query: String?) {
        if let q = path.firstIndex(of: "?") {
            return (String(path[..<q]), String(path[path.index(after: q)...]))
        }
        return (path, nil)
    }
}
