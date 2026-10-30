"""Generiše PDF bilješke iz HTML izvora pomoću Edge/Chrome (headless).

Upotreba:  python docs/src/build.py         (iz korijena repozitorija)
Izlaz:     docs/RuO - Lesson2.pdf, Lesson3.pdf, Lesson4.pdf
"""
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

SRC = Path(__file__).resolve().parent
OUT = SRC.parent
CANDIDATES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    "google-chrome", "chromium", "chromium-browser", "microsoft-edge",
]
browser = next((c for c in CANDIDATES if os.path.exists(c) or shutil.which(c)), None)
if not browser:
    sys.exit("Nije pronađen Edge/Chrome/Chromium.")


def style_comments(src: str) -> str:
    """Komentari (# ...) u blokovima koda dobivaju drugu boju."""
    def pre(m):
        body = re.sub(r'(^|\s)(#\s[^\n]*)$', lambda k: k.group(1) + '<span class="c">' + k.group(2) + '</span>',
                      m.group(2), flags=re.M)
        return m.group(1) + body + '</pre>'
    return re.sub(r'(<div class="code[^"]*">.*?<pre>)(.*?)</pre>', pre, src, flags=re.S)


for n in (2, 3, 4):
    tmp = SRC / f"_build{n}.html"
    tmp.write_text(style_comments((SRC / f"sedmica{n}.html").read_text(encoding="utf-8")), encoding="utf-8")
    out = OUT / f"RuO - Lesson{n}.pdf"
    out.unlink(missing_ok=True)
    profile = SRC / "_profile"
    subprocess.run([browser, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                    f"--user-data-dir={profile}", f"--print-to-pdf={out}", tmp.as_uri()], check=True)
    # novi headless način vraća kontrolu prije nego što je PDF zapisan: čekati da veličina postane stabilna
    last, stable = -1, 0
    for _ in range(120):
        size = out.stat().st_size if out.exists() else -1
        stable = stable + 1 if size > 0 and size == last else 0
        if stable >= 3:
            break
        last = size
        time.sleep(0.5)
    shutil.rmtree(profile, ignore_errors=True)
    if not out.exists():
        sys.exit(f"PDF nije napravljen: {out}")
    tmp.unlink()
    print("built", out)
