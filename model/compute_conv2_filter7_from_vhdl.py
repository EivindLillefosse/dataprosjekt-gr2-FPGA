import re
import numpy as np
from pathlib import Path

# Paths (adjust if needed)
root = Path(__file__).resolve().parents[1]
vivado_debug = root / 'vivado_project' / 'CNN.sim' / 'sim_1' / 'behav' / 'xsim' / 'cnn_intermediate_debug.txt'
coe_file = root / 'model' / 'fpga_weights_and_bias' / 'layer_2_conv2d_1_weights.coe'

def parse_pool1_region(vivado_path, row, col, region_size=3, channels=8):
    # Robust line-by-line parse of LAYER1_POOL1_OUTPUT blocks
    lines = vivado_path.read_text().splitlines()
    d = {}
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith('LAYER1_POOL1_OUTPUT:'):
            # parse coordinates
            m = re.search(r"LAYER1_POOL1_OUTPUT:\s*\[(\d+),(\d+)\]", line)
            if m:
                rr = int(m.group(1)); cc = int(m.group(2))
                chans = [0]*channels
                # read following indented lines
                j = i+1
                while j < len(lines) and lines[j].strip().startswith('Filter_'):
                    mm = re.search(r"Filter_(\d+):\s*(-?\d+)", lines[j].strip())
                    if mm:
                        ch_idx = int(mm.group(1)); val = int(mm.group(2))
                        if 0 <= ch_idx < channels:
                            chans[ch_idx] = val
                    j += 1
                d[(rr,cc)] = chans
                i = j
                continue
        i += 1
    # Collect region rows row..row+region_size-1 and cols col..col+region_size-1
    region = []
    for rr in range(row, row+region_size):
        for cc in range(col, col+region_size):
            if (rr,cc) not in d:
                raise ValueError(f"Missing Pool1 debug for {(rr,cc)}")
            region.append(d[(rr,cc)])
    return region

def parse_coe_for_filter(coe_path, filter_idx, kernel_size=3, in_channels=8, num_filters=16):
    # Read hex stream and unpack per address: each address packs num_filters bytes for that (kpos,channel)
    s = coe_path.read_text()
    # find memory_initialization_vector=...; pick inside <> or after =
    m = re.search(r"memory_initialization_vector\s*=\s*([^;]+);", s, re.I | re.S)
    if not m:
        raise ValueError("COE vector not found")
    vec = m.group(1).strip().strip(',')
    # remove commas and whitespace/newlines
    vec = re.sub(r"[\s,]", "", vec)
    # Each address is 128 bits = 32 hex chars? But in this COE they appear as 32-hex substrings separated by commas originally
    # The file uses chunks separated by commas; original grouping likely 32 hex chars per address
    # We'll split into groups of 32 hex chars
    addr_hexs = [vec[i:i+32] for i in range(0, len(vec), 32)]
    # For each addr, the organization is: all 16 filter weights for that (kernel_pos,channel)
    # Each filter weight is one byte (2 hex chars), MSB-first packing per spec -> filter 0 is the high-order byte
    # So for each addr_hex, split into 16 bytes
    kernel = []  # will be list length kernel_size*kernel_size of channel arrays
    for addr in addr_hexs:
        if len(addr) != 32:
            # skip short trailing
            continue
        bytes_list = [addr[i:i+2] for i in range(0, 32, 2)]
        # Convert to signed 8-bit ints
        signed = [np.int8(int(b,16)).item() for b in bytes_list]
        kernel.append(signed)  # length 16
    # kernel now indexed by addr index = kernel_pos * in_channels + channel
    # Build for desired filter: for each kernel_pos (0..K*K-1) collect the int8 for that filter across channels
    K2 = kernel_size*kernel_size
    if len(kernel) < K2 * in_channels:
        raise ValueError("Parsed fewer addresses than expected")
    filter_weights = []
    for kp in range(K2):
        ch_weights = []
        for ch in range(in_channels):
            addr_idx = kp*in_channels + ch
            # signed byte for this filter is at position filter_idx within kernel[addr_idx]
            ch_weights.append(int(kernel[addr_idx][filter_idx]))
        filter_weights.append(ch_weights)
    # reshape to (K, K, C)
    arr = np.array(filter_weights, dtype=np.int32).reshape((kernel_size, kernel_size, in_channels))
    return arr

def compute_conv_at(region, kernel):
    # region: list of 9 channel arrays (each length 8), kernel: (3,3,8)
    # flatten and compute int products
    region_arr = np.array(region, dtype=np.int32).reshape((3,3,8))
    prods = region_arr * kernel
    A = int(prods.sum())
    return region_arr, kernel, prods, A

def main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--row', type=int, default=0)
    p.add_argument('--col', type=int, default=1)
    p.add_argument('--filter', type=int, default=7)
    args = p.parse_args()
    r,c = args.row, args.col
    filt_idx = args.filter
    print(f'Parsing Pool1 region from VHDL debug at conv2 [{r},{c}]...')
    region = parse_pool1_region(vivado_debug, r, c)
    print('Region (row-major 3x3) channels:')
    for i, ch in enumerate(region):
        print(f'pos {i}:', ch)
    print(f'\nParsing COE weights for filter {filt_idx}...')
    kernel = parse_coe_for_filter(coe_file, filt_idx)
    print('Kernel shape:', kernel.shape)
    print('Kernel (per kernel_pos rows):')
    for kp in range(9):
        print(f'kp {kp}:', kernel.reshape(-1,8)[kp])
    region_arr, kernel_arr, prods, A = compute_conv_at(region, kernel)
    print('\nPer-element products (3x3x8):')
    print(prods.reshape(9,8))
    print('\nAccumulator A =', A)
    shifted = (A + (1<<5)) >> 6  # emulate arithmetic shift with rounding: add 32 then >>6
    print('Shifted (with rounding) =', shifted)
    print('Scaled float =', shifted/64.0)

if __name__ == '__main__':
    main()
