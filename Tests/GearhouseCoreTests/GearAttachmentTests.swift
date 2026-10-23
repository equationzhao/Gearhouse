import XCTest
@testable import GearhouseCore

final class GearAttachmentTests: XCTestCase {
    func testAttachmentLifecyclePreservesOnSoftDeleteAndRemovesOnPurge() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike", "name":"Bike", "type":"Bike"]]
        let id = UUID().uuidString.lowercased()
        let input: Value = ["id":.string(id), "gearId":"bike", "name":"Warranty.pdf", "contentType":"application/pdf", "bytes":100, "hash":.string(String(repeating:"a",count:64))]
        state = try engine.execute(state: state, action: "attachment-add", input: input)["state"]
        try GearAttachment.validateRecords(in: state)
        XCTAssertEqual(try GearAttachment.fileName(state["attachments"].array[0]), id + ".pdf")
        XCTAssertThrowsError(try engine.execute(state: state, action: "attachment-delete", input: ["id":.string(id)]))
        let deleted = try engine.execute(state: state, action: "attachment-delete", input: ["id":.string(id), "confirmed":true])["state"]
        XCTAssertTrue(deleted["attachments"].array.isEmpty)
        state = try engine.execute(state: state, action: "delete", input: ["id":"bike"])["state"]
        XCTAssertEqual(state["attachments"].array.count, 1)
        XCTAssertThrowsError(try engine.execute(state: state, action: "attachment-add", input: input))
        XCTAssertEqual(try engine.execute(state: state, action: "purge-preview", input: ["id":"bike"])["result"]["attachments"].integer, 1)
        state = try engine.execute(state: state, action: "purge", input: ["id":"bike", "confirmed":true])["state"]
        XCTAssertTrue(state["attachments"].array.isEmpty)
    }
    func testInvalidOwnerTypeAndOversizedAttachmentAreRejected() throws {
        let engine = try NativeDomain()
        var state = try engine.execute(state: .null, action: "initialize")["state"]
        state["gears"] = [["id":"bike"]]
        var input: Value = ["id":.string(UUID().uuidString.lowercased()), "gearId":"bike", "name":"file", "contentType":"application/pdf", "bytes":100, "hash":.string(String(repeating:"a",count:64))]
        input["bytes"] = .number(Double(GearAttachment.maximumBytes + 1))
        XCTAssertThrowsError(try engine.execute(state: state, action: "attachment-add", input: input))
        input["bytes"] = 100; input["contentType"] = "text/html"
        XCTAssertThrowsError(try engine.execute(state: state, action: "attachment-add", input: input))
        input["contentType"] = "application/pdf"; input["gearId"] = "missing"
        XCTAssertThrowsError(try engine.execute(state: state, action: "attachment-add", input: input))
    }
}
