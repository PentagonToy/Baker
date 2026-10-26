import AppKit
import WebKit

/// A temporary, isolated view for a plugin's foreground loopback setup page.
@MainActor final class PluginSetupWindow: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private let origin: URL
    private var onCancel: (() -> Void)?
    static func localURL(_ raw: String) -> URL? {
        guard raw.utf8.count <= 2048, let parts = URLComponents(string: raw),
              parts.scheme == "http", parts.host == "127.0.0.1", let port = parts.port,
              (1024...65535).contains(port), parts.user == nil, parts.password == nil,
              parts.fragment == nil, !parts.path.isEmpty else { return nil }
        return parts.url
    }
    init(url: URL, cancel: @escaping () -> Void) {
        origin = url; onCancel = cancel
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 410),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Baker · Plugin Setup"; window.isReleasedWhenClosed = false; window.delegate = self
        webView.navigationDelegate = self
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelSetup))
        let passwordsButton = NSButton(title: "Passwords…", target: self, action: #selector(openPasswords))
        passwordsButton.bezelStyle = .rounded
        passwordsButton.toolTip = "Open Apple Passwords to choose saved account details."
        cancelButton.bezelStyle = .rounded; cancelButton.keyEquivalent = "\u{1b}"
        let content = NSView(); window.contentView = content
        for view in [webView, cancelButton, passwordsButton] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor), webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor), webView.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -12),
            passwordsButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            passwordsButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14), cancelButton.widthAnchor.constraint(equalToConstant: 88)
        ])
    }
    func show() {
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        // Block remote subresources as well as navigation; setup stays on its exact loopback origin.
        let allowed = "^http://127\\.0\\.0\\.1:" + String(origin.port!) + "/"
        let rules: [[String: Any]] = [
            ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
            ["trigger": ["url-filter": allowed], "action": ["type": "ignore-previous-rules"]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) else { cancelSetup(); return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "baker-plugin-setup-" + UUID().uuidString, encodedContentRuleList: json) { [weak self] rule, _ in
            Task { @MainActor in
                guard let self, self.onCancel != nil else { return }
                guard let rule else { self.cancelSetup(); return }
                self.webView.configuration.userContentController.add(rule)
                self.webView.load(URLRequest(url: self.origin))
                WKContentRuleListStore.default().removeContentRuleList(forIdentifier: rule.identifier) { _ in }
            }
        }
    }
    func dismiss() {
        onCancel = nil; webView.stopLoading(); webView.navigationDelegate = nil
        webView.configuration.userContentController.removeAllContentRuleLists(); window.orderOut(nil); window.close()
    }
    @objc private func openPasswords() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func cancelSetup() { let callback = onCancel; dismiss(); callback?() }
    func windowWillClose(_ notification: Notification) { let callback = onCancel; onCancel = nil; callback?() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        decisionHandler(url?.scheme == origin.scheme && url?.host == origin.host && url?.port == origin.port && action.targetFrame != nil ? .allow : .cancel)
    }
}
