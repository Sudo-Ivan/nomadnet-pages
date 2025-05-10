#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import requests
from datetime import datetime, timezone
import os
import time
import hashlib

APP_NAME = "lxmfy_release_viewer"
CACHE_DIR_BASE = os.path.join(os.path.expanduser("~"), ".cache")
CACHE_DIR = os.path.join(CACHE_DIR_BASE, APP_NAME)
CACHE_FILE_NAME = "latest_release_info.json"
CACHE_FILE_PATH = os.path.join(CACHE_DIR, CACHE_FILE_NAME)
CACHE_LIFETIME_SECONDS = 12 * 3600
NOMADNET_CLIENT_CACHE_SECONDS = 300

NODE_HASH = "486efb02ad0cdb01540f1d7178ac668e"
GITHUB_REPO_OWNER = "lxmfy"
GITHUB_REPO_NAME = "LXMFy"
LATEST_RELEASE_API_URL = f"https://api.github.com/repos/{GITHUB_REPO_OWNER}/{GITHUB_REPO_NAME}/releases/latest"

STORAGE_FILES_DIR = "/home/dev/.nomadnetwork/storage/files/"
RETICULUM_FILES_BASE_PATH = "/file/"

def calculate_sha256(file_path: str) -> str | None:
    """Calculates the SHA-256 hash of a file."""
    sha256_hash = hashlib.sha256()
    try:
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except FileNotFoundError:
        return None
    except Exception:
        return None

