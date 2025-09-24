# Vivado TCL script to export simulation data for debug comparison
# Run this in Vivado after running simulation

# Export waveform data to CSV
set output_file "simulation_data.csv"

# Get current simulation time
set current_time [current_time]
puts "Current simulation time: $current_time"

# Open output file
set fp [open $output_file w]
puts $fp "time,signal_name,value,input_row,input_col,output_row,output_col,input_valid,output_valid"

# Get signal objects
set signals [list]

# Try to get signals from the testbench
if {[catch {
    lappend signals [get_objects -r /conv_layer_tb/input_pixel]
    lappend signals [get_objects -r /conv_layer_tb/input_valid]  
    lappend signals [get_objects -r /conv_layer_tb/input_row]
    lappend signals [get_objects -r /conv_layer_tb/input_col]
    lappend signals [get_objects -r /conv_layer_tb/output_pixel]
    lappend signals [get_objects -r /conv_layer_tb/output_valid]
    lappend signals [get_objects -r /conv_layer_tb/output_row]
    lappend signals [get_objects -r /conv_layer_tb/output_col]
} err]} {
    puts "Warning: Could not find some signals - $err"
}

# Export signal values at different time points
set time_step 10ns
set max_time 10us

for {set t 0} {$t < [scan $max_time %f]} {set t [expr $t + [scan $time_step %f]]} {
    set time_str "${t}ns"
    
    if {[catch {
        # Set simulation time
        set_property -dict [list CONFIG.TIME $time_str] [current_sim]
        
        foreach sig $signals {
            if {$sig ne ""} {
                set sig_name [get_property NAME $sig]
                set sig_value [get_value $sig]
                
                # Get additional context signals
                set input_row_val ""
                set input_col_val ""
                set output_row_val ""
                set output_col_val ""
                set input_valid_val ""
                set output_valid_val ""
                
                catch {set input_row_val [get_value [get_objects -r /conv_layer_tb/input_row]]}
                catch {set input_col_val [get_value [get_objects -r /conv_layer_tb/input_col]]}
                catch {set output_row_val [get_value [get_objects -r /conv_layer_tb/output_row]]}
                catch {set output_col_val [get_value [get_objects -r /conv_layer_tb/output_col]]}
                catch {set input_valid_val [get_value [get_objects -r /conv_layer_tb/input_valid]]}
                catch {set output_valid_val [get_value [get_objects -r /conv_layer_tb/output_valid]]}
                
                puts $fp "$time_str,$sig_name,$sig_value,$input_row_val,$input_col_val,$output_row_val,$output_col_val,$input_valid_val,$output_valid_val"
            }
        }
    } err]} {
        puts "Error at time $time_str: $err"
    }
}

close $fp
puts "Simulation data exported to $output_file"

# Alternative: Export specific transactions only
set transaction_file "transactions.csv"
set fp2 [open $transaction_file w]
puts $fp2 "transaction_type,time,row,col,value,filter_id"

# This would need to be customized based on your specific signal monitoring
# For now, this is a template

close $fp2
puts "Transaction data template created: $transaction_file"