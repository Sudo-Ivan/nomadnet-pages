#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import re

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

CONTENT_DIR = os.path.join(os.path.dirname(__file__), "content")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "blog")

for root, _, files in os.walk(CONTENT_DIR):
    for file in files:
        if file.endswith('.md'):
            md_path = os.path.join(root, file)
            rel_path = os.path.relpath(md_path, CONTENT_DIR)
            mu_path = os.path.join(OUTPUT_DIR, os.path.splitext(rel_path)[0] + ".mu")
            os.makedirs(os.path.dirname(mu_path), exist_ok=True)
            with open(md_path, 'r', encoding='utf-8') as f:
                md_content = f.read()
            mu_content = convert_markdown_to_micron(md_content)
            with open(mu_path, 'w', encoding='utf-8') as f:
                f.write(mu_content + "\n") 