#!/usr/bin/env bash
# Dev setup from a source checkout: creates a local venv with an editable install.
# End users: just `pipx install gmc-cli`.
set -euo pipefail
cd "$(dirname "$0")"

PY="$(command -v python3.13 || command -v python3.12 || command -v python3.11 || command -v python3)"
"$PY" -m venv .venv
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -e .
chmod +x gmc

echo "Done. Try: ./gmc auth login --client-id … --client-secret … --merchant-id …"
