import AppKit
import BakerCore
import SwiftUI

struct DropboxSettings: View {
    @ObservedObject var model: Workbench
    @ObservedObject var dropbox: DropboxController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Dropbox", systemImage: "shippingbox").font(.headline); Spacer()
                if dropbox.working { ProgressView().controlSize(.small); Button("Cancel", action: dropbox.cancel) }
                else if dropbox.connected { Button("Disconnect", action: dropbox.disconnect).disabled(model.busy) }
                else { Button("Connect Dropbox", action: dropbox.connect).disabled(model.busy || dropbox.appKey.isEmpty) }
            }
            Text(dropbox.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if dropbox.connected {
                HStack { Button("Upload Latest Capture", action: dropbox.uploadLatest).disabled(model.busy || model.captures.isEmpty); Button("Refresh Dropbox") { dropbox.refresh() }.disabled(model.busy) }
                if !dropbox.files.isEmpty {
                    List(dropbox.files) { file in
                        HStack { Image(systemName: "photo"); Text(file.name).lineLimit(1).truncationMode(.middle); Spacer(); Button("Import") { dropbox.importCapture(file) }.disabled(model.busy) }
                    }.frame(height: 200)
                }
                if dropbox.hasMore { Button("Load More") { dropbox.refresh(more: true) }.disabled(model.busy) }
                Text("Captures and saved formulas stay in the app folder. Each upload creates a new version.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Link("Privacy policy", destination: URL(string: "https://pentagontoy.github.io/Baker/legal/privacy.html")!)
                Text("·").foregroundStyle(.secondary)
                Link("Contact", destination: URL(string: "mailto:kanghanseul96@gmail.com")!)
            }.font(.caption)
            DisclosureGroup("Connection setup") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Dropbox App Key", text: $dropbox.appKey).textFieldStyle(.roundedBorder).disabled(dropbox.connected || dropbox.working)
                    Text("Register this redirect URI in Dropbox App Console → Settings → OAuth 2:").font(.caption)
                    Text(DropboxOAuth.redirect).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Enable files.metadata.read, files.content.read and files.content.write. No App Secret is needed.").font(.caption).foregroundStyle(.secondary)
                    Link("Dropbox App Console", destination: URL(string: "https://www.dropbox.com/developers/apps")!)
                }.padding(.top, 8)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }
}
