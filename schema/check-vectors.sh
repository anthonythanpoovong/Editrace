#!/usr/bin/env bash
# Runs a small reference implementation against schema/test-vectors/ so the fixtures can't drift
# from ADR 0002. Adapters and readers in other languages must reproduce the same results.
# Needs python3 (stdlib only, integer arithmetic only for time).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 -I - <<'PY'
import json, re, sys

fail = 0
def check(name, ok, detail=""):
    global fail
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  " + detail))
    if not ok:
        fail = 1

def load(name):
    return json.load(open(f"schema/test-vectors/{name}.json"))

# ---- rescale -----------------------------------------------------------------------------
def rescale(f, ts, tt):
    # round(f * (num_t/den_t) / (num_s/den_s)), halves up, integers only
    ns, ds, nt, dt = ts["num"], ts["den"], tt["num"], tt["den"]
    return (2 * f * nt * ds + ns * dt) // (2 * ns * dt)

for c in load("rescale")["cases"]:
    ts, tt = c["template_fps"], c["target_fps"]
    if c["type"] == "boundaries":
        got = [c["offset"] + rescale(f, ts, tt) for f in c["input"]]
    elif c["type"] == "ranges":
        got = []
        for r in c["input"]:
            a = rescale(r["start"], ts, tt)
            b = rescale(r["start"] + r["duration"], ts, tt)
            approx = False
            if b - a < 1:
                b, approx = a + 1, True
            got.append({"start": c["offset"] + a, "duration": b - a, "approximated": approx})
    elif c["type"] == "keyframes":
        got = [rescale(k["slot_start"] + k["frame"], ts, tt) - rescale(k["slot_start"], ts, tt)
               for k in c["input"]]
    else:
        check("rescale: " + c["name"], False, "unknown case type " + c["type"]); continue
    check("rescale: " + c["name"], got == c["expected"], f"got {got}, expected {c['expected']}")

# ---- timecode ----------------------------------------------------------------------------
def timecode(n, fps, drop):
    nominal = round(fps["num"] / fps["den"])
    if drop:
        if nominal not in (30, 60):
            raise ValueError("drop-frame exists only at 29.97 and 59.94")
        d = nominal // 15                       # labels skipped per minute: 2 or 4
        per_min, per_10 = nominal * 60 - d, nominal * 600 - d * 9
        blocks, m = divmod(n, per_10)
        n += d * 9 * blocks + (d * ((m - d) // per_min) if m >= d else 0)
    ff, ss = n % nominal, (n // nominal) % 60
    mm, hh = (n // (nominal * 60)) % 60, n // (nominal * 3600)
    return f"{hh:02}:{mm:02}:{ss:02}{';' if drop else ':'}{ff:02}"

for c in load("timecode")["cases"]:
    got = timecode(c["frame"], c["fps"], c["drop_frame"])
    check("timecode: " + c["name"], got == c["timecode"], f"got {got}, expected {c['timecode']}")

# ---- versions ----------------------------------------------------------------------------
def read_version(reader, migrations, doc):
    sem = lambda v: tuple(int(x) for x in v.split("."))
    (rmaj, _, _), (dmaj, _, _) = sem(reader), sem(doc)
    if dmaj > rmaj:
        return "reject", f"template is {doc}, reader supports {reader}"
    if dmaj < rmaj:
        return ("accept_via_migration", "") if dmaj in migrations else \
               ("reject", f"template is {doc}, reader is {reader} and has no migration")
    return "accept", ""

for c in load("versions")["cases"]:
    outcome, msg = read_version(c["reader"], c["migrations"], c["document"])
    ok = outcome == c["expected"] and all(v in msg for v in c.get("error_mentions", []))
    check("version: " + c["name"], ok, f"got {outcome} {msg!r}")

# ---- forward compatibility fixture -------------------------------------------------------
fc = load("forward-compat")
doc, exp = fc["document"], fc["expected"]
ids = set()
def collect(node):
    if isinstance(node, dict):
        if "id" in node: ids.add(node["id"])
        for v in node.values(): collect(v)
    elif isinstance(node, list):
        for v in node: collect(v)
collect(doc)
mentioned = set(exp["applied"]) | set(exp["skipped"])
check("forward-compat: every applied/skipped id exists in the document", mentioned <= ids, str(mentioned - ids))
check("forward-compat: applied and skipped do not overlap", not (set(exp["applied"]) & set(exp["skipped"])))
check("forward-compat: schema_version is a newer minor of the reader's major",
      re.match(r"^0\.[2-9]", doc["schema_version"]) is not None and fc["reader"].startswith("0."))
slots = {s["id"]: s for t in doc["tracks"] for s in t.get("slots", [])}
check("forward-compat: the preserved unknown field is really in the document",
      all(slots[p["id"]].get(p["field"]) == p["value"] for p in exp["preserved_unknown_fields"]))

sys.exit(fail)
PY
