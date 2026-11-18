#!/usr/bin/env python3
"""cases.py — test case file tool (stdlib only, no pip installs).

  cases.py lint FILE.json                 errors exit 1, warnings exit 0
  cases.py export FILE.json --xlsx OUT    Excel workbook (one row per step)
  cases.py export FILE.json --csv OUT
  cases.py split FILE.json OUTDIR         one JSON per case (for zephyr.sh create-case)
  cases.py from-walkthrough STEPS.jsonl STORY OUT.json   draft case from a recorded run
  cases.py import SHEET.xlsx|SHEET.csv OUT.json [--sheet NAME]   read the tester's own Excel/CSV
  cases.py list FILE.json                 id, priority, steps, name
  cases.py show FILE.json CASEID          one case, step by step
  cases.py results FILE.json RUNSDIR OUT.xlsx   new workbook with Actual/Status/Evidence/Version filled

File format: see ../reference/test-case-format.md
"""
import csv, glob, json, os, re, sys, zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

PRIORITIES = {"Critical", "High", "Normal", "Medium", "Low"}
VAGUE = re.compile(r"\b(works?|working|correct(ly)?|as expected|properly|fine|ok|successful(ly)?|appropriate)\b\.?$", re.I)
COLS = ["Case ID", "Story", "Title", "Objective", "Precondition", "Priority", "Type", "AC",
        "Step #", "Action", "Test Data", "Expected Result", "Actual Result", "Status", "Case Result", "Evidence", "App Version"]


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def lint(doc):
    errs, warns = [], []
    story = doc.get("story", "")
    if not re.match(r"^[A-Z][A-Z0-9_]+-\d+$", story or ""):
        if doc.get("source"):  # imported from the tester's sheet: Jira link is optional
            warns.append("story: no Jira key (sheet-only run; results go back to Excel, not Jira)")
        else:
            errs.append("story: missing or not a Jira key")
    cases = doc.get("cases") or []
    if not cases:
        errs.append("no cases")
    names = set()
    covered = set()
    sheet = bool(doc.get("source"))
    want_ac = bool(doc.get("story_ac")) or not sheet  # sheets rarely carry AC; don't nag per case
    no_exp = 0
    for i, c in enumerate(cases, 1):
        tag = f"case {i} ({c.get('id', '?')})"
        name = (c.get("name") or "").strip()
        if not name:
            errs.append(f"{tag}: no name")
        elif name.lower() in names:
            errs.append(f"{tag}: duplicate name '{name}'")
        names.add(name.lower())
        if len(name) > 120:
            warns.append(f"{tag}: name over 120 chars")
        if re.match(r"^\s*test\s+[A-Z]+-\d+", name, re.I):
            errs.append(f"{tag}: name looks like a ticket placeholder")
        if re.search(r"\b(and also|as well as|then also)\b", name, re.I):
            warns.append(f"{tag}: name reads like two scenarios — one scenario per case")
        if not c.get("precondition"):
            warns.append(f"{tag}: no precondition (user, role, data, environment)")
        if c.get("priority") and c["priority"] not in PRIORITIES:
            warns.append(f"{tag}: priority '{c['priority']}' not in {sorted(PRIORITIES)}")
        if not c.get("ac") and want_ac:
            warns.append(f"{tag}: not mapped to any acceptance criterion")
        covered.update(c.get("ac") or [])
        steps = c.get("steps") or []
        if not steps:
            errs.append(f"{tag}: no steps")
        if len(steps) > 15:
            warns.append(f"{tag}: {len(steps)} steps — consider splitting")
        for j, s in enumerate(steps, 1):
            if not (s.get("action") or "").strip():
                errs.append(f"{tag} step {j}: no action")
            exp = (s.get("expected") or "").strip()
            if not exp and j == len(steps):
                errs.append(f"{tag} step {j}: last step has no expected result")
            elif not exp and sheet:
                no_exp += 1
            elif not exp:
                warns.append(f"{tag} step {j}: no expected result (checked at a later step?)")
            elif VAGUE.search(exp) and len(exp.split()) < 6:
                warns.append(f"{tag} step {j}: vague expected '{exp}' — state the observable outcome")
    if no_exp:
        warns.append(f"{no_exp} intermediate step(s) have no expected result; the sheet checks at the last step. Fine for a hand-run; automation asserts only where the sheet says what to expect.")
    missing = [a for a in doc.get("story_ac", []) if a not in covered]
    if missing:
        warns.append("acceptance criteria with no case: " + ", ".join(missing))
    return errs, warns


