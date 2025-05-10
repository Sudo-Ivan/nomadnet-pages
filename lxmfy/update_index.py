#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import requests
from datetime import datetime, timezone
import os

NODE_HASH = "486efb02ad0cdb01540f1d7178ac668e"
GITHUB_REPO_OWNER = "lxmfy"
GITHUB_REPO_NAME = "LXMFy"
LATEST_RELEASE_API_URL = f"https://api.github.com/repos/{GITHUB_REPO_OWNER}/{GITHUB_REPO_NAME}/releases/latest"
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "index.mu")
FILES_DIR = os.path.join(os.path.dirname(__file__), "files")
RETICULUM_FILES_BASE_PATH = "/file/"


def format_timestamp_from_iso(iso_timestamp_str: str) -> str:
    if not iso_timestamp_str:
        return "N/A"
    try:
        dt_object = datetime.fromisoformat(iso_timestamp_str.replace("Z", "+00:00"))
        if dt_object.tzinfo is None:
            dt_object = dt_object.replace(tzinfo=timezone.utc)
        else:
            dt_object = dt_object.astimezone(timezone.utc)
        return dt_object.strftime('%Y-%m-%d %H:%M:%S %Z')
    except (ValueError, TypeError):
        return "Invalid Timestamp"

def format_size(size_bytes: int) -> str:
    if size_bytes is None:
        return "N/A"
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024**2:
        return f"{size_bytes/1024:.2f} KB"
    elif size_bytes < 1024**3:
        return f"{size_bytes/1024**2:.2f} MB"
    else:
        return f"{size_bytes/1024**3:.2f} GB"

def download_asset(asset_url: str, target_path: str) -> bool:
    try:
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        response = requests.get(asset_url, stream=True, timeout=60)
        response.raise_for_status()
        with open(target_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        return True
    except Exception:
        return False

def generate_micron_output(release_data: dict, local_assets: list) -> str:
    micron_lines = []
    release_name = release_data.get("name", "N/A")
    tag_name = release_data.get("tag_name", "N/A")
    published_at_iso = release_data.get("published_at")
    published_at_str = format_timestamp_from_iso(published_at_iso)
    release_notes = release_data.get("body", "No release notes provided.")

    micron_lines.append(f"> `!Latest LXMFy Release: {release_name} ({tag_name})`!")
    micron_lines.append(f"`!Published (UTC):` {published_at_str}")
    micron_lines.append("-")
    micron_lines.append(">> `!Release Notes`!")
    if release_notes:
        for note_line in release_notes.splitlines():
            stripped_line = note_line.strip()
            if stripped_line.startswith("#"): 
                level = len(stripped_line.split(" ")[0])
                title = stripped_line[level:].strip()
                micron_lines.append(f"{'>'*level} `!{title}`!")
            elif stripped_line.startswith("* ") or stripped_line.startswith("- "):
                micron_lines.append(f"  * {stripped_line[2:]}")
            elif stripped_line:
                micron_lines.append(f"  {stripped_line}")
    else:
        micron_lines.append("  No release notes provided.")
    micron_lines.append("-")
    if local_assets:
        micron_lines.append(">> `!Assets (Local Links)`!")
        for asset in local_assets:
            asset_name = asset["name"]
            asset_size_str = asset["size_str"]
            micron_lines.append(f"  `!File:` {asset_name}")
            micron_lines.append(f"  `!Size:` {asset_size_str}")
            micron_lines.append(f"  `!Link:` `_`[{asset_name}`{RETICULUM_FILES_BASE_PATH}{asset_name}]`_")
            micron_lines.append("  -")
        micron_lines.append("-")
    else:
        micron_lines.append(">> `!Assets`!")
        micron_lines.append("  No assets found for this release.")
        micron_lines.append("-")
    return '\n'.join(micron_lines)

def main():
    try:
        response = requests.get(LATEST_RELEASE_API_URL, timeout=15)
        response.raise_for_status()
        release_data = response.json()
        assets = release_data.get("assets", [])
        local_assets = []
        for asset in assets:
            asset_name = asset.get("name")
            asset_url = asset.get("browser_download_url")
            asset_size = asset.get("size")
            if not asset_name or not asset_url:
                continue
            local_path = os.path.join(FILES_DIR, asset_name)
            if not os.path.exists(local_path):
                print(f"Downloading {asset_name}...")
                download_asset(asset_url, local_path)
            local_assets.append({
                "name": asset_name,
                "size_str": format_size(asset_size)
            })
        micron_content = generate_micron_output(release_data, local_assets)
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            f.write(micron_content + "\n")
        print(f"Updated {OUTPUT_FILE} with latest LXMFy release info and local asset links.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main() 