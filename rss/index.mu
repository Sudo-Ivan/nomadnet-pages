#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import feedparser
import trafilatura
import requests
from datetime import datetime, timezone, time
import os
from urllib.parse import urlparse
import json

APP_NAME = "rss_rns"
CACHE_DIR_BASE = os.path.join(os.path.expanduser("~"), ".cache")
CACHE_DIR = os.path.join(CACHE_DIR_BASE, APP_NAME)
CACHE_FILE_NAME = "rss_feed_data.json"
CACHE_FILE_PATH = os.path.join(CACHE_DIR, CACHE_FILE_PATH)
CACHE_LIFETIME_SECONDS = 300
NOMADNET_CLIENT_CACHE_SECONDS = 60
FEEDS_FILE = os.path.join(os.path.dirname(__file__), "feeds.txt")
MAX_ENTRIES_PER_FEED = 5

def load_feeds():
    """Load feed URLs from feeds.txt"""
    try:
        with open(FEEDS_FILE, 'r', encoding='utf-8') as f:
            return [line.strip() for line in f if line.strip() and not line.startswith('#')]
    except Exception:
        return []

def get_feed_domain(url):
    """Extract domain name from URL for display"""
    try:
        return urlparse(url).netloc
    except:
        return url

def fetch_full_text(url):
    """Fetch and extract full text from article URL"""
    try:
        downloaded = trafilatura.fetch_url(url)
        if downloaded:
            text = trafilatura.extract(downloaded, include_comments=False, include_tables=False, output_format='txt')
            if text:
                return text[:500].strip() + "..." if len(text) > 500 else text.strip()
    except Exception:
        pass
    return None

def format_iso_timestamp_for_display(iso_timestamp_str: str) -> str:
    """Formats an ISO timestamp string for display."""
    if not iso_timestamp_str or iso_timestamp_str in ["Unknown time", "Error parsing date"]:
        return iso_timestamp_str
    try:
        dt_object = datetime.fromisoformat(iso_timestamp_str)
        if dt_object.tzinfo is None:
            dt_object = dt_object.replace(tzinfo=timezone.utc)
        else:
            dt_object = dt_object.astimezone(timezone.utc)
        return dt_object.strftime('%Y-%m-%d %H:%M:%S %Z')
    except ValueError:
        return "Invalid ISO date"

def generate_micron_output(feeds_data_from_cache):
    """Generate micron formatted output from cached feeds data"""
    lines = []
    
    current_time = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S %Z')
    lines.append(f"> `!RSS Feed Reader`!")
    lines.append(f"`!Last Updated (UTC):` {current_time} {feeds_data_from_cache.get('data_source_info', '')}")
    lines.append("-")

    processed_feeds_data = feeds_data_from_cache.get('feeds', {})

    if not processed_feeds_data:
        lines.append("No feed data to display.")
        return lines

    for feed_url, feed_content in processed_feeds_data.items():
        if not feed_content or 'entries' not in feed_content:
            continue

        feed_title = feed_content.get('title', get_feed_domain(feed_url))
        lines.append(f">> `!{feed_title}`!")
        
        for entry in feed_content['entries'][:MAX_ENTRIES_PER_FEED]:
            title = entry.get('title', 'No Title')
            link = entry.get('link', '#')
            published_iso = entry.get('published_iso', 'Unknown time') 
            published_display_str = format_iso_timestamp_for_display(published_iso)
            summary = entry.get('summary', '')
            
            lines.append(f"   `!{title}`!")
            lines.append(f"   `!Published:` {published_display_str}")
            
            full_text = fetch_full_text(link)
            if full_text:
                lines.append(f"   {full_text}")
            elif summary:
                 lines.append(f"   {summary[:300]}...")
            
            lines.append(f"   `!Link:` {link}")
            lines.append("-")
    
    return lines

def fetch_and_display_feeds():
    """Main function to fetch and display feeds"""
    output_collector = []
    cached_data_structure = {}
    data_source_info = ""

    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
    except OSError:
        pass

    if os.path.exists(CACHE_FILE_PATH):
        try:
            cache_file_mtime = os.path.getmtime(CACHE_FILE_PATH)
            if (time.time() - cache_file_mtime) < CACHE_LIFETIME_SECONDS:
                with open(CACHE_FILE_PATH, 'r', encoding='utf-8') as f:
                    cached_data_structure = json.load(f)
                data_source_info = "(`*Cached`*)"
                cached_data_structure['data_source_info'] = data_source_info
        except Exception:
            cached_data_structure = {}

    if not cached_data_structure.get('feeds'):
        feeds_to_process = load_feeds()
        processed_feed_details = {}
        data_source_info = "(`*Live data`*)"

        for url in feeds_to_process:
            try:
                parsed_feed_from_lib = feedparser.parse(url)
                if parsed_feed_from_lib.entries:
                    simplified_entries_for_cache = []
                    for entry_from_lib in parsed_feed_from_lib.entries:
                        published_time_struct = entry_from_lib.get('published_parsed') or entry_from_lib.get('updated_parsed')
                        
                        published_iso_str = "Unknown time"
                        if published_time_struct:
                            try:
                                dt_utc = datetime(
                                    published_time_struct.tm_year, published_time_struct.tm_mon, published_time_struct.tm_mday,
                                    published_time_struct.tm_hour, published_time_struct.tm_min, published_time_struct.tm_sec,
                                    tzinfo=timezone.utc
                                )
                                published_iso_str = dt_utc.isoformat()
                            except Exception:
                                published_iso_str = "Error parsing date"

                        simplified_entries_for_cache.append({
                            'title': entry_from_lib.get('title', 'No Title'),
                            'link': entry_from_lib.get('link', '#'),
                            'published_iso': published_iso_str,
                            'summary': entry_from_lib.get('summary', '')[:300]
                        })
                    
                    processed_feed_details[url] = {
                        'title': parsed_feed_from_lib.feed.get('title', get_feed_domain(url)),
                        'entries': simplified_entries_for_cache
                    }
            except Exception as e:
                output_collector.append(f"> `!Error fetching/parsing feed {url}:` {str(e)}")
        
        cached_data_structure = {
            'feeds': processed_feed_details,
            'data_source_info': data_source_info
        }

        if processed_feed_details and os.path.isdir(CACHE_DIR):
            try:
                with open(CACHE_FILE_PATH, 'w', encoding='utf-8') as f:
                    json.dump(cached_data_structure, f)
            except Exception:
                pass

    if cached_data_structure.get('feeds'):
        micron_lines = generate_micron_output(cached_data_structure)
        output_collector.extend(micron_lines)
    else:
        if not any("Error fetching/parsing feed" in line for line in output_collector):
             output_collector.append("> `!No feeds available`!")
             output_collector.append("Ensure feeds.txt is present and contains valid URLs, or check network.")


    final_print_lines = []
    if NOMADNET_CLIENT_CACHE_SECONDS is not None:
        final_print_lines.append(f"#!c={NOMADNET_CLIENT_CACHE_SECONDS}")
    
    final_print_lines.extend(output_collector)
    print("\n".join(final_print_lines))

fetch_and_display_feeds()