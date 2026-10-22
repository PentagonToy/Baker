# Unicode maths

Choose **Unicode** in the Formula Workspace for editable maths in ordinary text fields:

```text
𝑥² + 𝛼 𝑥 + ½ = 0
```

Choose Latin Modern Math (default), TeX Gyre Termes Math, TeX Gyre Pagella Math or STIX in [Settings](settings.md). Baker includes the first three fonts; Unicode conversion requires no TeX installation. Copy includes plain text and formatted text with that font. Ordinary Paste requests the formatting; Paste and Match Style uses the destination’s style.

In a Keynote table, enter text-editing mode inside a cell before pasting. Unicode approximates stacked fractions and cannot preserve a two-dimensional matrix. Choose Keynote or LaTeX when layout matters. The warning icon appears only when Unicode is unavailable; click it for details. Readable approximations do not show a warning icon.

Choose **Install for Other Apps…** to open the selected bundled font in Font Book. Install it there if Keynote or another destination substitutes a different font. The font changes glyph appearance; it does not add stacked fractions or matrix layout to plain Unicode.

## Supported notation

The converter approximates common operators, fractions, accents and scripts. Mathematical font commands retain their content without bold, script or other styling. Representable scripts include `e^{at}` → eᵃᵗ, `x^{k+1}` → xᵏ⁺¹, `V^{T}` → Vᵀ and `x_{\beta}` → xᵦ. Derivative primes such as `x^{\prime}` and `x^{\prime\prime}` become `x′` and `x″`; reverse primes are also supported. These are Unicode character approximations rather than TeX positioning. Unsupported scripts leave the Unicode field empty with a warning; Baker does not lowercase `p_T` or flatten an unsupported grouped subscript.

Sized delimiters such as `\bigl` and `\bigr` become ordinary delimiters with size loss described below the selected output. Invisible delimiters such as `\left .` remain invisible. Unsupported chemistry notation leaves the Unicode field empty.

The plain-text and formatted clipboard representations contain the same characters. Some modifier letters, including superscript letters and Greek subscripts, are absent from the selected maths font and can use a different fallback font. Installing that maths font does not add missing glyphs. Choose LaTeX when exact typography matters.

## Conversion checks and limits

Baker handles scoped legacy font declarations such as `{\bf u}`, starred operator names, continued fractions and mathematical classification wrappers emitted by OCR. Greek epsilon/phi variants follow the semantic glyphs used by the bundled preview: `\epsilon` → ϵ, `\varepsilon` → ε, `\phi` → ϕ and `\varphi` → φ. Uppercase Greek letters retain Greek character identity even where a renderer uses a Latin lookalike; delimiter bars remain distinct from divisibility and parallel relations.

| LaTeX | Plain Unicode |
| --- | --- |
| `x'=ax+b` or `x^{\prime}=ax+b` | x′=ax+b |
| `{\bf u}` | u |
| `\sum_{i\mathop{=}1}^{n}i` | ∑ᵢ₌₁ⁿi |
| `{a+b}^2` | (a+b)² |
| `\frac{a}{b}^2` | ((a)/(b))² |

Visible parentheses preserve the scope of scripts on grouped sums and linear fractions. TeX comments are omitted; escaped percent signs and apostrophes inside text remain text. Layout-only limitations appear as supporting text when Unicode is selected.

Unicode favours readable plain text over mathematical styling. Font commands such as `\bf` and `\mathbf` are removed while retaining their content. Unsupported commands, malformed groups and notation that cannot be converted leave the field empty. LaTeX remains available separately.

Development checks cover existing formula fixtures, authored examples and saved OCR outputs in both plain and italic-variable modes, with additional symbol, script-identity and clipboard round-trip checks. They test conversion behaviour, not OCR accuracy or paste appearance in every destination app. The audit tools generate an HTML comparison outside the repository without loading OCR models or modifying the system clipboard.
