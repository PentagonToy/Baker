import Foundation

var checks = 0
func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
    checks += 1
}
let samples: [(String, String)] = [
    (#"\left\|x\right\|"#, "‖x‖"),
    (#"x'=ax+b"#, "x′=ax+b"), (#"x''+x'''+x''''"#, "x″+x‴+x⁗"),
    (#"\text{don't}+x'"#, "don't+x′"), (#"\operatorname{don't}(x)"#, "don't(x)"),
    (#"{a+b}'"#, "(a+b)′"), (#"\frac{a}{b}'"#, "((a)/(b))′"),
    (#"\big x"#, #"\big x"#), (#"\left"#, #"\left"#),
    (#"\left\lfloor x\right\rfloor"#, "⌊ x⌋"),
    (#"\epsilon+\varepsilon+\phi+\varphi"#, "ϵ+ε+ϕ+φ"),
    (#"{\bf p}_r"#, "𝐩ᵣ"), (#"{\bf p q}+r"#, "𝐩 𝐪+r"),
    (#"{\bf p{\it q}r}+s"#, "𝐩𝑞𝐫+s"), (#"{\rm x}+y"#, "x+y"),
    (#"\operatorname*{arg\,max}"#, "arg max"), (#"\operatorname * { l i m }"#, "lim"),
    (#"\mathop{=}+\mathrel{\leq}"#, "=+≤"), (#"\mbox{a b}+\hbox{c d}"#, "a b+c d"),
    (#"\displaystyle\sum\limits_{n=0}^2n"#, "∑ₙ₌₀²n"),
    (#"\cfrac{a+b}{c}"#, "(a+b)/(c)"), (#"\cfrac[l]{a}{b}"#, "(a)/(b)"),
    (#"\cfrac[z]{a}{b}"#, #"\cfrac[z]{a}{b}"#),
    (#"P(A\mid B)"#, "P(A∣ B)"), (#"a\:b"#, "a b"),
    (#"\frac{a}{b}^2"#, "((a)/(b))²"), (#"{a+b}^2"#, "(a+b)²"),
    (#"{x}^2"#, "x²"), (#"\frac12^2"#, "½²"),
    (#"A=\begin{pmatrix}a&b\\c&d\end{pmatrix}"#, #"A=\begin{pmatrix}a&b\\c&d\end{pmatrix}"#),
    (#"\unknown{\alpha}"#, #"\unknown{\alpha}"#),
    (#"\overset{!}{=}"#, #"\overset{!}{=}"#),
    (#"\text{50\%}+x"#, "50%+x"), (#"x^"#, #"x^"#), (#"x}"#, #"x}"#),
    (#"\sqrt"#, #"\sqrt"#), (#"\mathrm"#, #"\mathrm"#),
    (#"x^{\prime}=ax+b"#, "x′=ax+b"), (#"f^\prime(x)"#, "f′(x)"),
    (#"x^{\prime\prime}"#, "x″"), (#"x^{\prime\prime\prime}"#, "x‴"),
    (#"x^{\prime\prime\prime\prime}"#, "x⁗"),
    (#"x^{\dprime}+y^{\trprime}+z^{\qprime}"#, "x″+y‴+z⁗"),
    (#"x^{\backprime}+y^{\backprime\backprime}+z^{\backtrprime}"#, "x‵+y‶+z‷"),
    (#"x_{\prime}"#, #"x_{\prime}"#), (#"x^{\prime q}"#, #"x^{\prime q}"#),
    (#"x^{\prime"#, #"x^{\prime"#),
    (#"\mathfrak{ABCDEFGHIJKLMNOPQRSTUVWXYZ}"#, "𝔄𝔅ℭ𝔇𝔈𝔉𝔊ℌℑ𝔍𝔎𝔏𝔐𝔑𝔒𝔓𝔔ℜ𝔖𝔗𝔘𝔙𝔚𝔛𝔜ℨ"),
    (#"\mathfrak{abcdefghijklmnopqrstuvwxyz}"#, "𝔞𝔟𝔠𝔡𝔢𝔣𝔤𝔥𝔦𝔧𝔨𝔩𝔪𝔫𝔬𝔭𝔮𝔯𝔰𝔱𝔲𝔳𝔴𝔵𝔶𝔷"),
    (#"\mathscr{ABCDEFGHIJKLMNOPQRSTUVWXYZ}"#, "𝒜ℬ𝒞𝒟ℰℱ𝒢ℋℐ𝒥𝒦ℒℳ𝒩𝒪𝒫𝒬ℛ𝒮𝒯𝒰𝒱𝒲𝒳𝒴𝒵"),
    (#"\mathscr{abcdefghijklmnopqrstuvwxyz}"#, "𝒶𝒷𝒸𝒹ℯ𝒻ℊ𝒽𝒾𝒿𝓀𝓁𝓂𝓃ℴ𝓅𝓆𝓇𝓈𝓉𝓊𝓋𝓌𝓍𝓎𝓏"),
    (#"\mathbfit{ABCDEFGHIJKLMNOPQRSTUVWXYZ}"#, "𝑨𝑩𝑪𝑫𝑬𝑭𝑮𝑯𝑰𝑱𝑲𝑳𝑴𝑵𝑶𝑷𝑸𝑹𝑺𝑻𝑼𝑽𝑾𝑿𝒀𝒁"),
    (#"\mathbfit{abcdefghijklmnopqrstuvwxyz}"#, "𝒂𝒃𝒄𝒅𝒆𝒇𝒈𝒉𝒊𝒋𝒌𝒍𝒎𝒏𝒐𝒑𝒒𝒓𝒔𝒕𝒖𝒗𝒘𝒙𝒚𝒛"),
    (#"e^{at}"#, "eᵃᵗ"), (#"x^{k+1}"#, "xᵏ⁺¹"), (#"V^{T}"#, "Vᵀ"),
    (#"x_{\beta\gamma\rho\varphi\chi}"#, "xᵦᵧᵨᵩᵪ"),
    (#"\mathfrak{CHIRZ}"#, "ℭℌℑℜℨ"), (#"\mathscr{BEFHILMRego}"#, "ℬℰℱℋℐℒℳℛℯℊℴ"),
    (#"\mathbfit{Az}"#, "𝑨𝒛"), (#"\boldsymbol{\alpha\Omega}"#, "𝜶𝜴"),
    (#"\mathbf{\alpha\Omega}"#, "𝛂𝛀"), (#"\check{x}+\breve{a}"#, "x̌+ă"),
    (#"\lfloor x\rfloor+\lceil y\rceil"#, "⌊ x⌋+⌈ y⌉"),
    (#"\therefore x\longrightarrow y\checkmark"#, "∴ x⟶ y✓"),
    (#"\left . x \right |"#, " x |"), (#"\bigl(x\bigr)"#, "(x)"),
    (#"\alphabet"#, #"\alphabet"#), (#"p_T"#, #"p_T"#), (#"x_{i\mu}"#, #"x_{i\mu}"#),
    (#"x^{q}"#, #"x^{q}"#), (#"\ce{2 H2 + O2 -> 2 H2O}"#, #"\ce{2 H2 + O2 -> 2 H2O}"#),
    (#"\frac{1x}{2}"#, "(1x)/(2)"), (#"\frac{a}{b"#, #"\frac{a}{b"#),
    (#"\mathit{h}+\mathbb{R}+x^2"#, "ℎ+ℝ+x²")
]
for (source, expected) in samples {
    let actual = UnicodeMath.convert(source)
    check(actual.text == expected, "\(source): expected \(expected), got \(actual.text)")
}
check(UnicodeMath.convert(#"e^{at}"#).warnings.isEmpty, "Representable scripts do not warn")
check(UnicodeMath.convert(#"p_T"#).warnings.contains { $0.contains("not supported by the Unicode converter") }, "Coverage warning is honest")
check(!UnicodeMath.convert(#"\big(x\big)"#).warnings.isEmpty, "Size loss is disclosed")
check(UnicodeMath.convert(#"\left . x \right |"#).warnings.isEmpty, "Invisible delimiter")
check(UnicodeMath.convert(#"e^{at}"#, italicVariables: true).text == "𝑒ᵃᵗ", "Automatic variable styling preserves scripts")
check(UnicodeMath.convert(String(repeating: "x", count: 100001)).text.count == 100001, "Length guard")
check(!UnicodeMath.convert(String(repeating: "^", count: 1000)).warnings.isEmpty, "Depth guard")

check(UnicodeMath.convert(#"x^{\prime}=ax+b"#, italicVariables: true).text == "𝑥′=𝑎𝑥+𝑏", "Prime with italic variables")
check(UnicodeMath.convert(#"x^{\prime}=ax+b"#).warnings.isEmpty, "Representable prime does not warn")
check(!UnicodeMath.convert(#"x_{\prime}"#).warnings.isEmpty, "Subscript prime is not silently moved upward")
check(UnicodeMath.convert("x% comment\n+y").text == "x+y", "TeX comment is not mathematical content")
check(UnicodeMath.convert(#"{\bf p}_r+q"#, italicVariables: true).text == "𝐩ᵣ+𝑞", "Declaration scope survives subscript and italic default")
check(UnicodeMath.convert(#"\epsilon+\varepsilon+\phi+\varphi"#, italicVariables: true).text == "𝜖+𝜀+𝜙+𝜑", "Greek variant identity survives italic styling")
for source in [#"\begin{matrix}a&b\\c&d\end{matrix}"#, #"\unknown{\alpha}"#, #"\binom{n}{k}"#, #"\overset{!}{=}"#] {
    for italic in [false, true] {
        let value = UnicodeMath.convert(source, italicVariables: italic)
        check(value.text == source && !value.warnings.isEmpty, "Unsupported structure retains exact source in both modes")
        check(value.warnings.count == Set(value.warnings).count, "Fallback warnings are deduplicated")
    }
}
for source in [#"x^"#, #"\sqrt"#, #"\mathrm"#, #"x}"#] {
    check(!UnicodeMath.convert(source).warnings.isEmpty, "Incomplete syntax cannot silently succeed")
}
for source in [#"\mathbb{\alpha}"#, #"{\cal \alpha}"#] {
    let value = UnicodeMath.convert(source)
    check(value.text == source && !value.warnings.isEmpty, "Unsupported Greek alphabet cannot silently become ordinary Greek")
}
for name in LatexWhitespace.standardOperators {
    check(UnicodeMath.convert("\\" + name + "(x)").warnings.isEmpty, "Standard operator " + name)
}
if CommandLine.arguments.count > 1 {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let symbols = try JSONSerialization.jsonObject(with: data) as! [String: String]
    for (name, expected) in symbols {
        check(UnicodeMath.convert("\\" + name).text == expected, "Bundled preview semantic glyph: " + name)
    }
}
print("Passed \(checks) Unicode regression checks")

for (source, expected) in [(#"{\bf x}+\mathbf{y}"#, "x+y"), (#"\mathcal{A}+\alpha"#, "A+α"), (#"x^{\prime}=a x+b"#, "x′=a x+b"), (#"\unknown{x}"#, ""), (#"\begin{unsupported}x\end{unsupported}"#, ""), (#"\frac{1}{2}"#, "½")] {
    precondition(UnicodeMath.approximate(source).text == expected, "Plain approximation: " + source)
}
print("Plain Unicode approximation: 6 checks passed")
