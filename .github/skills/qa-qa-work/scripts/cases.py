#!/usr/bin/env python3
"""cases.py — test case file tool (stdlib only, no pip installs).

  cases.py lint FILE.json                 errors exit 1, warnings exit 0
  cases.py export FILE.json --xlsx OUT    Excel workbook (one row per step)
  cases.py export FILE.json --csv OUT
  cases.py split FILE.json OUTDIR         one JSON per case (for zephyr.sh create-case)
  cases.py from-walkthrough STEPS.jsonl STORY OUT.json   draft case from a recorded run

File format: see ../reference/test-case-format.md
"""
import csv, json, re, sys, zipfile
from xml.sax.saxutils import escape

PRIORITIES = {"Critical", "High", "Normal", "Medium", "Low"}
VAGUE = re.compile(r"\b(works?|working|correct(ly)?|as expected|properly|fine|ok|successful(ly)?|appropriate)\b\.?$", re.I)
COLS = ["Case ID", "Story", "Title", "Objective", "Precondition", "Priority", "Type", "AC",
        "Step #", "Action", "Test Data", "Expected Result", "Actual Result", "Status", "Evidence", "App Version"]


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def lint(doc):
    errs, warns = [], []
    story = doc.get("story", "")
    if not re.match(r"^[A-Z][A-Z0-9_]+-\d+$", story or ""):
        errs.append("story: missing or not a Jira key")
    cases = doc.get("cases") or []
    if not cases:
        errs.append("no cases")
    names = set()
    covered = set()
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
        if not c.get("ac"):
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
            if not exp:
                errs.append(f"{tag} step {j}: no expected result")
            elif VAGUE.search(exp) and len(exp.split()) < 6:
                warns.append(f"{tag} step {j}: vague expected '{exp}' — state the observable outcome")
    missing = [a for a in doc.get("story_ac", []) if a not in covered]
    if missing:
        warns.append("acceptance criteria with no case: " + ", ".join(missing))
    return errs, warns


def rows(doc):
    for c in doc.get("cases", []):
        for j, s in enumerate(c.get("steps", []), 1):
            first = j == 1
            yield [c.get("id", "") if first else "", doc.get("story", "") if first else "",
                   c.get("name", "") if first else "", c.get("objective", "") if first else "",
                   c.get("precondition", "") if first else "", c.get("priority", "") if first else "",
                   c.get("type", "") if first else "", ", ".join(c.get("ac", [])) if first else "",
                   str(j), s.get("action", ""), s.get("data", ""), s.get("expected", ""),
                   s.get("actual", ""), s.get("status", ""), s.get("evidence", ""), s.get("version", "")]


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
    widths = [10, 12, 40, 30, 30, 10, 12, 10, 7, 45, 25, 45, 35, 10, 25, 14]
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
    if cmd == "from-walkthrough" and len(a) == 4:
        from_walkthrough(a[1], a[2], a[3]); return 0
    print(__doc__); return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
