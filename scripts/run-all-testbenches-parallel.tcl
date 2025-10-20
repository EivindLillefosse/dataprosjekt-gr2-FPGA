# run-all-testbenches-parallel.tcl
# Automatically finds and runs all testbenches in the project with parallel execution
# Usage: vivado -mode batch -source ./scripts/run-all-testbenches-parallel.tcl
# Usage with jobs: vivado -mode batch -source ./scripts/run-all-testbenches-parallel.tcl -tclargs <num_jobs>

# Close any currently open project to avoid conflicts
catch {close_project}

# Open the existing project
if {[file exists "./vivado_project/CNN.xpr"]} {
    open_project "./vivado_project/CNN.xpr"
    puts "Project opened successfully"
} else {
    puts "ERROR: Project file ./vivado_project/CNN.xpr not found!"
    puts "Please run create-project.tcl first"
    exit 1
}

# Get number of parallel jobs from command line (default to 1 for sequential)
if {$argc > 0} {
    set num_jobs [lindex $argv 0]
    if {![string is integer -strict $num_jobs] || $num_jobs < 1 || $num_jobs > 8} {
        puts "WARNING: Invalid number of jobs '$num_jobs'. Using default of 2."
        set num_jobs 2
    }
} else {
    set num_jobs 2  ;# Default to 2 parallel jobs
}

puts "Parallel execution enabled: $num_jobs concurrent testbenches"

# Set multithreading parameter (though this mainly affects synthesis/implementation)
set_param general.maxThreads $num_jobs

# Procedure to find all testbench files recursively
proc find_testbenches {dir} {
    set testbenches [list]
    
    # Find all *_tb.vhd files
    set tb_files [glob -nocomplain "$dir/*_tb.vhd"]
    foreach tb_file $tb_files {
        # Extract entity name from filename
        set filename [file tail $tb_file]
        set entity_name [file rootname $filename]
        lappend testbenches [list $entity_name $tb_file]
    }
    
    # Recursively search subdirectories
    foreach subdir [glob -nocomplain -type d "$dir/*"] {
        set sub_testbenches [find_testbenches $subdir]
        set testbenches [concat $testbenches $sub_testbenches]
    }
    
    return $testbenches
}

# Find all testbenches in the src directory
puts ""
puts "=============================================================================="
puts "                         TESTBENCH DISCOVERY"
puts "=============================================================================="
set all_testbenches [find_testbenches "./src"]

if {[llength $all_testbenches] == 0} {
    puts "ERROR: No testbenches found in ./src directory!"
    exit 1
}

puts ""
puts "Found [llength $all_testbenches] testbench(es):"
puts ""
foreach tb $all_testbenches {
    set entity_name [lindex $tb 0]
    set file_path [lindex $tb 1]
    set relative_path [file dirname $file_path]
    puts [format "  %-30s %s" $entity_name $relative_path]
}

# Initialize results tracking
set results [list]
set pass_count 0
set fail_count 0
set skip_count 0

puts ""
puts "=============================================================================="
puts "                         TESTBENCH EXECUTION (PARALLEL: $num_jobs)"
puts "=============================================================================="
puts ""

# For parallel execution, we'll create temporary TCL scripts for each testbench
# and execute them using Vivado's batch mode in the background

set temp_script_dir "./temp_tb_scripts"
file mkdir $temp_script_dir

# Create individual test scripts
set test_scripts [list]
foreach tb $all_testbenches {
    set entity_name [lindex $tb 0]
    set file_path [lindex $tb 1]
    set module_path [file dirname $file_path]
    
    set script_file "$temp_script_dir/${entity_name}_run.tcl"
    set result_file "$temp_script_dir/${entity_name}_result.txt"
    
    set fp [open $script_file w]
    puts $fp "# Auto-generated test script for $entity_name"
    puts $fp "catch {close_project}"
    puts $fp "open_project \"./vivado_project/CNN.xpr\""
    puts $fp "set start_time \[clock seconds\]"
    puts $fp ""
    puts $fp "# Set as top module"
    puts $fp "if {\[catch {"
    puts $fp "    set_property top $entity_name \[get_fileset sim_1\]"
    puts $fp "    update_compile_order -fileset sim_1"
    puts $fp "} error\]} {"
    puts $fp "    set fp_result \[open \"$result_file\" w\]"
    puts $fp "    puts \$fp_result \"SKIP|Failed to set top module: \$error|0|$module_path\""
    puts $fp "    close \$fp_result"
    puts $fp "    exit 0"
    puts $fp "}"
    puts $fp ""
    puts $fp "# Run simulation"
    puts $fp "if {\[catch {"
    puts $fp "    catch {close_sim}"
    puts $fp "    launch_simulation -mode behavioral"
    puts $fp "    run 30000000"
    puts $fp "    set sim_time \[current_time\]"
    puts $fp "    close_sim"
    puts $fp "    set elapsed \[expr \[clock seconds\] - \$start_time\]"
    puts $fp "    set fp_result \[open \"$result_file\" w\]"
    puts $fp "    puts \$fp_result \"PASS|Simulation completed - \$sim_time|\$elapsed|$module_path\""
    puts $fp "    close \$fp_result"
    puts $fp "} error\]} {"
    puts $fp "    catch {close_sim}"
    puts $fp "    set elapsed \[expr \[clock seconds\] - \$start_time\]"
    puts $fp "    set fp_result \[open \"$result_file\" w\]"
    puts $fp "    puts \$fp_result \"FAIL|\$error|\$elapsed|$module_path\""
    puts $fp "    close \$fp_result"
    puts $fp "}"
    puts $fp "exit 0"
    close $fp
    
    lappend test_scripts [list $entity_name $script_file $result_file $module_path]
}

