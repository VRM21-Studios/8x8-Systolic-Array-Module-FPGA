# SNN AXI Wrapper

## Overview

The SNN AXI wrapper provides a software-accessible control interface around the SNN processing core.

The wrapper combines:

* AXI4-Lite control and configuration registers
* AXI4-Stream spike input
* AXI4-Stream weight input
* AXI4-Stream spike output

This allows the SNN core to be integrated into an FPGA-based SoC environment where a processor configures and controls the accelerator through memory-mapped registers.

## Interface Architecture

```text
                    Processor / Host
                           │
                       AXI4-Lite
                           │
                           ▼
                 ┌──────────────────┐
                 │  SNN AXI Wrapper │
                 │                  │
                 │ Control Registers│
                 └────────┬─────────┘
                          │
                          ▼
                   ┌─────────────┐
                   │  SNN Core   │
                   └──────┬──────┘
                          │
                    AXI4-Stream
                          │
                          ▼
                    Spike Output
```

## AXI-Lite Register Map

The wrapper exposes the following control registers used by the verification environment:

| Address | Register    | Description                  |
| ------: | ----------- | ---------------------------- |
|  `0x00` | Control     | Clear and timestep control   |
|  `0x04` | Threshold   | Membrane firing threshold    |
|  `0x08` | Leak Factor | Fixed-point leak coefficient |
|  `0x0C` | Max Chunks  | Maximum active chunk address |

## Control Register

The control register contains control bits for membrane-state management and timestep operation.

The verification environment uses:

```text
Bit 0 = clear_vmem
Bit 1 = trigger_new_timestep
```

Writing:

```text
0x00000003
```

therefore requests:

```text
clear_vmem            = 1
trigger_new_timestep  = 1
```

## Automatic Trigger Clearing

The `trigger_new_timestep` control bit is intended as a pulse-like software trigger rather than a persistent configuration field.

After the trigger is consumed by the hardware, the corresponding bit is automatically cleared.

The wrapper testbench explicitly verifies this behavior by:

1. Writing `3` to the control register.
2. Waiting for the hardware to process the trigger.
3. Reading the control register.
4. Expecting the remaining value to be `1`.

Therefore:

```text
Written:
    0b0011

After trigger consumption:
    0b0001
```

## Threshold Register

The threshold register controls the membrane potential level required to generate a spike.

The SNN verification environment uses different threshold values depending on the scenario.

For example:

```text
threshold = 100
```

is used by the directed signed-weight and spike-pattern tests.

## Leak Factor Register

The leak factor is represented using fixed-point arithmetic.

The number of fractional bits is determined by:

```text
LEAK_FRAC_BITS
```

For the standard configuration:

```text
LEAK_FRAC_BITS = 15
```

the leak coefficient uses a Q-format with 15 fractional bits.

## Maximum Chunk Register

The maximum chunk register defines the active chunk range used by the SNN core.

For example:

```text
Max Chunks Register = 1
```

represents two chunk addresses:

```text
Chunk 0
Chunk 1
```

The AXI wrapper testbench uses this reduced configuration to keep simulation time short.

## AXI4-Stream Data Path

The wrapper forwards spike and weight streams to the SNN core.

The input consists of:

```text
Spike Stream
      +
Weight Stream
      │
      ▼
   SNN Core
      │
      ▼
Spike Output Stream
```

Spike and weight transactions are logically paired and use their respective `VALID/READY` handshakes.

## Host Integration

The intended system-level usage is:

```text
1. Host releases the SNN block from reset.
2. Host writes the threshold register.
3. Host writes the leak-factor register.
4. Host configures the active chunk range.
5. Host requests membrane-state clearing if required.
6. Host triggers a new timestep.
7. Host or DMA engine supplies spike and weight streams.
8. The SNN core produces spike vectors.
9. The host or downstream accelerator consumes the output stream.
```

## Verification Status

The AXI wrapper has a dedicated directed testbench:

```text
rtl/snn/tb/tb_snn_axi_wrapper.v
```

The testbench covers both memory-mapped control transactions and streaming data transactions.

It also verifies the control-register auto-clear behavior of the timestep trigger.
