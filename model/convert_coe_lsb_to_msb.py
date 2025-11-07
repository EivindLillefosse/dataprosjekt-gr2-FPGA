#!/usr/bin/env python3
import os
import re

def convert_word(word, num_bytes=16):
    # normalize
    w = word.strip()
    if w.startswith('0x') or w.startswith('0X'):
        w = w[2:]
    if len(w) % 2 == 1:
        w = '0' + w
    # pad to num_bytes*2 hex chars
    target_len = num_bytes * 2
    if len(w) < target_len:
        w = w.zfill(target_len)
    # split into bytes
    bytes_list = [w[i:i+2] for i in range(0, len(w), 2)]
    # LSB-first -> bytes_list[0] is MSB? We want to reverse order
    bytes_rev = list(reversed(bytes_list))
    return ''.join(bytes_rev)


def convert_coe(path):
    with open(path, 'r') as f:
        text = f.read()
    m = re.search(r"(memory_initialization_vector\s*=\s*)([^;]+)(;)", text, re.IGNORECASE | re.DOTALL)
    if not m:
        raise RuntimeError('COE vector not found')
    prefix, vec, suffix = m.group(1), m.group(2), m.group(3)
    # split
    parts = [p.strip() for p in vec.replace('\n','').split(',') if p.strip()]
    # determine bytes per word from first word length: len/2
    num_hex = len(parts[0])
    num_bytes = (num_hex + 1) // 2
    print(f'Converting {len(parts)} words, detected {num_bytes} bytes per word')
    newparts = [convert_word(p, num_bytes) for p in parts]
    newvec = ','.join(newparts)
    newtext = text[:m.start(2)] + newvec + text[m.end(2):]
    # backup
    bak = path + '.bak'
    print(f'Writing backup to {bak}')
    with open(bak, 'w') as bf:
        bf.write(text)
    with open(path, 'w') as nf:
        nf.write(newtext)
    print('Converted COE saved:', path)

if __name__ == '__main__':
    target = 'model/fpga_weights_and_bias/layer_2_conv2d_1_weights.coe'
    if not os.path.exists(target):
        target = 'fpga_weights_and_bias/layer_2_conv2d_1_weights.coe'
    print('Target:', target)
    convert_coe(target)
