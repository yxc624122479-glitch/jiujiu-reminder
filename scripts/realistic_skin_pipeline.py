#!/usr/bin/env python3
"""Prepare, assemble, and validate the 12x9 realistic Jiujiu skin."""

from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
except ImportError as exc:
    raise SystemExit("Pillow is required. Run this script with the bundled Codex Python runtime.") from exc


CELL_SIZE = 256
BOARD_COLUMNS = 4
BOARD_ROWS = 3
ATLAS_COLUMNS = 12
ATLAS_ROWS = 9
CHROMA_KEY = (255, 0, 255)

ACTIONS = [
    ("eating", "吃猫粮", 180, "lowering its head and naturally chewing food from a small bowl"),
    ("drinking", "喝水", 180, "lapping water naturally from a shallow bowl"),
    ("rolling", "翻肚打滚", 160, "rolling onto its back, showing its belly, and returning naturally"),
    ("grooming", "舔猫毛", 180, "licking a front paw and grooming its chest and shoulder fur"),
    ("chasing", "追蝴蝶", 140, "stalking and pouncing toward the right, without drawing the butterfly"),
    ("working", "工作", 200, "sitting attentively in front of a small open laptop and tapping the keyboard"),
    ("sleeping", "睡觉", 280, "curling up, breathing slowly, and briefly twitching an ear"),
    ("stretching", "伸懒腰", 180, "performing a full feline forward stretch and returning upright"),
    ("observing", "坐立观察", 220, "sitting alert, looking around, blinking, and tilting its head"),
]

PROPS = [
    ("butterfly", "a small realistic orange-and-black butterfly, wings open"),
    ("wand-lure", "the feather lure at the end of a cat teaser wand, compact and readable"),
    ("cat-treat", "the open tip of a squeezable cat treat tube with a small amount of paste"),
]


def ensure_dirs(run_dir: Path) -> None:
    for relative in [
        "decoded",
        "frames",
        "final/accessories",
        "prompts/actions",
        "prompts/props",
        "qa/previews",
        "references",
    ]:
        (run_dir / relative).mkdir(parents=True, exist_ok=True)


