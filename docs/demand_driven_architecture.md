# Demand-Driven CNN Architecture

## Overview
The reverse position calculator enables a **pull-based dataflow** where each layer requests exactly what it needs from upstream layers.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Final Output Controller                   │
│         (requests specific output position [r,c])            │
└────────────────────┬────────────────────────────────────────┘
                     │ output_req[r,c]
                     ↓
┌─────────────────────────────────────────────────────────────┐
│                   Pool2 Request Adapter                      │
│  Converts: output[r,c] → 4 input positions needed           │
│  [2r, 2c], [2r, 2c+1], [2r+1, 2c], [2r+1, 2c+1]            │
└────────────────────┬────────────────────────────────────────┘
                     │ input_req[multiple positions]
                     ↓
┌─────────────────────────────────────────────────────────────┐
│            Conv2 Reverse Position Calculator                 │
│  For each requested position, traverse 3×3 kernel:           │
│  output[r,c] → inputs [r:r+2, c:c+2]                        │
└────────────────────┬────────────────────────────────────────┘
                     │ input_req[kernel positions]
                     ↓
┌─────────────────────────────────────────────────────────────┐
│                   Pool1 Request Adapter                      │
│  Converts: output[r,c] → 4 input positions needed           │
└────────────────────┬────────────────────────────────────────┘
                     │ input_req[multiple positions]
                     ↓
┌─────────────────────────────────────────────────────────────┐
│            Conv1 Reverse Position Calculator                 │
│  For each requested position, traverse 3×3 kernel            │
└────────────────────┬────────────────────────────────────────┘
                     │ input_req[r,c]
                     ↓
┌─────────────────────────────────────────────────────────────┐
│                      Input Buffer                            │
│              (provides pixel at [r,c])                       │
└─────────────────────────────────────────────────────────────┘
```

## Example Trace

**Scenario:** Output controller requests position [2,3] from Pool2

### Step 1: Pool2 Adapter
```
Request: output[2,3]
Calculation: 2×2 block starting at [2*2, 3*2] = [4,6]
Generates 4 requests to Conv2:
  → [4,6], [4,7], [5,6], [5,7]
```

### Step 2: Conv2 Position Calculator (processing first request [4,6])
```
Request: output[4,6]
Calculation: 3×3 kernel starting at [4*1, 6*1] = [4,6]
Generates 9 requests to Pool1:
  kernel[0,0] → input[4,6]
  kernel[0,1] → input[4,7]
  kernel[0,2] → input[4,8]
  kernel[1,0] → input[5,6]
  ... (9 total)
  kernel[2,2] → input[6,8]
```

### Step 3: Pool1 Adapter (processing first request [4,6])
```
Request: output[4,6]
Calculation: 2×2 block starting at [4*2, 6*2] = [8,12]
Generates 4 requests to Conv1:
  → [8,12], [8,13], [9,12], [9,13]
```

### Step 4: Conv1 Position Calculator (processing first request [8,12])
```
Request: output[8,12]
Calculation: 3×3 kernel starting at [8*1, 12*1] = [8,12]
Generates 9 requests to Input:
  kernel[0,0] → input[8,12]
  kernel[0,1] → input[8,13]
  ... (9 total)
  kernel[2,2] → input[10,14]
```

### Step 5: Input Buffer
```
Provides pixels at requested positions:
  [8,12], [8,13], [8,14], [9,12], [9,13], ...
```

## Key Benefits

1. **No Pre-coordination Needed**: Each layer independently calculates what it needs
2. **Natural Ordering**: Data flows in the order requested by the final output
3. **Backpressure Handling**: Each layer can signal when it's ready (`input_pos_ready`)
4. **Modular**: Each layer's position logic is self-contained
5. **Easy to Reason About**: Clear request→response protocol

## Interface Signals

### Request Interface (downstream → upstream)
- `output_req_row` : integer - Requested output row
- `output_req_col` : integer - Requested output column  
- `output_req_valid` : std_logic - Request is valid
- `output_req_ready` : std_logic - Ready to accept new request

### Response Interface (upstream → downstream)
- `input_pos_row` : integer - Required input row
- `input_pos_col` : integer - Required input column
- `input_pos_valid` : std_logic - Input position is valid
- `input_pos_ready` : std_logic - Can provide this position

### Control Signals
- `region_done` : std_logic - Completed all positions for current output
- `kernel_done` : std_logic - Completed current kernel position (all channels)

## Implementation Notes

1. **Convolution Layers**: Use `reverse_position_calculator` with KERNEL_SIZE=3, STRIDE=1
2. **Pooling Layers**: Use `pool_request_adapter` with BLOCK_SIZE=2
3. **Handshaking**: Each layer waits for `input_pos_ready` before advancing
4. **State Management**: FSM tracks current output position and kernel traversal

## Next Steps

1. Integrate `reverse_position_calculator` into `conv_layer_modular`
2. Add `pool_request_adapter` to `max_pooling`
3. Create top-level controller in `cnn.vhd` that generates output position requests
4. Test end-to-end dataflow with testbench
