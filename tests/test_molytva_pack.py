"""Synthetic-only tests for the personal-use pack builder."""
from __future__ import annotations

from datetime import date
import hashlib
import importlib.util
import json
from pathlib import Path
from zipfile import ZipFile
from urllib.error import HTTPError

MODULE = Path(__file__).parents[1] / "tools/molytva_pack.py"
spec = importlib.util.spec_from_file_location("molytva_pack", MODULE)
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


def make_zip(path, files):
    path.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(path, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)


def row(day="20261104", week="23d", fast=0, rank="-", saints="* Свята<br>Тиждень 23-й по Зісланні"):
    return "|".join((day, week, "3", "0", "0", str(fast), rank, saints,
        "<i>Підзаголовок</i><br>Ап. – 1 Сол. 269 зач.; 4, 1-12.<br>Єв. – Йо. зач. 36; 10, 9-16.",
        "Гл. 5. Єв. 3"))


def fixture_cache(root):
    base = root / "assets"
    make_zip(base / "txt/calendars.zip", {"calendar26.txt": "\ufeff" + row() + "\r\n"})
    template = "<h1>Літургія</h1>" + "".join("<p>#" + key + "</p>" for key in (
        "antifon1", "antifon2", "antifon3", "vhidne", "tropari", "trysviate", "prokimen",
        "ap_title", "ap_text", "aleluia", "ev_title", "ev_text", "dostoino", "prychasnii", "vidpust"))
    make_zip(base / "txt/templates.zip", {"liz.html": template, "lvv.html": template,
        "style.css": "body { color: red; background: blue; margin: 1em; }"})
    make_zip(root / "zachala/zachala.zip", {"ap269.html": "<p>Апостол</p><p>Текст апостола</p>",
        "iv036.html": "<p>Євангеліє</p><p>Текст євангелія</p>"})
    make_zip(root / "benedict/benedict.zip", {"ap269.html": "<p>Розважання</p>"})
    make_zip(base / "2026/11/files.zip", {
        "u04.html": "<h1>Устав</h1><img src='icon.jpg'><img src='absent.jpg'>",
        "icon.jpg": b"fake image", "t05v.html": "<h1>Вечірня</h1>",
        "b04.html": "<ustav custom=n liturgia=liz /><apostol>#ap269</apostol>"
        "<evanhelie>#iv036</evanhelie><vhidne><p>Вхід</vhidne>"})
    return root


def test_calendar_decoding():
    labels = {"***": None, "02e": "Тиждень 2-й після Пасхи",
        "23d": "Тиждень 23-й по Зісланні", "03p": "Тиждень 3-й Великого посту",
        "00m": "М'ясопусний тиждень", "00s": "Сиропусний тиждень"}
    for code, expected in labels.items():
        assert pack.week_label(code) == expected
    for symbol, rank in pack.RANKS.items():
        key, data = pack.parse_calendar_row(row(rank=symbol, saints=symbol + " Свята"))
        assert key == "20261104" and data["rank"] == rank
        assert data["saints"] == [{"title": "Свята", "rank": rank}]
    for level in (0, 1, 2):
        _, data = pack.parse_calendar_row(row(fast=level))
        assert data["fast"] == level and data["weekday"] == 3
        assert data["tone"] == 5 and data["matins_gospel"] == 3
        assert data["readings"][0] == "Підзаголовок"
        assert len(data["saints"]) == 1


def test_reading_parser_and_liturgy_defaults(tmp_path):
    assert pack.reading_file("Ап. – 1 Сол. 269 зач.; 4, 1-12.") == "ap269.html"
    assert pack.reading_file("Єв. – Йо. зач. 36; 10, 9-16.") == "iv036.html"
    assert pack.reading_file("Підзаголовок") is None
    cache = fixture_cache(tmp_path / "cache")
    with ZipFile(cache / "zachala/zachala.zip") as readings:
        body, template = pack.assemble_liturgy(
            "<ustav custom=n liturgia=liz /><apostol>#ap269</apostol><evanhelie>#iv036</evanhelie>",
            {"liz.html": "#trysviate #dostoino #ap_title #ap_text #ev_title #ev_text"}, readings)
    assert template == "liz" and "Текст апостола" in body
    assert "Текст\xa0апостола" not in body and "Достойно є" in body
    assert "Святий Боже" in body and "#ap269" not in body


def tree_hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in root.rglob("*") if p.is_file()}


