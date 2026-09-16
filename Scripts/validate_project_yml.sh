#!/usr/bin/env bash
# Validates project.yml syntax without requiring xcodegen (Linux-safe).
# CI on any runner can catch malformed YAML before macOS jobs spend time.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 -c "import yaml" 2>/dev/null || pip3 install --quiet pyyaml

python3 - <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.exit("pyyaml missing")

with open("project.yml") as f:
    doc = yaml.safe_load(f)

assert doc["name"] == "WineVault", "project name must be WineVault"
assert doc["options"]["deploymentTarget"]["iOS"] == "26.0", "iOS 26 deployment target required"
app = doc["targets"]["WineVault"]
assert app["type"] == "application"
assert app["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"] == "com.infinityball.winevault"
assert "INFOPLIST_KEY_NSCameraUsageDescription" in app["settings"]["base"]
ui_tests = doc["targets"]["WineVaultUITests"]
assert ui_tests["type"] == "bundle.ui-testing"
assert {"WineVaultTests", "WineVaultUITests"}.issubset(
    set(doc["schemes"]["WineVault"]["test"]["targets"])
)
print("project.yml OK: iOS 26 app + unit/UI test targets + camera rationale")
PY
