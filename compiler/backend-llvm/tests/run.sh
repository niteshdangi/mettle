#!/bin/sh
set -eu

mettle=${METTLE:?set METTLE to the bootstrap compiler executable}
llvm=${LLVM_BIN:?set LLVM_BIN to the pinned LLVM bin directory}
profile=${1:?pass debug or release}
fixture=compiler/backend-llvm/tests
work=$(mktemp -d)
trap 'rm -f "$work/emitter" "$work/program.ll" "$work/program.bc" "$work/program"; rmdir "$work"' EXIT

"$mettle" test "$fixture" --library-dir library --cc "$llvm/clang++" --profile "$profile" --locked
"$mettle" build "$fixture" --library-dir library --cc "$llvm/clang++" --profile "$profile" --locked -o "$work/emitter"
"$work/emitter" > "$work/program.ll"
"$llvm/llvm-as" "$work/program.ll" -o "$work/program.bc"
"$llvm/clang" -Wno-override-module -O2 "$work/program.bc" -o "$work/program"
status=0
"$work/program" || status=$?
if [ "$status" -ne 42 ]; then
    printf 'Cross-module LLVM executable exited %s, expected 42\n' "$status" >&2
    exit 1
fi
