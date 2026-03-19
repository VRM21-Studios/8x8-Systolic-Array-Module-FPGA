`timescale 1ns / 1ps

/* ============================================================================
 * MODULE: systolic_core_engine
 * AUTHOR: VRM21-Studios
 * DESCRIPTION: 
 * A parameterized, weight-stationary Systolic Array core designed for 
 * high-throughput Matrix Multiplication (MAC operations). 
 * Fully pipelined with built-in data skewing, deskewing, and robust 
 * hardclip saturation for Q-format fixed-point arithmetic.
 *
 * FEATURES:
 * - Pure Dataflow Pipelining (Stall-free operation)
 * - AXI-Stream compatible metadata propagation (VALID & TLAST)
 * - Configurable fractional precision (Q-Format)
 * - Automatic internal bit-growth management (Accumulator sizing)
 * - Verilog-2001 synthesis-safe combinatorial shifting & saturation
 * ============================================================================ */

module systolic_core_engine #(
    parameter ROWS     = 8,   // Number of Processing Element rows
    parameter COLS     = 8,   // Number of Processing Element columns
    parameter WIDTH    = 16,  // Bit-width of input data and weights
    parameter FRAC_BIT = 10   // Fractional bits for Q-format fixed-point (e.g., Q6.10)
)(
    input  wire clk,
    input  wire rstn,         // Active-low synchronous reset
    input  wire clr,          // Active-high synchronous clear/flush

    // --- Dynamic Streaming Interface (Data A / Activations) ---
    input  wire [(ROWS * WIDTH)-1 : 0]                 s_data_a,
    input  wire                                        s_valid,
    input  wire                                        s_last,  // AXI-Stream TLAST
    output wire                                        s_ready,

    // --- Dynamic Streaming Interface (Data Y / Results) ---
    output reg  [(COLS * WIDTH)-1 : 0]                 m_data_y,
    output reg                                         m_valid,
    output reg                                         m_last,  // Propagated TLAST
    input  wire                                        m_ready,

    // --- Static Configuration Interface (Weights & Biases) ---
    // Note: Driven by AXI-Lite registers from the wrapper
    input  wire [(ROWS * COLS * WIDTH)-1 : 0]          i_weight,
    input  wire [(COLS * (WIDTH * 2 + ((ROWS == 1) ? 1 : $clog2(ROWS))))-1 : 0] i_bias
);

    // Global pipeline enable signal (backpressure control)
    wire pipe_en = m_ready;
    assign s_ready = m_ready;

    // =========================================================
    // 1. DSP-STYLE ACCUMULATOR & SATURATION LIMITS
    // =========================================================
    // Calculate required accumulator width to prevent internal overflow
    localparam PROD_WIDTH    = WIDTH * 2;
    localparam HEADROOM_BITS = (ROWS == 1) ? 1 : $clog2(ROWS);
    localparam ACC_WIDTH     = PROD_WIDTH + HEADROOM_BITS; 

    // Absolute saturation limits extended to ACC_WIDTH for safe comparison
    localparam signed [ACC_WIDTH-1:0] OUT_MAX = 
        {{(ACC_WIDTH-WIDTH){1'b0}}, 1'b0, {(WIDTH-1){1'b1}}}; // e.g., 32767 for 16-bit

    localparam signed [ACC_WIDTH-1:0] OUT_MIN = 
        {{(ACC_WIDTH-WIDTH){1'b1}}, 1'b1, {(WIDTH-1){1'b0}}}; // e.g., -32768 for 16-bit

    // =========================================================
    // 2. BUS UNPACKING (Flattened arrays to 2D signals)
    // =========================================================
    wire signed [WIDTH-1:0]     a_in   [0:ROWS-1];
    wire signed [WIDTH-1:0]     weight [0:ROWS-1][0:COLS-1];
    wire signed [ACC_WIDTH-1:0] bias   [0:COLS-1];

    genvar i, j, k, c_gen;
    generate
        for (i = 0; i < ROWS; i = i + 1) begin : UNPACK_ROW
            assign a_in[i] = s_data_a[(i * WIDTH) +: WIDTH];
            for (j = 0; j < COLS; j = j + 1) begin : UNPACK_W
                assign weight[i][j] = i_weight[((i * COLS + j) * WIDTH) +: WIDTH];
            end
        end
        for (j = 0; j < COLS; j = j + 1) begin : UNPACK_B
            assign bias[j] = i_bias[(j * ACC_WIDTH) +: ACC_WIDTH];
        end
    endgenerate

    // =========================================================
    // 3. INPUT SKEWING (Temporal alignment for Data A)
    // =========================================================
    // Skews the input rows so wavefront propagates diagonally
    wire signed [WIDTH-1:0] a_skew_w [0:ROWS-1][0:ROWS];
    reg  signed [WIDTH-1:0] a_skew_r [0:ROWS-1][1:ROWS]; 
    
    generate
        for (i = 0; i < ROWS; i = i + 1) begin : SKEW_A_ROW
            assign a_skew_w[i][0] = a_in[i];
            for (k = 0; k < i; k = k + 1) begin : SKEW_A_DELAY
                always @(posedge clk) begin
                    if (!rstn || clr) a_skew_r[i][k+1] <= 0;
                    else if (pipe_en) a_skew_r[i][k+1] <= a_skew_w[i][k];
                end
                assign a_skew_w[i][k+1] = a_skew_r[i][k+1];
            end
        end
    endgenerate

    // =========================================================
    // 4. SYSTOLIC CORE (Weight-Stationary MAC Array)
    // =========================================================
    wire signed [WIDTH-1:0]     a_pipe_w [0:ROWS-1][0:COLS];
    wire signed [ACC_WIDTH-1:0] y_pipe_w [0:ROWS][0:COLS-1];

    reg  signed [WIDTH-1:0]     a_pipe_r [0:ROWS-1][1:COLS];
    reg  signed [ACC_WIDTH-1:0] y_pipe_r [1:ROWS][0:COLS-1];

    generate
        // Initialize top of the array with biases
        for (j = 0; j < COLS; j = j + 1) begin : INIT_Y
            assign y_pipe_w[0][j] = bias[j]; 
        end

        // PE Matrix mapping
        for (i = 0; i < ROWS; i = i + 1) begin : PE_ROW
            assign a_pipe_w[i][0] = a_skew_w[i][i]; 
            for (j = 0; j < COLS; j = j + 1) begin : PE_COL
                // Processing Element Logic
                wire signed [PROD_WIDTH-1:0] product = a_pipe_w[i][j] * weight[i][j];
                wire signed [ACC_WIDTH-1:0]  y_ext   = y_pipe_w[i][j];
                
                always @(posedge clk) begin
                    if (!rstn || clr) begin
                        a_pipe_r[i][j+1] <= 0;
                        y_pipe_r[i+1][j] <= 0;
                    end else if (pipe_en) begin
                        a_pipe_r[i][j+1] <= a_pipe_w[i][j];
                        // Full accumulation to prevent internal precision loss
                        y_pipe_r[i+1][j] <= y_ext + product; 
                    end
                end
                assign a_pipe_w[i][j+1] = a_pipe_r[i][j+1];
                assign y_pipe_w[i+1][j] = y_pipe_r[i+1][j];
            end
        end
    endgenerate

    // =========================================================
    // 5. OUTPUT DESKEWING (Realignment of Data Y)
    // =========================================================
    // Realigns the staggered outputs back into a parallel bus
    wire signed [ACC_WIDTH-1:0] y_deskew_w [0:COLS-1][0:COLS];
    reg  signed [ACC_WIDTH-1:0] y_deskew_r [0:COLS-1][1:COLS];

    generate
        for (j = 0; j < COLS; j = j + 1) begin : DESKEW_Y_COL
            assign y_deskew_w[j][0] = y_pipe_w[ROWS][j];
            for (k = 0; k < (COLS - 1 - j); k = k + 1) begin : DESKEW_Y_DELAY
                always @(posedge clk) begin
                    if (!rstn || clr) y_deskew_r[j][k+1] <= 0;
                    else if (pipe_en) y_deskew_r[j][k+1] <= y_deskew_w[j][k];
                end
                assign y_deskew_w[j][k+1] = y_deskew_r[j][k+1];
            end
        end
    endgenerate

    // =========================================================
    // 6. METADATA PROPAGATION (VALID & TLAST)
    // =========================================================
    // Calculates total pipeline latency to sync sideband signals
    localparam TOTAL_DELAY = ROWS + COLS - 1;
    reg [TOTAL_DELAY-1:0] valid_shift;
    reg [TOTAL_DELAY-1:0] last_shift;
    
    integer v;
    always @(posedge clk) begin
        if (!rstn || clr) begin
            valid_shift <= 0;
            last_shift  <= 0;
        end else if (pipe_en) begin
            valid_shift[0] <= s_valid;
            last_shift[0]  <= s_last;
            for (v = 1; v < TOTAL_DELAY; v = v + 1) begin
                valid_shift[v] <= valid_shift[v-1];
                last_shift[v]  <= last_shift[v-1];
            end
        end
    end
    wire out_valid_internal = valid_shift[TOTAL_DELAY-1];
    wire out_last_internal  = last_shift[TOTAL_DELAY-1];

    // =========================================================
    // 7. FINAL STAGE: QUANTIZATION & HARDCLIP SATURATION
    // =========================================================
    
    // Combinatorial shifting (Verilog-2001 safe)
    wire signed [ACC_WIDTH-1:0] shifted_val_w [0:COLS-1];
    generate
        for (c_gen = 0; c_gen < COLS; c_gen = c_gen + 1) begin : SHIFT_STAGE
            assign shifted_val_w[c_gen] = y_deskew_w[c_gen][COLS - 1 - c_gen] >>> FRAC_BIT;
        end
    endgenerate
    
    initial begin
        m_data_y = 0;
        m_valid  = 0;
        m_last   = 0;
    end
    
    integer c;
    always @(posedge clk) begin
        if (!rstn || clr) begin
            m_data_y <= 0;
            m_valid  <= 0;
            m_last   <= 0;
        end 
        else if (pipe_en) begin
            m_valid <= out_valid_internal;
            m_last  <= out_last_internal;
            
            if (out_valid_internal) begin 
                for (c = 0; c < COLS; c = c + 1) begin
                    // Apply clipping to prevent wrap-around anomalies
                    if (shifted_val_w[c] > OUT_MAX)
                        m_data_y[(c * WIDTH) +: WIDTH] <= OUT_MAX[WIDTH-1:0];
                    else if (shifted_val_w[c] < OUT_MIN)
                        m_data_y[(c * WIDTH) +: WIDTH] <= OUT_MIN[WIDTH-1:0];
                    else
                        m_data_y[(c * WIDTH) +: WIDTH] <= shifted_val_w[c][WIDTH-1:0];
                end
            end
        end
    end

endmodule
