import numpy as np
npz = np.load('model/vhdl_conv_reference_output.npz')
img = npz['input_image']
weights = npz['weights']
biases = npz['biases']
out = npz['output']

row, col = 0, 1
window = img[row:row+3, col:col+3]
flat = window.flatten()
print('Input 3x3 window (row=0,col=1):', window.tolist())

print('\nweights.shape =', weights.shape)
print('biases.shape =', biases.shape)
print('output.shape =', out.shape)

# Extract correct 3x3 per-filter
for f in [1,5]:
    if weights.shape == (3,3,1,8):
        w3 = weights[:,:,0,f]
    elif weights.shape == (8,3,3):
        w3 = weights[f]
    elif weights.shape == (3,3,8):
        w3 = weights[:,:,f]
    else:
        # fallback: try reshape to (8,3,3)
        w3 = np.array(weights).reshape((8,3,3))[f]

    print('\nFilter', f, 'weights 3x3:')
    print(w3)
    b = int(biases[f])
    print('Bias (Q1.6):', b)

    terms = list(zip(flat.tolist(), w3.flatten().tolist()))
    prods = [(a*b) for (a,b) in terms]
    print('\nPer-term (pixel * weight) in Q1.6:')
    for idx,(p,w) in enumerate(terms):
        print(f'  term{idx}: pixel={p} * weight={w} => {p*w}')
    s_q16 = sum(prods)
    print('\nSum Q1.6:', s_q16)
    s_q212 = s_q16 << 6
    print('Sum Q2.12 (<<6):', s_q212)
    bias_q212 = b << 6
    print('Bias Q2.12 (bias<<6):', bias_q212)
    total_q212 = s_q212 + bias_q212
    print('Total Q2.12 (sum+bias):', total_q212)
    total_q16 = total_q212 >> 6
    print('Total Q1.6 after >>6:', total_q16)
    final = max(0, min(127, int(total_q16)))
    print('Final after ReLU/clamp:', final)
    print('Python reference out[row,col,f]:', int(out[row,col,f]))

print('\nVHDL reported for [0,1]: Filter_1=57, Filter_5=79')
