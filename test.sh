#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p tests/build
xcrun clang++ -std=c++17 -fobjc-arc -fblocks -framework Foundation \
  -Wall -Wextra -Werror -fsanitize=address,undefined tests/server.mm -o tests/build/server-test
tests/build/server-test
