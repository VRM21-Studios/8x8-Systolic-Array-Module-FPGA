# SNN Core Architecture

## Overview

The `vrm_snn_core` is a parameterized Spiking Neural Network (SNN) processing core implemented in synthesizable Verilog RTL.

The core implements a discrete-time neuron processing architecture based on a leaky integrate-and-fire (LIF) model. Incoming spike events are multiplied by signed synaptic weights, accumulated into a neuron membrane potential, optionally subjected to leakage, and compared against a programmable firing threshold.

The architecture is designed to support a large virtual neuron population through time-multiplexed chunk processing.

## Processing Model

The core processes neurons in parallel groups defined by:

```text
PARALLEL_NEURONS
```

Each input transaction contains:

* One spike input
* One weight value for every parallel neuron
* A `TLAST` indication identifying the final transaction of a chunk

For each active spike, the corresponding weight contribution is accumulated into the neuron membrane potential.

Conceptually:

```text
V_next = V_leak + spike × weight
```

where:

* `V_leak` is the membrane potential after leakage
* `spike` is the incoming binary spike
* `weight` is the signed synaptic weight
* `V_next` is the updated membrane potential

## LIF Behavior

The membrane potential is maintained between timesteps.

A configurable leak factor is applied before the new synaptic contribution is incorporated.

The resulting membrane potential is then compared against the programmable threshold:

```text
if V_next >= threshold:
    spike_out = 1
else:
    spike_out = 0
```

The exact fixed-point representation of the leak factor is controlled by `LEAK_FRAC_BITS`.

## Timestep Processing

A timestep is initiated through the `ctrl_new_timestep` control signal.

The optional `ctrl_clear_vmem` control signal clears the stored membrane state.

The general processing sequence is:

```text
             ┌──────────────────┐
Spike Input ─►                  │
Weight Input ─►  Input / MAC    │
             │     Pipeline     │
             └────────┬─────────┘
                      │
                      ▼
             ┌──────────────────┐
             │ Membrane State   │
             │      Vmem        │
             └────────┬─────────┘
                      │
                      ▼
             ┌──────────────────┐
             │ Leak / Threshold │
             │    Processing    │
             └────────┬─────────┘
                      │
                      ▼
             ┌──────────────────┐
             │ Spike Vector     │
             │     Output       │
             └──────────────────┘
```

## Chunk-Based Processing

A large virtual neuron population is divided into chunks.

For example, with:

```text
PARALLEL_NEURONS = 64
MAX_CHUNKS       = 4096
```

the architecture can address:

```text
64 × 4096 = 262,144
```

virtual neuron positions.

Only one chunk is processed by the parallel neuron hardware at a time. The membrane state of each chunk is retained in memory.

This allows the architecture to scale the virtual neuron population without requiring a proportional increase in physical neuron processing hardware.

## Signed Weight Processing

Synaptic weights are represented as signed values.

Both positive and negative weights therefore contribute naturally to the membrane potential:

```text
positive weight → increases membrane potential
negative weight → decreases membrane potential
```

Signed-weight behavior is explicitly exercised by the SNN verification environment.

## Parameterization

Important architectural parameters include:

| Parameter          | Description                                      |
| ------------------ | ------------------------------------------------ |
| `PARALLEL_NEURONS` | Number of neurons processed in parallel          |
| `WEIGHT_W`         | Synaptic weight width                            |
| `HEADROOM_BITS`    | Additional arithmetic headroom                   |
| `VMEM_W`           | Membrane potential width                         |
| `MAX_CHUNKS`       | Maximum number of virtual neuron chunks          |
| `LEAK_FRAC_BITS`   | Fractional-bit configuration for leak arithmetic |
| `FIFO_DEPTH`       | Output/input buffering depth                     |
| `ADDR_W`           | Chunk address width                              |
| `RAM_STYLE`        | FPGA memory implementation preference            |

## FPGA Memory

The membrane state storage is implemented using the reusable RAM infrastructure provided by the VRM21 RTL ecosystem.

The underlying RAM implementation can be selected according to the target FPGA architecture, including block-oriented and ultra RAM configurations.

The reusable RAM module is maintained separately in:

`VRM21-RTL-Utilities`

The SNN repository therefore does not duplicate the generic RAM implementation.

## Design Intent

The core is intended to provide:

* Parameterized neuron parallelism
* Signed synaptic weights
* Persistent membrane state
* Configurable leakage
* Programmable firing threshold
* Chunk-based virtual neuron scaling
* AXI4-Stream-compatible data movement
* FPGA-oriented memory inference
* Integration through an AXI-Lite control wrapper
