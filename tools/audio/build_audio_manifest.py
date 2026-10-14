#!/usr/bin/env python3
"""Build a deterministic metadata and checksum inventory for audio assets."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
AUDIO_ROOT = ROOT / "audio"
OUTPUT = AUDIO_ROOT / "AUDIO_MANIFEST.csv"

MUSIC_SOURCES = {
    "old_tower_inn_loop.ogg": "https://opengameart.org/content/medieval-the-old-tower-inn",
    "minstrel_dance_loop.ogg": "https://opengameart.org/content/medieval-minstrel-dance",
    "kings_feast_loop.ogg": "https://opengameart.org/content/medieval-kings-feast",
    "market_day_loop.ogg": "https://opengameart.org/content/medieval-market-day",
    "bards_tale_loop.ogg": "https://opengameart.org/content/medieval-the-bards-tale",
    "exploration.ogg": "https://opengameart.org/content/medieval-exploration",
    "battle.ogg": "https://opengameart.org/content/medieval-battle",
    "defeat.ogg": "https://opengameart.org/content/medieval-defeat-theme",
    "harvest_season.ogg": "https://opengameart.org/content/medieval-harvest-season",
    "victory.ogg": "https://opengameart.org/content/medieval-victory-theme",
}

AMBIENCE_SOURCES = {
    "market_medieval_crowd.ogg": "https://freesound.org/people/bolkmar/sounds/424790/",
    "market_busy_crowd.ogg": "https://freesound.org/people/ilmari_freesound/sounds/659634/",
    "tavern_chatter.ogg": "https://freesound.org/people/dazzamoo/sounds/651364/",
    "village_morning.ogg": "https://freesound.org/people/The_Sound_Side/sounds/331442/",
    "blacksmith_work.ogg": "https://freesound.org/people/LarsErikErtzgaardRingen/sounds/609757/",
    "fireplace_loop.ogg": "https://freesound.org/people/myLoop/sounds/852107/",
}


def checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def probe(path: Path) -> dict[str, str]:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "a:0",
            "-show_entries",
            "stream=codec_name,channels,sample_rate:format=duration",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)
    stream = payload["streams"][0]
    return {
        "codec": stream["codec_name"],
        "channels": str(stream["channels"]),
        "sample_rate": str(stream["sample_rate"]),
        "duration_seconds": f'{float(payload["format"]["duration"]):.3f}',
    }


def classify(path: Path) -> tuple[str, str, str]:
    relative = path.relative_to(AUDIO_ROOT)
    parts = relative.parts
    if parts[:2] == ("music", "randommind-medieval"):
        return "RandomMind Medieval", "music", MUSIC_SOURCES[path.name]
    if parts[:2] == ("ambience", "freesound-cc0"):
        return "Freesound CC0 Ambience", "ambience", AMBIENCE_SOURCES[path.name]
    if parts[:2] == ("sfx", "kenney-rpg"):
        return "Kenney RPG Audio", "sfx", "https://kenney.nl/assets/rpg-audio"
    if parts[:2] == ("sfx", "kenney-impact"):
        return "Kenney Impact Sounds", "sfx", "https://kenney.nl/assets/impact-sounds"
    if parts[:2] == ("sfx", "kenney-interface"):
        return "Kenney Interface Sounds", "sfx", "https://kenney.nl/assets/interface-sounds"
    raise ValueError(f"Unclassified audio file: {relative}")


def main() -> None:
    rows = []
    for path in sorted(AUDIO_ROOT.rglob("*.ogg")):
        collection, category, source = classify(path)
        metadata = probe(path)
        rows.append(
            {
                "path": path.relative_to(ROOT).as_posix(),
                "collection": collection,
                "category": category,
                "bytes": path.stat().st_size,
                **metadata,
                "sha256": checksum(path),
                "license": "CC0-1.0",
                "source": source,
            }
        )

    fieldnames = [
        "path",
        "collection",
        "category",
        "bytes",
        "duration_seconds",
        "channels",
        "sample_rate",
        "codec",
        "sha256",
        "license",
        "source",
    ]
    with OUTPUT.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} records to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
