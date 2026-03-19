# ==============================================================================
# Vivado TCL Script to Generate Block Design: systolic2
# Target Board: Xilinx Kria KV260
# ==============================================================================

puts "INFO: Building Block Design: systolic2..."

set design_name "systolic2"
create_bd_design $design_name

# ==============================================================================
# 1. Instantiate IPs
# ==============================================================================

# --- Custom Systolic Wrapper ---
set systolic_axi_wrapper_0 [create_bd_cell -type module -reference systolic_axi_wrapper systolic_axi_wrapper_0]
set_property -dict [list CONFIG.ROWS {8} CONFIG.COLS {8} CONFIG.C_AXIS_DATA_WIDTH {128}] $systolic_axi_wrapper_0

# --- Zynq UltraScale+ PS ---
set zynq_ultra_ps_e_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0]
# Terapkan Board Preset KV260 secara otomatis untuk menghindari ratusan baris konfigurasi MIO/DDR
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} $zynq_ultra_ps_e_0
set_property -dict [list \
  CONFIG.PSU__USE__M_AXI_GP0 {1} \
  CONFIG.PSU__USE__S_AXI_GP2 {1} \
  CONFIG.PSU__USE__S_AXI_GP3 {1} \
] $zynq_ultra_ps_e_0

# --- AXI DMA ---
set axi_dma_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
  CONFIG.c_include_sg {0} \
  CONFIG.c_m_axis_mm2s_tdata_width {128} \
  CONFIG.c_sg_length_width {26} \
] $axi_dma_0

# --- Interconnects & Resets ---
set ps8_0_axi_periph [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps8_0_axi_periph]
set_property CONFIG.NUM_MI {2} $ps8_0_axi_periph

set axi_smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc]
set axi_smc_1 [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_1]
set rst_ps8_0_99M [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps8_0_99M]

# ==============================================================================
# 2. Make Connections
# ==============================================================================

# --- Data Flow (AXI-Stream) ---
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins systolic_axi_wrapper_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins systolic_axi_wrapper_0/m_axis] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# --- Control Flow (AXI-Lite) ---
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins ps8_0_axi_periph/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M01_AXI] [get_bd_intf_pins systolic_axi_wrapper_0/s_axi]

# --- Memory Flow (DMA to Zynq HP Ports) ---
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_smc_1/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_1/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP1_FPD]

# --- Clocks & Resets ---
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
  [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
  [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] \
  [get_bd_pins zynq_ultra_ps_e_0/saxihp1_fpd_aclk] \
  [get_bd_pins ps8_0_axi_periph/ACLK] \
  [get_bd_pins ps8_0_axi_periph/S00_ACLK] \
  [get_bd_pins ps8_0_axi_periph/M00_ACLK] \
  [get_bd_pins ps8_0_axi_periph/M01_ACLK] \
  [get_bd_pins axi_smc/aclk] \
  [get_bd_pins axi_smc_1/aclk] \
  [get_bd_pins axi_dma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] \
  [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] \
  [get_bd_pins systolic_axi_wrapper_0/aclk] \
  [get_bd_pins rst_ps8_0_99M/slowest_sync_clk]

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins rst_ps8_0_99M/ext_reset_in]

connect_bd_net [get_bd_pins rst_ps8_0_99M/peripheral_aresetn] \
  [get_bd_pins ps8_0_axi_periph/ARESETN] \
  [get_bd_pins ps8_0_axi_periph/S00_ARESETN] \
  [get_bd_pins ps8_0_axi_periph/M00_ARESETN] \
  [get_bd_pins ps8_0_axi_periph/M01_ARESETN] \
  [get_bd_pins axi_smc/aresetn] \
  [get_bd_pins axi_smc_1/aresetn] \
  [get_bd_pins axi_dma_0/axi_resetn] \
  [get_bd_pins systolic_axi_wrapper_0/aresetn]

# ==============================================================================
# 3. Address Map Assignment
# ==============================================================================
assign_bd_address -offset 0xA0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg] -force
assign_bd_address -offset 0xA0010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs systolic_axi_wrapper_0/s_axi/reg0] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP3/HP1_DDR_LOW] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_LOW] -force

# ==============================================================================
# 4. Finalize
# ==============================================================================
regenerate_bd_layout
validate_bd_design
save_bd_design

puts "INFO: Block Design 'systolic2' generated successfully!"
