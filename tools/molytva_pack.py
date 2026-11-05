#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Build a personal-use KOReader text pack from cached Molytva Tserkvy archives."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import date, timedelta
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import zipfile

VERSION = "1.0.1"
SOURCE_URL = "https://prayer-service.pp.ua"
PROJECT_URL = "https://github.com/yyyaniv/prayer-service.koplugin"
USER_AGENT = f"molytva-pack/{VERSION} (+{PROJECT_URL})"
LICENSE = "Тексти © «Молитва Церкви» (prayer-service.pp.ua), А. Мартинишин; для особистого некомерційного користування з дозволу автора; комерційне використання заборонено"
RANKS = {"#": "great", "*": "vigil", "+": "polyeleos", "@": "doxology", "&": "sixfold"}
SERVICES = {"u": ("ustav", "Устав"), "s": ("saints", "Святі дня"), "tv": ("vespers", "Вечірня"),
            "tu": ("matins", "Утреня"), "tc": ("hours", "Часи"), "tn": ("compline", "Повечір'я"),
            "o": ("midnight", "Опівнічна"), "p": ("word", "Слово на день"),
            "l": ("presanctified", "Передшеосвячена")}
RE_READING = re.compile(r"[–-]\s*(?:\d\s+)?([А-ЯҐЄІЇа-яґєії]+)\.\s*(?:зач\.\s*)?(\d+)")
BOOKS = {"Мт": "mt", "Мр": "mr", "Лк": "lk", "Йо": "iv", "Ів": "iv"}
TAGS = ("antifon1", "antifon2", "antifon3", "vhidne", "tropari", "trysviate", "prokimen",
        "apostol", "aleluia", "evanhelie", "dostoino", "prychasnii", "vidpust")
DEFAULT_TRYSVIATE = ('<h4>Трисвяте</h4><p><b>Святий Боже, святий кріпкий, святий безсмертний, помилуй нас</b> <i>(3)</i>.'
    '<p><b>Слава Отцю, і Сину, і Святому Духові, і нині, і повсякчас, і на віки віків. Амінь.</b>'
    '<p><b>Святий безсмертний, помилуй нас.</b>'
    '<p><b>Святий Боже, святий кріпкий, святий безсмертний, помилуй нас.</b>')
DEFAULT_DOSTOINO = ('<b>Достойно є воістину величати блаженною Тебе, Богородицю, '
    'присноблаженну і пренепорочну і Матір Бога нашого. Чеснішу від херувимів '
    'і незрівнянно славнішу від серафимів, що без зотління Бога Слово породила, '
    'сущу Богородицю, Тебе величаємо.</b>')


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
    def handle_data(self, data):
        self.parts.append(data)
    def text(self):
        return html.unescape("".join(self.parts)).replace("\xa0", " ").strip()


def plain(value):
    parser = PlainText()
    parser.feed(value)
    return parser.text()


def split_html_lines(value):
    return [plain(part) for part in re.split(r"<br\s*/?>", value, flags=re.I) if plain(part)]


def week_label(code):
    if code == "***":
        return None
    m = re.fullmatch(r"(\d{2})([edpms])", code)
    if not m:
        raise ValueError(f"Unknown week code: {code}")
    number, kind = int(m[1]), m[2]
    if kind == "m": return "М'ясопусний тиждень"
    if kind == "s": return "Сиропусний тиждень"
    return {"e": f"Тиждень {number}-й після Пасхи", "d": f"Тиждень {number}-й по Зісланні",
            "p": f"Тиждень {number}-й Великого посту"}[kind]


def parse_calendar_row(row):
    fields = row.lstrip("\ufeff").rstrip("\r\n").split("|", 9)
    if len(fields) != 10 or not re.fullmatch(r"\d{8}", fields[0]):
        raise ValueError("Malformed calendar row")
    saints = []
    for item in re.split(r"<br\s*/?>", fields[7], flags=re.I):
        title = plain(item)
        if not title or re.search(r"Тиждень .* по Зісланні", title):
            continue
        marker = title[:1]
        if marker in RANKS: title = title[1:].strip()
        saint = {"title": title}
        if marker in RANKS: saint["rank"] = RANKS[marker]
        saints.append(saint)
    tone_field = fields[9].replace("*", " ")
    tone = re.search(r"Гл\.\s*(\d+)", tone_field)
    gospel = re.search(r"Єв\.\s*(\d+)", tone_field)
    # Omit empty values: some Lua JSON decoders turn null into a non-nil sentinel.
    return fields[0], drop_none({"week": week_label(fields[1]), "weekday": int(fields[2]),
        "day_type": int(fields[3]), "period": int(fields[4]), "fast": int(fields[5]),
        "rank": RANKS.get(fields[6]), "saints": saints, "readings": split_html_lines(fields[8]),
        "tone": int(tone[1]) if tone else None, "matins_gospel": int(gospel[1]) if gospel else None})


