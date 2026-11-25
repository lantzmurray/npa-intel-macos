#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
venv=${1:-"$root/.venv"}
npa="$venv/bin/npa"
python="$venv/bin/python"
work=$(mktemp -d "${TMPDIR:-/tmp}/npa-smoke.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 1' HUP INT TERM

cat > "$work/workflow.yaml" <<'YAML'
apiVersion: npa.workflow/v0.0.1
kind: Workflow
metadata:
  name: intel-macos-smoke
config:
  text: "smoke-{{run.id}}"
initial: check
states:
  check:
    run:
      argv: [echo, "{{config.text}}"]
    terminal: true
YAML
"$npa" workbench workflow validate-spec "$work/workflow.yaml" --json > "$work/validation.json"
"$npa" workbench workflow plan-spec "$work/workflow.yaml" --run-id intel-test --json > "$work/plan.json"
sed 's/^initial: check$/initial: missing/' "$work/workflow.yaml" > "$work/invalid.yaml"
if "$npa" workbench workflow validate-spec "$work/invalid.yaml" > "$work/invalid.log" 2>&1; then
    printf '%s\n' 'Invalid workflow unexpectedly passed.' >&2
    exit 1
fi

"$python" - "$work" <<'PY'
import json
import sys
from pathlib import Path

import cryptography
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.backends.openssl.backend import backend
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

work = Path(sys.argv[1])
validation = json.loads((work / "validation.json").read_text())
plan = json.loads((work / "plan.json").read_text())
assert validation["status"] == "valid"
assert plan["steps"][0]["argv"] == ["echo", "smoke-intel-test"]
assert cryptography.__version__ == "50.0.2"
assert "OpenSSL 3.5.9" in backend.openssl_version_text()
key = Ed25519PrivateKey.generate()
signature = key.sign(b"npa-intel-macos")
key.public_key().verify(signature, b"npa-intel-macos")
try:
    key.public_key().verify(signature, b"modified")
except InvalidSignature:
    pass
else:
    raise AssertionError("Modified message unexpectedly passed verification")
print("Passed: workflow validation, invalid-spec rejection, dry-run expansion, and Ed25519 checks.")
PY
