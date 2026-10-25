#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
# The domain must never acquire calendar write, UI, microphone or network authority.
if rg '^(@[^ ]+ )?import ' Sources/CalendarDomain | rg -v ':import (Foundation|CryptoKit|SessionDomain)$'; then
    print -u2 'CalendarDomain has an unexpected framework dependency.'
    exit 1
fi
for source in Sources/CalendarDomain/*.swift Sources/MemoryCalendarApp/*.swift; do
    lines=$(wc -l < "$source")
    if (( lines > 250 )); then
        print -u2 "Split responsibility before extending: $source ($lines lines)"
        exit 1
    fi
done
if rg 'store\.save|requestWriteOnlyAccess' Sources/MemoryCalendarApp/MemoryCalendarApp.swift Sources/MemoryCalendarApp/ProposalCard.swift; then
    print -u2 'Views must not call EventKit directly.'
    exit 1
fi
print 'Calendar boundaries passed.'
