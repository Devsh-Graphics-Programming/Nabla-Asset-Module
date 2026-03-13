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
    parser.add_argument(
        "--forbid-tree",
        action="append",
        default=[],
        help="Path relative to --build-dir that must not exist after materialization.",
    )
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

    forbidden_trees: list[str] = []
    for relative_path in args.forbid_tree:
        forbidden_path = (build_dir / relative_path).resolve()
        if forbidden_path.exists():
            forbidden_trees.append(str(forbidden_path))

    if forbidden_trees:
        preview = ", ".join(forbidden_trees[:5])
        raise SystemExit(
            f"Expected the following paths to stay absent after materialization, "
            f"but found {len(forbidden_trees)} present. First entries: {preview}"
        )

    files = sorted(iter_files(media_root))
    if not files:
        raise SystemExit(f"No files found under {media_root}")

    counts = {"symlink": 0, "hardlink": 0, "copy": 0}
    logical_size = 0
    estimated_extra_size = 0
    largest_files: list[dict[str, object]] = []
    mismatches: list[str] = []
    zip_file_count = 0
    invalid_zip_files: list[str] = []
    for path in files:
        materialization, file_size, extra_size = classify_materialization(path)
        relative_path = path.relative_to(build_dir).as_posix()
        counts[materialization] += 1
        logical_size += file_size
        estimated_extra_size += extra_size
        if materialization != args.expected_mode:
            mismatches.append(f"{relative_path}={materialization}")
        if path.suffix.lower() == ".zip":
            zip_file_count += 1
            if not zipfile.is_zipfile(path):
                invalid_zip_files.append(relative_path)
        largest_files.append(
            {
                "path": relative_path,
                "mode": materialization,
                "size_bytes": file_size,
                "size_human": format_bytes(file_size),
            }
        )

    largest_files.sort(key=lambda entry: (-int(entry["size_bytes"]), str(entry["path"])))
    largest_files = largest_files[:5]

    if mismatches:
        preview = ", ".join(mismatches[:5])
        raise SystemExit(
            f"Expected `{args.expected_mode}` for all {len(files)} files under {media_root} "
            f"but found {len(mismatches)} mismatches. First mismatches: {preview}"
        )

    if invalid_zip_files:
        preview = ", ".join(invalid_zip_files[:5])
        raise SystemExit(
            f"Expected every materialized .zip payload to stay a valid zip file, "
            f"but found {len(invalid_zip_files)} invalid files. First invalid entries: {preview}"
        )

    summary = {
        "build_dir": str(build_dir),
        "cache_root": str(cache_root),
        "expected_mode": args.expected_mode,
        "forbid_tree": args.forbid_tree,
        "file_count": len(files),
        "counts": counts,
        "logical_size_bytes": logical_size,
        "logical_size_human": format_bytes(logical_size),
        "estimated_extra_size_bytes": estimated_extra_size,
        "estimated_extra_size_human": format_bytes(estimated_extra_size),
        "zip_file_count": zip_file_count,
        "largest_files": largest_files,
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
            f"- Valid zip payloads: `{zip_file_count}`",
        ]
        if largest_files:
            lines.extend(("", "### Largest materialized files"))
            for entry in largest_files:
                lines.append(
                    f"- `{entry['path']}` `{entry['mode']}` `{entry['size_human']}`"
                )
        Path(step_summary).write_text("\n".join(lines) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    sys.exit(main())
