import SwiftUI

enum WebImportCandidate {
    case page(WebImportSource, title: String)
    case pdf(WebImportDownloadedPDF)

    var name: String {
        switch self {
        case let .page(_, title): title
        case let .pdf(file): file.url.lastPathComponent
        }
    }
}

struct WebImportView: View {
    let add: (WebImportCandidate) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var linkFocused: Bool
    @State private var candidate: WebImportCandidate?
    @State private var browserLink: URL?
    @State private var browser: WebImportBrowser?
    @State private var job: Task<Void, Never>?
    @State private var message = ""

    var body: some View {
        Group {
            if let browser {
                WebImportBrowserPane(browser: browser, busy: job != nil, error: message,
                                     back: returnFromBrowser, use: addBrowserContent)
            } else {
                importControls
            }
        }
        .font(BakerTypography.body)
        .buttonStyle(BakerButtonStyle())
        .padding(22)
        .frame(width: browser == nil ? 460 : 690)
        .background(BakerTheme.background)
        .foregroundStyle(BakerTheme.ink)
        .onDisappear { job?.cancel(); browser?.close() }
    }

    private var importControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Web Content").font(BakerTypography.title)
            HStack(spacing: 8) {
                TextField("Paste a web link", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .focused($linkFocused)
                    .onChange(of: address) {
                        candidate = nil
                        browserLink = nil
                        message = ""
                    }
                    .onSubmit(open)
                Button("Open", action: open)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .disabled(job != nil)

            if job != nil || candidate != nil || !message.isEmpty {
                HStack(spacing: 8) {
                    if job != nil { ProgressView().controlSize(.small) }
                    Text(job != nil ? "Opening link…" : (message.isEmpty ? candidate?.name ?? "" : message))
                        .font(BakerTypography.supporting).foregroundStyle(.secondary).lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if let browserLink {
                    Button(candidate == nil ? "Continue Here…" : "Open Page…") {
                        message = ""
                        browser = WebImportBrowser(url: browserLink)
                    }
                    .disabled(job != nil)
                }
                Spacer()
                Button("Add") {
                    if let candidate { addToQueue(candidate) }
                }
                .buttonStyle(BakerButtonStyle(prominent: true))
                .disabled(candidate == nil || job != nil)
            }
        }
        .defaultFocus($linkFocused, true)
    }

    private func open() {
        guard job == nil else { return }
        let link = address.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = nil
        browserLink = nil
        guard !link.contains(where: \.isWhitespace), let url = URL(string: link),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil else {
            message = WebImportError.invalidURL.localizedDescription
            return
        }
        message = ""
        job = Task {
            defer { job = nil }
            do {
                let page = try await WebImportSource.link(link).read()
                try Task.checkCancellation()
                candidate = .page(.html(page.html, baseURL: page.baseURL), title: page.baseURL?.host ?? "Web Page")
                browserLink = url
            } catch WebImportError.pdf {
                if !Task.isCancelled {
                    browserLink = url
                    browser = WebImportBrowser(url: url)
                }
            } catch {
                guard !Task.isCancelled else { return }
                switch error {
                case WebImportError.browserRequired, WebImportError.unavailable, WebImportError.unsupported, is URLError:
                    browserLink = url
                    message = "Open this link in Baker’s web view to continue."
                default:
                    message = error.localizedDescription
                }
            }
        }
    }

    private func returnFromBrowser() {
        browser?.close()
        browser = nil
        message = ""
    }

    private func addBrowserContent() {
        guard let browser, job == nil else { return }
        if let file = browser.pdf {
            addToQueue(.pdf(file))
            return
        }
        message = ""
        job = Task {
            defer { job = nil }
            do {
                let page = try await browser.page()
                try Task.checkCancellation()
                guard self.browser === browser else { return }
                let title = browser.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                addToQueue(.page(page, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? browser.origin))
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }

    private func addToQueue(_ item: WebImportCandidate) {
        if add(item) {
            browser?.close()
            dismiss()
        } else {
            message = "Wait for the current job to finish or make room in Clipboard & Files."
        }
    }
}

private struct WebImportBrowserPane: View {
    @ObservedObject var browser: WebImportBrowser
    let busy: Bool
    let error: String
    let back: () -> Void
    let use: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var enteringAddress = false
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { browser.webView.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous page")
                .disabled(!browser.canGoBack || busy)
                Button { browser.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload")
                .disabled(busy || browser.downloading)
                Text(browser.origin).font(BakerTypography.supporting).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                    enteringAddress.toggle()
                    if enteringAddress { addressFocused = true }
                } label: {
                    Image(systemName: "link")
                }
                .accessibilityLabel("Go to Address")
                .disabled(busy)
                if browser.loading || browser.downloading || busy {
                    ProgressView().controlSize(.small)
                }
            }

            if enteringAddress {
                HStack(spacing: 8) {
                    TextField("Enter a web address", text: $address)
                        .focused($addressFocused)
                        .onSubmit(openAddress)
                    Button("Go", action: openAddress).disabled(address.isEmpty)
                }
            }

            ZStack {
                WebImportBrowserSurface(browser: browser).allowsHitTesting(!busy)
                if browser.downloading || browser.pdf != nil {
                    VStack(spacing: 8) {
                        if browser.downloading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "doc.richtext").font(.title2) }
                        Text(browser.pdf?.url.lastPathComponent ?? "Downloading PDF…")
                            .font(BakerTypography.section).lineLimit(2)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BakerTheme.surface)
                }
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BakerTheme.border))

            HStack(spacing: 8) {
                Button("Back to Import", action: back).disabled(busy)
                Button("Open in Browser") { openURL(browser.initialURL) }
                    .disabled(busy)
                Spacer()
                Button(browser.pdf == nil ? "Add Page" : "Add PDF", action: use)
                    .buttonStyle(BakerButtonStyle(prominent: true))
                    .disabled(busy || (browser.pdf == nil && !browser.canUsePage))
            }
            Text(status)
                .font(BakerTypography.supporting)
                .foregroundStyle(.secondary)
        }
    }

    private func openAddress() {
        guard !address.isEmpty else { return }
        browser.open(address)
        address = ""
        enteringAddress = false
    }

    private var status: String {
        if !error.isEmpty { return error }
        if !browser.message.isEmpty { return browser.message }
        if browser.pdf != nil { return "Ready to add to Clipboard & Files." }
        return "Sign in if needed, then choose what to import."
    }
}
