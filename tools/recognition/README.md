# Baker OCR experiments

These tools compare local OCR engines, prepare checked training targets and package the small PDF engine selected by Baker. Running a comparison or the standalone preview does not replace the installed app; the app builder performs installation. Generated data, models, logs and bundles belong under `Agents/Repository/baker`, outside this source directory.

## Engine architecture

Ordinary text uses macOS Vision. The PDF engine keeps reliable native PDF text, detects regions with an ONNX layout model, and sends difficult text, formulae and tables to a quantised GLM-OCR derivative. It loads the large model only when a region needs OCR. Baker's existing reconstruction code supplies reading order, equation labels, author scripts, Markdown and LaTeX. Publication notices use native text OCR; table scripts are restored only from matching native labels. Sparse line repair is restricted to numbered bibliography blocks; mathematical prose remains visually recognised.

Paddle, GLM BF16, Vision and Tesseract supply independently checked training examples. Their complete models and training environments are not needed at inference time. This is sequence-level teacher selection and small adapter training; it does not combine incompatible model weights or establish that every teacher's strengths have transferred.

## Tools

| Tool | Role |
| --- | --- |
| `corpus.py` | Create self-authored text, formula and table examples with separate train, validation and test content |
| `recognise.py` | Save raw GLM/Paddle predictions and timings |
| `vision.js`, `text_baseline.py`, `formula_baseline.py` | Measure native text OCR, Tesseract and the existing MFR worker |
| `paddle_output.py` | Decode Paddle's OTSL tables with its installed official decoder |
| `evaluate.py` | Check text, grouped LaTeX, table values, merged cells and prediction coverage |
| `prepare_training.py` | Accept only teacher outputs that match authored targets; exclude test and regression references |
| `quantise.py`, `train.py` | Prepare mixed precision and train an adapter in the selected MLX environment |
| `prepare_minimal.py` | Extract the tested MLX-VLM 0.7.8 GLM definitions with their MIT licence and source hashes |
| `minimal.py` | Run single-image inference without PyTorch, Transformers or MLX-VLM |
| `layout.py`, `pdf_text.py`, `pdf_candidate.py` | Run the PDF pipeline used by the selected engine |
| `measure.py` | Measure whole-process time and macOS process-tree physical footprint, including compressed memory |
| `package.py`, `preview.py` | Create a separate offline runtime and a double-click PDF preview launcher |
| `validate.py` | Run PDF fixtures sequentially, check author order and equation labels, and optionally compile LaTeX |

## Reproduction

Use the host's designated agent Python for corpus preparation and scoring. Model comparison and training use their explicitly selected environments. Inference uses the generated standalone runtime. Successful agent execution does not establish compatibility with another Python environment or Mac.

The inference dependency versions are pinned in `requirements-inference.txt`; Python 3.12 arm64 is required. The extraction tool accepts only the tested MLX-VLM version. Installation and model preparation remain explicit steps; these scripts do not install dependencies or start servers.

For future training runs, pass `train.py --record /absolute/path/to/new-run.json` along with the MLX training arguments and an explicit seed. The record captures the arguments, interpreter, packages, source commit and tool hashes before training. It refuses to overwrite an existing record.

For a prepared bundle, double-click `Preview.command`, choose a PDF, and open the generated Markdown, LaTeX or figures. Results go into a new directory beside the bundle under `preview-results`. The source PDF and existing results are preserved. The launcher does not install or replace Baker.

The same preview supports a repeatable command:

```sh
"/absolute/path/to/engine/python/bin/python3.12" -I -B \
  "/absolute/path/to/engine/worker/preview.py" \
  --source "/absolute/path/to/input.pdf" \
  --output "/absolute/path/to/new-results"
```

`package.py --help` lists the required model, adapter, layout, extracted code, reconstruction source and provenance inputs. Run it from the minimal inference environment with a relocatable standalone CPython base. It refuses to overwrite an existing bundle, preserves dependency licences and creates a SHA-256 inventory. The source package builder and the generated bundle have separate roles; neither `package.py` nor `Preview.command` changes `/Applications/Baker.app`.

Run the structural checks with:

```sh
python tools/recognition/test_recognition.py
```

## Evaluation boundaries

The initial corpus contains 104 self-authored images: 54 training, 22 validation and 28 test cases. It covers six text languages, formulae and simple tables. Real papers and captured formula crops remain outside training. Previous OCR strings measure regression agreement, not correctness.

Select quantisation and training settings on validation data. Preserve raw predictions, image hashes and teacher-selection audits. Report missing or truncated predictions. Table scores compare cell values and spans rather than HTML formatting. Formula exact matching preserves fraction grouping but still penalises some valid alternate LaTeX syntax. Inspect difficult formulae and real PDF exports separately.

LaTeX comparison preserves command boundaries and text-mode spaces. The training target keeps the authored formula spelling after teacher checking; never train on a comparator's whitespace-stripped representation. Keep corrected labels and comparison normalisation separate.

The 17 October experiment produced an approximately 815 MiB checkpoint, a 1.5 MiB adapter and an approximately 1.45 GiB standalone PDF bundle. The PDF release packages the selected checkpoint and adapter with its notices and inference runtime. The small held-out corpus cannot establish general accuracy; adapter training has not demonstrated a broad improvement over the strong base model. Generic Korean recognition remains weak, so native text OCR is retained. Complex tables remain slower than the previous Pix2Text pipeline. Review scanned documents and complex tables against their source.

See [models and references](../../docs/help/recognition.md) for the current app configuration and measured limits. `model-provenance.json` records the selected checkpoint lineage; `notices/sources.json` records the retained upstream model cards and their hashes. The pinned BF16 checkpoint belongs to `mlx-community/GLM-OCR-bf16`, derived from Z.ai GLM-OCR.
