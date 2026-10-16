#!/usr/bin/env python3
"""Build the asset inventory and validate every GLB container."""

from __future__ import annotations

import csv
import hashlib
import json
import struct
from pathlib import Path


ASSET_ROOT = Path(__file__).resolve().parents[1]

COLLECTIONS = {
    "blocky-characters": {
        "source": "https://kenney.nl/assets/blocky-characters",
        "license": "licenses/kenney-blocky-characters-CC0.txt",
        "preview_root": "previews/blocky-characters",
    },
    "castle-kit": {
        "source": "https://kenney.nl/assets/castle-kit",
        "license": "licenses/kenney-castle-kit-CC0.txt",
        "preview_root": "previews/castle-kit",
    },
    "fantasy-town-kit": {
        "source": "https://kenney.nl/assets/fantasy-town-kit",
        "license": "licenses/kenney-fantasy-town-kit-CC0.txt",
        "preview_root": "previews/fantasy-town-kit",
    },
    "quaternius-medieval-village-standard": {
        "source": "https://quaternius.com/packs/medievalvillagemegakit.html",
        "license": "environments/quaternius-medieval-village-standard/LICENSE.txt",
        "preview_root": "environments/quaternius-medieval-village-standard/previews",
    },
    "quaternius-stylized-nature-standard": {
        "source": "https://quaternius.com/packs/stylizednaturemegakit.html",
        "license": "environments/quaternius-stylized-nature-standard/LICENSE.txt",
        "preview_root": "environments/quaternius-stylized-nature-standard/previews",
    },
    "quaternius-fantasy-props-standard": {
        "source": "https://quaternius.com/packs/fantasypropsmegakit.html",
        "license": "props/quaternius-fantasy-props-standard/LICENSE.txt",
        "preview_root": "props/quaternius-fantasy-props-standard/previews",
    },
    "option-01-kaykit-adventurers": {
        "source": "https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0",
        "license": "alternatives/option-01-kaykit-adventurers/LICENSE.txt",
        "preview_root": "alternatives/option-01-kaykit-adventurers/previews",
    },
    "option-02-kaykit-skeletons": {
        "source": "https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0",
        "license": "alternatives/option-02-kaykit-skeletons/LICENSE.txt",
        "preview_root": "alternatives/option-02-kaykit-skeletons/previews",
    },
    "option-03-kenney-graveyard": {
        "source": "https://kenney.nl/assets/graveyard-kit",
        "license": "alternatives/option-03-kenney-graveyard/LICENSE.txt",
        "preview_root": "alternatives/option-03-kenney-graveyard/previews",
    },
    "option-04-kenney-platformer": {
        "source": "https://kenney.nl/assets/platformer-kit",
        "license": "alternatives/option-04-kenney-platformer/LICENSE.txt",
        "preview_root": "alternatives/option-04-kenney-platformer/previews",
    },
    "option-05-kenney-mini-characters": {
        "source": "https://kenney.nl/assets/mini-characters",
        "license": "alternatives/option-05-kenney-mini-characters/LICENSE.txt",
        "preview_root": "alternatives/option-05-kenney-mini-characters/previews",
    },
    "option-03-kaykit-dungeon": {
        "source": "https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0",
        "license": "alternatives/option-03-kaykit-dungeon/LICENSE.txt",
        "preview_root": "alternatives/option-03-kaykit-dungeon/previews",
    },
    "option-04-kaykit-medieval-hexagon": {
        "source": "https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0",
        "license": "alternatives/option-04-kaykit-medieval-hexagon/LICENSE.txt",
        "preview_root": "alternatives/option-04-kaykit-medieval-hexagon/previews",
    },
    "option-05-kaykit-halloween": {
        "source": "https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0",
        "license": "alternatives/option-05-kaykit-halloween/LICENSE.txt",
        "preview_root": "alternatives/option-05-kaykit-halloween/previews",
    },
    "quaternius-universal-base-standard": {
        "source": "https://quaternius.com/packs/universalbasecharacters.html",
        "license": "character-tests/quaternius-universal-base-standard/LICENSE.txt",
        "preview_root": "character-tests/quaternius-universal-base-standard/previews",
    },
    "quaternius-universal-animation-library-1": {
        "source": "https://quaternius.com/packs/universalanimationlibrary.html",
        "license": "animations/quaternius-universal-animation-library-1/LICENSE.txt",
        "preview_root": "animations/quaternius-universal-animation-library-1/setup-guides",
    },
    "quaternius-universal-animation-library-2": {
        "source": "https://quaternius.com/packs/universalanimationlibrary2.html",
        "license": "animations/quaternius-universal-animation-library-2/LICENSE.txt",
        "preview_root": "animations/quaternius-universal-animation-library-2/setup-guides",
    },
    "quaternius-modular-outfits-fantasy-standard": {
        "source": "https://quaternius.com/packs/modularcharacteroutfitsfantasy.html",
        "license": "characters/quaternius-modular-outfits-fantasy-standard/LICENSE.txt",
        "preview_root": "characters/quaternius-modular-outfits-fantasy-standard/previews",
    },
    "village-commons": {
        "source": "original (Sovereign's Eye): props/village-commons/source/build_commons.py",
        "license": "props/village-commons/LICENSE.txt",
        "preview_root": "props/village-commons/previews",
    },
    "farm-field": {
        "source": "original (Sovereign's Eye): props/farm-field/source/build_farm.py",
        "license": "props/farm-field/LICENSE.txt",
        "preview_root": "props/farm-field/previews",
    },
    "market-square": {
        "source": "original (Sovereign's Eye): props/market-square/source/build_square.py",
        "license": "props/market-square/LICENSE.txt",
        "preview_root": "props/market-square/previews",
    },
    "status-wear": {
        "source": "original (Sovereign's Eye): characters/status-wear/source/build_wear.py",
        "license": "characters/status-wear/LICENSE.txt",
        "preview_root": "characters/status-wear/previews",
    },
    "home-yard": {
        "source": "original (Sovereign's Eye): props/home-yard/source/build_home.py",
        "license": "props/home-yard/LICENSE.txt",
        "preview_root": "props/home-yard/previews",
    },
    "smithy": {
        "source": "original (Sovereign's Eye): props/smithy/source/build_smithy.py",
        "license": "props/smithy/LICENSE.txt",
        "preview_root": "props/smithy/previews",
    },
}


