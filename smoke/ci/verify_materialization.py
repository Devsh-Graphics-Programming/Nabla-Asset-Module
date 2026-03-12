from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import zipfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", required=True)
    parser.add_argument("--cache-root", required=True)
    parser.add_argument("--expected-mode", required=True, choices=("symlink", "hardlink", "copy"))
    return parser.parse_args()


def iter_files(root: Path):
    for path in root.rglob("*"):
        if path.is_symlink() or path.is_file():
            yield path


def classify_materialization(path: Path) -> tuple[str, int, int]:
    link_info = path.lstat()
    if stat.S_ISLNK(link_info.st_mode):
        target_size = path.stat().st_size
        return ("symlink", target_size, link_info.st_size)

    direct_info = path.stat(follow_symlinks=False)
    if direct_info.st_nlink > 1:
        return ("hardlink", direct_info.st_size, 0)

    return ("copy", direct_info.st_size, direct_info.st_size)


def format_bytes(value: int) -> str:
    units = ("B", "KiB", "MiB", "GiB")
    size = float(value)
    unit = units[0]
    for unit in units:
        if size < 1024.0 or unit == units[-1]:
            break
        size /= 1024.0
    if unit == "B":
        return f"{int(size)} {unit}"
    return f"{size:.2f} {unit}"


def main() -> int:
    args = parse_args()
    build_dir = Path(args.build_dir).resolve()
    cache_root = Path(args.cache_root).resolve()
    media_root = build_dir / "media"
    if not media_root.exists():
        raise SystemExit(f"Missing materialized tree: {media_root}")

    bunny_path = media_root / "assets/mesh/standalone/stl/Stanford_Bunny.stl"
    yellowflower_path = media_root / "assets/mesh/bundles/obj/yellowflower.zip"
    required_paths = (bunny_path, yellowflower_path)
    for path in required_paths:
        if not path.exists():
            raise SystemExit(f"Missing required file: {path}")

    files = list(iter_files(media_root))
    if not files:
        raise SystemExit(f"No files found under {media_root}")

    counts = {"symlink": 0, "hardlink": 0, "copy": 0}
    logical_size = 0
    estimated_extra_size = 0
    for path in files:
        materialization, file_size, extra_size = classify_materialization(path)
        counts[materialization] += 1
        logical_size += file_size
        estimated_extra_size += extra_size

    sample_modes: dict[str, str] = {}
    for path in required_paths:
        materialization, _, _ = classify_materialization(path)
        sample_modes[str(path.relative_to(build_dir))] = materialization
        if materialization != args.expected_mode:
            raise SystemExit(
                f"Expected `{args.expected_mode}` for {path.name} but found `{materialization}`"
            )

    if not zipfile.is_zipfile(yellowflower_path):
        raise SystemExit(f"Expected a zip payload at {yellowflower_path}")

    summary = {
        "build_dir": str(build_dir),
        "cache_root": str(cache_root),
        "expected_mode": args.expected_mode,
        "file_count": len(files),
        "counts": counts,
        "logical_size_bytes": logical_size,
        "logical_size_human": format_bytes(logical_size),
        "estimated_extra_size_bytes": estimated_extra_size,
        "estimated_extra_size_human": format_bytes(estimated_extra_size),
        "sample_modes": sample_modes,
    }

    print(json.dumps(summary, indent=2, sort_keys=True))

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        lines = [
            "## Smoke materialization summary",
            "",
            f"- Expected mode: `{args.expected_mode}`",
            f"- Files: `{len(files)}`",
            f"- Counts: `symlink={counts['symlink']}` `hardlink={counts['hardlink']}` `copy={counts['copy']}`",
            f"- Logical size: `{format_bytes(logical_size)}`",
            f"- Estimated extra size in build tree: `{format_bytes(estimated_extra_size)}`",
            f"- Stanford_Bunny.stl: `{sample_modes[str(bunny_path.relative_to(build_dir))]}`",
            f"- yellowflower.zip: `{sample_modes[str(yellowflower_path.relative_to(build_dir))]}`",
        ]
        Path(step_summary).write_text("\n".join(lines) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    sys.exit(main())
