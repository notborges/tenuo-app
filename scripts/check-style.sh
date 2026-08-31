#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")/.."

status=0

dash=$(printf '\xE2\x80\x94')
if rg -n "$dash" Tenuo TenuoTests docs scripts tools README.md MANUAL-TESTS.md; then
    echo "Remove em dashes from the files above."
    status=1
fi

if rg -n '\.system\(size: [0-9]|cornerRadius: [0-9]' Tenuo \
    -g '*.swift' -g '!Tenuo/UI/DesignSystem.swift'; then
    echo "Use a design-system token for the hard-coded size or radius above."
    status=1
fi

if rg -n '[[:blank:]]+$' Tenuo TenuoTests docs scripts tools README.md MANUAL-TESTS.md \
    -g '*' --hidden -g '!.git/**'; then
    echo "Remove trailing whitespace from the files above."
    status=1
fi

if [[ "$status" -eq 0 ]]; then
    echo "Style OK"
fi

exit "$status"
