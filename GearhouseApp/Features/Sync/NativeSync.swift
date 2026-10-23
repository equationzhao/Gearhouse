import SwiftUI
import UniformTypeIdentifiers
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativeSync: View {
    @EnvironmentObject var store:NativeStore
    @State private var key=""
    @State private var connecting=false
    @State private var connectionOpen=false
    @State private var historyOpen=false
    @State private var from=NativeDate.parse("2024-01-01")
    @State private var to=Date()
    @State private var error:String?
    var body:some View {
        List {
            Section {
                Toggle("自动同步",isOn:Binding(get:{store.state["autoSync"]["enabled"] != false},set:store.setAutoSync)).disabled(!store.connected)
                HStack {
                    if store.busy {ProgressView();Text(store.progress).font(.caption)}
                    else {Text(store.state["autoSync"]["lastSuccess"].text.isEmpty ? "尚未同步":"最近同步 " + store.state["autoSync"]["lastSuccess"].text.replacingOccurrences(of:"T",with:" ").prefix(16))}
                }
                if !store.state["autoSync"]["error"].text.isEmpty {
                    Text(UserFacingError.text(store.state["autoSync"]["error"].text)).foregroundStyle(.red)
                }
                Button("立即同步"){store.startSync()}.disabled(!store.connected || store.busy)
            }
            Section {
                DisclosureGroup("历史补录",isExpanded:$historyOpen){
                    DatePicker("开始日期",selection:$from,in:...to,displayedComponents:.date)
                    DatePicker("结束日期",selection:$to,in:from...Date(),displayedComponents:.date)
                    Button("读取活动"){store.startSync(from:NativeDate.format(from,"yyyy-MM-dd"),to:NativeDate.format(to,"yyyy-MM-dd"))}.disabled(!store.connected || store.busy)
                }
                DisclosureGroup("Intervals.icu 连接",isExpanded:$connectionOpen){
                    if store.connected {LabeledContent("账户",value:store.state["account"]["name"].text)}
                    SecureField(store.connected ? "替换 API Key":"API Key",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(connecting ? "连接中…":store.connected ? "更新连接":"连接"){
                        connecting=true
                        Task{defer{connecting=false};do{try await store.connect(key);key="";connectionOpen=false;error=nil}catch let failure{error=failure.userFacingMessage}}
                    }.disabled(connecting || store.busy || key.trimmingCharacters(in:.whitespacesAndNewlines).count<8)
                    Link("Intervals.icu 设置",destination:URL(string:"https://intervals.icu/settings")!)
                }
            }
            Section { NavigationLink("备份与恢复") { NativeBackupSettings() }.accessibilityIdentifier("backup-settings") }
            Section("同步记录") {
                ForEach(Array(store.state["syncLog"].array.filter{$0["added"].integer+$0["updated"].integer+$0["removed"].integer+$0["unavailable"].integer>0}.prefix(20).enumerated()),id:\.offset){_,row in
                    VStack(alignment:.leading,spacing:4){Text(row["oldest"].text+" – "+row["newest"].text);Text("新增 \(row["added"].integer) · 更新 \(row["updated"].integer) · 移除 \(row["removed"].integer)").font(.caption).foregroundStyle(.secondary)}
                }
            }
            if let error {Section{Text(error).foregroundStyle(.red)}}
        }
        .navigationTitle("同步")
        .task { connectionOpen = !store.connected }
    }
}
