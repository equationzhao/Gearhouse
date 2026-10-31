import XCTest
import CryptoKit
import CoreGraphics
import ImageIO
@testable import GearhouseCore

final class GearBackupArchiveTests: XCTestCase {
    private var root: URL!
    private func imageData() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("GearBackupTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("media"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func fixture() throws -> Value {
        let id = UUID().uuidString.lowercased(), image = try imageData()
        let path = root.appendingPathComponent("media/" + id + ".jpg")
        try image.write(to: path)
        return ["account":["id":"athlete"], "gears":[["id":"chain", "categoryId":"Chain"]],
                "events":[["id":"installation", "gearId":"chain", "at":"2025-01-01T00:00:00", "parentId":.null]],
                "activities":[["id":"ride", "manual":true, "snapshot":[["id":"chain", "distanceIncluded":false]]]],
                "gearEvents":[["id":"wax", "gearId":"chain"]], "gearCategories":[["id":"custom", "indoorDistance":true]],
                "photos":[["id":.string(id), "hash":.string(try GearBackupArchive.hash(path))]]]
    }
    private func make(_ state: Value) throws -> URL {
        try GearBackupArchive.create(state: state, media: root.appendingPathComponent("media"), in: root.appendingPathComponent("backups"))
    }
    func testAttachmentsRoundTripAndRejectMissingCorruptAndLinkedFiles() throws {
        var state = try fixture()
        let id = UUID().uuidString.lowercased(), bytes = Data("%PDF-1.7\nreceipt fixture".utf8)
        let file = root.appendingPathComponent("media/" + id + ".pdf")
        try bytes.write(to: file)
        let record: Value = ["id":.string(id), "gearId":"chain", "name":"receipt.pdf", "contentType":"application/pdf", "bytes":.number(Double(bytes.count)), "hash":.string(try GearBackupArchive.hash(file))]
        state["attachments"] = [record]
        let backup = try make(state), restored = try GearBackupArchive.validate(at: backup)
        XCTAssertEqual(restored.state, state)
        XCTAssertEqual(restored.manifest.attachments?.count, 1)
        let packaged = backup.appendingPathComponent("media/" + id + ".pdf")
        XCTAssertEqual(try Data(contentsOf: packaged), bytes)
        try Data("corrupt".utf8).write(to: packaged)
        XCTAssertThrowsError(try GearBackupArchive.validate(at: backup))
        try FileManager.default.removeItem(at: packaged)
        XCTAssertThrowsError(try GearBackupArchive.validate(at: backup))
        try FileManager.default.createSymbolicLink(at: packaged, withDestinationURL: file)
        XCTAssertThrowsError(try GearBackupArchive.validate(at: backup))
        state["attachments"] = [record, record]
        XCTAssertThrowsError(try make(state))
        state["attachments"] = [["id":"../../secret", "gearId":"chain", "contentType":"application/pdf"]]
        XCTAssertThrowsError(try make(state))
    }
    func testLegacyManifestWithoutAttachmentsStillRestores() throws {
        let state = try fixture(), url = try make(state)
        XCTAssertNil(try GearBackupArchive.manifest(at: url).attachments)
        XCTAssertEqual(try GearBackupArchive.validate(at: url).state, state)
    }
    func testPackagePreservesAllStateAndCopiesImageWithoutBase64() throws {
        let state = try fixture(), url = try make(state)
        let restored = try GearBackupArchive.validate(at: url)
        XCTAssertEqual(restored.state, state)
        XCTAssertEqual(restored.manifest.accountID, "athlete")
        XCTAssertEqual(restored.manifest.photos.count, 1)
        XCTAssertEqual(restored.manifest.records, 2)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("media/" + state["photos"].array[0].id + ".jpg")), try Data(contentsOf: root.appendingPathComponent("media/" + state["photos"].array[0].id + ".jpg")))
        XCTAssertFalse(try String(contentsOf: url.appendingPathComponent("state.json")).contains("base64"))
    }
    func testCorruptStateOrPhotoAndMissingMediaCannotBeRestored() throws {
        let state = try fixture()
        let originalPhoto = root.appendingPathComponent("media/" + state["photos"].array[0].id + ".jpg")
        let originalBytes = try Data(contentsOf: originalPhoto)
        let stateBackup = try make(state)
        try Data("{}".utf8).write(to: stateBackup.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try GearBackupArchive.validate(at: stateBackup))
        let photoBackup = try make(state)
        let photo = photoBackup.appendingPathComponent("media/" + state["photos"].array[0].id + ".jpg")
        try Data([0, 1, 2, 3]).write(to: photo)
        XCTAssertThrowsError(try GearBackupArchive.validate(at: photoBackup))
        try FileManager.default.removeItem(at: photo)
        XCTAssertThrowsError(try GearBackupArchive.validate(at: photoBackup))
        XCTAssertEqual(try Data(contentsOf: originalPhoto), originalBytes)
    }
    func testFailedCreationDoesNotPublishAnIncompleteVersion() throws {
        var state = try fixture()
        var photos = state["photos"].array
        photos[0]["hash"] = "wrong"; state["photos"] = .array(photos)
        XCTAssertThrowsError(try make(state))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("backups").path), [])
    }
    func testCreationRejectsPackagesThatCannotBeRestored() throws {
        var state = try fixture()
        let photo = state["photos"].array[0]
        let source = root.appendingPathComponent("media/" + photo.id + ".jpg")
        try Data().write(to: source)
        state["photos"] = [["id": .string(photo.id), "hash": .string(try GearBackupArchive.hash(source))]]
        XCTAssertThrowsError(try make(state))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("backups").path), [])

        try Data([0xff, 0xd8, 0xff, 0xd9]).write(to: source)
        state["photos"] = [["id": .string(photo.id), "hash": .string(try GearBackupArchive.hash(source))]]
        XCTAssertThrowsError(try make(state))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("backups").path), [])

        state["photos"] = []
        state["events"] = .null
        XCTAssertThrowsError(try make(state))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("backups").path), [])
    }
    func testUnsafeImageIdentifierAndSymlinkAreRejected() throws {
        var state = try fixture()
        let url = try make(state), photo = state["photos"].array[0]
        let target = url.appendingPathComponent("media/" + photo.id + ".jpg")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: root.appendingPathComponent("media/" + photo.id + ".jpg"))
        XCTAssertThrowsError(try GearBackupArchive.validate(at: url))
        state["photos"] = [["id":"../../state", "hash":"invalid"]]
        XCTAssertThrowsError(try make(state))
    }
    func testRetentionKeepsRecentDailyAndWeeklyRecoveryPoints() {
        let now = Date(timeIntervalSince1970: 1792400000)
        let items = (0..<40).map { day in
            GearBackupManifest(format: 1, id: "day-\(day)", createdAt: now.addingTimeInterval(Double(-day) * 86400), accountID: nil, stateHash: "", gears: 0, activities: 0, records: 0, photos: [])
        }
        let retained = GearBackupArchive.retainedIDs(items, now: now)
        XCTAssertTrue(Set((0..<7).map { "day-\($0)" }).isSubset(of: retained))
        XCTAssertEqual(retained.intersection(Set((8...14).map { "day-\($0)" })).count, 1)
        XCTAssertFalse(retained.contains("day-39"))
        XCTAssertLessThan(retained.count, items.count)
    }
}
