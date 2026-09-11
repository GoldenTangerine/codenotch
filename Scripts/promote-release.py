#!/usr/bin/env python3
# @name: 最新稳定版本发布保护
# @Descripttion: 确认版本与更新附件后设置 GitHub Latest，避免旧版本覆盖更新入口。
# @version: 1.0.0
# @Author: sm
# @Date: 2026-09-11 11:10:33
# @LastEditTime: 2026-09-11 11:10:33
# @FilePath: Scripts/promote-release.py
import json
import re
import subprocess
import sys

REPOSITORY = "GoldenTangerine/codenotch"


def version(tag):
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", tag)
    return tuple(map(int, match.groups())) if match else None


def should_promote(tag, releases):
    candidate = version(tag)
    if candidate is None:
        return False
    target = next((release for release in releases if release["tag_name"] == tag), None)
    if target is None:
        raise ValueError(f"Release not found: {tag}")
    if target["draft"] or target["prerelease"]:
        return False
    assets = {asset["name"] for asset in target["assets"]}
    if not {"appcast.xml", "Codenotch.dmg"}.issubset(assets):
        raise ValueError("Latest requires appcast.xml and Codenotch.dmg")
    for release in releases:
        if release["draft"] or release["prerelease"]:
            continue
        other = version(release["tag_name"])
        # An unknown stable tag must not silently bypass downgrade protection.
        if other is None:
            raise ValueError(f"Cannot compare stable release: {release['tag_name']}")
        if other > candidate:
            return False
    return True


def promote(tag):
    result = subprocess.run(
        ["gh", "api", f"repos/{REPOSITORY}/releases?per_page=100", "--paginate", "--slurp"],
        check=True, capture_output=True, text=True,
    )
    releases = [release for page in json.loads(result.stdout) for release in page]
    if not should_promote(tag, releases):
        return False
    subprocess.run(
        ["gh", "release", "edit", tag, "--repo", REPOSITORY, "--latest"],
        check=True, stdout=sys.stderr,
    )
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 Scripts/promote-release.py vX.Y.Z")
    try:
        print("true" if promote(sys.argv[1]) else "false")
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
