`timescale 1ns / 1ps

/* ============================================================================
 * MODULE: systolic_axi_wrapper
 * AUTHOR: VRM21-Studios
 * DESCRIPTION: 
 * AXI4-Lite and AXI4-Stream wrapper for the Systolic Array Core Engine.
 * - AXI4-Lite: Used for static configuration (Soft Reset, Weights, Biases)
 * - AXI4-Stream (Slave): Receives input activations/features.
 * - AXI4-Stream (Master): Transmits computation results.
 *
 * NOTE ON SCALABILITY:
 * C_S_AXI_ADDR_WIDTH is set to 12-bit (4KB address space) to comfortably 
 * accommodate the memory map of a 32x32 array.
 * ============================================================================ */

module systolic_axi_wrapper #(
    // --- Systolic Core Parameters ---
    parameter ROWS               = 8,
    parameter COLS               = 8,
    parameter WIDTH              = 16,
    parameter FRAC_BIT           = 10,
    
    // --- AXI4 Interface Parameters ---
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 12, // 12-bit = 4KB space (Safe for up to 32x32 array)
    parameter C_AXIS_DATA_WIDTH  = 128 // Default to 128-bit (Fits 8 columns x 16-bit)
)(
    input  wire                                  aclk,
    input  wire                                  aresetn,

    // --- AXI4-LITE SLAVE INTERFACE (Control & Config) ---
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]       s_axi_awaddr,
    input  wire [2 : 0]                          s_axi_awprot,
    input  wire                                  s_axi_awvalid,
    output wire                                  s_axi_awready,
    
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0]       s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0]   s_axi_wstrb,
    input  wire                                  s_axi_wvalid,
    output wire                                  s_axi_wready,
    
    output wire [1 : 0]                          s_axi_bresp,
    output wire                                  s_axi_bvalid,
    input  wire                                  s_axi_bready,
    
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]       s_axi_araddr,
    input  wire [2 : 0]                          s_axi_arprot,
    input  wire                                  s_axi_arvalid,
    output wire                                  s_axi_arready,
    
    output wire [C_S_AXI_DATA_WIDTH-1 : 0]       s_axi_rdata,
    output wire [1 : 0]                          s_axi_rresp,
    output wire                                  s_axi_rvalid,
    input  wire                                  s_axi_rready,

    // --- AXI4-STREAM SLAVE INTERFACE (Input A) ---
    input  wire [C_AXIS_DATA_WIDTH-1 : 0]        s_axis_tdata,
    input  wire [(C_AXIS_DATA_WIDTH/8)-1 : 0]    s_axis_tkeep,
    input  wire                                  s_axis_tlast,
    input  wire                                  s_axis_tvalid,
    output wire                                  s_axis_tready,

    // --- AXI4-STREAM MASTER INTERFACE (Output Y) ---
    output wire [C_AXIS_DATA_WIDTH-1 : 0]        m_axis_tdata,
    output wire [(C_AXIS_DATA_WIDTH/8)-1 : 0]    m_axis_tkeep,
    output wire                                  m_axis_tlast,
    output wire                                  m_axis_tvalid,
    input  wire                                  m_axis_tready
);

    // =========================================================================
    // HELPER PARAMETERS & MEMORY MAP DEFINITION
    // =========================================================================
    localparam PROD_WIDTH    = WIDTH * 2;
    localparam HEADROOM_BITS = (ROWS == 1) ? 1 : $clog2(ROWS);
    localparam ACC_WIDTH     = PROD_WIDTH + HEADROOM_BITS; 

    localparam TOTAL_WEIGHT_BITS = ROWS * COLS * WIDTH;
    localparam TOTAL_BIAS_BITS   = COLS * ACC_WIDTH;

    localparam NUM_REG_WEIGHT = (TOTAL_WEIGHT_BITS + 31) / 32;
    localparam NUM_REG_BIAS   = (TOTAL_BIAS_BITS + 31) / 32;

    // Memory Map
    localparam ADDR_CTRL   = 12'h000;
    localparam ADDR_W_BASE = 12'h100; // Weights start at offset 0x100
    localparam ADDR_B_BASE = ADDR_W_BASE + (NUM_REG_WEIGHT * 4);

    // =========================================================================
    // INTERNAL REGISTERS & SIGNALS
    // =========================================================================
    // 2D Arrays for clean Vivado memory mapping (Prevents Multiple Driver error)
    reg [31:0] slv_reg_weight [0:NUM_REG_WEIGHT-1];
    reg [31:0] slv_reg_bias   [0:NUM_REG_BIAS-1];
    reg        r_soft_clr;

    reg axi_awready;
    reg axi_wready;
    reg [1:0] axi_bresp;
    reg axi_bvalid;
    reg axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg axi_rvalid;

    wire slv_reg_wren = axi_wready && s_axi_wvalid && axi_awready && s_axi_awvalid;
    wire slv_reg_rden = axi_arready && s_axi_arvalid && ~axi_rvalid;

    // =========================================================================
    // 1. AXI4-LITE WRITE LOGIC & REGISTER MAPPING
    // =========================================================================
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = axi_bresp;
    assign s_axi_bvalid  = axi_bvalid;

    integer w_idx, b_idx;
    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'b0;
            r_soft_clr  <= 1'b0;
            // Clear all register arrays
            for (w_idx = 0; w_idx < NUM_REG_WEIGHT; w_idx = w_idx + 1) slv_reg_weight[w_idx] <= 32'd0;
            for (b_idx = 0; b_idx < NUM_REG_BIAS; b_idx = b_idx + 1)   slv_reg_bias[b_idx]   <= 32'd0;
        end 
        else begin
            // Handshake logic
            axi_awready <= (~axi_awready && s_axi_awvalid && s_axi_wvalid) ? 1'b1 : 1'b0;
            axi_wready  <= (~axi_wready && s_axi_wvalid && s_axi_awvalid) ? 1'b1 : 1'b0;

            if (axi_awready && s_axi_awvalid && ~axi_bvalid && axi_wready && s_axi_wvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0; // OKAY
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0; 
            end

            // Address Decoding & Register Writes
            if (slv_reg_wren) begin
                if (s_axi_awaddr == ADDR_CTRL) begin
                    r_soft_clr <= s_axi_wdata[0];
                end
                else if (s_axi_awaddr >= ADDR_W_BASE && s_axi_awaddr < ADDR_B_BASE) begin
                    w_idx = (s_axi_awaddr - ADDR_W_BASE) >> 2;
                    if (w_idx < NUM_REG_WEIGHT) slv_reg_weight[w_idx] <= s_axi_wdata;
                end
                else if (s_axi_awaddr >= ADDR_B_BASE && s_axi_awaddr < (ADDR_B_BASE + (NUM_REG_BIAS * 4))) begin
                    b_idx = (s_axi_awaddr - ADDR_B_BASE) >> 2;
                    if (b_idx < NUM_REG_BIAS) slv_reg_bias[b_idx] <= s_axi_wdata;
                end
            end
        end
    end

    // =========================================================================
    // 2. AXI4-LITE READ LOGIC (Simple Readback)
    // =========================================================================
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = 2'b0; // OKAY
    assign s_axi_rvalid  = axi_rvalid;

    always @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 0;
        end else begin
            axi_arready <= (~axi_arready && s_axi_arvalid) ? 1'b1 : 1'b0;

            if (slv_reg_rden) begin
                axi_rvalid <= 1'b1;
                if (s_axi_araddr == ADDR_CTRL) 
                    axi_rdata <= {31'b0, r_soft_clr};
                else 
                    axi_rdata <= 32'hDEADBEEF; // Default unmapped read
            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 3. FLATTEN 2D ARRAYS FOR SYSTOLIC CORE INPUT
    // =========================================================================
    wire [TOTAL_WEIGHT_BITS-1:0] flat_weights;
    wire [TOTAL_BIAS_BITS-1:0]   flat_biases;
    genvar g;

    generate
        for (g = 0; g < NUM_REG_WEIGHT; g = g + 1) begin : FLAT_W
            if (g == NUM_REG_WEIGHT - 1 && (TOTAL_WEIGHT_BITS % 32 != 0))
                assign flat_weights[(g*32) +: (TOTAL_WEIGHT_BITS % 32)] = slv_reg_weight[g][(TOTAL_WEIGHT_BITS % 32)-1:0];
            else
                assign flat_weights[(g*32) +: 32] = slv_reg_weight[g];
        end

        for (g = 0; g < NUM_REG_BIAS; g = g + 1) begin : FLAT_B
            if (g == NUM_REG_BIAS - 1 && (TOTAL_BIAS_BITS % 32 != 0))
                assign flat_biases[(g*32) +: (TOTAL_BIAS_BITS % 32)] = slv_reg_bias[g][(TOTAL_BIAS_BITS % 32)-1:0];
            else
                assign flat_biases[(g*32) +: 32] = slv_reg_bias[g];
        end
    endgenerate

    // =========================================================================
    // 4. SYSTOLIC CORE INSTANTIATION & AXI-STREAM MAPPING
    // =========================================================================
    wire [(ROWS * WIDTH)-1 : 0] core_data_a;
    wire [(COLS * WIDTH)-1 : 0] core_data_y;
    
    // Safety check for AXI-Stream TDATA truncation/padding
    localparam CORE_OUT_WIDTH = COLS * WIDTH;
    
    assign core_data_a  = s_axis_tdata[(ROWS * WIDTH)-1 : 0];
    assign m_axis_tkeep = {(C_AXIS_DATA_WIDTH/8){1'b1}}; 

    generate
        if (C_AXIS_DATA_WIDTH > CORE_OUT_WIDTH) begin
            assign m_axis_tdata = {{(C_AXIS_DATA_WIDTH - CORE_OUT_WIDTH){1'b0}}, core_data_y};
        end else begin
            assign m_axis_tdata = core_data_y[C_AXIS_DATA_WIDTH-1 : 0];
        end
    endgenerate

    systolic_core_engine #(
        .ROWS(ROWS),
        .COLS(COLS),
        .WIDTH(WIDTH),
        .FRAC_BIT(FRAC_BIT)
    ) syst_inst (
        .clk        (aclk),
        .rstn       (aresetn), 
        .clr        (r_soft_clr), 

        .s_data_a   (core_data_a),
        .s_valid    (s_axis_tvalid),
        .s_last     (s_axis_tlast),
        .s_ready    (s_axis_tready),

        .m_data_y   (core_data_y),
        .m_valid    (m_axis_tvalid),
        .m_last     (m_axis_tlast),
        .m_ready    (m_axis_tready),

        .i_weight   (flat_weights),
        .i_bias     (flat_biases)
    );

endmodule