#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p tests/build
flags=(-std=c++17 -fobjc-arc -fblocks -framework Foundation -Itests/stubs
  -Wall -Wextra -Werror "-fsanitize=${ASC_SANITIZERS:-address,undefined}")
xcrun clang++ "${flags[@]}" tests/server.mm -o tests/build/server-test
xcrun clang++ "${flags[@]}" tests/control.mm -o tests/build/control-test
tests/build/server-test
tests/build/server-test --hook-failure
python3 tests/cli.py tests/build/control-test
