#!/bin/zsh
set -eu
source_directory="$(cd "$(dirname "$0")/.." && pwd)"
output_directory="${1:?Provide an absolute external output directory}"
case "$output_directory" in /*) ;; *) exit 1 ;; esac
mkdir -p "$output_directory/module-cache"
sed '/^    static func run(arguments:/,$d' "$source_directory/Sources/Baker/FormulaAdapter.swift" > "$output_directory/adapter-checks.swift"
print '}' >> "$output_directory/adapter-checks.swift"
cat "$source_directory/Tests/AdapterChecks/main.swift" >> "$output_directory/adapter-checks.swift"
swift -module-cache-path "$output_directory/module-cache" "$output_directory/adapter-checks.swift" "$output_directory"
