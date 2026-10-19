#!/bin/bash
# Inventory a local reference application without executing or modifying it.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-/Applications/Tangerine.app}"
rea_cli="${REA_CLI:-}"
if [[ -z "$rea_cli" ]]; then
  if command -v rea >/dev/null 2>&1; then
    rea_cli="$(command -v rea)"
  elif [[ -x "$project_root/../.tools/rea/node_modules/.bin/rea" ]]; then
    rea_cli="$project_root/../.tools/rea/node_modules/.bin/rea"
  else
    cat >&2 <<'HELP'
REA CLI not found. Install the pinned CLI (requires Node.js/npm):
  npm install --prefix /private/tmp/prisme-rea rea-agents@6.7.0
Then run:
  REA_CLI=/private/tmp/prisme-rea/node_modules/.bin/rea ./scripts/analyze-reference.sh
This does not configure an MCP client or install a disassembler.
HELP
    exit 1
  fi
fi
if [[ ! -d "$target" || ! -f "$target/Contents/Info.plist" ]]; then
  echo "Expected a readable macOS application bundle: $target" >&2
  exit 1
fi
command -v python3 >/dev/null 2>&1 || {
  echo "Python 3 is required to save the small, whitelisted identity summary." >&2
  exit 1
}

mkdir -p "$project_root/.analysis"
output_dir="$(mktemp -d "$project_root/.analysis/reference-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
"$rea_cli" --version > "$output_dir/rea-version.txt"

# Both commands use REA's built-in static artifact parser. Neither runs the app.
"$rea_cli" inspect-artifact "$target" --format json > "$output_dir/artifact.json"
"$rea_cli" trace-dylib-resolution "$target" --format json > "$output_dir/dylibs.json"

python3 - "$target" "$output_dir" <<'PY'
import hashlib
import json
from pathlib import Path
import plistlib
import sys

target, output = map(Path, sys.argv[1:])
plist_bytes = (target / "Contents/Info.plist").read_bytes()
info = plistlib.loads(plist_bytes)
keys = ("CFBundleName", "CFBundleIdentifier", "CFBundleExecutable",
        "CFBundleShortVersionString", "CFBundleVersion",
        "LSMinimumSystemVersion", "LSUIElement")
identity = {key: info.get(key) for key in keys}
identity["info_plist_sha256"] = hashlib.sha256(plist_bytes).hexdigest()
identity["observation_type"] = "direct-static-plist-read; not REA Evidence"
(output / "identity.json").write_text(json.dumps(identity, indent=2) + "\n")
for filename in ("artifact.json", "dylibs.json"):
    evidence = json.loads((output / filename).read_text())
    if "evidence_id" not in evidence:
        raise SystemExit(f"REA did not return Evidence in {filename}; inspect its error envelope.")
    print(f"{filename}: {evidence['evidence_id']}")
print(f"Local analysis saved to {output}")
PY

# Native tools are optional: some sandboxed hosts cannot compile REA's process
# ownership helper. Preserve their error envelopes instead of claiming success.
if [[ "${REA_NATIVE:-0}" == 1 ]]; then
  for operation in inspect-macho inspect-plist; do
    if ! "$rea_cli" "$operation" "$target" --format json > "$output_dir/$operation.json"; then
      echo "Optional $operation failed; inspect $output_dir/$operation.json" >&2
    fi
  done
fi
