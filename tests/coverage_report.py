# -*- coding: utf-8 -*-
"""
Created on Wed Dec 31 08:57:33 2025

@author: shane
"""

import os
import textwrap
import xml.etree.ElementTree as E

xml_file = os.environ.get("XML_FILE")
patt = os.environ.get("PATT")

tree = E.parse(xml_file)
missed = []
total_lines = 0
missed_lines = 0

for c in tree.findall(".//class"):
    if patt in c.get("filename", ""):
        for line in c.findall(".//line"):
            total_lines += 1
            if line.get("hits") == "0":
                missed.append(line.get("number"))
                missed_lines += 1

if total_lines > 0:
    COVERED = total_lines - missed_lines
    pct = (COVERED / total_lines) * 100
    COLOR = "\033[32;1m" if pct > 80 else "\033[33;1m" if pct > 50 else "\033[31;1m"
    print(f"{COLOR}Coverage: {pct:.1f}% ({COVERED}/{total_lines})\033[0m")
else:
    print(f"Coverage: N/A (0 lines found for {patt})")

if missed:
    print(f"\033[31;1m{len(missed)} missing lines\033[0m in {patt}:")
    print(
        textwrap.fill(
            ", ".join(missed), width=72, initial_indent="  ", subsequent_indent="  "
        )
    )
