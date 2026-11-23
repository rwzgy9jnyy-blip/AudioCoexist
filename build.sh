#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${THEOS:-}" || ! -f "$THEOS/makefiles/common.mk" ]]; then
  printf '%s\n' 'Set THEOS to a RootHide-compatible Theos checkout before building.' >&2
  exit 1
fi
export THEOS
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export PATH="$THEOS/bin:$PATH"

# Clean separately: entitlement changes must re-sign the helper executable.
make clean
make package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
