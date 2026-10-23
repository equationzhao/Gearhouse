import SwiftUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeActivityRow: View {
    let activity: Value
    var distance: Value? = nil
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text(activity["name"].text).font(.headline)
            Text(activity["at"].text.replacingOccurrences(of:"T",with:" ")).font(.caption).foregroundStyle(.secondary)
            Text(nativeDistance(distance ?? activity["distance"]) + " · " + nativeDuration(activity["seconds"])).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical,3)
    }
}
struct NativeActivities: View {
    @EnvironmentObject var store: NativeStore
    @State private var search = ""
    @State private var limit = 60
    @State private var rows: [Value] = []
    private func refreshRows() { rows = store.activities.filter { search.isEmpty || $0["name"].text.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            ForEach(Array(rows.prefix(limit))) { a in NavigationLink { NativeActivityDetail(id:a.id) } label: { NativeActivityRow(activity:a) } }
            if rows.count>limit {Button("显示更多"){limit+=60}}
            if rows.isEmpty {Text(search.isEmpty ? "暂无活动" : "没有匹配的活动").foregroundStyle(.secondary)}
        }
        .navigationTitle("活动").searchable(text:$search,prompt:"查找活动")
        .refreshable { await store.sync() }
        .onAppear { refreshRows() }
        .onChange(of: search) { _, _ in refreshRows() }
        .onChange(of: store.viewGeneration) { _, _ in refreshRows() }
    }
}
struct NativeActivityDetail: View {
    @EnvironmentObject var store: NativeStore
    let id: String
    var usedGear: String? = nil
    @State private var main = ""
    @State private var shoe = ""
    @State private var trainer = ""
    @State private var dirty = false
    @State private var rebuild = false
    @State private var saving = false
    @State private var error: String?
    @State private var preview: Value = [:]
    private var activity:Value {store.state["activities"].array.first{$0.id==id} ?? [:]}
    private var editable:Bool {!store.readOnly && !activity["unavailable"].flag && !activity["summary"].flag && !activity["deleted"].flag}
    private var assignment:Value {["main":.optional(main),"extras":.array([shoe,trainer].filter{!$0.isEmpty}.map(Value.string)),"excluded":[],"rebuild":.bool(rebuild)]}
    private var snapshot:[Value] {(dirty ? preview : activity)["snapshot"].array}
    private func choice(_ value:Binding<String>)->Binding<String>{Binding(get:{value.wrappedValue},set:{value.wrappedValue=$0;dirty=true})}
    private func candidates(_ types:[String], _ selected:String)->[Value]{store.state["gears"].array.filter{types.contains($0["type"].text) && (($0["deletedAt"].isNull && store.status($0.id, at: activity["at"].text) == "active") || $0.id==selected)}}
    var body:some View {
        List {
            Section {
                Text(activity["name"].text).font(.title2.bold())
                Text(activity["at"].text.replacingOccurrences(of:"T",with:" ")).foregroundStyle(.secondary)
                LabeledContent("类型",value:activity["type"].text)
                LabeledContent("活动距离",value:nativeDistance(activity["distance"]))
                LabeledContent("运动时间",value:nativeDuration(activity["seconds"]))
                if let usedGear, let row=activity["snapshot"].array.first(where:{$0.id==usedGear}) {
                    LabeledContent(store.name(usedGear),value:nativeDistance(row["distanceIncluded"] == false ? 0 : activity["distance"]))
                }
            }
            if store.view["inventoryConflicts"].array.contains(.string(id)) {
                Section { Text("活动使用了当时在库存或已退役的装备，请核对装备的使用日期。") }
            }
            Section("装备") {
                Picker("主装备",selection:choice($main)){Text("无").tag("");ForEach(candidates(["Bike","Shoes"],main)){Text($0["name"].text).tag($0.id)}}
                Picker("锁鞋",selection:choice($shoe)){Text("无").tag("");ForEach(candidates(["CyclingShoes"],shoe)){Text($0["name"].text).tag($0.id)}}
                Picker("骑行台",selection:choice($trainer)){Text("无").tag("");ForEach(candidates(["Trainer"],trainer)){Text($0["name"].text).tag($0.id)}}
            }.disabled(!editable || saving)
            Section {
                ForEach(snapshotRows(snapshot),id:\.0.id){row,depth in
                    HStack {Text(store.name(row.id)).padding(.leading,CGFloat(depth)*16);Spacer();if row["distanceIncluded"] == false {Text("不计距离").font(.caption).foregroundStyle(.secondary)}}
                }
            } header: {Text("装配")}
            if editable {
                Section {
                    Button("重算装备"){rebuild=true;dirty=true;updatePreview()}.disabled(saving)
                    if activity["pending"].flag {Button("重试同步"){saving=true;Task{defer{saving=false};do{try await store.sendGear(id);error=nil}catch let failure{error=failure.userFacingMessage}}}.disabled(saving)}
                    if dirty {Button("取消修改"){load()}.disabled(saving)}
                }
            } else if activity["unavailable"].flag || activity["summary"].flag {Section{Text("活动信息不完整，暂时无法修改装备。")}}
            if let error {Section{Text(error).foregroundStyle(.red)}}
            if !activity["error"].text.isEmpty {Section{Text(UserFacingError.text(activity["error"].text)).foregroundStyle(.red)}}
            NativePhotoSection(owner:"activity",ownerID:id,readOnly:!editable)
        }
        .navigationTitle("活动详情").navigationBarTitleDisplayMode(.inline)
        .toolbar {if editable {ToolbarItem(placement:.confirmationAction){Button(saving ? "同步中…":"保存"){
            saving=true
            Task{defer{saving=false};do{try await store.assign(id:id,assignment:assignment);load();error=nil}catch let failure{error=failure.userFacingMessage}}
        }.disabled(!dirty || saving)}}}
        .task{load()}
        .onChange(of:assignment){_,_ in if dirty{updatePreview()}}
        .onChange(of:store.revision){_,_ in if !dirty && !saving{load()}}
    }
    private func load(){main=activity["main"].text;shoe=activity["extras"].array.first{store.gear($0.text)["type"].text=="CyclingShoes"}?.text ?? "";trainer=activity["extras"].array.first{store.gear($0.text)["type"].text=="Trainer"}?.text ?? "";rebuild=false;dirty=false;preview=activity}
    private func updatePreview(){do{preview=try store.query("assignment-preview",["id":.string(id),"assignment":assignment]);error=nil}catch let failure{error=failure.userFacingMessage}}
}
func snapshotRows(_ rows:[Value])->[(Value,Int)]{
    var result:[(Value,Int)]=[],seen=Set<String>();let known=Set(rows.map(\.id))
    func walk(_ row:Value,_ depth:Int){guard seen.insert(row.id).inserted else{return};result.append((row,depth));for child in rows where child["parentId"].text==row.id{walk(child,depth+1)}}
    for row in rows where !known.contains(row["parentId"].text){walk(row,0)}
    return result
}
