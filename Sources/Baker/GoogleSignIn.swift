import AppKit
import BakerCore
import Network

enum SignInProvider { case google, dropbox; var title: String { self == .google ? "Google" : "Dropbox" } }

@MainActor
final class GoogleSignIn {
    private var sessionID: UUID?
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var continuation: CheckedContinuation<(code: String, redirect: String, verifier: String), Error>?
    private var timeout: Task<Void, Never>?
    func authorize(clientID: String, provider: SignInProvider = .google, openBrowser: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) async throws -> (code: String, redirect: String, verifier: String) {
        guard continuation == nil else { throw BakerError(message: "Sign-in is already running.") }
        let identifier = UUID(); sessionID = identifier
        let verifier = try GoogleOAuth.random(), state = try GoogleOAuth.random()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: provider == .google ? .any : NWEndpoint.Port(rawValue: DropboxOAuth.port)!)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                listener.stateUpdateHandler = { [weak self] status in
                    Task { @MainActor in
                        guard let self, self.sessionID == identifier, self.continuation != nil else { return }
                        switch status {
                        case .ready:
                            do {
                                guard let port = listener.port?.rawValue else { throw BakerError(message: "Could not open the local sign-in callback.") }
                                let url = try provider == .google ? GoogleOAuth.authorizationURL(clientID: clientID, port: port, verifier: verifier, state: state) : DropboxOAuth.authorizationURL(clientID: clientID, verifier: verifier, state: state)
                                guard openBrowser(url) else { throw BakerError(message: "Could not open your browser for sign-in.") }
                            } catch { self.finish(.failure(error)) }
                        case .failed: self.finish(.failure(BakerError(message: "The local sign-in callback could not start.")))
                        default: break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        guard let self, self.sessionID == identifier, self.connections.count < 4, self.continuation != nil else { connection.cancel(); return }
                        let id = UUID(); self.connections[id] = connection; connection.start(queue: .main)
                        self.receive(connection, id: id, data: Data(), state: state, verifier: verifier, provider: provider)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.connections.removeValue(forKey: id)?.cancel() }
                    }
                }
                listener.start(queue: .main)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
                    self?.finish(.failure(BakerError(message: "\(provider.title) sign-in timed out. Choose Connect to try again.")), sessionID: identifier)
                }
                if Task.isCancelled { cancel() }
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError()), sessionID: identifier) } }
    }
    private func receive(_ connection: NWConnection, id: UUID, data: Data, state: String, verifier: String, provider: SignInProvider) {
        let expectedSession = sessionID
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] part, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var buffer = data; if let part { buffer.append(part) }
                guard buffer.count <= 16384, error == nil else { self.connections.removeValue(forKey: id)?.cancel(); return }
                guard let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if !complete { self.receive(connection, id: id, data: buffer, state: state, verifier: verifier, provider: provider) }
                    else { self.connections.removeValue(forKey: id)?.cancel() }; return
                }
                let words = text.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard words.count == 3, words[0] == "GET", let port = self.listener?.port?.rawValue else { connection.cancel(); self.connections[id] = nil; return }
                do {
                    let code = try GoogleOAuth.callback(String(words[1]), port: port, state: state, path: provider == .google ? "/oauth/google" : "/oauth/dropbox")
                    let body = "\(provider.title) sign-in received. You can return to Baker."
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        Task { @MainActor in self.finish(.success((code, provider == .google ? GoogleOAuth.redirect(port) : DropboxOAuth.redirect, verifier)), sessionID: expectedSession) }
                    })
                } catch is GoogleOAuth.Declined {
                    connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in
                        Task { @MainActor in
                            let error: Error = provider == .google ? GoogleOAuth.Declined() : BakerError(message: "Dropbox sign-in was declined.")
                            self.finish(.failure(error), sessionID: expectedSession)
                        }
                    })
                } catch {
                    // An unrelated local request cannot terminate the outstanding OAuth session.
                    connection.send(content: Data("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
                    self.connections[id] = nil
                }
            }
        }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<(code: String, redirect: String, verifier: String), Error>, sessionID expected: UUID? = nil) {
        guard expected == nil || expected == sessionID, let continuation else { return }
        self.continuation = nil; sessionID = nil; timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil; connections.values.forEach { $0.cancel() }; connections = [:]
        continuation.resume(with: result)
    }
}
