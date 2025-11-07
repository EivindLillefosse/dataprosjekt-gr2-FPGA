#!/usr/bin/env python3
import re
import numpy as np
import os

def parse_coe_parts(path):
    with open(path,'r') as f:
        t=f.read()
    m=re.search(r"memory_initialization_vector\s*=\s*([^;]+);",t,re.IGNORECASE|re.DOTALL)
    if not m:
        raise RuntimeError('no vector')
    vec=m.group(1).replace('\n','').replace('\r','').strip()
    parts=[p.strip() for p in vec.split(',') if p.strip()]
    return parts

def hexword_bytes(word, num_filters):
    w=word
    if w.startswith('0x') or w.startswith('0X'):
        w=w[2:]
    if len(w)%2==1:
        w='0'+w
    needed=num_filters*2
    if len(w)<needed:
        w=w.zfill(needed)
    val=int(w,16)
    lsb=[(val>>(8*i))&0xFF for i in range(num_filters)]
    msb=[(val>>(8*(num_filters-1-i)))&0xFF for i in range(num_filters)]
    return lsb,msb

def to_signed8(b):
    return b-256 if b&0x80 else b

if __name__=='__main__':
    path='model/fpga_weights_and_bias/layer_0_conv2d_weights.coe'
    if not os.path.exists(path):
        path='fpga_weights_and_bias/layer_0_conv2d_weights.coe'
    print('Using',path)
    parts=parse_coe_parts(path)
    print('Words:',len(parts))
    # expected depth for layer0: 3*3*1=9 addresses
    for i,p in enumerate(parts[:6]):
        print(i,p)
    num_filters=8
    filter0_lsb=[]
    filter0_msb=[]
    for addr,w in enumerate(parts[:3*3*1]):
        lsb,msb=hexword_bytes(w,num_filters)
        filter0_lsb.append(lsb[0])
        filter0_msb.append(msb[0])
    # reshape to 3x3x1
    f_lsb=np.array(filter0_lsb,dtype=int).reshape(3,3,1)
    f_msb=np.array(filter0_msb,dtype=int).reshape(3,3,1)
    print('\nFilter0 LSB-first bytes (signed->float Q1.6):')
    for r in range(3):
        for c in range(3):
            val=to_signed8(f_lsb[r,c,0])
            print((r,c),val,val/64.0)
    print('\nFilter0 MSB-first bytes (signed->float Q1.6):')
    for r in range(3):
        for c in range(3):
            val=to_signed8(f_msb[r,c,0])
            print((r,c),val,val/64.0)

    # compare to Python NPZ if present
    if os.path.exists('model/intermediate_values.npz'):
        npz=np.load('model/intermediate_values.npz')
        if 'layer_0_filter_0' in npz:
            py=npz['layer_0_filter_0']
            # py contains float outputs (not weights). So instead inspect saved weights? Try to get from model export: check model/fpga_weights_and_bias file for layer_0_conv2d_weights.coe should reflect exporter.
            print('\nNote: Python NPZ stores filter outputs, not weights. To compare, check CNN.py exporter or saved weights in model/ directory if available.')
    print('\nDone')