def rows(doc):
    for c in doc.get("cases", []):
        for j, s in enumerate(c.get("steps", []), 1):
            first = j == 1
            yield [c.get("id", "") if first else "", (c.get("story") or doc.get("story", "")) if first else "",
                   c.get("name", "") if first else "", c.get("objective", "") if first else "",
                   c.get("precondition", "") if first else "", c.get("priority", "") if first else "",
                   c.get("type", "") if first else "", ", ".join(c.get("ac", [])) if first else "",
                   str(j), s.get("action", ""), s.get("data", ""), s.get("expected", ""),
                   s.get("actual", ""), s.get("status", ""), c.get("result", "") if first else "",
                   s.get("evidence", ""), s.get("version", "")]


def col(n):
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def write_xlsx(doc, out):
    def cell(r, c, v, style):
        return f'<c r="{col(c)}{r}" t="inlineStr" s="{style}"><is><t xml:space="preserve">{escape(str(v))}</t></is></c>'
    sheet_rows = ['<row r="1">' + "".join(cell(1, i + 1, h, 1) for i, h in enumerate(COLS)) + "</row>"]
    for r, row in enumerate(rows(doc), 2):
        sheet_rows.append(f'<row r="{r}">' + "".join(cell(r, i + 1, v, 2) for i, v in enumerate(row)) + "</row>")
    widths = [10, 12, 40, 30, 30, 10, 12, 10, 7, 45, 25, 45, 35, 10, 12, 25, 14]
    cols_xml = "".join(f'<col min="{i}" max="{i}" width="{w}" customWidth="1"/>' for i, w in enumerate(widths, 1))
    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    files = {
        "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
        "_rels/.rels": f'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="{rel}/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        "xl/workbook.xml": f'<?xml version="1.0" encoding="UTF-8"?><workbook {ns} xmlns:r="{rel}"><sheets><sheet name="Test Cases" sheetId="1" r:id="rId1"/></sheets></workbook>',
        "xl/_rels/workbook.xml.rels": f'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="{rel}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="{rel}/styles" Target="styles.xml"/></Relationships>',
        "xl/styles.xml": f'<?xml version="1.0" encoding="UTF-8"?><styleSheet {ns}><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
            '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/></patternFill></fill></fills>'
            '<borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="3"><xf/>'
            '<xf fontId="1" fillId="2" applyFont="1" applyFill="1"/><xf applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf></cellXfs></styleSheet>',
        "xl/worksheets/sheet1.xml": f'<?xml version="1.0" encoding="UTF-8"?><worksheet {ns}><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
            f'<cols>{cols_xml}</cols><sheetData>{"".join(sheet_rows)}</sheetData><autoFilter ref="A1:{col(len(COLS))}1"/></worksheet>',
    }
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)


def from_walkthrough(steps_path, story, out):
    steps = []
    with open(steps_path, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                s = json.loads(line)
                steps.append({"action": s.get("action", ""), "data": s.get("data", ""), "expected": s.get("expected", "")})
    doc = {"story": story, "story_ac": [], "cases": [{"id": "TC1", "name": f"DRAFT from walkthrough — rename", "objective": "",
           "precondition": "", "priority": "Normal", "type": "Functional", "ac": [], "steps": steps}]}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)
    print(f"Draft written: {out} ({len(steps)} steps). Rename, add precondition + AC mapping, then lint.")


