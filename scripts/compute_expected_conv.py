#!/usr/bin/env python3
"""Compute expected integer convolution outputs from COE hex for a 3x3 patch.
"""
import struct

# COE memory_initialization_vector (9 addresses, each 64-bit hex)
hex_words = [
    "17E804F706F7F8F5",
    "16F614FC09EFED0E",
    "10FA19F6F0EFFEF5",
    "020512F31615F116",
    "0E01FDF813FD0508",
    "F6FB11FDE9040405",
    "04130211140604FE",
    "E711FF08FC0C0D0A",
    "EB05FC07F401F4F2",
]

# Biases as exported (hex bytes): 00,09,00,00,07,00,00,04
biases = [0x00, 0x09, 0x00, 0x00, 0x07, 0x00, 0x00, 0x04]

# Inputs for output position [0,1] (kernel positions (0,0)..(2,2))
inputs = [2,3,4,3,4,5,4,5,6]

def word_to_bytes_le(hexstr):
    # hex string represents full 64-bit word in big-endian text; LSB is last byte
    w = int(hexstr, 16)
    # extract bytes little-endian: byte0 = LSB
    bs = []
    for i in range(8):
        bs.append((w >> (8*i)) & 0xFF)
    return bs

# Build weight matrix: addr x filter
weights = []
for hw in hex_words:
    bs = word_to_bytes_le(hw)
    # interpret each byte as signed int8
    weights.append([b - 256 if b > 127 else b for b in bs])

# Also build big-endian interpretation (MSB = filter0)
weights_be = []
for hw in hex_words:
    w = int(hw, 16)
    bs_be = []
    for i in range(8):
        shift = (7 - i) * 8
        b = (w >> shift) & 0xFF
        bs_be.append(b - 256 if b > 127 else b)
    weights_be.append(bs_be)

# Transpose to get per-filter list across 9 kernel positions
filters = list(zip(*weights))  # 8 tuples each of length 9

print('\nPer-filter weights (little-endian, kernel positions 0..8):')
for i,w in enumerate(filters):
    print(f'Filter {i}:', list(w))

print("Inputs (kernel order 0..8):", inputs)
print("Biases (int Q1.6):", biases)
print()

expected = []
for f_idx, wlist in enumerate(filters):
    s = 0
    for k, w in enumerate(wlist):
        s += w * inputs[k]
    s += biases[f_idx]
    expected.append(s)

# Compute big-endian-based expected values
filters_be = list(zip(*weights_be))
expected_be = []
for f_idx, wlist in enumerate(filters_be):
    s = 0
    for k, w in enumerate(wlist):
        s += w * inputs[k]
    s += biases[f_idx]
    expected_be.append(s)

print("Computed integer outputs (sum w*pixel + bias):")
for i,v in enumerate(expected):
    print(f"Filter {i}: {v}")

vivado_printed = [61,0,43,0,16,396,138,0]
print() 
print("Vivado printed:")
for i,v in enumerate(vivado_printed):
    print(f"Filter {i}: {v}")

print() 
print("Difference (computed - vivado):")
for i,(c,v) in enumerate(zip(expected, vivado_printed)):
    print(f"Filter {i}: {c - v}")

print("\nComputed using BIG-ENDIAN (MSB=filter0):")
for i,v in enumerate(expected_be):
    print(f"Filter {i}: {v}")

print("\nDifference BE (computed_be - vivado):")
for i,(c,v) in enumerate(zip(expected_be, vivado_printed)):
    print(f"Filter {i}: {c - v}")
