import Foundation

public enum ICUClientError: LocalizedError, Sendable {
    case invalidKey, badResponse(Int), invalidPayload, transport(String)
    public var errorDescription: String? {
        switch self { case .invalidKey: "API Key 无效"; case .badResponse(let code): code == 401 || code == 403 ? "Intervals.icu 拒绝访问，请检查 API Key" : "Intervals.icu 请求失败（HTTP \(code)）"; case .invalidPayload: "Intervals.icu 返回的数据格式无法识别"; case .transport(let message): message }
    }
}

public struct ICUClient: Sendable {
    public var key: String
    public var session: URLSession
    public init(key: String, session: URLSession = .shared) { self.key=key; self.session=session }
    private func request<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        guard key.count >= 8 else { throw ICUClientError.invalidKey }
        guard let url = URL(string: "https://intervals.icu/api/v1" + path) else { throw ICUClientError.invalidPayload }
        var request = URLRequest(url: url); request.timeoutInterval = 45
        let token = Data("API_KEY:\(key)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ICUClientError.transport("网络响应无效") }
            guard (200..<300).contains(http.statusCode) else { throw ICUClientError.badResponse(http.statusCode) }
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ICUClientError.invalidPayload }
        } catch let error as ICUClientError { throw error } catch { throw ICUClientError.transport(error.localizedDescription) }
    }
    public func athlete() async throws -> ICUAthlete { try await request("/athlete/0", as: ICUAthlete.self) }
    public func gears() async throws -> [ICUGear] { try await request("/athlete/0/gear", as: [ICUGear].self) }
    public func activities(oldest: String, newest: String) async throws -> [ICUActivity] {
        let fields = "id,name,type,start_date_local,start_date,distance,moving_time,elapsed_time,gear,source,trainer"
        let path = "/athlete/0/activities?oldest=\(oldest)&newest=\(newest)T23:59:59&fields=\(fields.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fields)"
        return try await request(path, as: [ICUActivity].self)
    }
}