# ---------- import from the tester's own sheet ----------

# Normalised header (lowercase, letters/digits only) -> field. First match per field wins.
ALIASES = {
    "id": ["testcaseid", "tcid", "caseid", "testid", "tcno", "testcaseno", "testcasenumber", "id", "scenariono", "scenarioid"],
    "story": ["userstory", "story", "ticketid", "ticket", "jiraid", "jira", "jirakey", "userstoryticketid", "requirementid", "reqid", "requirement"],
    "name": ["testcasetitle", "title", "testcasename", "testcase", "testcasedescription", "casedescription", "summary", "description"],
    "scenario": ["testscenario", "scenario", "scenarioname", "testscenarios"],
    "objective": ["objective", "purpose", "testobjective"],
    "precondition": ["precondition", "preconditions", "prerequisite", "prerequisites", "prereq", "setup"],
    "priority": ["priority"],
    "type": ["testtype", "type", "category"],
    "module": ["module", "feature", "area", "component", "screen", "page"],
    "ac": ["ac", "acceptancecriteria", "acref"],
    "step_no": ["stepno", "step", "stepnumber", "stepid"],
    "action": ["teststeps", "teststep", "steps", "action", "stepdetails", "stepdescription", "stepstoreproduce", "procedure", "testprocedure", "stepaction"],
    "data": ["testdata", "data", "inputdata", "input"],
    "expected": ["expectedresult", "expectedresults", "expected", "expectedoutput", "expectedoutcome"],
    "automation": ["automated", "automation", "automationstatus", "automatable", "automationcandidate"],
    "url": ["url", "pageurl", "link", "environment", "env"],
}


# Header typos seen in real sheets
TYPOS = {"discription": "description", "decription": "description", "precondtion": "precondition",
         "expexted": "expected", "expectd": "expected", "reslut": "result", "senario": "scenario"}


def norm(h):
    n = re.sub(r"[^a-z0-9]", "", str(h).lower())
    for bad, good in TYPOS.items():
        n = n.replace(bad, good)
    return n


def col_index(ref):
    n = 0
    for ch in re.match(r"[A-Z]+", ref).group(0):
        n = n * 26 + ord(ch) - 64
    return n - 1


def read_xlsx(path, sheet=None):
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
          "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        shared = []
        if "xl/sharedStrings.xml" in names:
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", ns):
                shared.append("".join(t.text or "" for t in si.iter("{%s}t" % ns["m"])))
        wb = ET.fromstring(z.read("xl/workbook.xml"))
        rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        target = {r.get("Id"): r.get("Target") for r in rels}
        sheets = [(s.get("name"), target[s.get("{%s}id" % ns["r"])]) for s in wb.find("m:sheets", ns)]
        if sheet:
            match = [x for x in sheets if x[0].lower() == sheet.lower()]
            if not match:
                raise SystemExit(f"sheet '{sheet}' not found. Sheets: {', '.join(n for n, _ in sheets)}")
            name, tgt = match[0]
        else:
            name, tgt = sheets[0]
        tgt = tgt.lstrip("/")
        tgt = tgt if tgt.startswith("xl/") else "xl/" + tgt
        root = ET.fromstring(z.read(tgt))
    table = []
    for row in root.iter("{%s}row" % ns["m"]):
        cells = {}
        for c in row.findall("m:c", ns):
            t, ref = c.get("t"), c.get("r")
            if t == "inlineStr":
                v = "".join(x.text or "" for x in c.iter("{%s}t" % ns["m"]))
            else:
                ve = c.find("m:v", ns)
                v = "" if ve is None else (ve.text or "")
                if t == "s" and v != "":
                    v = shared[int(v)]
                elif t is None and re.fullmatch(r"-?\d+\.0", v):
                    v = v[:-2]
            cells[col_index(ref)] = v
        width = max(cells) + 1 if cells else 0
        table.append([cells.get(i, "") for i in range(width)])
    return name, [sheet_name for sheet_name, _ in sheets], table


