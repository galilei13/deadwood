#!/bin/bash
# Compatibility wrapper for the original command documented in the README.
# Fixtures now use unique temporary directories and are cleaned up by XCTest.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test
