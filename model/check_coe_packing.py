#!/usr/bin/env python3
import os
import re

def parse_coe(filename):
    with open(filename, 'r') as f:
        text = f.read()
    # find memory_initialization_vector=...;
    m = re.search(r"memory_initialization_vector\s*=\s*([^;]+);", text, re.IGNORECASE | re.DOTALL)
    if not m:
        raise ValueError('COE vector not found')
    vec = m.group(1)
    # remove whitespace and newlines
    vec = vec.replace('\n','').replace('\r','').strip()
    # split by commas
    parts = [p.strip() for p in vec.split(',') if p.strip()]
    return parts


def hexword_to_bytes(hexword, num_filters=16):
    # normalize: remove possible 0x prefix
    hw = hexword
    if hw.startswith('0x') or hw.startswith('0X'):
        hw = hw[2:]
    # ensure even length
    if len(hw) % 2 == 1:
        hw = '0' + hw
    # pad to num_filters bytes if shorter
    needed = num_filters*2
    if len(hw) < needed:
        hw = hw.zfill(needed)
    # interpret as big integer
    val = int(hw, 16)
    # produce LSB-first bytes: byte0 is least significant
    lsb_bytes = [(val >> (8*i)) & 0xFF for i in range(num_filters)]
    # MSB-first: byte0 is most significant
    msb_bytes = [(val >> (8*(num_filters-1-i))) & 0xFF for i in range(num_filters)]
    return lsb_bytes, msb_bytes


def to_signed8(b):
    return b - 256 if b & 0x80 else b


def print_filter(filter_arr_q, title):
    print(title)
    for kr in range(3):
        for kc in range(3):
            row = [filter_arr_q[kr][kc][ch] for ch in range(8)]
            print(f"({kr},{kc}): ", row)
    print()


if __name__ == '__main__':
    coe_path = 'model/fpga_weights_and_bias/layer_2_conv2d_1_weights.coe'
    if not os.path.exists(coe_path):
        coe_path = 'fpga_weights_and_bias/layer_2_conv2d_1_weights.coe'
    print('Using COE:', coe_path)
    parts = parse_coe(coe_path)
    print('Number of addresses (hex words):', len(parts))
    # Conv2 depth = 3*3*8 = 72 addresses expected
    print('First 6 hex words (truncated):')
    for i,p in enumerate(parts[:6]):
        print(i, p[:64])
    # build filter0 array from parts
    depth = 3*3*8
    if len(parts) < depth:
        print('Warning: fewer addresses than expected:', len(parts), 'vs', depth)
    filter0_bytes_lsb = []
    filter0_bytes_msb = []
    for addr, word in enumerate(parts[:depth]):
        lsb, msb = hexword_to_bytes(word, num_filters=16)
        # filter0 as LSB-first => lsb[0]
        filter0_bytes_lsb.append(lsb[0])
        # filter0 as MSB-first => msb[0]
        filter0_bytes_msb.append(msb[0])
    # reshape into 3x3x8
    import numpy as np
    f0_lsb = np.zeros((3,3,8), dtype=int)
    f0_msb = np.zeros((3,3,8), dtype=int)
    for addr in range(min(len(filter0_bytes_lsb), depth)):
        kh = addr // (3*8)
        kw = (addr // 8) % 3
        c = addr % 8
        f0_lsb[kh, kw, c] = to_signed8(filter0_bytes_lsb[addr])
        f0_msb[kh, kw, c] = to_signed8(filter0_bytes_msb[addr])
    # print both as Q1.6 floats
    scale = 64.0
    print('\nFilter 0 (LSB-first interpretation) as signed int8 and float Q1.6:')
    for kr in range(3):
        for kc in range(3):
            ints = [int(x) for x in f0_lsb[kr,kc,:]]
            floats = [x/scale for x in ints]
            print(f"({kr},{kc}) ints: {ints}  floats: {[f'{v:.5f}' for v in floats]}")
    print('\nFilter 0 (MSB-first interpretation) as signed int8 and float Q1.6:')
    for kr in range(3):
        for kc in range(3):
            ints = [int(x) for x in f0_msb[kr,kc,:]]
            floats = [x/scale for x in ints]
            print(f"({kr},{kc}) ints: {ints}  floats: {[f'{v:.5f}' for v in floats]}")
    # Save to files for inspection
    np.savez('model/conv2_filter0_coe_parsed.npz', lsb=f0_lsb, msb=f0_msb)
    print('\nSaved parsed arrays to model/conv2_filter0_coe_parsed.npz')
