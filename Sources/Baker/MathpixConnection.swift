import Foundation
import Network
import SwiftUI

@MainActor final class MathpixConnection: ObservableObject {
    @Published private(set) var email = ""
    @Published private(set) var connected = false
    @Published private(set) var online = true
    @Published private(set) var working = false
    @Published var message = ""
    @Published var provider: String { didSet { defaults.set(provider, forKey: PreferenceKeys.recognitionProvider.name) } }
    struct Usage: Codable {
        var localImages = 0, localDocuments = 0, localPages = 0
        var onlineImages = 0, onlineDocuments = 0, onlinePages = 0
        var since = Date()
    }
    @Published private(set) var usage: Usage
    func record(online: Bool, pages: Int?) {
        if let pages {
            if online { usage.onlineDocuments += 1; usage.onlinePages += pages }
            else { usage.localDocuments += 1; usage.localPages += pages }
        } else if online { usage.onlineImages += 1 }
        else { usage.localImages += 1 }
        if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: PreferenceKeys.recognitionUsage.name) }
    }
    let client = MathpixClient()
    private let defaults: UserDefaults
    private let monitor = NWPathMonitor()
    private var authTask: Task<Void, Never>?
    var preferred: Bool { provider == "mathpix" && connected }
    var available: Bool { preferred && online }
    var routeDescription: String {
        if provider != "mathpix" { return "Baker · On this Mac" }
        if !connected { return "Baker · Sign in to use Mathpix" }
        return online ? "Mathpix · Online" : "Baker · Offline fallback"
    }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        usage = defaults.data(forKey: PreferenceKeys.recognitionUsage.name).flatMap { try? JSONDecoder().decode(Usage.self, from: $0) } ?? Usage()
        provider = defaults.string(forKey: PreferenceKeys.recognitionProvider.name) == "mathpix" ? "mathpix" : "baker"
        if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: PreferenceKeys.recognitionUsage.name) }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.online = online }
        }
        monitor.start(queue: DispatchQueue(label: "local.baker.mathpix.reachability"))
        restore()
    }
    deinit { monitor.cancel(); authTask?.cancel() }
    func restore(interactive: Bool = false) {
        guard !working else { return }; working = true
        authTask = Task {
            defer { working = false; authTask = nil }
            do {
                if let email = try await client.restore(interactive: interactive) { self.email = email; connected = true; message = "" }
            } catch { message = error.localizedDescription }
        }
    }
    func login(email: String, password: String) {
        guard !working else { return }; working = true; message = "Signing in…"
        authTask = Task {
            defer { working = false; authTask = nil }
            do {
                self.email = try await client.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                connected = true; provider = "mathpix"; message = "Signed in. Mathpix is selected."
            } catch { message = error.localizedDescription }
        }
    }
    func logout() {
        guard !working else { return }; working = true
        authTask = Task {
            defer { working = false; authTask = nil }
            do { try await client.logout(); email = ""; connected = false; provider = "baker"; message = "Signed out on this Mac." }
            catch { message = error.localizedDescription }
        }
    }
    func failed(_ error: Error) {
        if let failure = error as? MathpixClient.Failure, case .expired = failure { connected = false }
        message = error.localizedDescription
    }
    static func connectionFailure(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut].contains(error.code)
    }
}

@MainActor final class MathpixLoginDraft: ObservableObject {
    @Published var showLogin = false
    @Published var email = ""
    @Published var password = ""
}

struct MathpixSettings: View {
    @ObservedObject var connection: MathpixConnection
    let busy: Bool
    @StateObject private var draft = MathpixLoginDraft()
    private func usageColumn(_ title: String, images: Int, documents: Int, pages: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BakerTypography.section)
            Text("\(images) images · \(documents) PDFs")
            Text("\(pages) PDF pages").font(BakerTypography.supporting).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recognition").font(BakerTypography.section)
                Spacer()
                Text(connection.routeDescription).font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
            Picker("Recognition provider", selection: $connection.provider) {
                Text("Baker").tag("baker")
                Text("Mathpix").tag("mathpix").disabled(!connection.connected)
            }.pickerStyle(.segmented).disabled(busy || connection.working)
            if connection.connected {
                HStack {
                    Label(connection.email, systemImage: "checkmark.circle.fill").lineLimit(1)
                    Spacer(); Button("Sign Out", action: connection.logout).disabled(busy || connection.working)
                }
            } else {
                Button("Sign in to Mathpix…") { draft.showLogin = true }.disabled(busy || connection.working)
                if !connection.message.isEmpty { Button("Unlock Saved Login") { connection.restore(interactive: true) }.disabled(connection.working || busy) }
            }
            Text("Baker runs locally. Mathpix sends formulas and PDFs to your account and uses your plan allowance. Without a connection, Baker uses its installed local models.")
                .font(BakerTypography.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !connection.message.isEmpty { Text(connection.message).font(BakerTypography.supporting).foregroundStyle(.secondary).textSelection(.enabled) }
            Divider()
            HStack {
                Text("Usage").font(BakerTypography.section); Spacer()
                Text("Since " + connection.usage.since.formatted(date: .abbreviated, time: .omitted)).font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 24) {
                usageColumn("Baker · Local", images: connection.usage.localImages, documents: connection.usage.localDocuments, pages: connection.usage.localPages)
                usageColumn("Mathpix · Online", images: connection.usage.onlineImages, documents: connection.usage.onlineDocuments, pages: connection.usage.onlinePages)
            }
            Text("Completed conversions made by Baker on this Mac. Includes text and formula recognition. These counts are not your Mathpix account balance or remaining allowance.").font(BakerTypography.supporting).foregroundStyle(.secondary)

        }.sheet(isPresented: $draft.showLogin, onDismiss: { draft.password = "" }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sign in to Mathpix").font(BakerTypography.title)
                Text("Use your Mathpix email and password. Baker stores only the session token in macOS Keychain. Your password is not saved.").foregroundStyle(.secondary)
                TextField("Email", text: $draft.email).textContentType(.username)
                SecureField("Password", text: $draft.password).textContentType(.password)
                Text("SSO-only accounts need a Mathpix password. Mathpix plan limits apply; Baker does not enable extra usage.").font(BakerTypography.supporting).foregroundStyle(.secondary)
                if !connection.message.isEmpty { Text(connection.message).font(BakerTypography.supporting).foregroundStyle(.secondary) }
                HStack {
                    Button("Cancel") { draft.password = ""; draft.showLogin = false }.disabled(connection.working)
                    Spacer()
                    if connection.working { ProgressView().controlSize(.small) }
                    Button("Sign In") { connection.login(email: draft.email, password: draft.password); draft.password = "" }
                        .disabled(connection.working || draft.email.isEmpty || draft.password.isEmpty).keyboardShortcut(.defaultAction)
                }
            }.textFieldStyle(.roundedBorder).padding(24).frame(width: 440)
                .onChange(of: connection.connected) { if $0 { draft.showLogin = false } }
        }
    }
}
