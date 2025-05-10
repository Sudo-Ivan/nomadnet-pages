#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess
import re
from datetime import datetime, timezone

def get_rnstatus():
    """Execute rnstatus command and return its output"""
    try:
        result = subprocess.run(['rnstatus'], capture_output=True, text=True)
        return result.stdout
    except Exception as e:
        return f"Error executing rnstatus: {str(e)}"

def format_traffic(traffic_str):
    """Format traffic string to be more readable"""
    parts = traffic_str.strip().split()
    if len(parts) >= 2:
        return f"{parts[0]} {parts[1]}"
    return traffic_str

def parse_rnstatus(output):
    """Parse rnstatus output and format it for micron display"""
    lines = []
    
    current_time = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S %Z')
    lines.append(f"> `!Reticulum Network Status`!")
    lines.append(f"`!Generated at (UTC):` {current_time}")
    lines.append("-")

    sections = output.split('\n\n')
    
    for section in sections:
        if not section.strip():
            continue
            
        section_lines = section.strip().split('\n')
        if not section_lines:
            continue
            
        lines.append(f">> `!{section_lines[0]}`!")
        
        for line in section_lines[1:]:
            if not line.strip():
                continue
                
            if 'Traffic' in line:
                parts = line.split('Traffic')
                if len(parts) > 1:
                    lines.append(f"   `!Traffic:`")
                    traffic_lines = parts[1].strip().split('\n')
                    for t_line in traffic_lines:
                        if t_line.strip():
                            formatted = format_traffic(t_line)
                            lines.append(f"      {formatted}")
            else:
                if ':' in line:
                    key, value = line.split(':', 1)
                    lines.append(f"   `!{key.strip()}:` {value.strip()}")
                else:
                    lines.append(f"   {line.strip()}")
        
        lines.append("-")
    
    return lines

def main():
    """Main function to fetch and display status"""
    status_output = get_rnstatus()
    formatted_lines = parse_rnstatus(status_output)
    
    print("#!c=60")
    print("\n".join(formatted_lines))

if __name__ == "__main__":
    main()