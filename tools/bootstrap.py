#!/usr/bin/env python3
"""Install checksum-pinned build tools into the ignored project-local cache."""

import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]


def host_platform():
    host = (platform.system(), platform.machine())
    supported = {("Darwin", "arm64"): "macos-arm64", ("Linux", "x86_64"): "linux-x86_64"}
    if host not in supported:
        raise RuntimeError(f"No foundation toolchain artifacts selected for {host!r}")
    return supported[host]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def artifacts(selected):
    data = json.loads((ROOT / "tools/toolchain-artifacts.json").read_text())
    result = data["platforms"][selected]
    pins = json.loads((ROOT / "docs/toolchain-pins.json").read_text())["sources"]
    expected = {"llvm": pins[0]["tag"].removeprefix("llvmorg-"),
                "cmake": pins[1]["tag"].removeprefix("v"),
                "ninja": pins[2]["tag"].removeprefix("v")}
    if any(item["version"] != expected[name] for name, item in result.items()):
        raise RuntimeError("Artifact versions conflict with the selected source pins")
    return result


def install(selected):
    prefix, downloads = ROOT / ".tools" / selected, ROOT / ".tools/downloads"
    prefix.mkdir(parents=True, exist_ok=True)
    downloads.mkdir(parents=True, exist_ok=True)
    for name, item in artifacts(selected).items():
        destination = prefix / name
        marker = destination / ".artifact.json"
        if marker.is_file() and json.loads(marker.read_text()) == item:
            print(f"{selected}/{name}: already installed", flush=True)
            continue
        if destination.exists():
            raise RuntimeError(f"Unrecognized tool directory: {destination}; refusing to overwrite it")
        archive = downloads / Path(urlsplit(item["url"]).path).name
        if not archive.is_file():
            partial = archive.with_name(archive.name + ".partial")
            print(f"Downloading {archive.name}", flush=True)
            subprocess.run(
                ["curl", "--fail", "--location", "--retry", "3", "--connect-timeout", "30",
                 "--output", str(partial), item["url"]], check=True)
            partial.rename(archive)
        if sha256(archive) != item["sha256"]:
            raise RuntimeError(f"Checksum mismatch: {archive}; refusing extraction")
        print(f"Extracting verified {archive.name}", flush=True)
        with tempfile.TemporaryDirectory(prefix=f".{name}-", dir=prefix) as temporary:
            staging = Path(temporary)
            if archive.suffix == ".zip":
                with zipfile.ZipFile(archive) as source:
                    binary = staging / "ninja"
                    binary.write_bytes(source.read("ninja"))
                    binary.chmod(0o755)
                extracted = staging
            else:
                with tarfile.open(archive) as source:
                    for member in source:
                        target = (staging / member.name).resolve()
                        if not target.is_relative_to(staging.resolve()):
                            raise RuntimeError(f"Unsafe archive path: {member.name}")
                        if member.issym() or member.islnk():
                            link = (target.parent / member.linkname if member.issym()
                                    else staging / member.linkname).resolve()
                            if not link.is_relative_to(staging.resolve()):
                                raise RuntimeError(f"Unsafe archive link: {member.name}")
                        source.extract(member, staging)
                extracted = staging / item["root"]
            if extracted == staging:
                destination.mkdir()
                shutil.move(str(extracted / "ninja"), destination / "ninja")
            else:
                extracted.rename(destination)
        marker.write_text(json.dumps(item, indent=2) + "\n")
    print(f"Toolchain ready: {prefix}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("macos-arm64", "linux-x86_64"),
                        default=host_platform())
    arguments = parser.parse_args()
    install(arguments.platform)


if __name__ == "__main__":
    main()