def drop_none(value):
    return {key: item for key, item in value.items() if item is not None}


def reading_file(line):
    if not re.match(r"^(Ап|Єв)\.", line): return None
    match = RE_READING.search(line)
    if not match: return None
    prefix = "ap" if line.startswith("Ап.") else BOOKS.get(match[1])
    return f"{prefix}{int(match[2]):03d}.html" if prefix else None


def extract_tag(source, tag):
    match = re.search(r"<" + tag + r">(.*?)</" + tag + r">", source, re.S | re.I)
    return match[1].replace("\xa0", " ") if match else ""


def expand_zachala(value, zachala, warnings=None):
    """Replace #ap123-style references with the zachalo text; a missing file is dropped with a warning."""
    def replace(match):
        name = match[1] + ".html"
        if name not in zachala.namelist():
            if warnings is not None: warnings.append("missing zachalo " + name)
            return ""
        return zip_text(zachala, name)
    return re.sub(r"#((?:ap|mt|mr|lk|iv)\d{3}[a-z]?)", replace, value)


def assemble_liturgy(propers, templates, zachala, warnings=None):
    ustav = re.search(r"<ustav\b[^>]*\bliturgia=([a-z0-9_]+)\s*/>", propers, re.I)
    if not ustav: raise ValueError("No Liturgy template in bDD")
    template_name = ustav[1] + ".html"
    if template_name not in templates: raise ValueError("Missing Liturgy template: " + template_name)
    values = {tag: expand_zachala(extract_tag(propers, tag), zachala, warnings) for tag in TAGS}
    for tag in ("antifon1", "antifon2", "antifon3"):
        values[tag] = values[tag].replace("<b><i>", "<h4>").replace("</i></b>", "</h4>")
    values["vhidne"] = values["vhidne"].replace("<p>", " ")
    values["trysviate"] = values["trysviate"] or DEFAULT_TRYSVIATE
    values["dostoino"] = values["dostoino"] or DEFAULT_DOSTOINO
    for tag, stem in (("apostol", "ap"), ("evanhelie", "ev")):
        raw = values[tag]
        pos = raw.find("<p>", 5)
        values[stem + "_title"] = raw[:pos] if pos > 0 else ""
        values[stem + "_text"] = raw[pos:] if pos > 0 else raw
    output = templates[template_name]
    for key in (*TAGS, "ap_title", "ap_text", "ev_title", "ev_text"):
        output = output.replace("#" + key, values[key])
    remaining = re.findall(r"#[a-z_]+\d*", output)
    if remaining: raise ValueError("Unresolved Liturgy placeholder: " + ", ".join(sorted(set(remaining))))
    return output.replace("\xa0", " "), ustav[1]


def document(title, body, style="../../style.css"):
    return ('<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" lang="uk"><head>'
        '<meta charset="utf-8" /><title>' + html.escape(title) + '</title>'
        '<link rel="stylesheet" href="' + style + '" /></head><body>\n' + body + '\n</body></html>\n')


def eink_style(source):
    # Keep the source's layout, but remove declarations that rely on colour or backgrounds.
    source = re.sub(r"(?<![-\w])(?:background(?:-[\w-]+)?|color|border-color)\s*:[^;{}]+;?",
                    "", source, flags=re.I)
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return source.strip() + "\nbody { color: black; background: white; font-size: 1.1em; line-height: 1.35; }\nh1,h2,h3,h4 { font-weight: bold; }\ni,em,.rubric { font-style: italic; }\n"


