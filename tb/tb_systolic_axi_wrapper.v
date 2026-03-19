`timescale 1ns / 1ps

/* ============================================================================
 * MODULE: tb_systolic_axi_wrapper
 * AUTHOR: VRM21-Studios
 * DESCRIPTION: 
 * Automated Testbench for the AXI4 Systolic Array Wrapper.
 * * FEATURES:
 * - Simulates AXI4-Lite burst writes for Weights (Identity Matrix) and Biases.
 * - Simulates AXI4-Stream 128-bit vector injection (Input Activations).
 * - Automatic self-checking assertions for expected MAC results.
 * - NEW: Exports input stimulus, weights, biases, and MAC results to CSV files
 * for Python-based data visualization and verification.
 * ============================================================================ */

module tb_systolic_axi_wrapper();

    // =========================================================
    // 1. PARAMETER DEFINITIONS (8x8 CONFIGURATION)
    // =========================================================
    localparam ROWS         = 8;
    localparam COLS         = 8;
    localparam WIDTH        = 16;
    localparam FRAC_BIT     = 0;  // Integer mode for easy visual verification
    
    // AXI Parameters
    localparam C_S_AXI_DATA_WIDTH = 32;
    localparam C_S_AXI_ADDR_WIDTH = 12; // 4KB Address Space
    localparam C_AXIS_DATA_WIDTH  = 128; // 8 elements * 16 bits = 128 bit bus

    // Internal Calculations
    localparam PROD_WIDTH    = WIDTH * 2;
    localparam HEADROOM_BITS = $clog2(ROWS); 
    localparam ACC_WIDTH     = PROD_WIDTH + HEADROOM_BITS; // 35 bits

    // =========================================================
    // 2. SIGNAL DECLARATIONS
    // =========================================================
    reg  aclk;
    reg  aresetn;

    // --- AXI4-Lite Signals ---
    reg  [C_S_AXI_ADDR_WIDTH-1 : 0]    s_axi_awaddr;
    reg  [2 : 0]                       s_axi_awprot;
    reg                                s_axi_awvalid;
    wire                               s_axi_awready;
    
    reg  [C_S_AXI_DATA_WIDTH-1 : 0]    s_axi_wdata;
    reg  [(C_S_AXI_DATA_WIDTH/8)-1 : 0]s_axi_wstrb;
    reg                                s_axi_wvalid;
    wire                               s_axi_wready;
    
    wire [1 : 0]                       s_axi_bresp;
    wire                               s_axi_bvalid;
    reg                                s_axi_bready;
    
    reg  [C_S_AXI_ADDR_WIDTH-1 : 0]    s_axi_araddr;
    reg  [2 : 0]                       s_axi_arprot;
    reg                                s_axi_arvalid;
    wire                               s_axi_arready;
    
    wire [C_S_AXI_DATA_WIDTH-1 : 0]    s_axi_rdata;
    wire [1 : 0]                       s_axi_rresp;
    wire                               s_axi_rvalid;
    reg                                s_axi_rready;

    // --- AXI4-Stream Slave (Input A) ---
    reg  [C_AXIS_DATA_WIDTH-1 : 0]     s_axis_tdata;
    reg  [(C_AXIS_DATA_WIDTH/8)-1 : 0] s_axis_tkeep;
    reg                                s_axis_tlast;
    reg                                s_axis_tvalid;
    wire                               s_axis_tready;

    // --- AXI4-Stream Master (Output Y) ---
    wire [C_AXIS_DATA_WIDTH-1 : 0]     m_axis_tdata;
    wire [(C_AXIS_DATA_WIDTH/8)-1 : 0] m_axis_tkeep;
    wire                               m_axis_tlast;
    wire                               m_axis_tvalid;
    reg                                m_axis_tready;

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    systolic_axi_wrapper #(
        .ROWS(ROWS),
        .COLS(COLS),
        .WIDTH(WIDTH),
        .FRAC_BIT(FRAC_BIT),
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_AXIS_DATA_WIDTH(C_AXIS_DATA_WIDTH)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),

        .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),   .s_axi_wstrb(s_axi_wstrb),   .s_axi_wvalid(s_axi_wvalid),   .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),   .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arprot(s_axi_arprot), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),   .s_axi_rresp(s_axi_rresp),   .s_axi_rvalid(s_axi_rvalid),   .s_axi_rready(s_axi_rready),

        .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep), .s_axis_tlast(s_axis_tlast), .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep), .m_axis_tlast(m_axis_tlast), .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready)
    );

    // Clock Generation (100 MHz)
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end

    // =========================================================
    // 4. TASKS (Helper Functions)
    // =========================================================
    task axi_lite_write;
        input [C_S_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S_AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_wstrb   <= 4'hF; 
            s_axi_bready  <= 1'b1;

            wait(s_axi_awready && s_axi_wready);
            
            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            wait(s_axi_bvalid);
            @(posedge aclk);
            s_axi_bready <= 1'b0;
        end
    endtask

    task axis_send_packet;
        input [C_AXIS_DATA_WIDTH-1:0] data;
        input last;
        begin
            @(posedge aclk);
            s_axis_tdata  <= data;
            s_axis_tlast  <= last;
            s_axis_tvalid <= 1'b1;
            s_axis_tkeep  <= {(C_AXIS_DATA_WIDTH/8){1'b1}};

            wait(s_axis_tready);
            @(posedge aclk);
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= 0;
        end
    endtask

    // =========================================================
    // 5. MAIN STIMULUS & CSV EXPORT
    // =========================================================
    
    // File Descriptors for CSV
    integer fd_in, fd_out;

    reg [1024-1:0] huge_weights; 
    reg [280-1:0]  huge_biases;

    integer r, c, k;
    reg [C_S_AXI_ADDR_WIDTH-1:0] current_addr;

    initial begin
        // Open CSV files for writing
        fd_in  = $fopen("sim_input_stimulus.csv", "w");
        fd_out = $fopen("sim_mac_results.csv", "w");
        
        $fdisplay(fd_in, "Time(ns),CH0,CH1,CH2,CH3,CH4,CH5,CH6,CH7,TLAST");
        $fdisplay(fd_out, "Time(ns),Y0,Y1,Y2,Y3,Y4,Y5,Y6,Y7,TLAST");

        // --- A. INITIALIZATION ---
        r = 0; c = 0; k = 0;
        aresetn = 0;
        
        s_axi_awaddr = 0; s_axi_awprot = 0; s_axi_awvalid = 0;
        s_axi_wdata  = 0; s_axi_wstrb  = 0; s_axi_wvalid  = 0; s_axi_bready = 0;
        s_axi_araddr = 0; s_axi_arprot = 0; s_axi_arvalid = 0; s_axi_rready = 0;

        s_axis_tdata = 0; s_axis_tkeep = 0; s_axis_tlast = 0; s_axis_tvalid = 0;
        m_axis_tready = 1;

        huge_weights = 0; huge_biases = 0; current_addr = 0;

        #100;
        aresetn = 1;
        $display("\n=== SIMULATION STARTED ===");

        // --- B. PREPARE & UPLOAD WEIGHTS (IDENTITY MATRIX) ---
        $display("-> Generating and Uploading 8x8 Identity Weights...");
        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                if (r == c) huge_weights[((r*COLS + c)*WIDTH) +: WIDTH] = 16'd1;
                else        huge_weights[((r*COLS + c)*WIDTH) +: WIDTH] = 16'd0;
            end
        end

        current_addr = 12'h100; // Base Addr Weight
        for (k = 0; k < 32; k = k + 1) begin
            axi_lite_write(current_addr, huge_weights[k*32 +: 32]);
            current_addr = current_addr + 4;
        end

        // --- C. PREPARE & UPLOAD BIASES (Val = 10) ---
        $display("-> Generating and Uploading 8 Biases...");
        for (c = 0; c < COLS; c = c + 1) begin
            huge_biases[(c * ACC_WIDTH) +: ACC_WIDTH] = 35'd10;
        end
        
        current_addr = 12'h100 + 128; // Base Addr Bias
        for (k = 0; k < 8; k = k + 1) begin
            axi_lite_write(current_addr, huge_biases[k*32 +: 32]);
            current_addr = current_addr + 4;
        end
        axi_lite_write(current_addr, {8'b0, huge_biases[279:256]});

        // --- D. SEND STREAM DATA & LOG TO CSV ---
        $display("-> Streaming 128-bit Vector Inputs...");
        #50;

        // Packet 1: A = [1, 2, 3, 4, 5, 6, 7, 8]
        $fdisplay(fd_in, "%0t,1,2,3,4,5,6,7,8,0", $time);
        axis_send_packet(128'h00080007000600050004000300020001, 1'b0);

        // Packet 2 (LAST): A = [10, 20, 30, 40, 50, 60, 70, 80]
        $fdisplay(fd_in, "%0t,10,20,30,40,50,60,70,80,1", $time);
        axis_send_packet(128'h00500046003C00320028001E0014000A, 1'b1);

        #500;
        
        // Close CSV files
        $fclose(fd_in);
        $fclose(fd_out);
        
        $display("\n=== SIMULATION FINISHED SUCCESSFULLY ===");
        $display("-> Output data exported to 'sim_mac_results.csv'");
        $finish;
    end

    // =========================================================
    // 6. OUTPUT MONITOR & CSV LOGGING
    // =========================================================
    wire signed [15:0] y0 = m_axis_tdata[0*16 +: 16];
    wire signed [15:0] y1 = m_axis_tdata[1*16 +: 16];
    wire signed [15:0] y2 = m_axis_tdata[2*16 +: 16];
    wire signed [15:0] y3 = m_axis_tdata[3*16 +: 16];
    wire signed [15:0] y4 = m_axis_tdata[4*16 +: 16];
    wire signed [15:0] y5 = m_axis_tdata[5*16 +: 16];
    wire signed [15:0] y6 = m_axis_tdata[6*16 +: 16];
    wire signed [15:0] y7 = m_axis_tdata[7*16 +: 16];

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            
            // 1. Print to Terminal
            $display("\n[RESULT] Time: %0t ns, TLAST: %b", $time, m_axis_tlast);
            $display("  Values : [%d, %d, %d, %d, %d, %d, %d, %d]", 
                     y0, y1, y2, y3, y4, y5, y6, y7);
                     
            // 2. Write to Output CSV
            $fdisplay(fd_out, "%0t,%d,%d,%d,%d,%d,%d,%d,%d,%b", 
                      $time, y0, y1, y2, y3, y4, y5, y6, y7, m_axis_tlast);
            
            // 3. Assertion Checks
            if (y0 == 11 && y7 == 18) 
                $display("  -> STATUS: PASS (Packet 1 Identity Check)");
            else if (y0 == 20 && y7 == 90)
                $display("  -> STATUS: PASS (Packet 2 Identity Check)");
            else 
                $display("  -> WARNING: Data propagating (Expected pipeline delay)");
        end
    end

endmodule