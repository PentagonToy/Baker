# Unicode maths

Capture with **Formula**, then choose **Unicode** in the Formula Workspace when the receiving application needs ordinary editable text, such as a table cell. Baker recognises the equation and represents supported notation using mathematical Unicode characters:

```text
𝑥² + 𝛼 𝑥 + ½ = 0
```

Variables use mathematical italic Latin and Greek characters. Common symbols, supported superscripts/subscripts, fractions, roots and accents retain a mathematical appearance. Named operators and explicit upright text remain upright.

## Choose a font

In **Settings → Unicode maths font**, choose **STIX Two Math** (default), **STIX** or **Latin Modern Math**. The preview follows your selection. Baker uses installed fonts; if one is missing, Settings names the fallback. It does not install fonts automatically.

## Paste into another application

The Copy action places plain Unicode and formatted text containing the same characters on the clipboard. The formatted version includes the selected font. Paste normally to request that formatting. **Paste and Match Style** asks the destination to use its own text style; the mathematical Unicode characters remain.

For Keynote, enter text-editing mode inside the destination table cell before pasting. [Apple's paste guide](https://support.apple.com/guide/keynote/copy-and-paste-text-tan7cad4c5e1/mac) explains the difference between ordinary paste and matching the destination style. Actual Baker-to-Keynote table pasting still needs end-to-end verification.

## Representation limits

Plain Unicode cannot preserve every stacked fraction, matrix, stretchy bracket or arbitrary script. Matrices are not converted into two-dimensional Unicode layouts. Unsupported notation remains visible with a warning. Choose **LaTeX** in the Formula Workspace when exact mathematical layout matters.

There is no standalone clipboard LaTeX-to-Unicode converter or automatic conversion while editing LaTeX. Unicode output belongs to the formula OCR workflow.
