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
base = doc["schemes"]["WineVault"]
assert base["archive"]["config"] == "Release", "archive scheme must build Release for TestFlight"
app_settings = app["settings"]["base"]
assert app_settings.get("MARKETING_VERSION"), "MARKETING_VERSION required for release"
# Keep the release metadata draft in sync (WineVault/App/ReleaseInfo.swift).
import pathlib, re
release_info = pathlib.Path("WineVault/App/ReleaseInfo.swift")
if release_info.exists():
    version = re.search(
        r'static let version = "([^"]+)"', release_info.read_text()
    )
    assert version and version.group(1) == app_settings["MARKETING_VERSION"], (
        "ReleaseInfo.version must match MARKETING_VERSION"
    )
print("project.yml OK: iOS 26 app + unit/UI test targets + camera rationale + release scheme")
PY