def test_synthetic_build_missing_files_images_and_determinism(tmp_path):
    cache = fixture_cache(tmp_path / "cache")
    out1, out2 = tmp_path / "out1", tmp_path / "out2"
    report = pack.build(cache, out1, "2026-11", 1)
    pack.build(cache, out2, "2026-11", 1)
    assert tree_hashes(out1) == tree_hashes(out2)
    assert report["liturgy_templates"]["2026-11-04"] == "liz"
    assert "2026-11-05:liturgy" in report["missing"]
    assert "2026-11-04:matins" in report["missing"]
    day = out1 / "days/2026-11-04"
    assert (day / "liturgy.html").exists()
    assert (day / "icon.jpg").read_bytes() == b"fake image"
    assert "absent.jpg" not in (day / "ustav.html").read_text()
    assert "charset=\"utf-8\"" in (day / "ustav.html").read_text()
    assert "../../style.css" in (day / "ustav.html").read_text()
    assert "background: blue" not in (out1 / "style.css").read_text()
    assert json.loads((out1 / "days/index.json").read_text())["2026-11-04"]
    (day / "stale.html").write_text("old")
    pack.build(cache, out1, "2026-11", 1)
    assert not (day / "stale.html").exists()
    assert tree_hashes(out1) == tree_hashes(out2)


def test_missing_archive_is_clear(tmp_path):
    try:
        pack.build(tmp_path / "missing", tmp_path / "out", "2026-11", 1)
    except FileNotFoundError as exc:
        assert "assets/txt/calendars.zip" in str(exc)
        assert "assets/2026/11/files.zip" in str(exc)
    else:
        assert False, "expected missing archive report"


class FakeResponse:
    status = 200
    headers = {"Last-Modified": "Wed, 04 Nov 2026 10:00:00 GMT"}
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self): return b"zip bytes"


def test_download_last_modified_and_delay(tmp_path):
    requests, sleeps = [], []
    def opener(request):
        requests.append(request)
        return FakeResponse()
    paths = ["assets/txt/calendars.zip", "assets/txt/templates.zip"]
    pack.refresh_archives(tmp_path, paths, delay=120, opener=opener,
        sleep=sleeps.append, now=lambda: 0, today=lambda: date(2026, 11, 4))
    assert sleeps == [120]
    assert all(r.get_header("User-agent") == pack.USER_AGENT for r in requests)
    meta = json.loads((tmp_path / "cache-meta.json").read_text())
    assert meta[paths[0]] == "Wed, 04 Nov 2026 10:00:00 GMT"
    requests.clear(); sleeps.clear()
    pack.refresh_archives(tmp_path, paths, delay=120, opener=opener,
        sleep=sleeps.append, now=lambda: 0, today=lambda: date(2026, 11, 5))
    assert requests[0].get_header("If-modified-since") == meta[paths[0]]
    assert sleeps == [120]
    requests.clear(); sleeps.clear()
    pack.refresh_archives(tmp_path, paths, delay=120, opener=opener,
        sleep=sleeps.append, now=lambda: 0, today=lambda: date(2026, 11, 5))
    assert not requests and not sleeps
    def unchanged(request):
        raise HTTPError(request.full_url, 304, "Not Modified", {}, None)
    pack.refresh_archives(tmp_path, [paths[0]], opener=unchanged, sleep=lambda _: None,
        today=lambda: date(2026, 11, 6))
    assert (tmp_path / paths[0]).read_bytes() == b"zip bytes"


def test_missing_zachalo_is_warned_not_fatal(tmp_path):
    cache = fixture_cache(tmp_path / "cache")
    warnings = []
    with ZipFile(cache / "zachala/zachala.zip") as readings:
        body, _ = pack.assemble_liturgy(
            "<ustav custom=n liturgia=liz /><apostol>#ap999</apostol><evanhelie>#iv036</evanhelie>",
            {"liz.html": "#ap_text #ev_text"}, readings, warnings)
    assert "Текст євангелія" in body and "#ap999" not in body
    assert warnings == ["missing zachalo ap999.html"]


def test_propers_have_expanded_readings(tmp_path):
    cache = fixture_cache(tmp_path / "cache")
    pack.build(cache, tmp_path / "out", "2026-11", 1)
    propers = (tmp_path / "out/days/2026-11-04/liturgy-propers.html").read_text(encoding="utf-8")
    assert "апостола</p>" in propers and "#ap269" not in propers


def test_calendar_entries_have_no_nulls():
    _, data = pack.parse_calendar_row(row(week="***", rank="-", saints="Без знака").replace("Гл. 5. Єв. 3", ""))
    assert "week" not in data and "rank" not in data and "tone" not in data and "matins_gospel" not in data
    assert data["saints"] == [{"title": "Без знака"}]
    assert None not in data.values()
