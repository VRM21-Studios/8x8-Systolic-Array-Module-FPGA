```verilog
`timescale 1ns / 1ps

// ============================================================================
// Module: vrm_snn_axi
// Description:
//   AXI4-Lite control wrapper and AXI4-Stream interface adapter for the
//   VRM SNN processing core.
//
//   The wrapper exposes the SNN configuration registers through an AXI4-Lite
//   slave interface and connects the spike and weight datapaths directly to
//   AXI4-Stream interfaces suitable for DMA-based SoC integration.
//
//   The scalar spike input is presented as a 32-bit AXI4-Stream word at the
//   wrapper boundary. Only bit 0 is forwarded to the SNN core; the remaining
//   bits are treated as padding.
//
// Register Map:
//   0x00  Control Register
//         Bit 0 : Clear membrane-state memory
//         Bit 1 : Start a new timestep
//
//   0x04  Spike Threshold
//
//   0x08  Leak Factor
//         Bits [15:0] : Fixed-point leak coefficient
//
//   0x0C  Maximum Chunk Address
//
// Integration:
//   - AXI4-Lite is used for configuration and control.
//   - AXI4-Stream is used for spike and weight input.
//   - AXI4-Stream is used for generated spike output.
// ============================================================================

module vrm_snn_axi #(
    parameter PARALLEL_NEURONS = 64,
    parameter WEIGHT_W         = 16,
    parameter HEADROOM_BITS    = 10,
    parameter VMEM_W           = 32,
    parameter MAX_CHUNKS       = 4096,
    parameter LEAK_FRAC_BITS   = 15,
    parameter FIFO_DEPTH       = 8192,
    parameter RAM_STYLE        = "ultra",
    parameter ADDR_W           = $clog2(MAX_CHUNKS),

    // AXI4-Lite Interface Parameters
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 5
)(
    // ------------------------------------------------------------------------
    // Clock and Reset
    // ------------------------------------------------------------------------
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s_axis_spike:s_axis_weight:m_axis_spike, ASSOCIATED_RESET s_axi_aresetn" *)
    input wire  s_axi_aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire  s_axi_aresetn,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Interface
    // ------------------------------------------------------------------------
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] s_axi_awaddr,
    input wire [2 : 0]                    s_axi_awprot,
    input wire                            s_axi_awvalid,
    output wire                           s_axi_awready,
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] s_axi_wdata,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] s_axi_wstrb,
    input wire                            s_axi_wvalid,
    output wire                           s_axi_wready,
    output wire [1 : 0]                   s_axi_bresp,
    output wire                           s_axi_bvalid,
    input wire                            s_axi_bready,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] s_axi_araddr,
    input wire [2 : 0]                    s_axi_arprot,
    input wire                            s_axi_arvalid,
    output wire                           s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] s_axi_rdata,
    output wire [1 : 0]                   s_axi_rresp,
    output wire                           s_axi_rvalid,
    input wire                            s_axi_rready,

    // ------------------------------------------------------------------------
    // AXI4-Stream Spike Input
    // ------------------------------------------------------------------------
    input wire                            s_axis_spike_tvalid,
    input wire [31:0]                     s_axis_spike_tdata,
    input wire                            s_axis_spike_tlast,
    output wire                           s_axis_spike_tready,

    // ------------------------------------------------------------------------
    // AXI4-Stream Weight Input
    // ------------------------------------------------------------------------
    input wire                                  s_axis_weight_tvalid,
    input wire [(PARALLEL_NEURONS*WEIGHT_W)-1:0] s_axis_weight_tdata,
    output wire                                 s_axis_weight_tready,

    // ------------------------------------------------------------------------
    // AXI4-Stream Spike Output
    // ------------------------------------------------------------------------
    output wire [PARALLEL_NEURONS-1:0]          m_axis_spike_tdata,
    output wire                                 m_axis_spike_tvalid,
    output wire                                 m_axis_spike_tlast,
    input wire                                  m_axis_spike_tready
);

    // =========================================================================
    // 1. AXI4-Lite Slave Logic
    // =========================================================================

    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    reg axi_awready;
    reg axi_wready;
    reg [1 : 0] axi_bresp;
    reg axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg [1 : 0] axi_rresp;
    reg axi_rvalid;

    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = axi_bresp;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = axi_rresp;
    assign s_axi_rvalid  = axi_rvalid;

    // ------------------------------------------------------------------------
    // AXI-Lite Register Bank
    // ------------------------------------------------------------------------

    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0; // 0x00: Control
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1; // 0x04: Threshold
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2; // 0x08: Leak factor
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3; // 0x0C: Maximum chunk address

    wire slv_reg_rden;
    wire slv_reg_wren;

    assign slv_reg_wren =
        axi_wready &&
        s_axi_wvalid &&
        axi_awready &&
        s_axi_awvalid;

    assign slv_reg_rden =
        axi_arready &&
        s_axi_arvalid &&
        !axi_rvalid;

    // ------------------------------------------------------------------------
    // AXI-Lite Write Channel
    // ------------------------------------------------------------------------

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'b0;

            slv_reg0 <= 0;
            slv_reg1 <= 32'd15000;
            slv_reg2 <= 32'd29491;
            slv_reg3 <= 0;
        end else begin

            // Capture a write address only when both address and data are
            // presented simultaneously.
            if (!axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_awaddr  <= s_axi_awaddr;
            end else begin
                axi_awready <= 1'b0;
            end

            if (!axi_wready && s_axi_wvalid && s_axi_awvalid) begin
                axi_wready <= 1'b1;
            end else begin
                axi_wready <= 1'b0;
            end

            // Decode the register address and update the selected register.
            case (axi_awaddr[4:2])
                3'h0: if (slv_reg_wren) slv_reg0 <= s_axi_wdata;
                3'h1: if (slv_reg_wren) slv_reg1 <= s_axi_wdata;
                3'h2: if (slv_reg_wren) slv_reg2 <= s_axi_wdata;
                3'h3: if (slv_reg_wren) slv_reg3 <= s_axi_wdata;
                default: ;
            endcase

            // Bit 1 of the control register is used as a one-cycle timestep
            // control pulse.
            if (!slv_reg_wren && slv_reg0[1])
                slv_reg0[1] <= 1'b0;

            // Generate an AXI-Lite write response after accepting the write.
            if (axi_awready &&
                s_axi_awvalid &&
                !axi_bvalid &&
                axi_wready &&
                s_axi_wvalid) begin

                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;

            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // AXI-Lite Read Channel
    // ------------------------------------------------------------------------

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rresp   <= 2'b0;
        end else begin

            if (!axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_araddr  <= s_axi_araddr;
            end else begin
                axi_arready <= 1'b0;
            end

            if (slv_reg_rden) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b0;
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // Multiplex the selected register onto the AXI-Lite read data bus.
    always @(*) begin
        case (axi_araddr[4:2])
            3'h0: axi_rdata = slv_reg0;
            3'h1: axi_rdata = slv_reg1;
            3'h2: axi_rdata = slv_reg2;
            3'h3: axi_rdata = slv_reg3;
            default: axi_rdata = 0;
        endcase
    end

    // =========================================================================
    // 2. SNN Control Signal Generation
    // =========================================================================

    wire ctrl_clear_vmem =
        slv_reg0[0];

    wire ctrl_new_timestep_pulse =
        slv_reg0[1];

    wire signed [VMEM_W-1:0] i_thresh =
        slv_reg1[VMEM_W-1:0];

    wire [15:0] i_leak_factor =
        slv_reg2[15:0];

    wire [$clog2(MAX_CHUNKS)-1:0] i_max_chunks =
        slv_reg3[$clog2(MAX_CHUNKS)-1:0];

    // =========================================================================
    // 3. SNN Core Instantiation
    // =========================================================================

    vrm_snn_core #(
        .PARALLEL_NEURONS(PARALLEL_NEURONS),
        .WEIGHT_W(WEIGHT_W),
        .HEADROOM_BITS(HEADROOM_BITS),
        .VMEM_W(VMEM_W),
        .MAX_CHUNKS(MAX_CHUNKS),
        .LEAK_FRAC_BITS(LEAK_FRAC_BITS),
        .FIFO_DEPTH(FIFO_DEPTH),
        .RAM_STYLE(RAM_STYLE),
        .ADDR_W(ADDR_W)
    ) U_SNN_CORE (
        .aclk(s_axi_aclk),
        .aresetn(s_axi_aresetn),

        .ctrl_new_timestep(ctrl_new_timestep_pulse),
        .ctrl_clear_vmem(ctrl_clear_vmem),
        .i_thresh(i_thresh),
        .i_leak_factor(i_leak_factor),
        .i_max_chunks(i_max_chunks),

        // The AXI4-Stream spike input is 32 bits wide at the wrapper
        // boundary. Only bit 0 is consumed by the scalar spike datapath.
        .s_axis_spike_tvalid(s_axis_spike_tvalid),
        .s_axis_spike_tdata(s_axis_spike_tdata[0]),
        .s_axis_spike_tlast(s_axis_spike_tlast),
        .s_axis_spike_tready(s_axis_spike_tready),

        .s_axis_weight_tvalid(s_axis_weight_tvalid),
        .s_axis_weight_tdata(s_axis_weight_tdata),
        .s_axis_weight_tready(s_axis_weight_tready),

        .m_axis_spike_tdata(m_axis_spike_tdata),
        .m_axis_spike_tvalid(m_axis_spike_tvalid),
        .m_axis_spike_tlast(m_axis_spike_tlast),
        .m_axis_spike_tready(m_axis_spike_tready)
    );

endmodule
```
