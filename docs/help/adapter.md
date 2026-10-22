# Local recognition adapter

Baker keeps an app-neutral, headless recognition entry point for future local clients. It has no dependency on Deerstalker, URL schemes or shared clipboard names. A caller starts one short-lived process, sends one versioned JSON request on standard input and closes that input, then reads one JSON response from standard output. No application window, capture sound, notification, capture-history entry or clipboard change is produced by this path.

## Capabilities and invocation

Run `Baker.app/Contents/MacOS/Baker --adapter-info` to inspect the protocol version and supported operations without loading a model. Version 1 currently offers `formula` only; text OCR, PDF conversion and other operations are not advertised as available through this adapter.

```sh
printf '%s' '{"version":1,"id":"client-request-42","operation":"formula","image":"/absolute/path/equation.png"}' \
  | /Applications/Baker.app/Contents/MacOS/Baker --adapter
```

Prepare formula recognition once through Baker's ordinary settings before using the adapter. It reuses the installed runtime and existing model configuration; requests do not download, install or provision models. Developer runtime overrides retain their existing meaning.

## Request and response

A request requires `version` (1), a non-empty `id` up to 128 UTF-8 bytes, `operation` (`formula`) and an absolute local `image` path. Input JSON is bounded to 64 KiB. The path must identify a regular non-empty file no larger than 16 MiB; the existing worker applies its own image/model limits. Unsupported versions/operations and malformed requests return structured errors without starting recognition.

```json
{"version":1,"id":"client-request-42","result":{"latex":"E = mc^{2}","model":"mfr","modelScore":0.91}}
```

An error response contains `version`, the caller's `id` when available and an `error` string, without `result`. Process exit status is 0 for success/capability information, 1 for recognition/request errors and 2 for invalid adapter command-line usage. `modelScore` is optional model token confidence, not a verified probability of correctness. Callers own review, presentation, output formatting, clipboard policy and history. The adapter does not attempt to classify prose as equations.

The original menu-bar application path is unchanged when no adapter flag is supplied. No persistent adapter server or additional resident model is created. Multiple clients should serialise expensive requests themselves; caller-owned process cancellation and retry remain follow-up work.

## Validation status

Pure request/response checks cover success, caller identity, rejected paths, versions/operations, malformed and oversized input, and engine-call isolation. The complete Baker source typechecks. A release package was rebuilt and installed on the M1 Pro on 19 October 2026. Capability probing passed, and a synthetic E = mc² image returned equivalent LaTeX through the packaged adapter in approximately 1.12 seconds with an empty error stream. This is a single functional smoke check, not a general accuracy or cold/warm performance benchmark.


When rebuilding with an existing runtime that contains a quantised formula model, pass its matching descriptor through `BAKER_FORMULA_MODEL_MANIFEST`. Packaging rejects a bundled model/descriptor variant mismatch instead of silently selecting an unprepared model directory. This setting affects packaging only and does not download models.