def read_table(path, sheet=None):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".xlsx", ".xlsm"):
        return read_xlsx(path, sheet)
    if ext == ".csv":
        with open(path, encoding="utf-8-sig", newline="") as f:
            return os.path.basename(path), [], [r for r in csv.reader(f)]
    raise SystemExit(f"{ext} not supported. Save the sheet as .xlsx or .csv (File > Save As) and try again.")


def map_header(table):
    best = (0, None, {})
    for i, row in enumerate(table[:15]):
        m = {}
        for j, h in enumerate(row):
            n = norm(h)
            for field, names in ALIASES.items():
                if field not in m and n in names:
                    m[field] = j
                    break
        if len(m) > best[0]:
            best = (len(m), i, m)
    if best[0] < 2 or "action" not in best[2] and "name" not in best[2]:
        raise SystemExit("could not find a header row (need at least a title/scenario or steps column)")
    return best[1], best[2]


PRIORITY_MAP = {"P1": "Critical", "P2": "High", "P3": "Normal", "P4": "Low", "BLOCKER": "Critical",
                "MAJOR": "High", "MINOR": "Low", "HIGHEST": "Critical", "LOWEST": "Low"}
NUMBERED = re.compile(r"^\s*(?:step\s*)?\d+\s*[.):-]\s*", re.I)


INLINE_NUM = re.compile(r"(?:^|\s)(\d{1,2})\s*[.)]\s*(?=\S)")


def split_inline(text):
    """'1.Click A   2.Click B 3.Check C' (one line, Excel-wrapped) -> lines, if numbers run 1,2,3..."""
    cuts, want = [], 1
    for mt in INLINE_NUM.finditer(text):
        if int(mt.group(1)) == want:
            cuts.append(mt.start(1)); want += 1
    if len(cuts) < 2:
        return None
    return [text[i:j].strip() for i, j in zip(cuts, cuts[1:] + [len(text)])]


def split_numbered(text):
    text = str(text).replace("\r", "")
    if "\n" not in text.strip():
        parts = split_inline(text.strip())
        if parts:
            text = "\n".join(parts)
    lines = [l for l in text.split("\n") if l.strip()]
    if len(lines) > 1 and sum(1 for l in lines if NUMBERED.match(l)) >= len(lines) / 2:
        out = []
        for l in lines:
            if NUMBERED.match(l) or not out:
                out.append(NUMBERED.sub("", l).strip())
            else:
                out[-1] += " " + l.strip()
        return out
    return [str(text).strip()] if str(text).strip() else []


def tidy(text):
    """Numbered text squashed onto one line -> '1. a; 2. b'. Long space runs -> single space."""
    parts = split_inline(text) if "\n" not in text else None
    text = "; ".join(parts) if parts else text
    return re.sub(r"[ \t]{2,}", " ", text).strip()


