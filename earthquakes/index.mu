#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import requests
from datetime import datetime, timezone
import os
import time

APP_NAME = "earthquakes_rns"
CACHE_DIR_BASE = os.path.join(os.path.expanduser("~"), ".cache")
CACHE_DIR = os.path.join(CACHE_DIR_BASE, APP_NAME)
CACHE_FILE_NAME = "all_hour_earthquake_data.json"
CACHE_FILE_PATH = os.path.join(CACHE_DIR, CACHE_FILE_NAME)
CACHE_LIFETIME_SECONDS = 900
NOMADNET_CLIENT_CACHE_SECONDS = 0 

LATEST_DATA_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson"

def format_timestamp_to_utc_string(timestamp_ms: int) -> str:
    """Formats a timestamp in milliseconds to a UTC string."""
    if timestamp_ms is None:
        return "N/A"
    try:
        dt_object = datetime.fromtimestamp(float(timestamp_ms) / 1000, timezone.utc)
        return dt_object.strftime('%Y-%m-%d %H:%M:%S %Z')
    except (ValueError, TypeError):
        return "Invalid Timestamp"

def generate_micron_output(data: dict, data_source_info: str) -> list[str]:
    """Generates micron formatted output from earthquake data."""
    micron_lines = []
    
    metadata = data.get("metadata", {})
    report_title = metadata.get("title", "USGS All Earthquakes, Past Hour")
    generated_ms = metadata.get("generated")
    data_actual_timestamp_str = format_timestamp_to_utc_string(generated_ms) 
    
    micron_lines.append(f"> `!{report_title}`!")
    micron_lines.append(f"`!Data valid as of (UTC):` {data_actual_timestamp_str} {data_source_info}")
    
    source_url_from_data = metadata.get("url")
    display_url = source_url_from_data if source_url_from_data else LATEST_DATA_URL
    micron_lines.append(f"`!Original source feed URL:` {display_url}")
    micron_lines.append("-")

    features = data.get("features", [])
    if not features:
        micron_lines.append("No earthquake features reported in this period.")
        return micron_lines

    for feature in features:
        properties = feature.get("properties", {})
        event_title = properties.get("title", "N/A (No title)")
        event_time_ms = properties.get("time")
        event_time_str = format_timestamp_to_utc_string(event_time_ms)
        
        mag = properties.get("mag")
        mag_str = f"{float(mag):.1f}" if isinstance(mag, (int, float)) or (isinstance(mag, str) and mag.replace('.', '', 1).isdigit()) else "N/A"
        
        place = properties.get("place", "N/A")
        status = properties.get("status", "N/A")
        tsunami = properties.get("tsunami", 0)

        micron_lines.append(f">> `!{event_title}`!")
        micron_lines.append(f"   `!Location:` {place}")
        micron_lines.append(f"   `!Occurred at (UTC):` {event_time_str}")
        micron_lines.append(f"   `!Magnitude:` {mag_str}")
        micron_lines.append(f"   `!Status:` {status}")
        if tsunami == 1:
            micron_lines.append(f"   `!Tsunami Warning:` Yes")
        micron_lines.append("-")
        
    return micron_lines

def fetch_and_display_earthquake_data():
    """Fetches earthquake data, caches it, and displays it in micron format."""
    output_collector = []
    earthquake_data = None
    data_source_info = ""

    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
    except OSError:
        pass

    if os.path.exists(CACHE_FILE_PATH):
        try:
            cache_mtime = os.path.getmtime(CACHE_FILE_PATH)
            if (time.time() - cache_mtime) < CACHE_LIFETIME_SECONDS:
                with open(CACHE_FILE_PATH, 'r', encoding='utf-8') as f:
                    earthquake_data = json.load(f)
                data_source_info = "(`*Cached`*)"
        except json.JSONDecodeError:
            earthquake_data = None 
        except Exception:
            earthquake_data = None

    if earthquake_data is None:
        try:
            response = requests.get(LATEST_DATA_URL, timeout=15)
            response.raise_for_status()
            earthquake_data = response.json()
            data_source_info = "(`*Live data`*)"
            
            if os.path.isdir(CACHE_DIR):
                try:
                    with open(CACHE_FILE_PATH, 'w', encoding='utf-8') as f:
                        json.dump(earthquake_data, f)
                except Exception:
                    pass

        except requests.exceptions.Timeout:
            output_collector.append("> `!Error: Data Fetch Timeout`!")
            output_collector.append(f"Could not retrieve live data from {LATEST_DATA_URL} within 15s.")
        except requests.exceptions.HTTPError as e:
            output_collector.append("> `!Error: HTTP Problem`!")
            output_collector.append(f"Failed to retrieve live data: {e.response.status_code} {e.response.reason}")
        except requests.exceptions.RequestException as e:
            output_collector.append("> `!Error: Network Problem`!")
            output_collector.append(f"Could not retrieve live earthquake data: {e}")
        except json.JSONDecodeError:
            output_collector.append("> `!Error: Data Parsing Problem`!")
            output_collector.append("Could not parse live earthquake data (invalid JSON received).")
        except Exception as e:
            output_collector.append("> `!Error: Unexpected Fetch Issue`!")
            output_collector.append(f"An unexpected error occurred while fetching data: {str(e)}")
    
    if earthquake_data:
        micron_data_lines = generate_micron_output(earthquake_data, data_source_info)
        output_collector.extend(micron_data_lines)
    else:
        if not any("`!Error:" in line for line in output_collector):
            output_collector.append("> `!Error: No Data Available`!")
            output_collector.append("Unable to load earthquake data from cache or live source.")

    final_print_lines = []
    if NOMADNET_CLIENT_CACHE_SECONDS is not None:
        final_print_lines.append(f"#!c={NOMADNET_CLIENT_CACHE_SECONDS}")
    
    final_print_lines.extend(output_collector)
    print("\n".join(final_print_lines))

fetch_and_display_earthquake_data()