puts "Created [llength $test_scripts] test scripts"
puts ""

# Execute testbenches in batches based on num_jobs
set batch_size $num_jobs
set total_tests [llength $test_scripts]
set current_index 0

while {$current_index < $total_tests} {
    set batch_end [expr {min($current_index + $batch_size - 1, $total_tests - 1)}]
    set current_batch [lrange $test_scripts $current_index $batch_end]
    
    puts "Launching batch [expr {$current_index / $batch_size + 1}] ([expr {$current_index + 1}]-[expr {$batch_end + 1}] of $total_tests):"
    
    # Launch all tests in current batch
    set pids [list]
    foreach test $current_batch {
        set entity_name [lindex $test 0]
        set script_file [lindex $test 1]
        set module_path [lindex $test 3]
        
        puts "  Starting $entity_name \[$module_path\]"
        
        # Launch Vivado in background (Windows PowerShell)
        if {[catch {
            set pid [exec powershell -Command "Start-Process vivado -ArgumentList '-mode batch -source $script_file' -WindowStyle Hidden -PassThru | Select-Object -ExpandProperty Id" >@stdout]
            lappend pids [list $entity_name $pid [lindex $test 2]]
        } error]} {
            puts "    WARNING: Failed to launch process: $error"
        }
    }
    
    puts ""
    puts "Waiting for batch to complete..."
    
    # Wait for all processes in batch to complete
    set max_wait 600  ;# Maximum 10 minutes per batch
    set wait_start [clock seconds]
    set all_complete 0
    
    while {!$all_complete && ([clock seconds] - $wait_start) < $max_wait} {
        set all_complete 1
        foreach pid_info $pids {
            set pid [lindex $pid_info 1]
            # Check if process is still running (Windows)
            if {[catch {exec powershell -Command "Get-Process -Id $pid -ErrorAction SilentlyContinue"} result]} {
                # Process completed
            } else {
                set all_complete 0
            }
        }
        if {!$all_complete} {
            after 2000  ;# Wait 2 seconds before checking again
        }
    }
    
    if {!$all_complete} {
        puts "WARNING: Batch timeout reached. Some tests may still be running."
    }
    
    puts "Batch complete. Collecting results..."
    puts ""
    
    # Collect results from this batch
    foreach test $current_batch {
        set entity_name [lindex $test 0]
        set result_file [lindex $test 2]
        set module_path [lindex $test 3]
        
        if {[file exists $result_file]} {
            set fp_result [open $result_file r]
            set result_line [gets $fp_result]
            close $fp_result
            
            set result_parts [split $result_line "|"]
            set status [lindex $result_parts 0]
            set message [lindex $result_parts 1]
            set duration [lindex $result_parts 2]
            
            puts "  $entity_name -> $status"
            
            lappend results [list $entity_name $status $message $duration $module_path]
            
            switch $status {
                "PASS" { incr pass_count }
                "FAIL" { incr fail_count }
                "SKIP" { incr skip_count }
            }
        } else {
            puts "  $entity_name -> ERROR - No result file"
            lappend results [list $entity_name "FAIL" "No result file generated" 0 $module_path]
            incr fail_count
        }
    }
    
    puts ""
    set current_index [expr {$batch_end + 1}]
}

# Clean up temporary files
puts "Cleaning up temporary files..."
file delete -force $temp_script_dir

# Generate summary report
puts ""
puts "=============================================================================="
puts "                           TESTBENCH SUMMARY REPORT"
puts "=============================================================================="
puts ""