def download_asset(asset_url: str, target_path: str, asset_name: str) -> tuple[bool, str]:
    """Downloads an asset. Returns (success_status, message)."""
    try:
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        response = requests.get(asset_url, stream=True, timeout=60)
        response.raise_for_status()
        with open(target_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        return True, f"Successfully downloaded {asset_name}."
    except requests.exceptions.Timeout:
        return False, f"Timeout downloading {asset_name}."
    except requests.exceptions.HTTPError as e:
        return False, f"HTTP error downloading {asset_name}: {e.response.status_code}"
    except requests.exceptions.RequestException as e:
        return False, f"Network error downloading {asset_name}: {str(e)[:100]}"
    except OSError as e:
        return False, f"OS error saving {asset_name} to {target_path}: {str(e)[:100]}"
    except Exception as e:
        return False, f"Unexpected error downloading {asset_name}: {str(e)[:100]}"

def format_timestamp_from_iso(iso_timestamp_str: str) -> str:
    """Converts an ISO 8601 timestamp string to a human-readable UTC string."""
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
    """Converts a size in bytes to a human-readable string (KB, MB, GB)."""
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

def generate_micron_output(release_data: dict, processed_assets: list, data_source_info: str, download_messages: list) -> list[str]:
    """Generates micron formatted output with local Reticulum links."""
    micron_lines = []

    release_name = release_data.get("name", "N/A")
    tag_name = release_data.get("tag_name", "N/A")
    published_at_iso = release_data.get("published_at")
    published_at_str = format_timestamp_from_iso(published_at_iso)
    release_notes = release_data.get("body", "No release notes provided.")

    micron_lines.append(f"> `!Latest LXMFy Release: {release_name} ({tag_name})`!")
    micron_lines.append(f"`!Published (UTC):` {published_at_str} {data_source_info}")
    micron_lines.append("-")

    if download_messages:
        micron_lines.append(">> `!Download Status Updates`!")
        for msg in download_messages:
            micron_lines.append(f"  {msg}")
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

    if processed_assets:
        micron_lines.append(">> `!Assets (Local Reticulum Links)`!")
        for asset in processed_assets:
            asset_name = asset.get("name", "N/A")
            asset_size_str = asset.get("size_str", "N/A")
            
            micron_lines.append(f"  `!File:` {asset_name}")
            micron_lines.append(f"  `!Size:` {asset_size_str}")
            if asset.get("is_local"):
                rns_link = f"`_`[{asset_name}`{NODE_HASH}:/file/{asset_name}]`_"
                micron_lines.append(f"  `!Link:` {rns_link}")
            elif asset.get("download_attempted") and not asset.get("download_successful"):
                micron_lines.append(f"  `!Status:` Download failed. Check server logs or messages above.")
            else:
                micron_lines.append(f"  `!Status:` File not available locally or error in processing.")
            micron_lines.append("  -") 
        micron_lines.append("-")
    else:
        micron_lines.append(">> `!Assets`!")
        micron_lines.append("  No assets found for this release or error processing them.")
        micron_lines.append("-")
        
    return micron_lines

def fetch_and_display_release_info():
    """Fetches, downloads assets, and displays latest release info."""
    output_collector = []
    release_info_api = None
    data_source_info = ""
    download_messages = []

    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
    except OSError as e:
        download_messages.append(f"# Notice: Could not create cache directory {CACHE_DIR}: {e}")
        pass 

    if os.path.exists(CACHE_FILE_PATH):
        try:
            cache_mtime = os.path.getmtime(CACHE_FILE_PATH)
            if (time.time() - cache_mtime) < CACHE_LIFETIME_SECONDS:
                with open(CACHE_FILE_PATH, 'r', encoding='utf-8') as f:
                    release_info_api = json.load(f)
                data_source_info = "(`*Cached API Data`*)"
        except Exception:
            release_info_api = None

    if release_info_api is None:
        try:
            headers = {"Accept": "application/vnd.github.v3+json"}
            response = requests.get(LATEST_RELEASE_API_URL, headers=headers, timeout=15)
            response.raise_for_status()
            release_info_api = response.json()
            data_source_info = "(`*Live API Data`*)"
            if os.path.isdir(CACHE_DIR):
                try:
                    with open(CACHE_FILE_PATH, 'w', encoding='utf-8') as f:
                        json.dump(release_info_api, f)
                except Exception:
                     download_messages.append(f"# Notice: Could not write to API cache file {CACHE_FILE_PATH}.")
        except requests.exceptions.Timeout:
            output_collector.append("> `!Error: GitHub API Timeout`!")
        except requests.exceptions.HTTPError as e:
            output_collector.append("> `!Error: GitHub API HTTP Problem`!")
        except requests.exceptions.RequestException as e:
            output_collector.append("> `!Error: Network Problem with API`!")
        except json.JSONDecodeError:
            output_collector.append("> `!Error: API Data Parsing Problem`!")
        except Exception as e:
            output_collector.append(f"> `!Error: Unexpected API Fetch Issue: {str(e)[:100]}`!")

    processed_assets_for_display = []
    if release_info_api and "assets" in release_info_api:
        try:
            os.makedirs(STORAGE_FILES_DIR, exist_ok=True)
        except OSError as e:
            download_messages.append(f"> `!Critical Error:` Could not create storage directory {STORAGE_FILES_DIR}: {e}. Downloads will fail.")

        for asset_api_data in release_info_api.get("assets", []):
            asset_name = asset_api_data.get("name")
            asset_download_url = asset_api_data.get("browser_download_url")
            asset_item_for_display = {
                "name": asset_name,
                "size_str": format_size(asset_api_data.get("size")),
                "is_local": False,
                "sha256_hash": None,
                "download_attempted": False,
                "download_successful": False
            }

            if not asset_name or not asset_download_url:
                download_messages.append(f"# Skipping asset with missing name or URL: {asset_api_data.get('id', 'Unknown ID')}")
                processed_assets_for_display.append(asset_item_for_display)
                continue

            target_local_path = os.path.join(STORAGE_FILES_DIR, asset_name)
            asset_item_for_display["local_path"] = target_local_path

            if os.path.exists(target_local_path):
                asset_item_for_display["is_local"] = True
                asset_item_for_display["sha256_hash"] = calculate_sha256(target_local_path)
                if not asset_item_for_display["sha256_hash"]:
                     download_messages.append(f"# Warning: Could not hash existing local file: {asset_name}")
            elif os.access(STORAGE_FILES_DIR, os.W_OK):
                asset_item_for_display["download_attempted"] = True
                success, msg = download_asset(asset_download_url, target_local_path, asset_name)
                download_messages.append(msg)
                asset_item_for_display["download_successful"] = success
                if success:
                    asset_item_for_display["is_local"] = True
                    asset_item_for_display["sha256_hash"] = calculate_sha256(target_local_path)
                    if not asset_item_for_display["sha256_hash"]:
                        download_messages.append(f"# Warning: Could not hash newly downloaded file: {asset_name}")
            else:
                download_messages.append(f"# Notice: Cannot write to {STORAGE_FILES_DIR}, skipping download for {asset_name}.")
            
            processed_assets_for_display.append(asset_item_for_display)
    
    if release_info_api:
        micron_data_lines = generate_micron_output(release_info_api, processed_assets_for_display, data_source_info, download_messages)
        output_collector.extend(micron_data_lines)
    else:
        if not any("`!Error:" in line for line in output_collector):
            output_collector.append("> `!Error: No Release Data Available`!")
            output_collector.append("Unable to load or fetch latest LXMFy release information from GitHub API.")

    final_print_lines = []
    if NOMADNET_CLIENT_CACHE_SECONDS is not None:
        final_print_lines.append(f"#!c={NOMADNET_CLIENT_CACHE_SECONDS}")
    
    final_print_lines.extend(output_collector)
    print("\n".join(final_print_lines))

if __name__ == "__main__":
    fetch_and_display_release_info()
