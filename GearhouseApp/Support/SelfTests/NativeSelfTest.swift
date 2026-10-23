#if DEBUG
import Foundation
import UIKit
#if canImport(GearhouseCore)
import GearhouseCore
#endif

private final class NativeFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var deleted = false
    private static var target = "bike1"
    private static var failWrite = false
    static func configure(deleted: Bool = false, failWrite: Bool = false) { lock.lock(); defer {lock.unlock()}; self.deleted=deleted;self.failWrite=failWrite }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); defer {Self.lock.unlock()}
        let path=request.url!.path
        var status=200, payload:Value=[:]
        if path.hasSuffix("/gear") {
            payload=[["id":"bike1","name":"Fixture Bike","type":"Bike","component_ids":["wheel"]],["id":"bike2","name":"Other Bike","type":"Bike"],["id":"wheel","name":"Fixture Wheel","type":"Wheelset","component":true,"distance":1000,"time":100,"activities":1]]
        } else if path.hasSuffix("/activities") {
            payload=Self.deleted ? [] : [Self.activity()]
        } else if path.contains("/activity/") {
            if Self.deleted { status=404 }
            else if request.httpMethod=="PUT" {
                if Self.failWrite {status=500}
                else {
                    var data=request.httpBody
                    if data==nil,let stream=request.httpBodyStream {
                        stream.open();defer{stream.close()};var collected=Data(),buffer=[UInt8](repeating:0,count:4096)
                        while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};collected.append(buffer,count:n)}
                        data=collected
                    }
                    if let data,let body=try? Value.decode(data){Self.target=body["gear"]["id"].text}
                    payload=Self.activity()
                }
            } else {payload=Self.activity()}
        } else {payload=["id":"fixture-athlete","name":"Fixture Account"]}
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:(try? payload.jsonData()) ?? Data());client?.urlProtocolDidFinishLoading(self)
    }
    private static func activity()->Value{["id":"fixture-ride","name":"Fixture Ride","type":"Ride","start_date_local":"2026-10-01T08:00:00","distance":12000,"moving_time":1200,"source":"MANUAL","icu_athlete_id":"fixture-athlete","gear":["id":.optional(target)]]}
    override func stopLoading() {}
}