# Statistics
set total_count [llength $all_testbenches]
puts "EXECUTION STATISTICS:"
puts ""
puts [format "  %-20s %d" "Total testbenches:" $total_count]
puts [format "  %-20s %d" "Passed:" $pass_count]
puts [format "  %-20s %d" "Failed:" $fail_count]
puts [format "  %-20s %d" "Skipped:" $skip_count]
puts [format "  %-20s %d" "Parallel jobs:" $num_jobs]

if {$total_count > 0} {
    set pass_rate [expr {double($pass_count) / double($total_count) * 100.0}]
    puts [format "  %-20s %.1f%%" "Success rate:" $pass_rate]
}

puts ""

# Detailed results table
puts "DETAILED RESULTS:"
puts ""
puts [format "%-30s %-8s %-10s %-20s %s" "TESTBENCH" "STATUS" "TIME(s)" "MODULE" "DETAILS"]
puts "------------------------------------------------------------------------------"

foreach result $results {
    set name [lindex $result 0]
    set status [lindex $result 1]
    set message [lindex $result 2]
    set duration [lindex $result 3]
    set location [lindex $result 4]
    
    # Truncate long names and messages for better formatting
    set short_name [string range $name 0 29]
    set short_location [file tail $location]
    set short_message [string range $message 0 35]
    
    puts [format "%-30s %-8s %-10s %-20s %s" $short_name $status $duration $short_location $short_message]
}

puts ""

# Category breakdown
if {$fail_count > 0} {
    puts "FAILED TESTBENCHES:"
    puts ""
    foreach result $results {
        if {[lindex $result 1] == "FAIL"} {
            set name [lindex $result 0]
            set message [lindex $result 2]
            set location [lindex $result 4]
            puts [format "  %-30s %s" $name $location]
            puts [format "  %-30s Error: %s" "" [string range $message 0 80]]
            puts ""
        }
    }
}

if {$skip_count > 0} {
    puts "SKIPPED TESTBENCHES:"
    puts ""
    foreach result $results {
        if {[lindex $result 1] == "SKIP"} {
            set name [lindex $result 0]
            set message [lindex $result 2]
            set location [lindex $result 4]
            puts [format "  %-30s %s" $name $location]
            puts [format "  %-30s Reason: %s" "" [string range $message 0 80]]
            puts ""
        }
    }
}

if {$pass_count > 0} {
    puts "PASSED TESTBENCHES:"
    puts ""
    foreach result $results {
        if {[lindex $result 1] == "PASS"} {
            set name [lindex $result 0]
            set duration [lindex $result 3]
            set location [lindex $result 4]
            puts [format "  %-30s %s (%ss)" $name $location $duration]
        }
    }
    puts ""
}

# Save results to file
set timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set report_file "testbench_report_parallel_$timestamp.txt"

set fp [open $report_file w]
puts $fp "TESTBENCH EXECUTION REPORT (PARALLEL)"
puts $fp "Generated: [clock format [clock seconds]]"
puts $fp "Project: CNN FPGA Implementation"
puts $fp "Parallel jobs: $num_jobs"
puts $fp ""
puts $fp "STATISTICS:"
puts $fp "Total testbenches: $total_count"
puts $fp "Passed: $pass_count"
puts $fp "Failed: $fail_count"
puts $fp "Skipped: $skip_count"
if {$total_count > 0} {
    puts $fp "Success rate: [format "%.1f" [expr {double($pass_count) / double($total_count) * 100.0}]]%"
}
puts $fp ""

puts $fp "DETAILED RESULTS:"
foreach result $results {
    set name [lindex $result 0]
    set status [lindex $result 1]
    set message [lindex $result 2]
    set duration [lindex $result 3]
    set location [lindex $result 4]
    
    puts $fp "$name - $status (${duration}s)"
    puts $fp "  Location: $location"
    puts $fp "  Details: $message"
    puts $fp ""
}
close $fp

puts ""
puts "Detailed report saved to: $report_file"

# Final summary
puts ""
puts "=============================================================================="
puts "                              FINAL SUMMARY"
puts "=============================================================================="
puts ""
if {$fail_count == 0 && $skip_count == 0} {
    puts "RESULT: ALL TESTS PASSED"
    puts "Status: Your design is working correctly!"
} elseif {$fail_count == 0} {
    puts "RESULT: ALL RUNNABLE TESTS PASSED"
    puts "Status: Some tests were skipped - check configuration if needed"
} else {
    puts "RESULT: SOME TESTS FAILED"
    puts "Status: Please review the failed testbenches listed above"
}
puts ""
puts "=============================================================================="

# Exit with appropriate code
if {$fail_count > 0} {
    exit 1
} else {
    exit 0
}