def import_sheet(path, out, sheet=None):
    sname, all_sheets, table = read_table(path, sheet)
    hdr, m = map_header(table)
    # "Step" column: numbers -> step number, text -> the step itself
    if "step_no" in m and "action" not in m:
        m["action"] = m.pop("step_no")
    # Scenario only (no per-case title) -> scenario is the title. Both -> scenario is a group carried down.
    if "scenario" in m and "name" not in m:
        m["name"] = m.pop("scenario")
    get = lambda r, f: (str(r[m[f]]).strip() if f in m and m[f] < len(r) and r[m[f]] is not None else "")
    # Key/value block above the header ("Project Name | RedBus", "Module | Login")
    meta = {}
    for r in table[:hdr]:
        cells = [str(x).strip() for x in r]
        for j, v in enumerate(cells[:-1]):
            if v and cells[j + 1] and norm(v) in ("projectname", "project", "module", "feature", "createdby", "application", "release"):
                meta[v] = cells[j + 1]
    sheet_module = next((v for k, v in meta.items() if norm(k) in ("module", "feature")), "")
    cases, cur, scenario = [], None, ""
    for ri, r in enumerate(table[hdr + 1:], start=hdr + 2):
        if not any(str(x).strip() for x in r):
            continue
        cid, name = get(r, "id"), get(r, "name")
        if get(r, "scenario"):
            scenario = get(r, "scenario")
        new = (cid and (cur is None or cid != cur["id"])) or (not cid and "id" not in m and name and (cur is None or name != cur["name"]))
        if new or cur is None:
            cur = {"id": cid or f"TC{len(cases) + 1}", "name": name, "objective": get(r, "objective"),
                   "precondition": tidy(get(r, "precondition")), "priority": get(r, "priority"), "type": get(r, "type"),
                   "scenario": scenario if "scenario" in m else "",
                   "labels": [x for x in [get(r, "module") or sheet_module, ("automated" if get(r, "automation").lower() in ("yes", "y", "automated", "done") else "")] if x],
                   "ac": [a.strip() for a in re.split(r"[,;\n]", get(r, "ac")) if a.strip()],
                   "story": get(r, "story"), "url": get(r, "url"), "steps": [], "source_rows": [ri, ri]}
            cases.append(cur)
        cur["source_rows"][1] = ri
        for f in ("name", "precondition", "priority", "objective", "story"):
            if not cur[f] and get(r, f):
                cur[f] = get(r, f)
        acts, exps, data = split_numbered(get(r, "action")), split_numbered(get(r, "expected")), get(r, "data")
        if not acts and exps:
            acts = ["(see title)"] * len(exps)
        for k, a in enumerate(acts):
            if len(exps) == len(acts):
                e = exps[k]
            else:
                e = " ".join(exps) if k == len(acts) - 1 else ""
            cur["steps"].append({"action": a, "data": data if k == 0 else "", "expected": e})
    for c in cases:
        if not c["name"]:
            c["name"] = c["steps"][0]["action"][:100] if c["steps"] else c["id"]
        if c["priority"]:
            key = c["priority"].strip()
            c["priority"] = PRIORITY_MAP.get(key.upper(), key.capitalize())
    stories = sorted({c["story"] for c in cases if re.match(r"^[A-Z][A-Z0-9_]+-\d+$", c["story"])})
    doc = {"story": stories[0] if len(stories) == 1 else "", "story_ac": [],
           "source": {"file": os.path.abspath(path), "sheet": sname, "sheets": all_sheets, "header_row": hdr + 1,
                      "columns": {f: table[hdr][j] for f, j in m.items()}, "meta": meta},
           "cases": cases}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
    print(f"Imported {len(cases)} case(s), {sum(len(c['steps']) for c in cases)} step(s) from '{sname}' -> {out}")
    print("Columns used: " + ", ".join(f"{f}='{str(table[hdr][j]).strip()}'" for f, j in m.items()))
    if meta:
        print("Sheet info: " + ", ".join(f"{k}={v}" for k, v in meta.items()))
    unused = [str(h).strip() for j, h in enumerate(table[hdr]) if str(h).strip() and j not in m.values()]
    if unused:
        print("Columns ignored: " + ", ".join(unused))
    if len(stories) > 1:
        print("Stories in sheet: " + ", ".join(stories))
    if all_sheets and len(all_sheets) > 1:
        print("Other sheets: " + ", ".join(x for x in all_sheets if x != sname) + "  (use --sheet NAME)")


def list_cases(doc):
    for c in doc.get("cases", []):
        auto = " [automated]" if "automated" in c.get("labels", []) else ""
        print(f"{c.get('id','')}\t{c.get('priority','') or '-'}\t{len(c.get('steps', []))} steps\t{c.get('name','')}{auto}")