def read_glb_json(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("file is too short to be a GLB")

    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("missing glTF magic header")
    if version != 2:
        raise ValueError(f"unsupported GLB version {version}")
    if declared_length != len(data):
        raise ValueError(
            f"declared length {declared_length} does not match {len(data)} bytes"
        )

    json_length, chunk_type = struct.unpack_from("<I4s", data, 12)
    if chunk_type != b"JSON":
        raise ValueError("first GLB chunk is not JSON")
    payload = data[20 : 20 + json_length].decode("utf-8").rstrip(" \t\r\n\x00")
    document = json.loads(payload)
    if document.get("asset", {}).get("version") != "2.0":
        raise ValueError("embedded document is not glTF 2.0")
    return document


def read_gltf_json(path: Path) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("asset", {}).get("version") != "2.0":
        raise ValueError("document is not glTF 2.0")
    return document


def read_model_json(path: Path) -> dict:
    if path.suffix == ".glb":
        return read_glb_json(path)
    if path.suffix == ".gltf":
        return read_gltf_json(path)
    raise ValueError(f"unsupported model format: {path.suffix}")


def medieval_village_category(stem: str) -> str:
    category_prefixes = (
        ("Balcony_", "balconies"),
        ("Corner_", "corners"),
        ("DoorFrame_", "doors"),
        ("Door_", "doors"),
        ("Floor_", "floors"),
        ("HoleCover_", "floors"),
        ("Overhang_", "overhangs"),
        ("Prop_", "props"),
        ("Roof_", "roofs"),
        ("Stair", "stairs"),
        ("Wall_", "walls"),
        ("WindowShutters_", "windows"),
        ("Window_", "windows"),
    )
    for prefix, category in category_prefixes:
        if stem.startswith(prefix):
            return category
    return "architecture"


def stylized_nature_category(stem: str) -> str:
    if stem.startswith(("CommonTree_", "DeadTree_", "Pine_", "TwistedTree_")):
        return "trees"
    if stem.startswith(("Pebble_", "RockPath_", "Rock_")):
        return "rocks-paths"
    return "plants-ground-cover"


def fantasy_props_category(stem: str) -> str:
    if stem.startswith(("Book", "Bottle", "Potion", "Scroll", "SmallBottle", "Cauldron")):
        return "books-alchemy"
    if stem.startswith(("Bed", "Bench", "Bookcase", "Cabinet", "Chair", "Nightstand", "Peg_Rack", "Shelf", "Stool", "Table_Large")):
        return "furniture"
    if stem.startswith(("Anvil", "Axe", "Dummy", "Pickaxe", "Shield", "Sword", "WeaponStand", "Whetstone", "Workbench")):
        return "workshop-weapons"
    if stem.startswith(("Banner", "Candle", "Chalice", "Chandelier", "Lantern", "Torch", "Vase")):
        return "lighting-decor"
    if stem.startswith(("Carrot", "FarmCrate", "Stall", "Coin")) or stem == "Barrel_Apples":
        return "market-goods"
    if stem.startswith(("Mug", "Pot_", "Table_Fork", "Table_Knife", "Table_Plate", "Table_Spoon")):
        return "tableware"
    if stem.startswith(("Bag", "Barrel", "Bucket", "Cage", "Chain", "Chest", "Crate", "Pouch", "Rope")):
        return "storage-utility"
    return "small-utility"


def collection_for(path: Path) -> tuple[str, str]:
    relative = path.relative_to(ASSET_ROOT)
    if relative.parts[0] == "alternatives" and relative.parts[2] == "models":
        return relative.parts[1], "alternative"
    if relative.parts[:2] == (
        "character-tests",
        "quaternius-universal-base-standard",
    ):
        return "quaternius-universal-base-standard", relative.parts[3]
    if relative.parts[0] == "animations":
        return relative.parts[1], "animation-library"
    if relative.parts[:2] == (
        "characters",
        "quaternius-modular-outfits-fantasy-standard",
    ):
        return "quaternius-modular-outfits-fantasy-standard", relative.parts[3]
    if relative.parts[:2] == ("characters", "status-wear"):
        return "status-wear", "aprons" if "Apron" in path.stem else "headwear"
    if relative.parts[:2] == ("characters", "blocky"):
        return "blocky-characters", "characters"
    if relative.parts[:2] == ("environments", "castle-kit"):
        return "castle-kit", relative.parts[2]
    if relative.parts[:2] == ("environments", "fantasy-town-kit"):
        return "fantasy-town-kit", relative.parts[2]
    if relative.parts[:2] == (
        "environments",
        "quaternius-medieval-village-standard",
    ):
        return "quaternius-medieval-village-standard", medieval_village_category(
            path.stem
        )
    if relative.parts[:2] == (
        "environments",
        "quaternius-stylized-nature-standard",
    ):
        return "quaternius-stylized-nature-standard", stylized_nature_category(
            path.stem
        )
    if relative.parts[:2] == ("props", "village-commons"):
        for prefix, category in (("SE_Well_", "wells"), ("SE_Banner_", "banners"), ("SE_Signpost_", "signposts")):
            if path.stem.startswith(prefix):
                return "village-commons", category
        return "village-commons", "commons"
    if relative.parts[:2] == ("props", "farm-field"):
        for prefix, category in (("SE_Crop_", "crops"), ("SE_Fence_", "fences"), ("SE_Gate_", "gates")):
            if path.stem.startswith(prefix):
                return "farm-field", category
        return "farm-field", "yard"
    if relative.parts[:2] == ("props", "market-square"):
        for prefix, category in (("SE_Kerb_", "kerbs"), ("SE_MarketCross", "crosses"), ("SE_Trough_", "troughs")):
            if path.stem.startswith(prefix):
                return "market-square", category
        return "market-square", "square"
    if relative.parts[:2] == ("props", "home-yard"):
        for prefix, category in (("SE_Bench", "benches"), ("SE_Garden", "gardens")):
            if path.stem.startswith(prefix):
                return "home-yard", category
        return "home-yard", "yard"
    if relative.parts[:2] == ("props", "smithy"):
        return "smithy", "forges" if path.stem.startswith("SE_Forge_") else "smithy"
    if relative.parts[:2] == ("props", "quaternius-fantasy-props-standard"):
        return "quaternius-fantasy-props-standard", fantasy_props_category(
            path.stem
        )
    raise ValueError(f"unrecognized asset location: {relative}")


def main() -> None:
    rows = []
    errors = []
    external_dependency_count = 0
    missing_dependencies = []

    model_paths = list(ASSET_ROOT.glob("**/*.glb")) + list(
        ASSET_ROOT.glob("**/*.gltf")
    )
    for path in sorted(model_paths):
        relative = path.relative_to(ASSET_ROOT).as_posix()
        collection, category = collection_for(path)
        metadata = COLLECTIONS[collection]

        try:
            document = read_model_json(path)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            errors.append({"path": relative, "error": str(exc)})
            continue

        external_uris = [
            item["uri"]
            for section in ("buffers", "images")
            for item in document.get(section, [])
            if "uri" in item and not item["uri"].startswith("data:")
        ]
        dependency_paths = []
        for uri in external_uris:
            dependency_path = (path.parent / uri).resolve()
            dependency_paths.append(
                dependency_path.relative_to(ASSET_ROOT).as_posix()
            )
            external_dependency_count += 1
            if not dependency_path.is_file():
                missing_dependencies.append(
                    {"path": relative, "missing": uri}
                )

        animation_names = [
            animation.get("name", f"animation-{index + 1}")
            for index, animation in enumerate(document.get("animations", []))
        ]
        preview = ""
        for ext in (".png", ".jpg"):
            candidate = f"{metadata['preview_root']}/{path.stem}{ext}"
            if (ASSET_ROOT / candidate).is_file():
                preview = candidate
                break

        rows.append(
            {
                "path": relative,
                "collection": collection,
                "category": category,
                "bytes": path.stat().st_size,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "mesh_count": len(document.get("meshes", [])),
                "node_count": len(document.get("nodes", [])),
                "material_count": len(document.get("materials", [])),
                "animation_clip_count": len(animation_names),
                "animation_clips": " | ".join(animation_names),
                "dependencies": " | ".join(dependency_paths),
                "preview": preview,
                "license": metadata["license"],
                "source": metadata["source"],
            }
        )

    manifest_path = ASSET_ROOT / "ASSET_MANIFEST.csv"
    with manifest_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=list(rows[0]), lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)

    report = {
        "format": "glTF 2.0 (GLB and JSON glTF)",
        "models_checked": len(rows) + len(errors),
        "models_valid": len(rows),
        "models_with_previews": sum(bool(row["preview"]) for row in rows),
        "models_with_animation": sum(row["animation_clip_count"] > 0 for row in rows),
        "external_dependencies_checked": external_dependency_count,
        "missing_dependencies": missing_dependencies,
        "errors": errors,
        "checks": [
            "GLB magic header, version, and declared length when applicable",
            "JSON document readability",
            "glTF asset version 2.0",
            "external buffer and image references",
            "matching preview file",
            "SHA-256 checksum",
        ],
    }
    (ASSET_ROOT / "VALIDATION.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )

    if errors or missing_dependencies:
        raise SystemExit(
            f"validation failed: {len(errors)} invalid model(s), "
            f"{len(missing_dependencies)} missing external dependency/dependencies"
        )

    print(
        f"Validated {len(rows)} glTF 2.0 model files; "
        f"{report['models_with_previews']} previews; "
        f"{report['models_with_animation']} animated models."
    )


if __name__ == "__main__":
    main()
