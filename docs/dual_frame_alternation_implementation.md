# Dual Frame Alternation Implementation

## Overview
Updated `SPI_memory_controller_backup.vhd` to handle alternating 28×28 CNN frames and 200×200 VGA frames over SPI. The controller now implements a deterministic frame alternation pattern with simplified VGA architecture.

## Architecture Changes

### Buffer Configuration
- **CNN Buffers (A, B, C)**: Triple buffer for 28×28 frames (784 bytes each)
  - 10-bit addressing
  - Uses `BRAM_dual_port` component
  - Rotates between buffers to allow CNN inference on stable data
  
- **VGA Buffer (D)**: Single buffer for 200×200 frames (40,000 bytes)
  - 16-bit addressing
  - Uses `BRAM_dual_port_large` component
  - Continuously overwritten (tearing acceptable)

### Removed Components
Eliminated unnecessary VGA buffers E and F along with all associated logic:
- Removed 24+ signal declarations (bram_E_*, bram_F_*)
- Removed BRAM_E_inst and BRAM_F_inst instantiations
- Removed write address counters, pixel counters, and status flags for E/F
- Removed FSM states WRITE_E and WRITE_F
- Removed VGA buffer selection multiplexing logic

### Frame Type Tracking
Added deterministic frame alternation:
- `current_frame_type`: Tracks the type of frame currently being written ('0' = CNN, '1' = VGA)
- `next_frame_type`: Determines routing for the next incoming frame
- Toggled in TRANSITION state after each frame completion

## FSM State Machine Updates

### IDLE State
Enhanced to detect frame type and route appropriately:
```vhdl
if next_frame_type = '0' then
    -- Route to CNN triple buffer (28×28)
    current_state <= WRITE_A;
    initialize CNN counters
else
    -- Route to VGA single buffer (200×200)
    current_state <= WRITE_D;
    initialize VGA counters
end if;
```

### WRITE_A, WRITE_B, WRITE_C States
Updated CNN buffer write states:
- Changed completion checks from `MAX_PIXELS - 1` to `MAX_PIXELS_CNN - 1`
- Ensures proper 28×28 frame boundary detection (784 bytes)
- Maintains existing busy-check and buffer rotation logic

### WRITE_D State (New)
Added complete VGA buffer write handler:
- Writes to buffer D (200×200, 40,000 bytes)
- Uses 16-bit addressing (`write_addr_D`)
- Completion check: `write_addr_D = (MAX_PIXELS_VGA - 1)` → 39,999
- No busy check (single buffer, continuous overwrite)
- Sets `completed_buffer <= "11"` to distinguish VGA completion

### TRANSITION State (Modified)
Enhanced to handle both CNN and VGA frame completions:

**For VGA frames** (`completed_buffer = "11"`):
- Clear write enable for buffer D
- Toggle to expect CNN frame next: `next_frame_type <= '0'`
- Return to IDLE state

**For CNN frames** (`completed_buffer /= "11"`):
- Update `last_written` flags based on completed buffer
- Select next available CNN buffer (A → B → C priority)
- Toggle to expect VGA frame next: `next_frame_type <= '1'`

## Memory Reset Updates

### Reset State Machine
Extended to clear all four buffers:
- Added `RESET_CLEAR_D` state
- Added `reset_addr_vga` signal (16-bit for VGA buffer)
- Sequence: RESET_CLEAR_A → RESET_CLEAR_B → RESET_CLEAR_C → RESET_CLEAR_D → RESET_DONE

### Reset Timing
- CNN buffers A/B/C: 784 cycles each (10-bit counter)
- VGA buffer D: 40,000 cycles (16-bit counter)
- Total reset time: ~42,352 clock cycles

## Address Width Updates

### VGA Interface
- Port: `vga_addr` changed from `std_logic_vector(9 downto 0)` to `(15 downto 0)`
- Internal: `write_addr_D`, `pixel_count_D` changed to `unsigned(15 downto 0)`
- BRAM connection: Direct 16-bit address to `bram_D_addrb` and `bram_D_addr_writea`

### Simplified VGA Routing
Removed all multiplexing and buffer selection:
```vhdl
-- Direct connection to buffer D
vga_data <= bram_D_doutb;
bram_D_addrb <= vga_addr;
```

## Pixel Limits

Added frame-specific constants:
- `MAX_PIXELS_CNN`: `unsigned(9 downto 0)` = 784 (28×28)
- `MAX_PIXELS_VGA`: `unsigned(15 downto 0)` = 40,000 (200×200)

## Frame Alternation Flow

Expected sequence:
1. **IDLE** → Check `next_frame_type` = '0' → **WRITE_A** (CNN frame)
2. Write 28×28 pixels to buffer A
3. **WRITE_A** → **TRANSITION** (CNN complete, `completed_buffer = "00"`)
4. **TRANSITION** → Update flags, toggle `next_frame_type` to '1' → **IDLE**
5. **IDLE** → Check `next_frame_type` = '1' → **WRITE_D** (VGA frame)
6. Write 200×200 pixels to buffer D
7. **WRITE_D** → **TRANSITION** (VGA complete, `completed_buffer = "11"`)
8. **TRANSITION** → Toggle `next_frame_type` to '0' → **IDLE**
9. Repeat from step 1 with next CNN buffer (B or C)

## Testing Considerations

### Verification Points
- Frame type toggle works correctly after each completion
- WRITE_D state handles 16-bit addressing without overflow
- CNN triple buffer rotation continues (A → B → C → A...)
- VGA buffer D gets continuously overwritten
- Reset clears all 42,352 bytes (A+B+C+D)

### Expected Behavior
- SPI transmits alternating frames: CNN, VGA, CNN, VGA...
- CNN can read from `last_written` buffer during new frame reception
- VGA always reads from buffer D (tearing may occur during writes)
- No frame type auto-detection (deterministic toggle pattern)

## Design Trade-offs

### VGA Single Buffer
- **Advantage**: Reduced BRAM usage (saves ~80,000 bytes)
- **Trade-off**: VGA may display tearing during SPI writes
- **Justification**: User accepted tearing for this backup controller

### Deterministic Frame Alternation
- **Advantage**: Simple, predictable state machine
- **Trade-off**: No frame size auto-detection from SPI data
- **Requirement**: SPI sender must follow strict alternation pattern

### 16-bit VGA Addressing
- **Advantage**: Supports full 200×200 resolution (40,000 bytes)
- **Trade-off**: Larger address busses and counters
- **Impact**: Minimal resource increase (~6 extra flip-flops per signal)

## Files Modified
- `src/SPI/SPI_memory_controller_backup.vhd` — Complete dual-frame implementation

## Related Documentation
- `docs/dual_frame_controller_changes.md` — Initial design notes
- `.github/copilot-instructions.md` — Project architecture reference

## Compilation Status
✅ No VHDL syntax errors
✅ All state transitions implemented
✅ Reset sequence covers all buffers
✅ Address width consistency verified