@MainActor
enum NativeSelfTest {
    static func seedAttachments(_ store: NativeStore) async {
        guard store.directory.lastPathComponent == "GearhousePreview", store.state["attachments"].array.isEmpty else { return }
        do {
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x:0,y:0,width:400,height:250)).pdfData { context in
                context.beginPage()
                ("Gearhouse Receipt" as NSString).draw(at:CGPoint(x:30,y:40),withAttributes:[.font:UIFont.systemFont(ofSize:24)])
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("发票.pdf")
            try pdf.write(to:url)
            defer { try? FileManager.default.removeItem(at:url) }
            try await store.addAttachment(from:url,gearID:"tarmac")
        } catch { store.error = error.userFacingMessage }
    }
    static func run() async {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("GearhouseTests-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:directory)}
        var report:[String:String]=[:]
        func check(_ condition:Bool,_ name:String)throws{report[name]=condition ? "passed":"failed";if !condition{throw DomainError("Self-test failed: "+name)}}
        do {
            let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[NativeFixtureProtocol.self]
            let store=NativeStore(directory:directory,secretStore:MemorySecretStore("fixture-test-key"),session:URLSession(configuration:config))
            await store.sync(from:"2026-10-01",to:"2026-10-02")
            if let error=store.error { report["syncError"] = error }; try check(store.state["activities"].array.count==1 && store.state["gears"].array.count==3,"initialSync")
            let bike=store.state["gears"].array.first{$0["remoteId"].text=="bike1"}!,other=store.state["gears"].array.first{$0["remoteId"].text=="bike2"}!
            let total = store.currentStatistics[bike.id]["distance"].double
            try check(total == 12000, "initialCurrentTotals")
            var reminder = GearReminder(gearID: bike.id); reminder.title = "Fixture"; reminder.mode = .total; reminder.kilometers = 1
            try store.saveReminder(reminder)
            store.snapshotDate = "2025-01-01"
            try check(store.reminderOccurrence(reminder).distance == total && store.currentStatistics[bike.id]["distance"].double == total, "snapshotDoesNotReplaceReminderTotals")
            store.snapshotDate = nil
            try check(try store.query("view") == store.query("view"), "repeatedViewQueryStable")

            try await store.assign(id:"fixture-ride",assignment:["main":other["id"],"extras":[],"excluded":[]])
            let written=store.state["activities"].array[0]
            try check(written["remoteId"].text=="bike2" && !written["pending"].flag,"gearWriteReadback")
            NativeFixtureProtocol.configure(failWrite:true)
            do {try await store.assign(id:"fixture-ride",assignment:["main":bike["id"],"extras":[],"excluded":[]]);throw DomainError("Expected failed write")}catch{}
            try check(store.state["activities"].array[0]["pending"].flag && !store.state["activities"].array[0]["error"].isNull,"writeFailurePreservesIntent")
            NativeFixtureProtocol.configure()
            try await store.sendGear("fixture-ride")
            try check(!store.state["activities"].array[0]["pending"].flag,"retryWrite")
            let image=UIGraphicsImageRenderer(size:CGSize(width:80,height:60)).image{ctx in UIColor.blue.setFill();ctx.fill(CGRect(x:0,y:0,width:80,height:60))}
            let photo=try store.addImage(image.pngData()!,owner:"gear",id:bike.id)
            try store.commit("photo-edit",["ownerType":"gear","ownerId":bike["id"],"action":"cover","id":.string(photo)])
            let copied = try store.commit("gear-copy", ["sourceId":bike["id"], "gear":["name":"Independent copy"], "copyReminders":true])
            try check(copied["remoteId"].isNull && store.currentStatistics[copied.id]["distance"].double == 0 && store.reminders.filter { $0.gearID == copied.id }.count == 1, "copyEquipmentAndReminderRules")
            let wheel = store.gears.first { $0["type"].text == "Wheelset" }!
            let installation = store.state["events"].array.first { $0["gearId"].text == wheel.id }!
            try store.commit("history-save", ["id":installation["id"], "gearId":wheel["id"], "parentId":bike["id"], "at":"2026-10-01"])
            let record = try store.commit("event-save", ["requestId":.string(UUID().uuidString), "event":["gearId":wheel["id"], "kind":"inspection", "occurredDate":"2026-10-02"]])
            try check(GearTimeline.buildRows(state: store.view, gearID: bike.id).contains { $0.id == record.id && $0["subjectGearId"].text == wheel.id }, "bikeTimelineIncludesComponentRecord")
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x:0,y:0,width:200,height:100)).pdfData { context in context.beginPage(); ("Receipt" as NSString).draw(at:CGPoint(x:20,y:20),withAttributes:nil) }
            let sourcePDF = directory.appendingPathComponent("Receipt.pdf")
            try pdf.write(to:sourcePDF)
            try await store.addAttachment(from:sourcePDF,gearID:bike.id)
            let sourceImage = directory.appendingPathComponent("Warranty.png")
            try image.pngData()!.write(to:sourceImage)
            try await store.addAttachment(from:sourceImage,gearID:bike.id)
            let attachments = store.state["attachments"].array
            try check(attachments.count == 2 && attachments.contains { $0["contentType"].text == "application/pdf" } && attachments.contains { $0["contentType"].text == "image/jpeg" }, "pdfAndImageAttachments")
            let backup=try store.exportBackup()
            let restored=NativeStore(directory:directory.appendingPathComponent("Restored"),secretStore:MemorySecretStore(),session:URLSession(configuration:config))
            try restored.importBackup(backup)
            try check(restored.state["photos"].array.count==1 && FileManager.default.fileExists(atPath:restored.photoURL(photo).path),"photoBackupRoundTrip")
            try check(restored.state["attachments"] == store.state["attachments"] && (try Data(contentsOf:restored.attachmentURL(attachments[0]))) == pdf, "attachmentJSONBackupRoundTrip")
            let worker = NativeBackupWorker()
            let package = try await worker.safety(state:store.state,directory:directory)
            let manifest = try GearBackupArchive.validate(at:package).manifest
            try check(manifest.attachments?.count == 2, "attachmentVersionBackup")
            try store.commit("attachment-delete",["id":attachments[0]["id"],"confirmed":true])
            try check(!FileManager.default.fileExists(atPath:try store.attachmentURL(attachments[0]).path), "attachmentDeleteRemovesFile")
            let prepared = try await worker.prepare(.init(manifest:manifest,url:package,uploaded:true,local:true),bookmark:nil,namespace:"Gearhouse QA Backups",work:directory.appendingPathComponent("BackupWork"))
            _ = try store.beginBackupRestore()
            _ = try await worker.installMedia(from:prepared.url,state:prepared.state,into:directory)
            try store.applyRestoredBackup(prepared.state); store.endBackupRestore()
            try check(store.state["attachments"].array.count == 2 && (try Data(contentsOf:store.attachmentURL(attachments[0]))) == pdf, "attachmentVersionRestoreAfterDelete")
            try store.commit("photo-edit",["ownerType":"gear","ownerId":bike["id"],"action":"delete","id":.string(photo),"confirmed":true])
            try check(!FileManager.default.fileExists(atPath:store.photoURL(photo).path),"photoDeleteRemovesFile")
            NativeFixtureProtocol.configure(deleted:true)
            await store.sync(from:"2026-10-01",to:"2026-10-02")
            try check(store.state["activities"].array[0]["deleted"].flag,"remote404RemovesActivity")
            try check(store.activities.isEmpty, "activityListInvalidatesAfterDeletion")
            try check(store.reminderOccurrence(reminder).distance == 0, "reminderCacheInvalidatesAfterDeletion")
            let summary=try store.query("view")
            try check(summary["statistics"][bike.id]["distance"].double==0,"deletedActivityRemovedFromUsage")
        } catch let failure {report["error"]=failure.localizedDescription}
        let reportURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("native-self-test.json")
        try? JSONEncoder().encode(report).write(to:reportURL,options:.atomic)
    }
}
#endif
