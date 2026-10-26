# Local recognition adapter

Baker accepts local formula requests through a short-lived command-line process. Send one versioned JSON request on standard input, close the input, then read one response from standard output. The adapter leaves windows, the clipboard and capture history unchanged.

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

Without an adapter flag, Baker starts its normal menu-bar interface. Each request runs in a short-lived process. Clients should serialise expensive requests and own process cancellation and retry.

Formula weights download separately through Settings. The adapter uses the selected prepared model and leaves provisioning to the app.
