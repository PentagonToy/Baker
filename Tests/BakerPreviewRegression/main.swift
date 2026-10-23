// Run with tools/test_formula_preview.py; exercises the current app renderer in WebKit.
import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
Task { @MainActor in
    var checks = 0
    var failures: [String] = []
    let renderer = FormulaPreviewRenderer(resourceURL: resources)
    func check(_ value: Bool, _ label: String) {
        checks += 1
        if !value { failures.append(label); print("FAIL", label) }
    }
    var fixtures: [(String, String)] = [
        ("operators", #"\operatorname{ e x p }(-x)+\log x+\sin x"#),
        ("big", #"\big(c_r^2d_r(\mathbf{x})^2+3c_rd_r(\mathbf{x})+3\big)"#),
        ("piecewise", #"\phi_r(x)=\left\{\begin{aligned}{}&{}&{}&(1-d_r(x)^2/c_r^2)^5,&d_r(x)\leq c_r,\\{}&{}&{}&0,&d_r(x)>c_r.\end{aligned}\right."#),
        ("legacy-bold", #"\phi_r(x;{\bf p}_r)"#),
        ("accents", #"\hat{x}+\vec{v}+\overline{AB}+\dot{x}+\ddot{x}"#),
        ("limits", #"\displaystyle\sum\limits_{n=0}^{\infty}\frac{x^n}{n!}=\exp(x)"#),
        ("binomial", #"\binom{n}{k}+\boldsymbol{\alpha}+\pmod{n}"#),
        ("annotations", #"\underbrace{a+b}_{n}\overset{!}{=}c\xrightarrow{\Delta}d"#),
        ("starred-operator", #"\operatorname*{arg\,max}_{x} f(x)+\varlimsup_{n\to\infty}x_n"#),
        ("matrix", #"\begin{pmatrix}a&b\\c&d\end{pmatrix}"#),
        ("cases", #"f(x)=\begin{cases}x^2&x>0\\0&\text{otherwise}\end{cases}"#),
        ("chemistry", #"\ce{2 H2 + O2 -> 2 H2O}"#),
        ("ions", #"\ce{SO4^2- + Ba^2+ -> BaSO4 v}"#),
        ("equilibrium", #"\ce{N2 + 3 H2 <=> 2 NH3}"#),
        ("isotope", #"\ce{^{14}_{6}C -> ^{14}_{7}N + e-}"#),
        ("hydrate", #"\ce{CuSO4 * 5 H2O}"#),
        ("plain-chemistry", #"\mathrm{SO_4}^{2-}+{}^{14}_{6}\mathrm{C}"#),
        ("delimited", #"$$\frac{a}{b}+\sqrt{x}$$"#),
        ("safe-text", #"\text{<script>alert(1)</script>}"#)
    ]
    fixtures += LatexWhitespace.standardOperators.sorted().map { ("operator-" + $0, "\\" + $0 + " x") }
    do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if CommandLine.arguments.count > 3 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
            let examples = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let names = examples.keys.filter { $0.hasPrefix("keynote-user-") }.sorted()
            check(names.count == 3, "Three reported Keynote failures supplied")
            for name in names {
                if let value = examples[name] as? [String: String], let converted = value["converted"] { fixtures.append((name, converted)) }
                else { check(false, "Missing converted fixture " + name) }
            }
        }
        for (label, source) in fixtures {
            do {
                let start = Date()
                let image = try await renderer.render(source)
                check(image.size.width > 32 && image.size.height > 32, label)
                let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                check(bitmap.pixelsWide == Int(image.size.width * 2) && bitmap.pixelsHigh == Int(image.size.height * 2), label + " Retina scale")
                let png = bitmap.representation(using: .png, properties: [:])!
                try png.write(to: output.appendingPathComponent(label + ".png"))
                // A full padding border must survive initial font loading and snapshotting.
                let edges = [(0,0),(bitmap.pixelsWide-1,0),(0,bitmap.pixelsHigh-1),(bitmap.pixelsWide-1,bitmap.pixelsHigh-1)]
                check(edges.allSatisfy { x,y in
                    guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return colour.redComponent > 0.95 && colour.greenComponent > 0.95 && colour.blueComponent > 0.95
                }, label + " padding")
                print("PASS",label,bitmap.pixelsWide,bitmap.pixelsHigh,String(format:"%.3fs",Date().timeIntervalSince(start)))
            } catch { check(false,label + ": " + error.localizedDescription) }
        }
        for source in [#"\href{https://example.com}{x}"#, #"\includegraphics{https://example.com/x.png}"#, #"\chemfig{H-O-H}"#, #"\ch{H2O}"#, #"\unknowncommand{x}"#, #"\frac{a}{"#, #"\def\a{\a}\a"#, String(repeating:"x",count:8001), ""] {
            do { _ = try await renderer.render(source); check(false,"Expected source fallback: " + String(source.prefix(40))) }
            catch { check(true,"Source fallback"); print("EXPECTED",String(source.prefix(40)),error.localizedDescription) }
        }
        let first = try await renderer.render(#"\ce{H2O}"#)
        let cached = try await renderer.render(#"\ce{H2O}"#)
        check(first === cached,"Same-source cache reuse")
        renderer.clearCache()
        let rebuilt = try await renderer.render(#"\ce{H2O}"#)
        check(rebuilt !== first,"Cache clear regenerates snapshot")
        async let a = renderer.render(#"\sqrt{1+x^2}"#)
        async let b = renderer.render(#"\ce{CO2}"#)
        let both = try await (a,b)
        check(both.0.size != both.1.size,"Queued snapshots stay associated with their source")
        let cancelled = Task { try await renderer.render(#"\int_0^1 x^2\,dx"#) }
        cancelled.cancel()
        do { _ = try await cancelled.value; check(false,"Cancelled render") }
        catch is CancellationError { check(true,"Cancelled render") }
        let interrupted = Task { try await renderer.render(#"\int_0^2\sin(x)\,dx"#) }
        await Task.yield()
        interrupted.cancel()
        do { _ = try await interrupted.value; check(false,"Active render cancellation") }
        catch is CancellationError { check(true,"Active render cancellation") }
        _ = try await renderer.render(#"\ce{AgCl}"#)
        check(true,"Renderer recovers after cancellation")
        let defined = try await renderer.render(#"\gdef\bakerprivate{q}\bakerprivate"#)
        check(defined.size.width > 0,"Per-equation macro definition")
        do { _ = try await renderer.render(#"\bakerprivate"#); check(false,"Macro isolation") }
        catch { check(true,"Macro isolation") }
    } catch { check(false,"Unexpected: " + error.localizedDescription) }
    print("RESULT",checks,"checks",failures.count,"failures")
    fflush(stdout)
    exit(failures.isEmpty ? 0 : 1)
}
application.run()
