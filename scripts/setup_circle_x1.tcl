# setup_circle_x1.tcl -- Create circle_x1 Vivado project and run simulation
# Uses 8.3 short paths to avoid spaces in "Anubhav Gupta" username

set proj_dir {C:/Users/ANUBHA~1/Desktop/Projects/CIRCLE~2}
set ip_dir   {C:/Users/ANUBHA~1/Desktop/Projects/CIRCLE~2/src/ip}
set rtl_dir  {C:/Users/ANUBHA~1/Desktop/Projects/CIRCLE~2/src/rtl}
set sim_dir  {C:/Users/ANUBHA~1/Desktop/Projects/CIRCLE~2/sim}

create_project circle_x1 $proj_dir -part xc7a35tcpg236-1 -force

# Add IP and RTL to design sources
add_files -norecurse [glob "${ip_dir}/*.v"]
add_files -norecurse [glob "${rtl_dir}/*.v"]

# Add IP and RTL to sim_1
add_files -fileset sim_1 -norecurse [glob "${ip_dir}/*.v"]
add_files -fileset sim_1 -norecurse [glob "${rtl_dir}/*.v"]

# Testbench to sim_1
add_files -fileset sim_1 -norecurse "${sim_dir}/circle_x1_tb.v"

# Set tops
set_property top circle_x1    [get_filesets sources_1]
set_property top circle_x1_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# Launch behavioral simulation
launch_simulation -simset sim_1 -mode behavioral
run 10ms
close_sim
