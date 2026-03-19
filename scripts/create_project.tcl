# ==============================================================================
# Vivado TCL Script to Re-create AXI-Native Systolic Array Project
# Target Board: Xilinx Kria KV260 Vision AI Starter Kit
# ==============================================================================

# Set Project Variables
set project_name "axi_systolic_array"
set part_name "xck26-sfvc784-2LV-c"
set board_part "xilinx.com:kv260_som:part0:1.4"

# Dynamically find the root directory of the git repository
set origin_dir [file normalize [file dirname [info script]]/..]

# ==============================================================================
# 1. Create Project & Set Board Properties
# ==============================================================================
create_project ${project_name} ${origin_dir}/vivado_proj -part ${part_name} -force
set obj [current_project]
set_property board_part ${board_part} $obj
set_property default_lib xil_defaultlib $obj
set_property simulator_language Mixed $obj

# ==============================================================================
# 2. Add Source & Simulation Files
# ==============================================================================
puts "INFO: Adding RTL and Simulation files..."

# Add RTL sources
add_files -fileset sources_1 [list \
  [file normalize "${origin_dir}/rtl/systolic_core_engine.v"] \
  [file normalize "${origin_dir}/rtl/systolic_axi_wrapper.v"] \
]

# Add Simulation sources
add_files -fileset sim_1 [list \
  [file normalize "${origin_dir}/sim/tb_systolic_core_engine.v"] \
  [file normalize "${origin_dir}/sim/tb_systolic_axi_wrapper.v"] \
]

set_property top tb_systolic_axi_wrapper [get_filesets sim_1]

# ==============================================================================
# 3. Create Block Design (Zynq PS + DMA + Systolic Wrapper)
# ==============================================================================
puts "INFO: Creating Block Design..."

set design_name "systolic_bd"
create_bd_design $design_name

# --- Add IPs ---
# 1. Systolic AXI Wrapper (Our Custom IP)
set systolic_wrapper [create_bd_cell -type module -reference systolic_axi_wrapper systolic_wrapper_0]
set_property -dict [list CONFIG.ROWS {8} CONFIG.COLS {8} CONFIG.C_AXIS_DATA_WIDTH {128}] $systolic_wrapper

# 2. Zynq UltraScale+ PS (Configured for KV260)
set zynq_ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1" }  [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list \
  CONFIG.PSU__USE__M_AXI_GP0 {1} \
  CONFIG.PSU__USE__S_AXI_GP2 {1} \
  CONFIG.PSU__USE__S_AXI_GP3 {1} \
] $zynq_ps

# 3. AXI DMA
set axi_dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
  CONFIG.c_include_sg {0} \
  CONFIG.c_m_axis_mm2s_tdata_width {128} \
] $axi_dma

# 4. Interconnects & Resets
set axi_periph [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps8_0_axi_periph]
set_property CONFIG.NUM_MI {2} $axi_periph

set smartconnect_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
set smartconnect_1 [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_1]
set rst_ps [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps8_0_99M]

# --- Connections ---
# AXI Stream (Data Flow)
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins systolic_wrapper_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins systolic_wrapper_0/m_axis] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# AXI Lite (Control Flow)
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins ps8_0_axi_periph/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ps8_0_axi_periph/M01_AXI] [get_bd_intf_pins systolic_wrapper_0/s_axi]

# DMA to PS Memory (HP Ports)
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins smartconnect_1/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_1/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP1_FPD]

# Clocks & Resets
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
  [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
  [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] \
  [get_bd_pins zynq_ultra_ps_e_0/saxihp1_fpd_aclk] \
  [get_bd_pins ps8_0_axi_periph/ACLK] \
  [get_bd_pins ps8_0_axi_periph/S00_ACLK] \
  [get_bd_pins ps8_0_axi_periph/M00_ACLK] \
  [get_bd_pins ps8_0_axi_periph/M01_ACLK] \
  [get_bd_pins smartconnect_0/aclk] \
  [get_bd_pins smartconnect_1/aclk] \
  [get_bd_pins axi_dma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] \
  [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] \
  [get_bd_pins systolic_wrapper_0/aclk] \
  [get_bd_pins rst_ps8_0_99M/slowest_sync_clk]

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins rst_ps8_0_99M/ext_reset_in]

connect_bd_net [get_bd_pins rst_ps8_0_99M/peripheral_aresetn] \
  [get_bd_pins ps8_0_axi_periph/ARESETN] \
  [get_bd_pins ps8_0_axi_periph/S00_ARESETN] \
  [get_bd_pins ps8_0_axi_periph/M00_ARESETN] \
  [get_bd_pins ps8_0_axi_periph/M01_ARESETN] \
  [get_bd_pins smartconnect_0/aresetn] \
  [get_bd_pins smartconnect_1/aresetn] \
  [get_bd_pins axi_dma_0/axi_resetn] \
  [get_bd_pins systolic_wrapper_0/aresetn]

# --- Address Assignments ---
assign_bd_address -offset 0xA0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg] -force
assign_bd_address -offset 0xA0010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] [get_bd_addr_segs systolic_wrapper_0/s_axi/reg0] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP3/HP1_DDR_LOW] -force
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] [get_bd_addr_segs zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_LOW] -force

# Auto-route Layout and Validate
regenerate_bd_layout
validate_bd_design
save_bd_design

# ==============================================================================
# 4. Generate Top-Level Wrapper
# ==============================================================================
puts "INFO: Generating Block Design Wrapper..."
make_wrapper -files [get_files ${design_name}.bd] -top -import
set_property top ${design_name}_wrapper [current_fileset]

puts "=========================================================="
puts "SUCCESS: Project recreated successfully!"
puts "You can now run Synthesis or Implementation."
puts "=========================================================="
