# Conversion quality: next-session priority

Recorded on 16 October 2026. Starting implementation: `68a1294` on `main`.

## User report

The user reports that Baker's Markdown and LaTeX conversion is far below Mathpix quality and almost unusable. Treat conversion quality as a critical unresolved product issue. Passing execution, export or model-integrity tests does not establish useful document conversion. No new conversion-quality validation was performed during this closing session.

The exact failing input and output have not yet been isolated. Start with PDF-to-Markdown and PDF-to-LaTeX, while checking whether formula capture/copy output also contributes to the complaint. Do not label the problem as formatting alone before inspecting the results.

## First work tomorrow

1. Locate the previously supplied PDF and its Mathpix Markdown/LaTeX exports, originally provided under `Tests/temp`. Check existing agent reference notes and external artefacts for their current location before asking the user to provide them again.
2. Convert the same representative pages in Baker and compare source, Mathpix output and Baker output side by side. Include prose, displayed and inline equations, matrices, tables, figures, columns and scanned content where present.
3. Separate failures in page layout/reading order, text extraction, formula detection/recognition and output serialisation. Record concrete before/after examples rather than a single model confidence score.
4. Revisit `agent/reference-engine-audit.md` and the collected reference engines. Select changes based on the observed failures; plain text extraction with Markdown or LaTeX wrappers is not sufficient for structured scientific documents.
5. Implement a bounded improvement and verify it against the same comparison corpus before calling it fixed. Keep installation automatic, preserve local processing and avoid loading heavy engines while idle.

## Acceptance criteria

Output must preserve reading order and usable paragraph structure, separate inline/displayed maths, retain equation structure and matrix rows, and avoid silently flattening tables or dropping figures. LaTeX output must be checked for compilation and visual fidelity on representative pages; Markdown must be reviewed in a maths-capable renderer. State unsupported cases explicitly. Format wrappers and cosmetic spacing do not count as an accuracy improvement.

## Scope and end-of-day state

The user asked to stop implementation work today, retain this hand-off in `agent/`, and make a local commit only. Do not push this closing commit or publish its notes automatically. `agent/` remains ignored generally; only this sanitised note is explicitly included in the requested local commit. Check this local-only commit before the next remote publication.

GitHub distribution remains the intended route. Cloud/server work is deferred. The previous installed app contains automatic formula-model preparation and the file-workspace visibility/picker repair; these do not resolve the conversion-quality complaint.
