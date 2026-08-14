#!/usr/bin/env bash
# Validate a runtime manifest. Always performs structural checks with jq;
# additionally runs a full JSON Schema validation when the python3
# jsonschema module is available (as it is on CI runners).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${SCRIPT_DIR}/lib.sh"

need jq

manifest="${1:-}"
[[ -n "${manifest}" && -f "${manifest}" ]] || die "usage: validate-manifest.sh <manifest.json>"
schema="${REPO_ROOT}/runtime-manifest.schema.json"

jq -e '
  .schema_version == 1
  and (.postgres_version | type == "string" and test("^[0-9]+\\.[0-9]+$"))
  and (.runtime_revision | type == "number")
  and (.runtime_version | type == "string")
  and (.platform | test("^(linux|darwin)-(amd64|arm64)$"))
  and (.source.filename | type == "string")
  and (.source.sha256 | test("^[0-9a-f]{64}$"))
  and (.runtime.build_commit | type == "string")
  and (.runtime.built_at | type == "string")
  and (.configure_options | type == "array")
  and (.extensions | type == "array" and length >= 1 and all(.[]; (.name | type == "string") and (.required | type == "boolean")))
  and (.tools | type == "array" and (index("postgres") != null) and (index("initdb") != null) and (index("pg_ctl") != null))
' "${manifest}" >/dev/null || die "manifest failed structural validation: ${manifest}"

if python3 -c 'import jsonschema' >/dev/null 2>&1; then
  python3 - "${schema}" "${manifest}" <<'PY'
import json, sys
import jsonschema
with open(sys.argv[1]) as f:
    schema = json.load(f)
with open(sys.argv[2]) as f:
    doc = json.load(f)
jsonschema.validate(doc, schema)
PY
  log "manifest OK (structural + JSON Schema): ${manifest}"
else
  log "manifest OK (structural; python3-jsonschema not available for full schema validation): ${manifest}"
fi
