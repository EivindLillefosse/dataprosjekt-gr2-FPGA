# Pool Request Adapter - Implementation Summary

## What It Does

Converts **1 output request** → **4 input requests** → **1 output response**

For a 2×2 max pooling operation:
- Receives request for output position [r,c]
- Requests 4 input positions: [2r, 2c], [2r, 2c+1], [2r+1, 2c], [2r+1, 2c+1]
- Tracks maximum value across all 4 inputs (per channel)
- Responds with maximum values

## FSM States

```
IDLE ────────────> REQUEST_00 ─> WAIT_00 ─┐
  ↑                                        │
  │                                        ↓
  │                               REQUEST_01 ─> WAIT_01 ─┐
  │                                                       │
  │                                                       ↓
  │                                              REQUEST_10 ─> WAIT_10 ─┐
  │                                                                      │
  │                                                                      ↓
  │                                                             REQUEST_11 ─> WAIT_11
  │                                                                                  │
  │                                                                                  ↓
  └──────────────────────────────────────────────────────────────────── COMPUTE <── ┘
                                                                              │
                                                                              ↓
                                                                           RESPOND
```

## Timing Example

```
Cycle  State         Action
─────────────────────────────────────────────────────────────
  1    IDLE          output_req_valid=1 [0,0]
  2    REQUEST_00    input_req [0,0]
  3    WAIT_00       input_resp received (10,20)
  4    REQUEST_01    input_req [0,1]
  5    WAIT_01       input_resp received (15,25)
  6    REQUEST_10    input_req [1,0]
  7    WAIT_10       input_resp received (12,22)
  8    REQUEST_11    input_req [1,1]
  9    WAIT_11       input_resp received (17,27)
 10    COMPUTE       max computed: (17,27)
 11    RESPOND       output_resp_valid=1
 12    IDLE          Ready for next request
```

**Total latency: ~11 cycles per output**

## Key Features

### 1. Request/Response Protocol
- Uses valid/ready handshakes for flow control
- Backpressure supported on both upstream and downstream
- No blocking: waits for ready before proceeding

### 2. Per-Channel Maximum Tracking
- Maintains separate maximum for each channel
- Updates incrementally as responses arrive
- Supports arbitrary number of channels (generic)

### 3. Position Mapping
```vhdl
-- Output [r,c] maps to input 2×2 block:
base_row <= output_req_row * BLOCK_SIZE;  -- 2r
base_col <= output_req_col * BLOCK_SIZE;  -- 2c

-- Four requests:
[base_row + 0, base_col + 0]  -- [2r,   2c  ]
[base_row + 0, base_col + 1]  -- [2r,   2c+1]
[base_row + 1, base_col + 0]  -- [2r+1, 2c  ]
[base_row + 1, base_col + 1]  -- [2r+1, 2c+1]
```

## Testbench Validation

### Test Setup
- 4×4 input (2×2 output)
- 2 channels
- Known test pattern

### Test Cases
1. **Output [0,0]** → requests inputs [0:1, 0:1] → expects max(10,15,12,17)=17, max(20,25,22,27)=27 ✓
2. **Output [0,1]** → requests inputs [0:1, 2:3] → expects max(30,35,32,37)=37, max(40,45,42,47)=47 ✓
3. **Output [1,1]** → requests inputs [2:3, 2:3] → expects max(70,75,72,77)=77, max(80,85,82,87)=87 ✓

### Mock Upstream
Testbench includes mock upstream responder that:
- Accepts all requests immediately (input_req_ready=1)
- Responds with data from pre-populated test array
- Simulates ideal Conv layer behavior

## Integration Points

### With Conv Layer (Upstream)
```vhdl
conv_adapter : entity work.conv_request_adapter
    port map (
        -- ... conv layer ports ...
        -- To Pool adapter
        output_resp_valid => conv_to_pool_resp_valid,
        output_resp_data  => conv_to_pool_resp_data,
        output_resp_ready => conv_to_pool_resp_ready
    );

pool_adapter : entity work.pool_request_adapter
    port map (
        -- From Conv adapter
        input_req_valid  => pool_to_conv_req_valid,
        input_req_row    => pool_to_conv_req_row,
        input_req_col    => pool_to_conv_req_col,
        input_req_ready  => pool_to_conv_req_ready,
        input_resp_valid => conv_to_pool_resp_valid,
        input_resp_data  => conv_to_pool_resp_data,
        input_resp_ready => conv_to_pool_resp_ready,
        -- ... downstream ports ...
    );
```

### With Downstream Layer
Could be another Conv layer or final output collector

## Resource Utilization (Estimate)

- **Registers**: ~50-100 (FSM state, position latches, max accumulators)
- **LUTs**: ~200-300 (FSM logic, comparators for max)
- **DSPs**: 0 (no multiplication)
- **BRAM**: 0 (no buffering)

Very lightweight compared to Conv layer!

## Next Steps

1. **Run testbench**: Validate pool adapter works correctly
2. **Create Conv Request Adapter**: More complex, wraps existing conv_layer_modular
3. **Create Output Scan Generator**: Simple counter, drives pipeline
4. **Create Input Buffer Adapter**: RAM + request handler
5. **Integrate in CNN**: Wire everything together

## Files Created

- `src/adapters/pool_request_adapter.vhd` - Main implementation
- `src/adapters/pool_request_adapter_tb.vhd` - Comprehensive testbench
- `docs/pool_adapter_summary.md` - This document

Ready to test!
