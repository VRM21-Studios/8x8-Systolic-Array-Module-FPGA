# Address Map (AXI4-Lite)

The `systolic_axi_wrapper` uses a 12-bit address space (4KB) via the AXI4-Lite interface for static configuration. This memory map is designed to be scalable for up to a 32x32 array, though the current default configuration is 8x8.

All registers are 32-bit wide.

| Address Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x000` | `REG_CTRL` | R/W | **Control Register**. <br> - `Bit[0]`: Soft Clear (Active High). Set to 1 to flush the systolic pipeline, then set to 0 to resume normal operation. |
| `0x100 - 0x17C` | `REG_WEIGHT_BASE` | W | **Weight Matrix Registers**. <br> Stores the flattened 8x8 weight matrix. <br> - Each 16-bit weight is packed into 32-bit registers (Little Endian). <br> - Total size: 64 weights * 16 bits = 1024 bits (requires 32 registers). |
| `0x180 - 0x1A0` | `REG_BIAS_BASE` | W | **Bias Vector Registers**. <br> Stores the 8 bias values. <br> - Each bias requires 35 bits (Accumulator width). <br> - Total size: 8 biases * 35 bits = 280 bits. <br> - Packed densely across 9 registers of 32-bit width. |

**Note on Data Packing:**
When writing weights and biases from the Processing System (e.g., via ARM CPU), ensure the bit-shifting logic perfectly aligns with the flattened 1D wire array expected by the Verilog module.
