#!/usr/bin/env python3
"""
Diagnose weight packing order by checking first COE address.
"""
import re
from pathlib import Path

WEIGHTS_COE = Path(r"c:\Users\eivin\Documents\Skule\FPGA\dataprosjekt-gr2-FPGA\model\fpga_weights_and_bias\layer_5_dense_weights.coe")

def parse_coe_first_address():
    txt = WEIGHTS_COE.read_text(errors='ignore')
    m = re.search(r"memory_initialization_vector\s*=\s*(.*);", txt, flags=re.S)
    if not m:
        raise RuntimeError('No memory_initialization_vector')
    vec = m.group(1).replace('\n', '').replace('\r', '')
    parts = [p.strip() for p in vec.split(',') if p.strip()]
    return parts[0]  # First address

def hex_to_bytes(hexstr):
    h = re.sub(r'[^0-9A-Fa-f]', '', hexstr)
    if len(h) % 2:
        h = '0' + h
    return [int(h[i:i+2], 16) for i in range(0, len(h), 2)]

# Get first address
first_addr = parse_coe_first_address()
print(f"First COE address (hex): {first_addr[:32]}... ({len(first_addr)} chars)")

# Parse as bytes
b = hex_to_bytes(first_addr)
print(f"Parsed into {len(b)} bytes")

# Convert to signed
signed = [x - 256 if x >= 128 else x for x in b]

print("\nFirst 10 bytes (MSB-first, should be neuron 0-9 for input 0):")
for i in range(min(10, len(signed))):
    print(f"  Byte[{i}] = {b[i]:02X} (unsigned={b[i]}, signed={signed[i]})")

print("\nLast 10 bytes (LSB-last, should be neuron 54-63 for input 0):")
for i in range(max(0, len(signed)-10), len(signed)):
    print(f"  Byte[{i}] = {b[i]:02X} (unsigned={b[i]}, signed={signed[i]})")

# Check if values look reasonable (should be in range -128 to 127, Q1.6 means -2.0 to ~1.98)
reasonable = [s for s in signed if -128 <= s <= 127]
print(f"\n{len(reasonable)}/{len(signed)} bytes in valid signed 8-bit range")

# Statistical check
import statistics
print(f"Mean: {statistics.mean(signed):.2f}")
print(f"StdDev: {statistics.stdev(signed):.2f}")
print(f"Min: {min(signed)}, Max: {max(signed)}")
