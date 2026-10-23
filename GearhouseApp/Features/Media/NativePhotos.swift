import SwiftUI
import PhotosUI
#if canImport(GearhouseCore)
import GearhouseCore
#endif

struct NativePhotoStrip: View {
    @EnvironmentObject var store: NativeStore
    let owner: String
    let ownerID: String
    @State private var open = false
    private var photos: [Value] { store.view["photos"].array.filter { $0["ownerType"].text == owner && $0["ownerId"].text == ownerID } }
    var body: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(photos) { photo in
                        if let image = UIImage(contentsOfFile: store.photoURL(photo.id).path) {
                            Button { open = true } label: { Image(uiImage: image).resizable().scaledToFill().frame(width: 100, height: 80).clipped().clipShape(RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .sheet(isPresented: $open) { NativePhotoGallery(ids: photos.map(\.id)) }
        }
    }
}
struct NativePhotoGallery: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    var body: some View {
        NavigationStack {
            TabView {
                ForEach(ids, id: \.self) { id in
                    if let image = UIImage(contentsOfFile: store.photoURL(id).path) {
                        ScrollView([.horizontal,.vertical]) { Image(uiImage: image).resizable().scaledToFit().frame(width: UIScreen.main.bounds.width) }
                    }
                }
            }.tabViewStyle(.page).background(.black)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
struct NativePhotoSection: View {
    @EnvironmentObject var store: NativeStore
    let owner: String
    let ownerID: String
    var gearID = ""
    var readOnly = false
    @State private var selected: [PhotosPickerItem] = []
    @State private var managing = false
    @State private var loading = false
    private var photos: [Value] { store.view["photos"].array.filter { $0["ownerType"].text == owner && $0["ownerId"].text == ownerID } }
    var body: some View {
        Section {
            if owner == "gear", let image = UIImage(contentsOfFile: store.photoURL(store.gear(ownerID)["coverPhotoId"].text).path) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 190).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            }
            NativePhotoStrip(owner: owner, ownerID: ownerID)
            if !readOnly {
                HStack {
                    PhotosPicker(selection: $selected, maxSelectionCount: max(1, 40 - photos.count), matching: .images) { Label("添加图片", systemImage: "photo.badge.plus") }.disabled(loading || photos.count >= 40)
                    Spacer()
                    if loading { ProgressView() }
                    if !photos.isEmpty { Button("管理") { managing = true }.buttonStyle(.borderless) }
                }
            }
        }
        .onChange(of: selected) { _, items in
            guard !items.isEmpty else { return }
            loading = true
            Task {
                defer { loading = false; selected = [] }
                do { for item in items { if let bytes = try await item.loadTransferable(type: Data.self) { _ = try store.addImage(bytes, owner: owner, id: ownerID, gearID: gearID) } } }
                catch let failure { store.error = failure.userFacingMessage }
            }
        }
        .sheet(isPresented: $managing) { NativePhotoManager(owner: owner, ownerID: ownerID) }
    }
}
struct NativePhotoManager: View {
    @EnvironmentObject var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let owner: String
    let ownerID: String
    @State private var deleting: String?
    private var photos: [Value] { store.state["photos"].array.filter { $0["ownerType"].text == owner && $0["ownerId"].text == ownerID } }
    var body: some View {
        NavigationStack {
            List {
                ForEach(photos) { photo in
                    HStack {
                        if let image = UIImage(contentsOfFile: store.photoURL(photo.id).path) { Image(uiImage:image).resizable().scaledToFill().frame(width:72,height:60).clipped().clipShape(RoundedRectangle(cornerRadius:8)) }
                        Spacer()
                        if owner == "gear" {
                            Button { store.perform("photo-edit", ["ownerType": .string(owner), "ownerId": .string(ownerID), "action":"cover", "id":photo["id"]]) } label: { Image(systemName: store.gear(ownerID)["coverPhotoId"] == photo["id"] ? "star.fill" : "star") }.buttonStyle(.borderless).accessibilityLabel("设为封面")
                        }
                        Button(role: .destructive) { deleting = photo.id } label: { Image(systemName:"trash") }.buttonStyle(.borderless)
                    }
                }.onMove { indexes, target in
                    var ids = photos.map(\.id); ids.move(fromOffsets:indexes,toOffset:target)
                    store.perform("photo-edit", ["ownerType": .string(owner), "ownerId": .string(ownerID), "action":"reorder", "ids":.array(ids.map(Value.string))])
                }
            }
            .navigationTitle("图片").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { EditButton() }; ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("删除这张图片？", isPresented: Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}), titleVisibility:.visible, presenting: deleting) { id in
                Button("删除",role:.destructive) { store.perform("photo-edit",["ownerType":.string(owner),"ownerId":.string(ownerID),"action":"delete","id":.string(id),"confirmed":true]); deleting=nil }
            }
        }
    }
}
struct NativeEventPhotos: View {
    @EnvironmentObject var store: NativeStore
    let draft: String
    let gearID: String
    @Binding var selected: [String]
    @State private var picking: [PhotosPickerItem] = []
    @Binding var loading: Bool
    var body: some View {
        Section("图片") {
            ForEach(selected,id:\.self) { id in
                HStack {
                    if let image=UIImage(contentsOfFile:store.photoURL(id).path) { Image(uiImage:image).resizable().scaledToFill().frame(width:90,height:65).clipped().clipShape(RoundedRectangle(cornerRadius:8)) }
                    Spacer()
                    Button { if let index = selected.firstIndex(of: id), index > 0 { selected.swapAt(index,index-1) } } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless).disabled(selected.first == id).accessibilityLabel("向前移")
                    Button { selected.removeAll{$0==id} } label: { Image(systemName:"minus.circle").foregroundStyle(.red) }.buttonStyle(.borderless)
                }
            }.onMove { indexes,target in selected.move(fromOffsets:indexes,toOffset:target) }
            PhotosPicker(selection:$picking,maxSelectionCount:max(1,40-selected.count),matching:.images) { Label("添加图片",systemImage:"photo.badge.plus") }.disabled(loading || selected.count>=40)
            if loading { ProgressView() }
        }
        .onChange(of:picking) { _,items in
            guard !items.isEmpty else{return};loading=true
            Task {
                defer{loading=false;picking=[]}
                do {for item in items {if let bytes=try await item.loadTransferable(type:Data.self){selected.append(try store.addImage(bytes,owner:"draft",id:draft,gearID:gearID))}}}
                catch let failure{store.error=failure.userFacingMessage}
            }
        }
    }
}
