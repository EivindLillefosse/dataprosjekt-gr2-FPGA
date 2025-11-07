# Request/Response Architecture Summary

## Key Concept: Pull-Based Dataflow

Instead of pushing data forward (Input → Conv1 → Pool1 → Conv2 → Pool2 → Output), we **pull data backward**:
- Output layer requests what it needs
- Each layer requests from upstream to fulfill downstream requests
- Data flows back up once available

## Architecture Overview

```
USER                                                      INPUT MEMORY
  ↓                                                            ↑
  | "I want output[2,3]"                                     |
  ↓                                                           |
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  OUTPUT SCANNER                                            │
│    Generates: req[2,3]                                     │
│         ↓ request                                          │
│         ↑ response                                         │
│                                                            │
│  POOL2 ADAPTER                                            │
│    Needs: Conv2[4,6],[4,7],[5,6],[5,7] (2×2 block)       │
│         ↓ 4 requests                                       │
│         ↑ 4 responses → compute max → 1 response up       │
│                                                            │
│  CONV2 ADAPTER + CONV LAYER                               │
│    For each output[4,6] needs:                            │
│      Pool1[4:6, 6:8] (3×3 window)                         │
│         ↓ 9 requests                                       │
│         ↑ 9 responses → MAC → 1 response up               │
│                                                            │
│  POOL1 ADAPTER                                            │
│    For each output[4,6] needs:                            │
│      Conv1[8,12],[8,13],[9,12],[9,13] (2×2 block)        │
│         ↓ 4 requests                                       │
│         ↑ 4 responses → compute max → 1 response up       │
│                                                            │
│  CONV1 ADAPTER + CONV LAYER                               │
│    For each output[8,12] needs:                           │
│      Input[8:10, 12:14] (3×3 window)                      │
│         ↓ 9 requests                                       │
│         ↑ 9 responses → MAC → 1 response up               │
│                                                            │
│  INPUT BUFFER                                             │
│    Stores 28×28 image, responds to requests              │
│         ↑ requests from Conv1                             │
│         ↓ pixel data responses                            │
│                                                            │
└─────────────────────────────────────────────────────────────┘
```

## Request Multiplication

One output request triggers a cascade:

```
1 final output request
  ↓
4 Pool2 input requests (2×2)
  ↓
4×9 = 36 Conv2 input requests (each needs 3×3)
  ↓
36×4 = 144 Pool1 input requests (each needs 2×2)
  ↓
144×9 = 1,296 Conv1 input requests (each needs 3×3)
  ↓
1,296×9 = 11,664 Input buffer accesses (each needs 3×3)
```

**But**: Many requests overlap! Same input pixel used in multiple windows.

## Adapter Responsibilities

### Pool Adapter
```
State machine:
  IDLE → Receive output request [r,c]
  REQUEST → Issue 4 input requests:
    [2r, 2c], [2r, 2c+1], [2r+1, 2c], [2r+1, 2c+1]
  COLLECT → Accumulate 4 responses, track maximum
  RESPOND → Send maximum as output response
```

### Conv Adapter
```
State machine:
  IDLE → Receive output request [r,c]
  REQUEST → Issue 9 input requests (3×3 window):
    [r+kr, c+kc] for kr,kc ∈ {0,1,2}
  COLLECT → Forward each response to existing conv_layer
  WAIT → Wait for conv_layer to compute result
  RESPOND → Send conv result as output response
```

### Input Buffer Adapter
```
Dual-port RAM or external memory controller
  On request [r,c]:
    - Look up pixel at [r,c]
    - Assert resp_valid with data
    - Wait for resp_ready handshake
```

## Signal Flow Example

```
Clock cycle view for single output[0,0] request:

Cycle 1: Output scanner requests [0,0]
Cycle 2: Pool2 adapter receives, requests Conv2[0,0]
Cycle 3: Conv2 adapter receives, requests Pool1[0,0]
Cycle 4: Pool1 adapter receives, requests Conv1[0,0]
Cycle 5: Conv1 adapter receives, requests Input[0,0]
Cycle 6: Input buffer responds with pixel[0,0]
Cycle 7: Conv1 requests Input[0,1]
Cycle 8: Input buffer responds with pixel[0,1]
...
Cycle 14: Conv1 has all 9 pixels, starts MAC
Cycle 16: Conv1 MAC complete, responds to Pool1
Cycle 17: Pool1 requests Conv1[0,1]
...
Cycle 70: Pool1 has all 4 pixels, computes max, responds to Conv2
Cycle 71: Conv2 requests Pool1[0,1]
...
Cycle 650: Conv2 has all 9 pixels, starts MAC
Cycle 652: Conv2 MAC complete, responds to Pool2
...
Cycle 680: Pool2 has all 4 pixels, computes max, responds to Output
Cycle 681: Output scanner requests [0,1]
```

Total latency per output: ~680 cycles (depends on channel count, etc.)

## Benefits vs Current Architecture

### Current (Push-Based)
- ✅ Simpler conceptually
- ✅ Lower latency (pipelined)
- ❌ Fixed processing order
- ❌ No random access to outputs
- ❌ Hard to coordinate across layers

### Request/Response (Pull-Based)
- ✅ Flexible output ordering
- ✅ Can compute specific outputs on-demand
- ✅ Natural backpressure handling
- ✅ Each layer independent
- ❌ Higher latency per output
- ❌ More complex state machines

## When to Use Each

### Push-Based (Current)
Use when:
- Processing entire image sequentially
- Low latency critical
- Streaming data

### Pull-Based (Request/Response)
Use when:
- Need specific outputs (not full image)
- Output ordering matters for downstream processing
- Want to optimize memory access patterns
- Testing/debugging (can request specific positions)

## Hybrid Approach

Best of both worlds:
1. Use request/response adapters as **wrappers**
2. Keep existing push-based cores
3. Adapter converts between protocols
4. Can switch between modes via generics

This is what the integration guide proposes!

## Implementation Priority

1. **Output Scan Generator** (simple counter, block-scan order)
2. **Input Buffer Adapter** (RAM + request handler)
3. **Pool Request Adapter** (4-request generator + max tracker)
4. **Conv Request Adapter** (9-request generator + conv layer wrapper)
5. **Top-Level Integration** (wire everything together)

## Summary

The request/response architecture gives you **precise control** over data flow and processing order. By working backward from desired outputs, you ensure every computation is necessary and correctly ordered for downstream layers (like pooling).

The adapter approach means you can keep your existing, tested conv layers and just add orchestration logic around them.
