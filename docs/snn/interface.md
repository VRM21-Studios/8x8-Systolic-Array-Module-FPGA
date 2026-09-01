# SNN Core Interface

## Overview

The `vrm_snn_core` uses AXI4-Stream-style interfaces for spike and weight input/output, together with synchronous control signals for timestep and membrane-state management.

## Control Interface

| Signal              | Direction | Description                             |
| ------------------- | --------- | --------------------------------------- |
| `aclk`              | Input     | Core clock                              |
| `aresetn`           | Input     | Active-low reset                        |
| `ctrl_new_timestep` | Input     | Starts processing of a new timestep     |
| `ctrl_clear_vmem`   | Input     | Clears membrane potential state         |
| `i_thresh`          | Input     | Signed membrane firing threshold        |
| `i_leak_factor`     | Input     | Fixed-point leak factor                 |
| `i_max_chunks`      | Input     | Last chunk address / active chunk range |

## Spike Input Stream

| Signal                | Direction | Description                                  |
| --------------------- | --------- | -------------------------------------------- |
| `s_axis_spike_tvalid` | Input     | Spike input valid                            |
| `s_axis_spike_tdata`  | Input     | Input spike value                            |
| `s_axis_spike_tlast`  | Input     | Marks the final transaction of a chunk       |
| `s_axis_spike_tready` | Output    | Indicates that the core can accept the input |

The spike stream uses the standard `VALID/READY` handshake concept.

A transaction is accepted when:

```text
s_axis_spike_tvalid && s_axis_spike_tready
```

## Weight Input Stream

| Signal                 | Direction | Description                                    |
| ---------------------- | --------- | ---------------------------------------------- |
| `s_axis_weight_tvalid` | Input     | Weight input valid                             |
| `s_axis_weight_tdata`  | Input     | Packed weights for all parallel neurons        |
| `s_axis_weight_tready` | Output    | Indicates that the core can accept the weights |

The width of the packed weight bus is:

```text
WEIGHT_BUS_W = PARALLEL_NEURONS × WEIGHT_W
```

Each neuron occupies one `WEIGHT_W` field in the packed vector.

For neuron `n`:

```text
s_axis_weight_tdata[
    n*WEIGHT_W +: WEIGHT_W
]
```

contains the corresponding signed synaptic weight.

## Output Spike Stream

| Signal                | Direction | Description           |
| --------------------- | --------- | --------------------- |
| `m_axis_spike_tdata`  | Output    | Parallel spike vector |
| `m_axis_spike_tvalid` | Output    | Output valid          |
| `m_axis_spike_tlast`  | Output    | Marks the final chunk |
| `m_axis_spike_tready` | Input     | Downstream ready      |

The output vector contains one spike bit for every physical neuron lane:

```text
m_axis_spike_tdata[PARALLEL_NEURONS-1:0]
```

A transaction is transferred when:

```text
m_axis_spike_tvalid && m_axis_spike_tready
```

## TLAST Semantics

`TLAST` identifies the end of a chunk.

For a configuration such as:

```text
PARALLEL_NEURONS = 64
MAX_CHUNKS       = 4096
```

one timestep can produce up to 4096 output chunk transactions.

The final chunk is indicated by:

```text
m_axis_spike_tlast = 1
```

## Stream Synchronization

Spike and weight input streams are logically paired.

A valid processing transaction requires both input streams to participate in the handshake:

```text
s_axis_spike_tvalid
&&
s_axis_spike_tready
&&
s_axis_weight_tvalid
&&
s_axis_weight_tready
```

This ensures that spike information and its corresponding weight vector remain aligned.

## Reset

`aresetn` is active-low.

During reset, the testbench and integration environment hold the stream interfaces inactive and subsequently release reset before starting normal SNN processing.

## Interface Usage

A typical processing sequence is:

```text
1. Reset the core.
2. Configure threshold and leak parameters.
3. Optionally clear membrane state.
4. Assert new-timestep control.
5. Send spike/weight transactions.
6. Mark the end of each chunk using TLAST.
7. Consume the output spike vectors.
8. Detect the final output chunk using TLAST.
```
