import numpy as np
import tensorflow as tf

npz = np.load('model/intermediate_values.npz', allow_pickle=True)
pool1 = npz['layer_1_output']
conv2 = npz['layer_2_output']
print('conv2[0,0,1] float:', conv2[0,0,1])

mdl = tf.keras.models.load_model('model/saved_model')
conv2_layer = None
for l in mdl.layers:
    if hasattr(l, 'kernel') and l.kernel is not None:
        ks = l.kernel.shape
n_found = 0
for l in mdl.layers:
    if hasattr(l, 'kernel') and l.kernel is not None:
        ks = l.kernel.shape
        # kernel shape (h,w,in_ch,out_ch)
        if len(ks) == 4 and ks[0] == 3 and ks[1] == 3 and ks[2] == 8 and ks[3] == 16:
            conv2_layer = l
            n_found += 1
            break
if conv2_layer is None:
    print('conv2 layer not found by shape, listing conv layers:')
    for i,l in enumerate(mdl.layers):
        if hasattr(l, 'kernel') and l.kernel is not None:
            print(i, l.name, l.kernel.shape)
    raise SystemExit('conv2 not found')
print('Using layer:', conv2_layer.name)
weights, bias = conv2_layer.get_weights()
print('weights shape', weights.shape, 'bias shape', bias.shape)

filter_idx = 1
region = pool1[0:3,0:3,:]
kernel = weights[:,:,:,filter_idx]

np.set_printoptions(precision=8, suppress=True)
print('\nRegion (float) per channel slice:')
for ch in range(region.shape[2]):
    print('ch', ch)
    print(region[:,:,ch])
    print()
print('Kernel (float) per channel slice:')
for ch in range(kernel.shape[2]):
    print('ch', ch)
    print(kernel[:,:,ch])
    print()

# float conv details
prod = region * kernel
sumprod = prod.sum()
print('\nFloat sumprod =', sumprod)
print('bias =', bias[filter_idx])
print('final float =', sumprod + bias[filter_idx])

# integer Q1.6 emulation
scale = 64
r_q = np.round(region * scale).astype(int)
k_q = np.round(kernel * scale).astype(int)
int_prods = r_q * k_q

print('\nregion_q flatten:', r_q.flatten())
print('kernel_q flatten:', k_q.flatten())
print('int_prods flatten:', int_prods.flatten())
A = int_prods.sum()
print('Accumulator A =', A)
shifted = A // 64
print('Shifted (A//64) =', shifted)
print('bias_q =', int(round(bias[filter_idx]*scale)))
print('biased =', shifted + int(round(bias[filter_idx]*scale)))
print('biased float =', (shifted + int(round(bias[filter_idx]*scale)))/scale)

# Also print signed 16-bit representation of A and biased
def to_signed(val, bits):
    mask = (1 << bits) - 1
    v = val & mask
    if v & (1 << (bits-1)):
        v = v - (1<<bits)
    return v

print('\nSigned 32-bit A:', A)
print('A as signed 16-bit:', to_signed(A, 16))
print('biased as signed 16-bit:', to_signed(shifted + int(round(bias[filter_idx]*scale)), 16))
