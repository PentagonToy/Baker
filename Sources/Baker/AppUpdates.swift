import AppKit
import BakerCore
import SwiftUI

/// Owns a small, opt-in metadata request. It never downloads or replaces an app.
@MainActor
final class AppUpdates: ObservableObject {
    @Published private(set) var automatic: Bool
    @Published private(set) var offerID = 0
    @Published private(set) var checking = false
    @Published private(set) var available: AppRelease?
    @Published private(set) var message: String?
    @Published private(set) var lastChecked: Date?
    private let preferences: BakerPreferences
    private let current: AppVersion?
    private let fetch: () async throws -> Data
    private let now: () -> Date
    private var request: Task<Void, Never>?
    private var timer: Timer?
    private var generation = 0
    private var started = false

    init(defaults: UserDefaults = .standard,
         version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
         now: @escaping () -> Date = Date.init,
         fetch: @escaping () async throws -> Data = AppUpdates.fetchReleases) {
        preferences = BakerPreferences(defaults: defaults); current = AppVersion(version)
        self.now = now; self.fetch = fetch
        automatic = preferences[PreferenceKeys.automaticUpdates]
        let timestamp = preferences[PreferenceKeys.updateLastSuccess]
        lastChecked = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }
    func start() { guard !started else { return }; started = true; schedule() }
    func setAutomatic(_ enabled: Bool) {
        guard automatic != enabled else { return }
        automatic = enabled; preferences[PreferenceKeys.automaticUpdates] = enabled
        timer?.invalidate(); timer = nil
        if !enabled { cancelRequest() }
        if started { schedule() }
    }
    private func schedule() {
        guard automatic else { return }
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkIfDue() }
        }
        timer?.tolerance = 300
    }
    func checkIfDue() {
        guard automatic else { return }
        let last = preferences[PreferenceKeys.updateLastAttempt]
        guard last <= 0 || now().timeIntervalSince1970 - last >= 86_400 else { return }
        check(manual: false)
    }
    func check(manual: Bool = true) {
        guard !checking else { return }
        guard let current else { if manual { message = "Update checks are available in a versioned Baker app." }; return }
        checking = true; message = nil
        preferences[PreferenceKeys.updateLastAttempt] = now().timeIntervalSince1970
        generation += 1; let token = generation
        request = Task { [weak self, fetch] in
            do {
                let data = try await fetch()
                try Task.checkCancellation()
                let release = try AppRelease.newest(in: data, after: current)
                guard let self, self.generation == token else { return }
                self.available = release; self.lastChecked = self.now()
                if manual && release != nil { self.offerID += 1 }
                self.preferences[PreferenceKeys.updateLastSuccess] = self.lastChecked!.timeIntervalSince1970
                self.message = release == nil ? "You’re up to date." : nil
            } catch {
                guard let self, self.generation == token else { return }
                if manual && !Task.isCancelled { self.message = "Couldn’t check for updates. Check your connection and try again." }
            }
            guard let self, self.generation == token else { return }
            self.checking = false; self.request = nil
        }
    }
    func stop() { started = false; timer?.invalidate(); timer = nil; cancelRequest() }
    private func cancelRequest() { generation += 1; request?.cancel(); request = nil; checking = false }

    nonisolated static func fetchReleases() async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/PentagonToy/Baker/releases?per_page=20")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Baker-Update-Check", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= 524_288 else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 524_288 { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

@MainActor
private final class UpdateOffer: ObservableObject { @Published var visible = false }

struct AppUpdatesSettings: View {
    @ObservedObject var updates: AppUpdates
    @StateObject private var offer = UpdateOffer()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Check automatically")
                Spacer()
                Toggle("Check automatically", isOn: Binding(get: { updates.automatic }, set: updates.setAutomatic))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }.frame(minHeight: 30).help("Checks GitHub once a day. Downloads open in your browser.")
            HStack {
                Button("Check Now") { updates.check() }.disabled(updates.checking)
                if updates.checking { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
            }
            if let release = updates.available {
                HStack {
                    Text("Baker \(release.version.description) is available.")
                    Spacer()
                    Button("View Update…") { offer.visible = true }
                }
            } else if let message = updates.message {
                Text(message).foregroundStyle(.secondary)
            }
            if let date = updates.lastChecked {
                Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
        }.onChange(of: updates.offerID) { _, _ in offer.visible = true }
            .sheet(isPresented: $offer.visible) {
                if let release = updates.available {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Baker \(release.version.description) is available").font(.title2.weight(.semibold))
                        ScrollView { Text(release.notes.isEmpty ? "See the release notes for details." : release.notes).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 260)
                        HStack {
                            Button("Release Notes") { NSWorkspace.shared.open(release.page) }
                            Spacer()
                            Button("Later") { offer.visible = false }.keyboardShortcut(.cancelAction)
                            Button("Download DMG") { NSWorkspace.shared.open(release.download); offer.visible = false }.keyboardShortcut(.defaultAction)
                        }
                    }.padding(24).frame(width: 560).font(BakerTypography.body)
                }
            }
    }
}
