#!/bin/zsh
set -eu
source_directory="$(cd "$(dirname "$0")/.." && pwd)"
output_directory="${1:?Provide an absolute external output directory}"
case "$output_directory" in /*) ;; *) print -u2 "Use an absolute output directory."; exit 1 ;; esac
mkdir -p "$output_directory/module-cache"
sed '/^@MainActor extension Workbench/,$d' "$source_directory/Sources/Baker/FormulaHandoff.swift" > "$output_directory/handoff-checks.swift"
cat "$source_directory/Tests/FormulaHandoffChecks/main.swift" >> "$output_directory/handoff-checks.swift"
swift -module-cache-path "$output_directory/module-cache" "$output_directory/handoff-checks.swift"
