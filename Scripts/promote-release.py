#!/usr/bin/env python3
# @name: 最新稳定版本发布保护
# @Descripttion: 确认版本与更新附件后设置 GitHub Latest，避免旧版本覆盖更新入口。
# @version: 1.0.0
# @Author: sm
# @Date: 2026-09-11 11:10:33
# @LastEditTime: 2026-09-11 11:10:33
# @FilePath: Scripts/promote-release.py
import json
import base64
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

REPOSITORY = "GoldenTangerine/codenotch"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def validate_appcast(tag, data, dmg_size):
    root = ET.fromstring(data)
    items = root.findall("./channel/item")
    if root.tag != "rss" or len(items) != 1:
        raise ValueError("Update feed must contain exactly one release")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Update feed has no download")
    expected = f"https://github.com/{REPOSITORY}/releases/download/{tag}/Codenotch.dmg"
    if enclosure.get("url") != expected:
        raise ValueError("Update download does not match the release tag")
    display = item.findtext(f"{SPARKLE}shortVersionString") or enclosure.get(f"{SPARKLE}shortVersionString")
    build = item.findtext(f"{SPARKLE}version") or enclosure.get(f"{SPARKLE}version")
    if version(tag) is None or display != tag.removeprefix("v") or not build:
        raise ValueError("Update version does not match the release")
    if dmg_size <= 0 or enclosure.get("length") != str(dmg_size):
        raise ValueError("Update download size does not match the DMG")
    signature = enclosure.get(f"{SPARKLE}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Update feed requires an EdDSA signature")
    return signature


def verify_archive(dmg, signature, info_path):
    with Path(info_path).open("rb") as info:
        public_key = plistlib.load(info)["SUPublicEDKey"]
    subprocess.run(
        ["swift", str(Path(__file__).with_name("verify-update.swift")),
         str(dmg), signature, public_key], check=True,
    )


def validate_published_appcast(tag, releases):
    target = next(release for release in releases if release["tag_name"] == tag)
    dmg = next(asset for asset in target["assets"] if asset["name"] == "Codenotch.dmg")
    with tempfile.TemporaryDirectory() as folder:
        subprocess.run(
            ["gh", "release", "download", tag, "--repo", REPOSITORY,
             "--pattern", "appcast.xml", "--dir", folder], check=True,
        )
        validate_appcast(tag, (Path(folder) / "appcast.xml").read_bytes(), dmg["size"])


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
    validate_published_appcast(tag, releases)
    subprocess.run(
        ["gh", "release", "edit", tag, "--repo", REPOSITORY, "--latest"],
        check=True, stdout=sys.stderr,
    )
    latest = subprocess.run(
        ["gh", "api", f"repos/{REPOSITORY}/releases/latest"],
        check=True, capture_output=True, text=True,
    )
    if json.loads(latest.stdout).get("tag_name") != tag:
        raise ValueError(f"GitHub Latest does not match {tag}")
    return True


if __name__ == "__main__":
    try:
        if len(sys.argv) == 6 and sys.argv[1] == "--validate":
            signature = validate_appcast(sys.argv[2], Path(sys.argv[3]).read_bytes(), Path(sys.argv[4]).stat().st_size)
            verify_archive(sys.argv[4], signature, sys.argv[5])
        elif len(sys.argv) == 2:
            print("true" if promote(sys.argv[1]) else "false")
        else:
            sys.exit("Usage: promote-release.py vX.Y.Z | --validate vX.Y.Z appcast.xml Codenotch.dmg Info.plist")
    except (ValueError, KeyError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
