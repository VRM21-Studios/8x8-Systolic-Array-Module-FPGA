# SNN RTL

This directory contains the RTL implementation of the Spiking Neural Network (SNN) accelerator used by the VRM21 NPU Series.

## RTL Modules

| File             | Description                                                                                               |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| `vrm_snn_core.v` | Parameterized parallel SNN processing core implementing a Leaky Integrate-and-Fire (LIF) neuron datapath. |
| `vrm_snn_axi.v`  | AXI4-Lite control wrapper and AXI4-Stream interface adapter for SoC and DMA-based integration.            |

## External RTL Dependency

The SNN core uses `vrm_ram_core.v` for membrane-potential state storage. This module is maintained separately in the VRM21 reusable RTL utility repository and is intentionally not duplicated in this repository.

Obtain the required module from:

**VRM21-RTL-Utilities**

[VRM21-Studios/VRM21-RTL-Utilities](https://github.com/VRM21-Studios/VRM21-RTL-Utilities?utm_source=chatgpt.com)

The required source file is:

```text
VRM21-RTL-Utilities/
└── rtl/
    └── vrm_ram_core.v
```

Copy or include `vrm_ram_core.v` in the project's RTL compilation flow before synthesizing the SNN modules.

## Dependency

```text
vrm_snn_core.v
        │
        └── vrm_ram_core.v
                │
                └── VRM21-RTL-Utilities
```

The external RAM module provides the configurable memory implementation used for the SNN membrane-state storage.
