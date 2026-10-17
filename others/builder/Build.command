#!/bin/zsh
set -u
builder_dir="${0:A:h}"
workspace_dir="${builder_dir:h:h:h:h:h}"
chip="$(/usr/sbin/system_profiler SPHardwareDataType)"
case "$chip" in
    *"Apple M1 Pro"*) builder_host=m1pro ;;
    *"Apple M5"*) builder_host=m5 ;;
    *) print -u2 "This Mac has no configured Baker build environment."; exit 1 ;;
esac
builder_python="$workspace_dir/Agents/Environment/$builder_host/bin/python"
if [[ ! -x "$builder_python" ]]; then
    print -u2 "The prepared build environment is missing: $builder_python"
    exit 1
fi
builder_logs="$workspace_dir/Agents/Repository/baker/builder/logs"
mkdir -p "$builder_logs"
builder_log="$builder_logs/$(date +%Y-%m-%d_%H-%M-%S)-$$.log"
"$builder_python" "$builder_dir/build.py" "$@" 2>&1 | /usr/bin/tee "$builder_log"
builder_result=${pipestatus[1]}
print "Log: $builder_log"
if [[ -t 0 ]]; then
    print ""
    read -k 1 "?Press any key to close…"
fi
exit "$builder_result"
