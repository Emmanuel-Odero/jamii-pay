"""Download static TTFs from Google Fonts (old UA => truetype URLs) into assets/fonts/."""
import os
import re
import urllib.request

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "fonts")
os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "Mozilla/4.0"}
FAMS = [
    ("Plus+Jakarta+Sans:wght@400;500;600;700;800", "PlusJakartaSans"),
    ("Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800", "BricolageGrotesque"),
    ("JetBrains+Mono:wght@400;500;700", "JetBrainsMono"),
]
NAMES = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold"}


def main() -> None:
    for fam_q, prefix in FAMS:
        url = "https://fonts.googleapis.com/css2?family=" + fam_q + "&display=swap"
        css = (
            urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30)
            .read()
            .decode()
        )
        blocks = re.findall(r"@font-face\s*{([^}]*)}", css)
        seen: dict[int, str] = {}
        for body in blocks:
            w = re.search(r"font-weight:\s*(\d+)", body)
            u = re.search(r"url\((https://[^)]+)\)", body)
            if w and u and int(w.group(1)) not in seen:
                seen[int(w.group(1))] = u.group(1)
        if not seen:
            raise SystemExit("no faces parsed for " + fam_q + "\n" + css[:500])
        for weight in sorted(seen):
            dest = os.path.join(OUT, prefix + "-" + NAMES[weight] + ".ttf")
            urllib.request.urlretrieve(seen[weight], dest)
            print(prefix + "-" + NAMES[weight] + ".ttf", os.path.getsize(dest), "bytes")


if __name__ == "__main__":
    main()
