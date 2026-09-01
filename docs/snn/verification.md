# SNN Verification

## Verification Overview

The SNN core is verified using multiple directed testbenches targeting arithmetic correctness, scaling behavior, spike-pattern generation, and LIF dynamics.

The verification environment is intentionally divided into independent scenarios so that individual architectural behaviors can be isolated.

## Testbench Organization

The SNN testbench files are located under:

```text
rtl/snn/tb/
```

Current testbenches:

| Testbench                | Purpose                                     |
| ------------------------ | ------------------------------------------- |
| `tb_snn_signed_weight.v` | Signed positive/negative weight validation  |
| `tb_snn_scale.v`         | Large virtual-neuron scaling validation     |
| `tb_snn_spike_pattern.v` | Mixed spike-pattern validation              |
| `tb_snn_lif_dynamics.v`  | LIF temporal behavior validation            |
| `tb_snn_axi_wrapper.v`   | AXI-Lite and AXI4-Stream wrapper validation |

## Signed Weight Test

`tb_snn_signed_weight.v` validates signed synaptic weight handling.

The test intentionally applies negative and positive weights across consecutive timesteps.

The scenario verifies that a negative contribution decreases the membrane potential rather than being interpreted as a large unsigned positive value.

The test sequence includes:

```text
Timestep 1:
    Weight = -100
    Vmem   = -100
    Output = 0

Timestep 2:
    Weight = +150
    Vmem   = +50
    Output = 0

Timestep 3:
    Weight = +60
    Vmem   = +110
    Output = 1
```

with a threshold of:

```text
100
```

This directly exercises signed accumulation and threshold behavior.

## Large-Scale Test

`tb_snn_scale.v` validates the chunk-based scaling architecture.

The test configuration uses:

```text
PARALLEL_NEURONS = 64
MAX_CHUNKS       = 4096
```

resulting in:

```text
262,144 virtual neurons
```

The test injects a negative weight into every chunk and verifies that no unintended spikes are generated.

The output stream is monitored across the complete chunk range, including the final `TLAST` transaction.

## Spike Pattern Test

`tb_snn_spike_pattern.v` validates mixed neuron behavior within the same parallel vector.

The test assigns different weights to alternating neuron lanes.

For the documented checkerboard scenario:

```text
Even lanes = +150
Odd lanes  = +40
Threshold  = 100
```

the expected spike vector is:

```text
5555555555555555
```

for a 64-bit output vector.

This verifies that different neuron lanes can independently produce spike/no-spike results while being processed through the same pipeline.

## LIF Dynamics Test

`tb_snn_lif_dynamics.v` evaluates temporal LIF behavior across multiple timesteps.

The test provides a repeating input-spike pattern and different synaptic weights while recording internal membrane-state information.

The testbench also generates:

```text
vmem_dump.txt
rtl_trace.txt
```

for post-simulation inspection.

The trace includes internal pipeline and membrane-state information such as:

* Chunk address
* Pipeline validity
* Partial-sum registers
* Previous membrane potential
* Leaked membrane potential
* Updated membrane potential
* Spike output

These traces are intended for debugging and architectural validation rather than as part of the synthesizable RTL.

## AXI Wrapper Test

`tb_snn_axi_wrapper.v` validates the integration layer around the SNN core.

The test covers:

1. AXI-Lite register writes.
2. AXI-Lite register readback.
3. Control-register operation.
4. Automatic clearing of the timestep trigger.
5. AXI4-Stream spike input.
6. AXI4-Stream weight input.
7. AXI4-Stream output monitoring.
8. TLAST propagation.

## Verification Philosophy

The testbenches use directed scenarios rather than relying exclusively on random stimulus.

Each test targets a specific architectural property:

```text
Signed arithmetic
        │
        ▼
Virtual scaling
        │
        ▼
Parallel spike generation
        │
        ▼
Temporal LIF behavior
        │
        ▼
System-level AXI integration
```

This structure makes failures easier to localize to a specific part of the design.
