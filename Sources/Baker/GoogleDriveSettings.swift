import AppKit
import SwiftUI

struct GoogleDriveSettings: View {
    @ObservedObject var model: Workbench
    @ObservedObject var drive: GoogleDriveController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Google Drive", systemImage: "cloud").font(.headline)
                Spacer()
                if drive.working {
                    ProgressView().controlSize(.small)
                    Button("Cancel", action: drive.cancel)
                } else if drive.connected { Button("Disconnect", action: drive.disconnect).disabled(model.busy) }
                else { Button("Connect Google", action: drive.connect).disabled(model.busy || drive.clientID.isEmpty) }
            }
            Text(drive.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if drive.connected {
                HStack {
                    Button("Upload Latest Capture", action: drive.uploadLatest).disabled(model.busy || model.captures.isEmpty)
                    Button("Refresh Drive") { drive.refresh() }.disabled(model.busy)
                }
                if !drive.files.isEmpty {
                    List(drive.files) { file in
                        HStack {
                            Image(systemName: "photo")
                            Text(file.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Import") { drive.importCapture(file) }.disabled(model.busy)
                        }.padding(.vertical, 3)
                    }.frame(height: 230)
                    if drive.hasMore { Button("Load More") { drive.refresh(more: true) }.disabled(model.busy) }
                }
                Text("Uploads create Baker versions. Import keeps a local copy. Transfers are manual.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Link("Privacy policy", destination: URL(string: "https://pentagontoy.github.io/Baker/legal/privacy.html")!)
                Text("·").foregroundStyle(.secondary)
                Link("Contact", destination: URL(string: "mailto:kanghanseul96@gmail.com")!)
            }.font(.caption)
            DisclosureGroup("Connection setup") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Desktop OAuth Client ID").font(.caption)
                    TextField("…apps.googleusercontent.com", text: $drive.clientID).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced)).frame(minWidth: 0, maxWidth: .infinity).disabled(drive.connected || drive.working)
                    Button("Import Desktop JSON…", action: drive.importConfiguration).disabled(drive.connected || drive.working)
                    Text("If Google says Baker is testing, add your signing-in account under Google Auth Platform → Audience → Test users.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link("Google Auth Platform · Audience", destination: URL(string: "https://console.cloud.google.com/auth/audience")!)
                    Button("Google Developer Console") { NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!) }
                }.padding(.top, 8)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }
}
