#!/usr/bin/env python3
"""Linux-safe consistency check between ReleaseInfo.swift and AppStoreMetadata.plist
(issue #7). Mirrors what ReleaseMetadataTests asserts on macOS runners, and runs
on any Linux CI job (no Swift toolchain required)."""
import plistlib, re, sys

with open("WineVault/AppStoreMetadata.plist", "rb") as f:
    plist = plistlib.load(f)
src = open("WineVault/App/ReleaseInfo.swift").read()


def join_literals(text):
    return "".join(
        s.replace('\\"', '"')
        for s in re.findall(r'"((?:[^"\\]|\\.)*)"', text)
    )


def literal_after(name):
    """Extract a (possibly multi-line, string-concatenated) literal assigned
    to `static let name` via a simple line scan."""
    lines = src.splitlines()
    out = []
    started = False
    for line in lines:
        if not started:
            if re.search(r"static let %s(\s*:\s*String)?\s*=" % re.escape(name), line):
                started = True
                rhs = line.split("=", 1)[1].strip()
                if rhs:
                    return join_literals(rhs)
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith(("///", "//")):
            break
        if "+" not in stripped and '"' not in stripped:
            break
        out.append(stripped)
    return join_literals(" ".join(out)) if out else None


errors = []

simple = {
    "Version": "version",
    "BundleID": "bundleID",
    "Name": "appTitle",
    "Subtitle": "subtitle",
    "PrimaryCategory": "primaryCategory",
    "SecondaryCategory": "secondaryCategory",
    "PrivacyDeclaration": "privacyDeclaration",
    "Keywords": "keywords",
}
for key, var in simple.items():
    v = literal_after(var)
    if v is None:
        errors.append(f"could not extract ReleaseInfo.{var}")
    elif v != plist[key]:
        errors.append(f"MISMATCH {key}: swift={v!r} plist={plist[key]!r}")

# description: assembled from releaseIntro + bullets
intro_m = re.search(
    r"releaseIntro =\s*\n((?:[ \t]*(?:\"(?:[^\"\\]|\\.)*\"|\+)[ \t]*\n?)+)", src
)
bullets_m = re.search(
    r"releaseBullets: \[String\] = \[(.*?)^\s*\]", src, re.S | re.M
)
if not intro_m or not bullets_m:
    errors.append("could not extract releaseIntro/releaseBullets")
else:
    intro = join_literals(intro_m.group(1))
    entries = re.findall(r'\n[ \t]+((?:"(?:[^"\\]|\\.)*"\s*\+?\s*\n?)+),', bullets_m.group(1))
    bullets = [join_literals(e) for e in entries]
    computed = intro + "\n\n" + "\n".join(bullets)
    if len(bullets) != 6:
        errors.append(f"expected 6 bullets, parsed {len(bullets)}")
    if computed != plist["Description"]:
        errors.append("Description mismatch")
        print("swift:", repr(computed))
        print("plist:", repr(plist["Description"]))

# screenshot plan
pat = re.compile(
    r'ScreenshotSlot\(\s*display:\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*\n?)+),\s*'
    r'pixelSize:\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*\n?)+),\s*'
    r'caption:\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*\n?)+)\s*\)'
)
slots = [tuple(join_literals(g) for g in m) for m in pat.findall(src)]
plan = plist["ScreenshotPlan"]
if len(slots) != len(plan):
    errors.append(f"plan count swift={len(slots)} plist={len(plan)}")
for (d, s, c), e in zip(slots, plan):
    if (d, s, c) != (e["Display"], e["PixelSize"], e["Caption"]):
        errors.append(f"plan mismatch: {(d, s, c)} vs {(e['Display'], e['PixelSize'], e['Caption'])}")

# marketing version pairing
mvs = re.findall(r'MARKETING_VERSION: "?([0-9.]+)"?', open("project.yml").read())
if mvs != [plist["Version"]]:
    errors.append(f"MARKETING_VERSION {mvs} vs metadata {plist['Version']}")

# store field limits
for k, lim in {"Name": 30, "Subtitle": 30, "Keywords": 100, "Description": 4000}.items():
    if len(plist[k]) > lim:
        errors.append(f"{k} exceeds {lim} ({len(plist[k])})")
for e in plan:
    if len(e["Caption"]) > 170:
        errors.append("caption exceeds 170")

# product-contract wording guards
d = plist["Description"].lower()
for banned in ["health", "healthy", "cardiovascular", "antioxidant", "moderation",
               "current price", "actual price", "guaranteed"]:
    if banned in d:
        errors.append(f"banned wording: {banned}")
for req in ["estimate", "offline", "no account", "no telemetry"]:
    if req not in d:
        errors.append(f"missing required phrase: {req}")

print("RELEASE METADATA CONSISTENCY:", "OK" if not errors else "FAILED",
      f"(description {len(plist['Description'])}/4000 chars, {len(plan)} screenshot slots)")
for e in errors:
    print(" -", e)
sys.exit(1 if errors else 0)
