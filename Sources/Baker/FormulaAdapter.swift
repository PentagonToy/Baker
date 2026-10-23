import Foundation

/// A headless, app-neutral entry point. Presentation and clipboard belong to callers.
enum FormulaAdapter {
    struct Request: Decodable { let version: Int; let id: String; let operation: String; let image: String }
    struct Result: Encodable { let latex: String; let model: String; let modelScore: Double? }
    struct Response: Encodable { let version = 1; let id: String?; let result: Result?; let error: String? }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func reply(_ data: Data, recognise: (URL) throws -> FormulaRecognition) -> Data {
        var id: String?
        let response: Response
        do {
            guard data.count <= 65536 else { throw Failure(message: "Request exceeds 64 KiB.") }
            let request = try JSONDecoder().decode(Request.self, from: data)
            guard !request.id.isEmpty, request.id.utf8.count <= 128 else { throw Failure(message: "Invalid request id.") }
            id = request.id
            guard request.version == 1, request.operation == "formula" else { throw Failure(message: "Unsupported adapter version or operation.") }
            guard request.image.hasPrefix("/"), !request.image.contains("\0") else { throw Failure(message: "Use an absolute local image path.") }
            let url = URL(fileURLWithPath: request.image)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let bytes = values.fileSize, bytes > 0, bytes <= 16 * 1024 * 1024 else {
                throw Failure(message: "Use an image file no larger than 16 MiB.")
            }
            let value = try recognise(url)
            response = Response(id: id, result: Result(latex: value.latex, model: value.model, modelScore: value.confidence), error: nil)
        } catch { response = Response(id: id, result: nil, error: error.localizedDescription) }
        return (try? JSONEncoder().encode(response)) ?? Data(#"{"version":1,"error":"Response encoding failed."}"#.utf8)
    }

    static func run(arguments: [String]) -> Int32? {
        guard let flag = arguments.first, flag == "--adapter" || flag == "--adapter-info" else { return nil }
        guard arguments.count == 1 else {
            FileHandle.standardOutput.write(Data(#"{"version":1,"error":"Pass one JSON request on stdin."}"#.utf8)); return 2
        }
        if flag == "--adapter-info" {
            FileHandle.standardOutput.write(Data(#"{"version":1,"operations":["formula"],"input":"local-image","output":"latex","presentation":"headless"}"#.utf8)); return 0
        }
        var input = Data()
        while input.count <= 65536 {
            guard let chunk = try? FileHandle.standardInput.read(upToCount: 65537 - input.count), !chunk.isEmpty else { break }
            input.append(chunk)
        }
        let output = reply(input) { image in
            let defaults = BakerPreferences()
            let python: String, config: String
            if defaults[PreferenceKeys.developerRuntimeOverrides] {
                python = defaults[PreferenceKeys.python]; config = defaults[PreferenceKeys.config]
            } else {
                guard let resources = Bundle.main.resourceURL else { throw Failure(message: "The formula runtime is unavailable. Prepare it in Baker Settings.") }
                let engine = FormulaEngine(rawValue: defaults[PreferenceKeys.formulaEngine]) ?? .mfr
                let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let root = support.appendingPathComponent("Baker/Models")
                let variant = FormulaEngine.cachedMFRVariant(root: root)
                let manifest = try engine.manifest(variant: variant)
                python = resources.appendingPathComponent("Runtime/python/bin/python3.12").path
                config = root.appendingPathComponent(engine.directoryName(variant: manifest.variant) + "/baker-config.json").path
            }
            return try recogniseFormulaResult(image, python: python, config: config)
        }
        FileHandle.standardOutput.write(output)
        FileHandle.standardOutput.write(Data("\n".utf8))
        let value = try? JSONSerialization.jsonObject(with: output) as? [String: Any]
        return value?["error"] == nil ? 0 : 1
    }
}
