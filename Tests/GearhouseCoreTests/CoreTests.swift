import XCTest
@testable import GearhouseCore

private final class ICUFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        var body: String
        if path.hasSuffix("/gear") {
            body = #"[{"id":"bike-1","name":"Tarmac","type":"Bike"},{"id":"bike-2","name":"Propel","type":"Bike"}]"#
        } else if path.hasSuffix("/activities") {
            body = #"[{"id":123,"name":"Morning ride","type":"Ride","start_date_local":"2026-10-15T08:30:00","distance":42000,"moving_time":3600,"gear":{"id":"bike-2","name":"Propel"},"trainer":false}]"#
        } else {
            body = #"{"id":42,"name":"Test rider","weight":70.5,"icu_wellness":{},"email":null,"athlete":true}"#
        }
        if path.hasSuffix("/activities"), request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("API_KEY:indoor-fixture-key".utf8).base64EncodedString() {
            body = #"[{"id":123,"type":"VirtualRide","start_date_local":"2026-10-15T08:30:00","distance":42000,"gear":{"id":"bike-2"}},{"id":124,"type":"Ride","trainer":true,"start_date_local":"2026-10-15T10:00:00","distance":10000,"gear":{"id":"bike-2"}}]"#
        }
        let unauthorized = request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("API_KEY:invalid-test-key".utf8).base64EncodedString()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: unauthorized ? 401 : 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CoreTests: XCTestCase {
    private func fixtureClient(key: String = "fixture-test-key") -> ICUClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ICUFixtureProtocol.self]
        return ICUClient(key: key, session: URLSession(configuration: config))
    }
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
    }
    func testJSONRoundTripAndKeyExcludedFromState() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MemorySecretStore()
        let repo = LocalRepository(url: url, secretStore: store)
        try await repo.saveAPIKey("test-key-1234")
        let key = await repo.apiKey()
        XCTAssertEqual(key, "test-key-1234")
        let activity = Activity(id: "a", name: "Ride", type: "Ride", at: Date(), mainGearID: "local-bike")
        try await repo.replace(GearhouseState(gears: [Gear(id: "local-bike", name: "Bike", type: .bike, remoteID: "bike-1")], activities: [activity]))
        let reloaded = LocalRepository(url: url, secretStore: store)
        let state = await reloaded.state
        XCTAssertEqual(state.activities.first?.mainGearID, "local-bike")
        XCTAssertFalse(try String(contentsOf: url).contains("test-key-1234"))
    }
    func testRealisticPayloadSyncAndChangedRemoteGear() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = LocalRepository(url: url, secretStore: MemorySecretStore())
        try await repo.replace(GearhouseState(gears: [Gear(id: "old-bike", name: "Tarmac", type: .bike, remoteID: "bike-1")], activities: [Activity(id: "123", name: "Old", type: "Ride", at: Date(), remoteGearID: "bike-1", mainGearID: "old-bike")]))
        try await repo.sync(client: fixtureClient(), oldest: "2026-10-01", newest: "2026-10-16")
        let state = await repo.state
        XCTAssertEqual(state.accountName, "Test rider")
        XCTAssertEqual(state.activities.count, 1)
        XCTAssertEqual(state.activities[0].mainGearID, "icu-bike-2")
        XCTAssertEqual(state.activities[0].distance, 42000)
        XCTAssertEqual(state.activities[0].at, ISO8601DateFormatter().date(from: "2026-10-15T00:30:00Z"))
        XCTAssertNotNil(state.lastSync)
        let reloaded = LocalRepository(url: url, secretStore: MemorySecretStore())
        let saved = await reloaded.state
        XCTAssertEqual(saved.activities[0].mainGearID, "icu-bike-2")
    }
    func testUnauthorizedSyncDoesNotReplaceSavedData() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = LocalRepository(url: url, secretStore: MemorySecretStore())
        try await repo.replace(GearhouseState(accountName: "Existing account"))
        do {
            try await repo.sync(client: fixtureClient(key: "invalid-test-key"), oldest: "2026-10-01", newest: "2026-10-16")
            XCTFail("Expected unauthorized error")
        } catch let error as ICUClientError {
            guard case .badResponse(401) = error else { return XCTFail("Unexpected error") }
        }
        let state = await repo.state
        XCTAssertEqual(state.accountName, "Existing account")
        XCTAssertNil(state.lastSync)
    }
    func testScalarAndObjectGearReferences() throws {
        for json in [#"{"id":1,"gear":"bike-1"}"#, #"{"id":"1","gear":{"id":"bike-1"}}"#] {
            let row = try JSONDecoder().decode(ICUActivity.self, from: Data(json.utf8))
            XCTAssertEqual(row.id.value, "1")
            XCTAssertEqual(row.gear?.id.value, "bike-1")
        }
    }
    func testNewIndoorActivitiesExcludedWhileExistingPolicyIsPreserved() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repo = LocalRepository(url: url, secretStore: MemorySecretStore())
        try await repo.sync(client: fixtureClient(key: "indoor-fixture-key"), oldest: "2026-10-01", newest: "2026-10-16")
        let imported = await repo.state
        XCTAssertEqual(imported.activities.count, 2)
        XCTAssertTrue(imported.activities.allSatisfy { $0.equipmentDistanceIncluded == false })
        var legacy = imported
        legacy.activities[0].equipmentDistanceIncluded = nil
        try await repo.replace(legacy)
        try await repo.sync(client: fixtureClient(key: "indoor-fixture-key"), oldest: "2026-10-01", newest: "2026-10-16")
        let refreshed = await repo.state
        XCTAssertNil(refreshed.activities[0].equipmentDistanceIncluded)
        XCTAssertEqual(refreshed.activities[0].equipmentDistance, 10000)
    }

}