def prepare(run_dir: Path, face_reference: Path, body_reference: Path) -> None:
    ensure_dirs(run_dir)
    guide_path = run_dir / "references/layout-guide-4x3.png"
    make_layout_guide(guide_path)

    identity = (
        "The same photorealistic silver-and-black American shorthair cat from the references: "
        "round face, dense short fur, black forehead stripes, white muzzle/chest/front paws, "
        "yellow-green round eyes, sturdy slightly chubby body. Preserve exact face, markings, "
        "eye color, proportions, fur length, and tail pattern in every frame."
    )
    shared = (
        "Create a 4 columns by 3 rows animation pose board containing exactly 12 chronological frames, "
        "read left-to-right and top-to-bottom. Every slot shows one complete, separated, centered cat pose "
        "at consistent scale and baseline. Use a perfectly uniform pure #ff00ff background across the entire "
        "image. No grid, borders, labels, frame numbers, text, shadows, floor, scenery, motion blur, duplicate "
        "cats, overlapping slots, cropped body parts, or objects crossing slot boundaries."
    )

    (run_dir / "prompts/base.md").write_text(
        "\n".join(
            [
                "Use case: photorealistic-natural",
                "Asset type: canonical desktop-pet identity reference",
                f"Primary request: {identity}",
                "Composition: one complete full-body seated cat, centered with generous padding.",
                "Background: perfectly uniform pure #ff00ff chroma key.",
                "Avoid: floor, cast shadow, scenery, text, watermark, collar, extra props, cropped whiskers.",
            ]
        ),
        encoding="utf-8",
    )

    for action_id, title, _, motion in ACTIONS:
        (run_dir / f"prompts/actions/{action_id}.md").write_text(
            "\n".join(
                [
                    "Use case: photorealistic-natural",
                    f"Asset type: 12-frame desktop-pet animation board for {title}",
                    f"Identity lock: {identity}",
                    f"Motion: a seamless natural cycle of the cat {motion}.",
                    shared,
                    "Motion quality: anatomically plausible weight shift, continuous paws/head/tail path, loop-ready first and last poses.",
                ]
            ),
            encoding="utf-8",
        )

    (run_dir / "prompts/actions/treat.md").write_text(
        "\n".join(
            [
                "Use case: photorealistic-natural",
                "Asset type: 12-frame desktop-pet interaction animation board",
                f"Identity lock: {identity}",
                "Motion: the seated cat leans forward and repeatedly licks a cat treat held just in front of its mouth; do not draw the treat or a hand.",
                shared,
                "Motion quality: subtle tongue, mouth, head, whisker, and paw movement; seamless loop.",
            ]
        ),
        encoding="utf-8",
    )

    for name, description in PROPS:
        (run_dir / f"prompts/props/{name}.md").write_text(
            "\n".join(
                [
                    "Use case: product-mockup",
                    "Asset type: transparent desktop-pet interaction prop",
                    f"Primary request: {description}.",
                    "Composition: one isolated object centered with generous padding, readable at 64px.",
                    "Background: perfectly uniform pure #ff00ff chroma key.",
                    "Avoid: hands, cat, floor, shadow, text, watermark, duplicate objects.",
                ]
            ),
            encoding="utf-8",
        )

    manifest = {
        "face_reference": str(face_reference.resolve()),
        "body_reference": str(body_reference.resolve()),
        "layout_guide": str(guide_path.resolve()),
        "chroma_key": "#ff00ff",
        "board": {"columns": BOARD_COLUMNS, "rows": BOARD_ROWS, "frames": 12},
        "atlas": {
            "columns": ATLAS_COLUMNS,
            "rows": ATLAS_ROWS,
            "cell_width": CELL_SIZE,
            "cell_height": CELL_SIZE,
            "width": ATLAS_COLUMNS * CELL_SIZE,
            "height": ATLAS_ROWS * CELL_SIZE,
        },
        "actions": [
            {"id": action_id, "title": title, "duration_ms": duration}
            for action_id, title, duration, _ in ACTIONS
        ],
        "interaction_action": {"id": "treat", "duration_ms": 180},
        "props": [name for name, _ in PROPS],
    }
    (run_dir / "generation-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"ok": True, "run_dir": str(run_dir), "guide": str(guide_path)}, ensure_ascii=False))


def make_layout_guide(path: Path) -> None:
    width, height = 1024, 768
    image = Image.new("RGB", (width, height), CHROMA_KEY)
    draw = ImageDraw.Draw(image)
    line = (235, 235, 235)
    for column in range(1, BOARD_COLUMNS):
        x = column * width // BOARD_COLUMNS
        draw.line((x, 0, x, height), fill=line, width=2)
    for row in range(1, BOARD_ROWS):
        y = row * height // BOARD_ROWS
        draw.line((0, y, width, y), fill=line, width=2)
    for row in range(BOARD_ROWS):
        for column in range(BOARD_COLUMNS):
            left = column * width // BOARD_COLUMNS
            top = row * height // BOARD_ROWS
            right = (column + 1) * width // BOARD_COLUMNS
            bottom = (row + 1) * height // BOARD_ROWS
            inset = 18
            draw.rectangle((left + inset, top + inset, right - inset, bottom - inset), outline=(250, 250, 250), width=1)
    image.save(path)


def crop_to_aspect(image: Image.Image, aspect: float) -> Image.Image:
    current = image.width / image.height
    if math.isclose(current, aspect, rel_tol=1e-4):
        return image
    if current > aspect:
        width = round(image.height * aspect)
        left = (image.width - width) // 2
        return image.crop((left, 0, left + width, image.height))
    height = round(image.width / aspect)
    top = (image.height - height) // 2
    return image.crop((0, top, image.width, top + height))


def remove_chroma(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    rgb = rgba.convert("RGB")
    flooded = rgb.copy()
    fill_color = (1, 2, 3)
    for corner in [(0, 0), (rgb.width - 1, 0), (0, rgb.height - 1), (rgb.width - 1, rgb.height - 1)]:
        ImageDraw.floodfill(flooded, corner, fill_color, thresh=82)

    red, green, blue = flooded.split()
    filled = ImageChops.multiply(
        ImageChops.multiply(red.point(lambda value: 255 if value == fill_color[0] else 0),
                            green.point(lambda value: 255 if value == fill_color[1] else 0)),
        blue.point(lambda value: 255 if value == fill_color[2] else 0),
    )
    matte = ImageChops.invert(filled)
    source_red, source_green, source_blue = rgb.split()
    chroma_like = ImageChops.multiply(
        ImageChops.multiply(
            source_red.point(lambda value: 255 if value >= 180 else 0),
            source_blue.point(lambda value: 255 if value >= 155 else 0),
        ),
        source_green.point(lambda value: 255 if value <= 115 else 0),
    )
    matte = ImageChops.multiply(matte, ImageChops.invert(chroma_like))
    matte = ImageChops.multiply(matte, rgba.getchannel("A"))
    rgba.putalpha(matte)

    normalized = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    normalized.alpha_composite(rgba)
    return normalized


def extract_board(board_path: Path, output_dir: Path) -> list[Image.Image]:
    board = crop_to_aspect(Image.open(board_path).convert("RGBA"), BOARD_COLUMNS / BOARD_ROWS)
    board = remove_chroma(board)
    output_dir.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    for index in range(ATLAS_COLUMNS):
        column = index % BOARD_COLUMNS
        row = index // BOARD_COLUMNS
        left = round(column * board.width / BOARD_COLUMNS)
        top = round(row * board.height / BOARD_ROWS)
        right = round((column + 1) * board.width / BOARD_COLUMNS)
        bottom = round((row + 1) * board.height / BOARD_ROWS)
        cropped = board.crop((left, top, right, bottom)).resize((236, 236), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
        frame.alpha_composite(cropped, (10, 10))
        frame = clean_keyed_edges(frame)
        frame = normalize_transparent_rgb(frame)
        frame.save(output_dir / f"{index:02d}.png")
        frames.append(frame)
    return frames


def normalize_transparent_rgb(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    normalized = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    normalized.alpha_composite(rgba)
    return normalized


def clean_keyed_edges(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    contracted_alpha = rgba.getchannel("A").filter(ImageFilter.MinFilter(5))
    contracted_alpha = contracted_alpha.filter(ImageFilter.GaussianBlur(0.45))
    rgba.putalpha(contracted_alpha)
    return rgba


def process_prop(source: Path, destination: Path) -> Image.Image:
    image = remove_chroma(Image.open(source))
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"prop has no visible pixels: {source}")
    cropped = image.crop(bbox)
    cropped.thumbnail((220, 220), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(cropped, ((CELL_SIZE - cropped.width) // 2, (CELL_SIZE - cropped.height) // 2))
    canvas = clean_keyed_edges(canvas)
    canvas = normalize_transparent_rgb(canvas)
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)
    return canvas


def count_nontransparent(image: Image.Image) -> int:
    histogram = image.getchannel("A").histogram()
    return sum(histogram[1:])


def flattened_data(image: Image.Image) -> list[int]:
    data = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    return list(data)


def transparent_residue_count(image: Image.Image) -> int:
    count = 0
    pixels = image.convert("RGBA")
    data = pixels.get_flattened_data() if hasattr(pixels, "get_flattened_data") else pixels.getdata()
    for red, green, blue, alpha in data:
        if alpha == 0 and (red != 0 or green != 0 or blue != 0):
            count += 1
    return count


def build(run_dir: Path, install_dir: Path) -> None:
    ensure_dirs(run_dir)
    rows: dict[str, list[Image.Image]] = {}
    errors: list[str] = []
    warnings: list[str] = []
    cells: list[dict[str, object]] = []

    for row, (action_id, title, duration, _) in enumerate(ACTIONS):
        source = run_dir / f"decoded/{action_id}.png"
        if not source.exists():
            errors.append(f"missing action board: {source}")
            continue
        frames = extract_board(source, run_dir / f"frames/{action_id}")
        rows[action_id] = frames
        for column, frame in enumerate(frames):
            nontransparent = count_nontransparent(frame)
            cells.append({"action": action_id, "row": row, "column": column, "nontransparent_pixels": nontransparent})
            if nontransparent < 1_000:
                errors.append(f"{action_id} frame {column} is nearly empty")
            edge_alpha = (
                flattened_data(frame.getchannel("A").crop((0, 0, CELL_SIZE, 1)))
                + flattened_data(frame.getchannel("A").crop((0, CELL_SIZE - 1, CELL_SIZE, CELL_SIZE)))
                + flattened_data(frame.getchannel("A").crop((0, 0, 1, CELL_SIZE)))
                + flattened_data(frame.getchannel("A").crop((CELL_SIZE - 1, 0, CELL_SIZE, CELL_SIZE)))
            )
            if sum(value > 0 for value in edge_alpha) > 40:
                warnings.append(f"{action_id} frame {column} touches the cell edge")

    treat_source = run_dir / "decoded/treat.png"
    if treat_source.exists():
        treat_frames = extract_board(treat_source, run_dir / "frames/treat")
    else:
        treat_frames = []
        errors.append(f"missing interaction board: {treat_source}")

    props: dict[str, Image.Image] = {}
    for name, _ in PROPS:
        source = run_dir / f"decoded/{name}.png"
        if not source.exists():
            errors.append(f"missing prop: {source}")
            continue
        props[name] = process_prop(source, run_dir / f"final/accessories/{name}.png")

    if errors:
        write_validation(run_dir, False, errors, warnings, cells)
        raise SystemExit("\n".join(errors))

    atlas = Image.new("RGBA", (ATLAS_COLUMNS * CELL_SIZE, ATLAS_ROWS * CELL_SIZE), (0, 0, 0, 0))
    for row, (action_id, _, _, _) in enumerate(ACTIONS):
        for column, frame in enumerate(rows[action_id]):
            atlas.alpha_composite(frame, (column * CELL_SIZE, row * CELL_SIZE))
    atlas = normalize_transparent_rgb(atlas)
    atlas_path = run_dir / "final/spritesheet-realistic.png"
    atlas.save(atlas_path, optimize=True)

    treat_strip = Image.new("RGBA", (ATLAS_COLUMNS * CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
    for column, frame in enumerate(treat_frames):
        treat_strip.alpha_composite(frame, (column * CELL_SIZE, 0))
    treat_strip = normalize_transparent_rgb(treat_strip)
    treat_path = run_dir / "final/interaction-treat.png"
    treat_strip.save(treat_path, optimize=True)

    if atlas.size != (3072, 2304):
        errors.append(f"wrong atlas size: {atlas.size}")
    if treat_strip.size != (3072, 256):
        errors.append(f"wrong treat strip size: {treat_strip.size}")
    if transparent_residue_count(atlas) != 0:
        errors.append("atlas contains RGB residue in transparent pixels")
    if transparent_residue_count(treat_strip) != 0:
        errors.append("treat strip contains RGB residue in transparent pixels")

    make_contact_sheet(rows, run_dir / "qa/contact-sheet.png")
    make_previews(rows, run_dir / "qa/previews")
    if treat_frames:
        save_gif(treat_frames, run_dir / "qa/previews/treat.gif", 180)

    install_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(atlas_path, install_dir / atlas_path.name)
    shutil.copy2(treat_path, install_dir / treat_path.name)
    for name in props:
        shutil.copy2(run_dir / f"final/accessories/{name}.png", install_dir / f"{name}.png")

    write_validation(run_dir, not errors, errors, warnings, cells)
    print(
        json.dumps(
            {
                "ok": not errors,
                "atlas": str(atlas_path),
                "install_dir": str(install_dir),
                "warnings": warnings,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


def make_contact_sheet(rows: dict[str, list[Image.Image]], destination: Path) -> None:
    scale = 0.25
    cell = round(CELL_SIZE * scale)
    label_height = 18
    sheet = Image.new("RGB", (ATLAS_COLUMNS * cell, ATLAS_ROWS * (cell + label_height)), (245, 245, 245))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for row, (action_id, title, _, _) in enumerate(ACTIONS):
        y = row * (cell + label_height)
        draw.text((4, y + 3), f"{row}: {action_id} {title}", fill=(25, 25, 25), font=font)
        for column, frame in enumerate(rows[action_id]):
            checker = Image.new("RGB", (cell, cell), (225, 225, 225))
            checker_draw = ImageDraw.Draw(checker)
            block = 8
            for cy in range(0, cell, block):
                for cx in range(0, cell, block):
                    if (cx // block + cy // block) % 2:
                        checker_draw.rectangle((cx, cy, cx + block - 1, cy + block - 1), fill=(250, 250, 250))
            resized = frame.resize((cell, cell), Image.Resampling.LANCZOS)
            checker.paste(resized.convert("RGB"), mask=resized.getchannel("A"))
            sheet.paste(checker, (column * cell, y + label_height))
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)


def save_gif(frames: list[Image.Image], destination: Path, duration: int) -> None:
    backgrounds: list[Image.Image] = []
    for frame in frames:
        background = Image.new("RGBA", frame.size, (245, 245, 245, 255))
        background.alpha_composite(frame)
        backgrounds.append(background.convert("P", palette=Image.Palette.ADAPTIVE))
    backgrounds[0].save(destination, save_all=True, append_images=backgrounds[1:], duration=duration, loop=0, disposal=2)


def make_previews(rows: dict[str, list[Image.Image]], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    durations = {action_id: duration for action_id, _, duration, _ in ACTIONS}
    for action_id, frames in rows.items():
        save_gif(frames, output_dir / f"{action_id}.gif", durations[action_id])


def write_validation(
    run_dir: Path,
    ok: bool,
    errors: list[str],
    warnings: list[str],
    cells: list[dict[str, object]],
) -> None:
    result = {
        "ok": ok,
        "format": "PNG",
        "mode": "RGBA",
        "width": 3072,
        "height": 2304,
        "columns": ATLAS_COLUMNS,
        "rows": ATLAS_ROWS,
        "cell_width": CELL_SIZE,
        "cell_height": CELL_SIZE,
        "errors": errors,
        "warnings": warnings,
        "cells": cells,
    }
    path = run_dir / "qa/validation.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--run-dir", type=Path, required=True)
    prepare_parser.add_argument("--face-reference", type=Path, required=True)
    prepare_parser.add_argument("--body-reference", type=Path, required=True)

    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--run-dir", type=Path, required=True)
    build_parser.add_argument("--install-dir", type=Path, required=True)

    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.run_dir.resolve(), args.face_reference.resolve(), args.body_reference.resolve())
    elif args.command == "build":
        build(args.run_dir.resolve(), args.install_dir.resolve())
    else:
        raise AssertionError(args.command)


if __name__ == "__main__":
    main()