def show_case(doc, cid):
    for c in doc.get("cases", []):
        if c.get("id") == cid:
            print(f"{c['id']}  {c.get('name','')}")
            for k in ("scenario", "story", "precondition", "priority", "url"):
                if c.get(k):
                    print(f"{k.capitalize()}: {c[k]}")
            for j, s in enumerate(c.get("steps", []), 1):
                print(f"{j}. {s.get('action','')}" + (f"\n   data: {s['data']}" if s.get("data") else "") +
                      (f"\n   expect: {s['expected']}" if s.get("expected") else ""))
            return 0
    print(f"no case '{cid}'"); return 1


def fill_results(doc, runs_dir):
    """Attach the latest hand-run per case (meta CASE == case id) to the doc."""
    latest = {}
    for meta in glob.glob(os.path.join(runs_dir, "*", "*", "meta.env")):
        d = os.path.dirname(meta)
        kv = dict(l.rstrip("\n").split("=", 1) for l in open(meta, encoding="utf-8") if "=" in l)
        cid = kv.get("CASE", "")
        if cid and (cid not in latest or os.path.basename(d) > os.path.basename(latest[cid][0])):
            latest[cid] = (d, kv)
    n = 0
    for c in doc.get("cases", []):
        if c.get("id") not in latest:
            continue
        d, kv = latest[c["id"]]
        steps = {}
        sp = os.path.join(d, "steps.jsonl")
        if os.path.exists(sp):
            for l in open(sp, encoding="utf-8"):
                if l.strip():
                    s = json.loads(l); steps[int(s.get("n", 0))] = s
        st = os.path.join(d, "status")
        c["result"] = open(st).read().strip().capitalize() if os.path.exists(st) else "In progress"
        for j, s in enumerate(c.get("steps", []), 1):
            r = steps.get(j)
            if r:
                s["actual"], s["status"] = r.get("actual", ""), r.get("status", "").capitalize()
                s["evidence"] = os.path.relpath(r["evidence"]) if r.get("evidence") else ""
            s["version"] = kv.get("VERSION", "")
        n += 1
    return n


def main(a):
    if len(a) < 2:
        print(__doc__); return 1
    cmd = a[0]
    if cmd == "lint":
        errs, warns = lint(load(a[1]))
        for e in errs: print("ERROR  ", e)
        for w in warns: print("WARN   ", w)
        print(f"{len(errs)} error(s), {len(warns)} warning(s)")
        return 1 if errs else 0
    if cmd == "export" and len(a) == 4:
        doc = load(a[1])
        if a[2] == "--xlsx":
            write_xlsx(doc, a[3])
        elif a[2] == "--csv":
            with open(a[3], "w", newline="", encoding="utf-8-sig") as f:
                w = csv.writer(f); w.writerow(COLS); w.writerows(rows(doc))
        else:
            print("use --xlsx or --csv"); return 1
        print(f"Wrote {a[3]}"); return 0
    if cmd == "split" and len(a) == 3:
        import os
        doc = load(a[1]); os.makedirs(a[2], exist_ok=True)
        for i, c in enumerate(doc["cases"], 1):
            p = os.path.join(a[2], f"{c.get('id') or 'TC' + str(i)}.json")
            with open(p, "w", encoding="utf-8") as f: json.dump(c, f, indent=2)
            print(p)
        return 0
    if cmd == "import" and len(a) >= 3:
        sheet = a[a.index("--sheet") + 1] if "--sheet" in a else None
        import_sheet(a[1], a[2], sheet); return 0
    if cmd == "list":
        list_cases(load(a[1])); return 0
    if cmd == "show" and len(a) == 3:
        return show_case(load(a[1]), a[2])
    if cmd == "results" and len(a) == 4:
        doc = load(a[1]); n = fill_results(doc, a[2]); write_xlsx(doc, a[3])
        print(f"Wrote {a[3]} with results for {n} of {len(doc.get('cases', []))} case(s). The original sheet was not changed.")
        return 0
    if cmd == "from-walkthrough" and len(a) == 4:
        from_walkthrough(a[1], a[2], a[3]); return 0
    print(__doc__); return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
