#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import re
import json
from datetime import datetime

NODE_HASH = "486efb02ad0cdb01540f1d7178ac668e"
CONTENT_DIR = os.path.join(os.path.dirname(__file__), "content")
CACHE_LIFETIME = 300

def ensure_content_dir():
    os.makedirs(CONTENT_DIR, exist_ok=True)

def convert_markdown_to_micron(markdown_text):
    lines = markdown_text.split('\n')
    micron_lines = []
    in_code_block = False
    in_list = False
    list_indent = 0
    for line in lines:
        if not line.strip():
            if in_list:
                in_list = False
            micron_lines.append("")
            continue
        if line.startswith('```'):
            in_code_block = not in_code_block
            if in_code_block:
                micron_lines.append("`=")
            else:
                micron_lines.append("``")
            continue
        if in_code_block:
            micron_lines.append(line)
            continue
        heading_match = re.match(r'^(#{1,6})\s+(.+)$', line)
        if heading_match:
            level = len(heading_match.group(1))
            text = heading_match.group(2)
            micron_lines.append(f"{'>' * level} `!{text}`!")
            continue
        list_match = re.match(r'^(\s*)[*-]\s+(.+)$', line)
        if list_match:
            current_indent = len(list_match.group(1))
            text = list_match.group(2)
            if not in_list or current_indent != list_indent:
                in_list = True
                list_indent = current_indent
            micron_lines.append(f"{'  ' * (current_indent // 2)}* {text}")
            continue
        line = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'`_`[\1`\2]`_', line)
        line = re.sub(r'\*\*([^*]+)\*\*', r'`!\1`!', line)
        line = re.sub(r'\*([^*]+)\*', r'`*\1`*', line)
        if re.match(r'^[-*_]{3,}$', line):
            micron_lines.append("-")
            continue
        micron_lines.append(line)
    return '\n'.join(micron_lines)

def get_markdown_files():
    markdown_files = []
    for root, _, files in os.walk(CONTENT_DIR):
        for file in files:
            if file.endswith('.md'):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, CONTENT_DIR)
                markdown_files.append({
                    'path': rel_path,
                    'full_path': full_path,
                    'modified': os.path.getmtime(full_path)
                })
    return markdown_files

def generate_micron_page(markdown_path):
    try:
        with open(markdown_path, 'r', encoding='utf-8') as f:
            content = f.read()
        return convert_markdown_to_micron(content)
    except Exception as e:
        return f"> `!Error reading file`!\n{str(e)}"

def generate_index():
    markdown_files = get_markdown_files()
    markdown_files.sort(key=lambda x: x['modified'], reverse=True)
    micron_lines = []
    micron_lines.append("> `!Blog Posts`!")
    micron_lines.append("-")
    for file_info in markdown_files:
        rel_path = file_info['path']
        title = os.path.splitext(os.path.basename(rel_path))[0].replace('-', ' ').title()
        date = datetime.fromtimestamp(file_info['modified']).strftime('%Y-%m-%d')
        micron_url = f"{NODE_HASH}:/page/blog/" + os.path.splitext(rel_path)[0].replace(os.sep, '/') + ".mu"
        micron_lines.append(f"`_`[{title}`{micron_url}]`_")
        micron_lines.append(f"`*Published:* {date}")
        micron_lines.append("-")
    return '\n'.join(micron_lines)

def main():
    ensure_content_dir()
    request_path = os.environ.get('REQUEST_PATH', '/')
    if request_path in ['/', '/blog/', '/blog/index.mu', '', '/page/blog/', '/page/blog/index.mu']:
        content = generate_index()
    else:
        if request_path.startswith('/page/blog/'):
            post_path = request_path[len('/page/blog/'):].replace('.mu', '.md')
        elif request_path.startswith('/blog/'):
            post_path = request_path[len('/blog/'):].replace('.mu', '.md')
        else:
            post_path = request_path.replace('.mu', '.md').lstrip('/')
        full_path = os.path.join(CONTENT_DIR, post_path)
        if os.path.isdir(full_path):
            content = generate_index()
        elif os.path.exists(full_path):
            content = generate_micron_page(full_path)
        else:
            content = "> `!Error: Post not found`!"
    print(f"#!c={CACHE_LIFETIME}")
    print(content)

if __name__ == "__main__":
    main()
