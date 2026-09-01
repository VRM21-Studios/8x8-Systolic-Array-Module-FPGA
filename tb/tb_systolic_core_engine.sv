`timescale 1ns / 1ps

/* ============================================================================
 * MODULE: tb_systolic_core_engine
 * AUTHOR: VRM21-Studios
 * DESCRIPTION: 
 * Direct Testbench for the bare Systolic Core Engine.
 * Bypasses AXI-Lite/Stream wrappers to test the raw math and pipelining.
 * * FEATURES:
 * - Direct static injection of Weights and Biases (Identity Matrix + Offset).
 * - Streamlined handshake testing (Valid/Ready/Last).
 * - CSV Export for Python visualization.
 * ============================================================================ */

module tb_systolic_core_engine();

    // =========================================================
    // 1. PARAMETERS (8x8 CONFIGURATION)
    // =========================================================
    localparam ROWS         = 8;
    localparam COLS         = 8;
    localparam WIDTH        = 16;
    localparam FRAC_BIT     = 0;  // Q-Format integer mode untuk kemudahan baca
    
    localparam PROD_WIDTH    = WIDTH * 2;
    localparam HEADROOM_BITS = $clog2(ROWS); 
    localparam ACC_WIDTH     = PROD_WIDTH + HEADROOM_BITS; // 35 bits

    localparam TOTAL_WEIGHT_BITS = ROWS * COLS * WIDTH;
    localparam TOTAL_BIAS_BITS   = COLS * ACC_WIDTH;

    // =========================================================
    // 2. SIGNAL DECLARATIONS
    // =========================================================
    reg  clk;
    reg  rstn;
    reg  clr;

    // --- Dynamic Stream A (Input) ---
    reg  [(ROWS * WIDTH)-1 : 0] s_data_a;
    reg                         s_valid;
    reg                         s_last;
    wire                        s_ready;

    // --- Dynamic Stream Y (Output) ---
    wire [(COLS * WIDTH)-1 : 0] m_data_y;
    wire                        m_valid;
    wire                        m_last;
    reg                         m_ready;

    // --- Static Config ---
    reg  [TOTAL_WEIGHT_BITS-1 : 0] i_weight;
    reg  [TOTAL_BIAS_BITS-1 : 0]   i_bias;

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    systolic_core_engine #(
        .ROWS(ROWS),
        .COLS(COLS),
        .WIDTH(WIDTH),
        .FRAC_BIT(FRAC_BIT)
    ) dut (
        .clk(clk),
        .rstn(rstn),
        .clr(clr),
        
        .s_data_a(s_data_a),
        .s_valid(s_valid),
        .s_last(s_last),
        .s_ready(s_ready),
        
        .m_data_y(m_data_y),
        .m_valid(m_valid),
        .m_last(m_last),
        .m_ready(m_ready),
        
        .i_weight(i_weight),
        .i_bias(i_bias)
    );

    // Clock Gen (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // 4. TASKS
    // =========================================================
    task send_vector;
        input [(ROWS * WIDTH)-1 : 0] data;
        input last_flag;
        begin
            @(posedge clk);
            s_data_a <= data;
            s_valid  <= 1'b1;
            s_last   <= last_flag;

            wait(s_ready);
            @(posedge clk);
            s_valid <= 1'b0;
            s_last  <= 1'b0;
            s_data_a <= 0;
        end
    endtask

    // =========================================================
    // 5. MAIN STIMULUS & CSV EXPORT
    // =========================================================
    integer fd_in, fd_out;
    integer r, c;

    initial begin
        // Open CSV Files
        fd_in  = $fopen("core_input_stimulus.csv", "w");
        fd_out = $fopen("core_mac_results.csv", "w");
        
        $fdisplay(fd_in, "Time(ns),A0,A1,A2,A3,A4,A5,A6,A7,TLAST");
        $fdisplay(fd_out, "Time(ns),Y0,Y1,Y2,Y3,Y4,Y5,Y6,Y7,TLAST");

        // Init
        rstn     = 0;
        clr      = 0;
        s_data_a = 0;
        s_valid  = 0;
        s_last   = 0;
        m_ready  = 1; // Always ready (no backpressure from sink)
        r        = 0;
        c        = 0;
        
        i_weight = 0;
        i_bias   = 0;

        #50;
        rstn = 1;
        $display("\n=== BARE METAL CORE SIMULATION STARTED ===");

        // --- A. INJEKSI STATIS: WEIGHTS (Identity) & BIASES (15) ---
        $display("-> Mengisi Weight (Identity) & Bias (Val=15) secara instan...");
        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                if (r == c) i_weight[((r*COLS + c)*WIDTH) +: WIDTH] = 16'd1;
                else        i_weight[((r*COLS + c)*WIDTH) +: WIDTH] = 16'd0;
            end
        end
        for (c = 0; c < COLS; c = c + 1) begin
            i_bias[(c * ACC_WIDTH) +: ACC_WIDTH] = 35'd15;
        end

        #20;

        // --- B. TEMBAK DATA STREAM ---
        $display("-> Mengirim Stream Data...");
        
        // Packet 1: A = [1, 2, 3, 4, 5, 6, 7, 8]
        $fdisplay(fd_in, "%0t,1,2,3,4,5,6,7,8,0", $time);
        send_vector(128'h00080007000600050004000300020001, 1'b0);

        // Packet 2: A = [10, 20, 30, 40, 50, 60, 70, 80]
        $fdisplay(fd_in, "%0t,10,20,30,40,50,60,70,80,0", $time);
        send_vector(128'h00500046003C00320028001E0014000A, 1'b0);
        
        // Packet 3 (LAST): A = [100, 200, 300, 400, 500, 600, 700, 800]
        $fdisplay(fd_in, "%0t,100,200,300,400,500,600,700,800,1", $time);
        send_vector(128'h032002BC025801F40190012C00C80064, 1'b1);

        #300;
        
        $fclose(fd_in);
        $fclose(fd_out);
        $display("\n=== BARE METAL CORE SIMULATION FINISHED ===");
        $finish;
    end

    // =========================================================
    // 6. OUTPUT MONITOR & CSV LOGGING
    // =========================================================
    wire signed [15:0] y0 = m_data_y[0*16 +: 16];
    wire signed [15:0] y1 = m_data_y[1*16 +: 16];
    wire signed [15:0] y2 = m_data_y[2*16 +: 16];
    wire signed [15:0] y3 = m_data_y[3*16 +: 16];
    wire signed [15:0] y4 = m_data_y[4*16 +: 16];
    wire signed [15:0] y5 = m_data_y[5*16 +: 16];
    wire signed [15:0] y6 = m_data_y[6*16 +: 16];
    wire signed [15:0] y7 = m_data_y[7*16 +: 16];

    always @(posedge clk) begin
        if (m_valid && m_ready) begin
            $display("\n[CORE OUT] Time: %0t ns, TLAST: %b", $time, m_last);
            $display("  Values : [%d, %d, %d, %d, %d, %d, %d, %d]", 
                     y0, y1, y2, y3, y4, y5, y6, y7);
            
            $fdisplay(fd_out, "%0t,%d,%d,%d,%d,%d,%d,%d,%d,%b", 
                      $time, y0, y1, y2, y3, y4, y5, y6, y7, m_last);
                      
            // Check logic (Y = A + Bias(15))
            if (y0 == 16 && y7 == 23) 
                $display("  -> STATUS: PASS (Packet 1)");
            else if (y0 == 25 && y7 == 95)
                $display("  -> STATUS: PASS (Packet 2)");
            else if (y0 == 115 && y7 == 815)
                $display("  -> STATUS: PASS (Packet 3 - LAST)");
        end
    end

endmodule
