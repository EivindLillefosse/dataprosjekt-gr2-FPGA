#!/usr/bin/env python3
import numpy as np
import os, re

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

# create VHDL test image (same as CNN.py)
def create_test_image_28x28():
    test_image = np.zeros((28,28), dtype=np.uint8)
    for i in range(28):
        for j in range(28):
            test_image[i,j] = (i + j + 1) % 256
    return test_image

if __name__=='__main__':
    coe_path='model/fpga_weights_and_bias/layer_0_conv2d_weights.coe'
    if not os.path.exists(coe_path):
        coe_path='fpga_weights_and_bias/layer_0_conv2d_weights.coe'
    parts=parse_coe_parts(coe_path)
    # layer0 depth = 3*3*1 = 9
    num_filters=8
    f0_lsb=[]; f0_msb=[]
    for addr,w in enumerate(parts[:9]):
        lsb,msb=hexword_bytes(w,num_filters)
        f0_lsb.append(lsb[0])
        f0_msb.append(msb[0])
    f0_lsb=np.array(f0_lsb,dtype=int).reshape(3,3,1)
    f0_msb=np.array(f0_msb,dtype=int).reshape(3,3,1)
    # convert to signed and to float Q1.6
    f0_lsb_signed = np.vectorize(lambda x: x-256 if x&0x80 else x)(f0_lsb)
    f0_msb_signed = np.vectorize(lambda x: x-256 if x&0x80 else x)(f0_msb)
    f0_lsb_float = f0_lsb_signed.astype(float)/64.0
    f0_msb_float = f0_msb_signed.astype(float)/64.0

    # load bias for layer0 if available
    bias_path='model/fpga_weights_and_bias/layer_0_conv2d_biases.coe'
    bias_val=None
    if os.path.exists(bias_path):
        with open(bias_path,'r') as f:
            t=f.read()
        vec=t.split('memory_initialization_vector=')[-1].split(';')[0]
        partsb=[p.strip() for p in vec.split(',') if p.strip()]
        b0=int(partsb[0],16)
        if b0 & 0x80:
            b0 = b0 - 256
        bias_val = b0/64.0

    # create test image and extract patch [0:3,0:3]
    img=create_test_image_28x28().astype(float)
    patch=img[0:3,0:3]
    # conv1 multiply: sum(patch * weights) + bias
    sum_lsb=0.0
    sum_msb=0.0
    for kr in range(3):
        for kc in range(3):
            w_l = f0_lsb_float[kr,kc,0]
            w_m = f0_msb_float[kr,kc,0]
            p = patch[kr,kc]
            sum_lsb += p * w_l
            sum_msb += p * w_m
    if bias_val is not None:
        sum_lsb += bias_val
        sum_msb += bias_val

    print('Conv1 [0,0] Filter0 using COE LSB-first weights:', sum_lsb)
    print('Conv1 [0,0] Filter0 using COE MSB-first weights:', sum_msb)

    # compare to python NPZ reference if present
    if os.path.exists('model/intermediate_values.npz'):
        npz=np.load('model/intermediate_values.npz')
        if 'layer_0_filter_0' in npz:
            py=npz['layer_0_filter_0']
            print('Python NPZ layer_0_filter_0[0,0]:', py[0,0])
    print('Done')
