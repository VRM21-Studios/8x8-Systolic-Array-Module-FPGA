# SNN Memory and Scaling

## Overview

The SNN core separates physical processing parallelism from the size of the virtual neuron population.

This allows a relatively small number of physical neuron-processing lanes to represent a much larger logical network.

## Parallel Neuron Lanes

`PARALLEL_NEURONS` defines the number of neurons processed simultaneously.

For example:

```text
PARALLEL_NEURONS = 64
```

means that each processing transaction operates on 64 neuron lanes.

The corresponding weight input width is:

```text
64 × 16 = 1024 bits
```

when `WEIGHT_W = 16`.

## Chunk-Based Scaling

The virtual neuron population is divided into chunks.

The approximate virtual neuron capacity is:

```text
Virtual Neurons =
    PARALLEL_NEURONS × MAX_CHUNKS
```

For the large-scale verification configuration:

```text
PARALLEL_NEURONS = 64
MAX_CHUNKS       = 4096
```

the resulting virtual population is:

```text
64 × 4096 = 262,144 virtual neurons
```

The physical arithmetic hardware remains 64 lanes wide while the membrane states are distributed across the chunk-addressed memory space.

## Membrane State Storage

Each neuron requires persistent membrane state.

The memory system therefore stores the membrane potential associated with each neuron lane and chunk.

The chunk address determines which section of the virtual neuron population is being processed.

Conceptually:

```text
              Chunk Address
                    │
                    ▼
       ┌────────────────────────┐
       │ Membrane State Memory  │
       ├────────────────────────┤
       │ Chunk 0   → 64 neurons │
       │ Chunk 1   → 64 neurons │
       │ Chunk 2   → 64 neurons │
       │   ...                  │
       │ Chunk N   → 64 neurons │
       └────────────────────────┘
```

## RAM Implementation

The SNN core uses the reusable VRM21 RAM infrastructure instead of maintaining a separate generic RAM implementation.

The RAM implementation is available from:

[VRM21-RTL-Utilities](https://github.com/VRM21-Studios/VRM21-RTL-Utilities?utm_source=chatgpt.com)

The relevant reusable module is:

```text
rtl/vrm_ram_core.v
```

The `RAM_STYLE` parameter allows the SNN design to request an FPGA-specific memory implementation.

Examples used during verification include:

```text
RAM_STYLE = "block"
RAM_STYLE = "ultra"
```

## Block RAM Configuration

The reduced-scale verification environment uses block-oriented RAM inference.

This configuration is useful for:

* Fast simulation
* Small memory configurations
* Validation of signed membrane-state behavior
* General functional verification

## Ultra RAM Configuration

The large-scale SNN verification environment uses:

```text
RAM_STYLE = "ultra"
```

This configuration is intended to model the memory architecture required for the large virtual neuron population.

The corresponding verification configuration processes:

```text
4096 chunks
×
64 neuron lanes
=
262,144 virtual neurons
```

## Address Width

The chunk address width is selected according to the number of supported chunks.

For 4096 chunks:

```text
ADDR_W = 12
```

because:

```text
2^12 = 4096
```

The address width therefore scales with the virtual neuron memory depth rather than the number of physical neuron lanes.

## Scaling Principle

The architecture trades memory capacity for virtual neuron count.

Increasing:

```text
MAX_CHUNKS
```

increases the number of virtual neurons while leaving:

```text
PARALLEL_NEURONS
```

unchanged.

Increasing:

```text
PARALLEL_NEURONS
```

instead increases instantaneous processing parallelism and consequently increases arithmetic and input-bus resources.

This provides two independent architectural scaling dimensions:

```text
                 SNN Scaling
                     │
          ┌──────────┴──────────┐
          │                     │
          ▼                     ▼
 PARALLEL_NEURONS          MAX_CHUNKS
 Processing Throughput     Virtual Capacity
          │                     │
          ▼                     ▼
 Arithmetic Resources       Memory Resources
```