def months_from(start, count):
    year, month = map(int, start.split("-"))
    if not 1 <= month <= 12 or count < 1: raise ValueError("Invalid month range")
    return [(year + (month - 1 + i) // 12, (month - 1 + i) % 12 + 1) for i in range(count)]


def refresh_archives(cache, paths, delay=120, opener=urlopen, sleep=time.sleep,
                     now=time.monotonic, today=date.today):
    meta_path = cache / "cache-meta.json"
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    checked = meta.setdefault("_checked", {})
    last_request = None
    for relative in paths:
        if (cache / relative).exists() and checked.get(relative) == today().isoformat():
            continue
        if last_request is not None:
            wait = delay - (now() - last_request)
            if wait > 0: sleep(wait)
        headers = {"User-Agent": USER_AGENT}
        if relative in meta: headers["If-Modified-Since"] = meta[relative]
        request = Request(SOURCE_URL + "/" + relative, headers=headers)
        last_request = now()
        try:
            response = opener(request)
            with response:
                if response.status == 304:
                    body, modified = None, None
                else:
                    body = response.read()
                    modified = response.headers.get("Last-Modified")
        except HTTPError as exc:
            if exc.code != 304: raise
            body, modified = None, None
        checked[relative] = today().isoformat()
        if body is None: continue
        dest = cache / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(body)
        if modified: meta[relative] = modified
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def zip_text(archive, name):
    return archive.read(name).decode("utf-8-sig", errors="replace")


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def write_html(path, title, body, archive=None, style="../../style.css"):
    path.parent.mkdir(parents=True, exist_ok=True)
    if archive:
        def replace_img(match):
            src = match[1]
            if not re.fullmatch(r"[\w.-]+\.(?:jpg|jpeg|png|gif)", src, re.I) or src not in archive.namelist(): return ""
            (path.parent / src).write_bytes(archive.read(src))
            return match[0]
        body = re.sub(r'<img\b[^>]*\bsrc=["\']([^"\']+)["\'][^>]*>', replace_img, body, flags=re.I)
    path.write_text(document(title, body, style), encoding="utf-8")


def build(cache, out, start, count, calendar="new-julian"):
    months = months_from(start, count)
    suffix = "n" if calendar == "gregorian" else ""
    paths = ["assets/txt/calendars.zip", "assets/txt/templates.zip", "zachala/zachala.zip", "benedict/benedict.zip"]
    paths += [f"assets/{year}{suffix}/{month:02d}/files.zip" for year, month in months]
    missing_archives = [path for path in paths if not (cache / path).exists()]
    if missing_archives: raise FileNotFoundError("Missing cached archives: " + ", ".join(missing_archives))
    # Remove only paths owned by this pack format, so a refresh cannot retain stale day files.
    for directory in ("calendar", "days", "services"):
        target = out / directory
        if target.exists(): shutil.rmtree(target)
    archives = {p: zipfile.ZipFile(cache / p) for p in paths}
    templates_zip = archives[paths[1]]
    templates = {name: zip_text(templates_zip, name) for name in templates_zip.namelist() if name.endswith(".html")}
    sample = Path(__file__).resolve().parents[1] / "molytva.koplugin/sample-pack"
    for name in ("fixed", "movable"):
        write_json(out / "calendar" / (name + ".json"), json.loads((sample / "calendar" / (name + ".json")).read_text()))
    years = {}
    calendar_zip = archives[paths[0]]
    for year in sorted({y for y, _ in months}):
        filename = f"calendar{year % 100:02d}{suffix}.txt"
        if filename not in calendar_zip.namelist(): raise FileNotFoundError("Missing calendar file: " + filename)
        entries = {}
        for row in zip_text(calendar_zip, filename).splitlines():
            if not row.strip(): continue
            key, value = parse_calendar_row(row)
            entries[key[4:6] + "-" + key[6:8]] = value
        years[year] = entries
        write_json(out / "calendar" / f"{year}.json", entries)
    zips = {"zachala": archives[paths[2]], "benedict": archives[paths[3]]}
    report = {"counts": Counter(), "missing": [], "warnings": [], "liturgy_templates": {}}
    index = {}
    for year, month in months:
        archive = archives[f"assets/{year}{suffix}/{month:02d}/files.zip"]
        names = set(archive.namelist())
        first = date(year, month, 1)
        next_month = date(year + (month == 12), month % 12 + 1, 1)
        current = first
        while current < next_month:
            day_key = current.isoformat()
            day = f"{current.day:02d}"
            available = []
            day_dir = out / "days" / day_key
            for prefix, (service, title) in SERVICES.items():
                filename = (prefix[0] + day + prefix[1:] if prefix.startswith("t") else prefix + day) + ".html"
                if filename not in names:
                    report["missing"].append(f"{day_key}:{service}")
                    continue
                write_html(day_dir / (service + ".html"), f"{title} — {day_key}", zip_text(archive, filename), archive)
                available.append(service)
                report["counts"][service] += 1
            bfile = "b" + day + ".html"
            if bfile in names:
                propers = zip_text(archive, bfile)
                day_warnings = []
                write_html(day_dir / "liturgy-propers.html", f"Змінні частини Літургії — {day_key}",
                           expand_zachala(propers, zips["zachala"], day_warnings), archive)
                available.append("liturgy-propers")
                report["counts"]["liturgy-propers"] += 1
                try:
                    body, template_name = assemble_liturgy(propers, templates, zips["zachala"], day_warnings)
                    write_html(day_dir / "liturgy.html", f"Літургія — {day_key}", body, archive)
                    report["liturgy_templates"][day_key] = template_name
                    available.append("liturgy")
                    report["counts"]["liturgy"] += 1
                except ValueError as exc: report["warnings"].append(f"{day_key}: {exc}")
                report["warnings"].extend(f"{day_key}: {w}" for w in sorted(set(day_warnings)))
            else: report["missing"].extend((f"{day_key}:liturgy", f"{day_key}:liturgy-propers"))
            lines = years[year].get(f"{month:02d}-{day}", {}).get("readings", []) if len(available) > 1 else []
            reading_parts = []
            for line in lines:
                name = reading_file(line)
                if not name: continue
                if name not in zips["zachala"].namelist():
                    report["warnings"].append(f"{day_key}: missing zachalo {name}")
                    continue
                reading_parts.append("<h2>" + html.escape(line) + "</h2>" + zip_text(zips["zachala"], name))
                if name in zips["benedict"].namelist():
                    reading_parts.append("<h3>Розважання владики Венедикта</h3>" + zip_text(zips["benedict"], name))
            if reading_parts:
                write_html(day_dir / "readings.html", f"Читання — {day_key}", "\n".join(reading_parts), zips["zachala"])
                available.append("readings")
                report["counts"]["readings"] += 1
            else: report["missing"].append(f"{day_key}:readings")
            index[day_key] = sorted(available)
            current += timedelta(days=1)
    write_json(out / "days/index.json", index)
    services = [{"id": "about-pack", "title": "Про пакет", "file": "services/about-pack.html"}]
    write_html(out / "services/about-pack.html", "Про пакет", "<h1>Молитва Церкви</h1><p>Пакет для особистого некомерційного користування. Комерційне використання текстів заборонено.</p>", style="../style.css")
    for name, title in (("liz", "Літургія Івана Золотоустого"), ("lvv", "Літургія Василія Великого")):
        generic = re.sub(r"#[a-z_]+\d*", "", templates[name + ".html"])
        write_html(out / "services" / (name + ".html"), title, generic, templates_zip, style="../style.css")
        services.append({"id": name, "title": title, "file": "services/" + name + ".html"})
    write_json(out / "services/index.json", services)
    (out / "style.css").write_text(eink_style(zip_text(templates_zip, "style.css")), encoding="utf-8")
    write_json(out / "pack.json", {"format": 2, "id": "molytva-cerkvy", "name": "Молитва Церкви", "version": VERSION,
        "calendar": calendar, "generated": date.today().isoformat(), "range": {"from": start, "to": f"{months[-1][0]}-{months[-1][1]:02d}"},
        "license": LICENSE, "source": SOURCE_URL})
    write_json(out / "build-report.json", report)
    for archive in archives.values(): archive.close()
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    command = parser.add_subparsers(dest="command", required=True)
    build_cmd = command.add_parser("build")
    for flag in ("cache", "out", "from"):
        build_cmd.add_argument("--" + flag, required=True)
    build_cmd.add_argument("--months", type=int, required=True)
    build_cmd.add_argument("--calendar", choices=("new-julian", "gregorian"), default="new-julian")
    build_cmd.add_argument("--download", action="store_true")
    build_cmd.add_argument("--delay", type=int, default=120)
    args = parser.parse_args(argv)
    cache, out = Path(args.cache), Path(args.out)
    if args.download:
        months = months_from(getattr(args, "from"), args.months)
        suffix = "n" if args.calendar == "gregorian" else ""
        paths = ["assets/txt/calendars.zip", "assets/txt/templates.zip", "zachala/zachala.zip", "benedict/benedict.zip"]
        paths += [f"assets/{y}{suffix}/{m:02d}/files.zip" for y, m in months]
        refresh_archives(cache, paths, delay=args.delay)
    try:
        report = build(cache, out, getattr(args, "from"), args.months, args.calendar)
    except (FileNotFoundError, ValueError, zipfile.BadZipFile) as exc:
        parser.exit(2, str(exc) + "\n")
    print(f"Built {len(report['counts'])} service types; {len(report['missing'])} missing items; {len(report['warnings'])} warnings at {out}")


if __name__ == "__main__":
    main()
