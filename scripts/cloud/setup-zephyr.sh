#!/usr/bin/env bash
# Compatibility entry point; use the same setup on local and cloud hosts.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
bash "$root/scripts/setup.sh"
