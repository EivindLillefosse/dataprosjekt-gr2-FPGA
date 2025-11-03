# Debug Python reference calculation for position [0,1], filter 1
import numpy as np

# Load data
data = np.load('model/vhdl_conv_reference_output.npz')
input_image = data['input_image']
weights = data['weights']
biases = data['biases']

# Position [0,1] with stride 1
out_r, out_c = 0, 1
f = 1
base_r = out_r * 1  # stride = 1
base_c = out_c * 1

print(f'Computing output position [{out_r},{out_c}] filter {f}')
print(f'Input region: [{base_r}:{base_r+3}, {base_c}:{base_c+3}]')
print(f'Input values:')
print(input_image[base_r:base_r+3, base_c:base_c+3])

# Replicate the Python reference calculation
acc_q2_12 = 0
for kr in range(3):
    for kc in range(3):
        pixel = input_image[base_r + kr, base_c + kc]
        weight = weights[kr, kc, 0, f]
        product_q1_6 = weight * pixel
        product_q2_12 = product_q1_6 << 6
        acc_q2_12 += product_q2_12
        print(f'  [{kr},{kc}]: pixel={pixel}, weight={weight}, prod={product_q1_6}, acc_q2_12={acc_q2_12}')

bias_q2_12 = biases[f] << 6
acc_q2_12 += bias_q2_12
print(f'After bias: acc_q2_12 = {acc_q2_12}')

acc_q2_12 = max(-32768, min(32767, acc_q2_12))
scaled_q1_6 = acc_q2_12 >> 6
scaled_q1_6 = max(-128, min(127, scaled_q1_6))
relu_output = max(0, scaled_q1_6)

print(f'Scaled: {scaled_q1_6}, ReLU: {relu_output}')
print(f'Actual Python output at [0,1][1]: {data["output"][0,1,1]}')
