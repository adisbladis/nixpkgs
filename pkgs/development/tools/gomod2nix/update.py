#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p nix -p python3 -p python3.pkgs.requests
from pprint import pprint
import subprocess
import requests
import os.path
import shutil
import json


OWNER = "tweag"
REPO = "gomod2nix"
URL = f"https://api.github.com/repos/{OWNER}/{REPO}/releases/latest"


# Ideally this would use shutil.copytree, but that doesn't give control over directory permissions
def copy_tree(src, dst):
    """Copy a tree without permissions"""
    subprocess.check_output([
        "cp",
        "-r",
        "--no-preserve=mode,ownership",
        src,
        dst,
    ])


if __name__ == "__main__":

    pkg_dir = os.path.dirname(os.path.abspath(__file__))
    nixpkgs_dir = os.path.abspath(os.path.join(pkg_dir, "../../../../"))

    builder_dir = os.path.join(nixpkgs_dir, "pkgs/build-support/go/gomod2nix")

    r = requests.get(URL)
    if not r.ok:
        raise ValueError(f"Request returned {r.status_code}")

    resp = r.json()

    tag_name = resp["tag_name"]
    sha256, store_path = subprocess.check_output([
        "nix-prefetch-url",
        "--unpack",
        "--print-path",
        resp["tarball_url"],
    ]).strip().decode().split("\n")

    try:
        shutil.rmtree(builder_dir)
    except FileNotFoundError:
        pass

    copy_tree(os.path.join(store_path, "builder"), builder_dir)
    copy_tree(os.path.join(store_path, "generic.nix"), "generic.nix")
    copy_tree(os.path.join(store_path, "gomod2nix.toml"), "gomod2nix.toml")

    with open("src.json", "w") as f:
        f.write(json.dumps({
            "owner": OWNER,
            "repo": REPO,
            "sha256": sha256,
            "rev": tag_name,
        }) + "\n")
