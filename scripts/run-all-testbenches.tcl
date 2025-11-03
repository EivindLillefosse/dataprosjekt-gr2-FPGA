# run-all-testbenches.tcl
# Automatically finds and runs all testbenches in the project
# Usage: vivado -mode batch -source ./scripts/run-all-testbenches.tcl

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

# Global timestamp for this run (used for per-test logs & final report)
set run_timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]

# Ensure log output directory exists for detailed per-test error logs
set per_test_log_dir "./testbench_logs"
if {![file exists $per_test_log_dir]} {
    file mkdir $per_test_log_dir
}

# ---------------------------------------------------------------------------
# Log file monitoring setup
# We snapshot line counts of .log files before executing tests, then after each
# testbench we only scan the newly appended lines for ERROR patterns. This helps
# catch underlying compile/elaboration errors that don't always surface via
# Tcl exceptions.
# ---------------------------------------------------------------------------

# Collect log files inside vivado_project plus the root vivado.log (if present)
set log_files [list]
set project_log_candidates [glob -nocomplain "./vivado_project/*.log"]
foreach lf $project_log_candidates { lappend log_files $lf }
if {[file exists "./vivado.log"]} {
    lappend log_files "./vivado.log"
}

array set log_line_counts {}
foreach lf $log_files {
    if {[file exists $lf]} {
        set fp [open $lf r]
        set lines [split [read $fp] "\n"]
        close $fp
        set log_line_counts($lf) [llength $lines]
    } else {
        set log_line_counts($lf) 0
    }
}

# Reset log snapshot (to be called per test if needed for isolation)
proc reset_log_snapshot {log_filesVar lineCountsVar} {
    upvar $log_filesVar log_files
    upvar $lineCountsVar log_line_counts
    foreach lf $log_files {
        if {[file exists $lf]} {
            set fp [open $lf r]
            set lines [split [read $fp] "\n"]
            close $fp
            set log_line_counts($lf) [llength $lines]
        } else {
            set log_line_counts($lf) 0
        }
    }
}

# Helper proc to scan new log lines for ERROR patterns
proc scan_new_log_errors {log_filesVar lineCountsVar} {
    upvar $log_filesVar log_files
    upvar $lineCountsVar log_line_counts
    set aggregated {}
    foreach lf $log_files {
        if {![file exists $lf]} { continue }
        set fp [open $lf r]
        set lines [split [read $fp] "\n"]
        close $fp
        set prevCount 0
        if {[info exists log_line_counts($lf)]} { set prevCount $log_line_counts($lf) }
        # Slice new lines (if any)
        if {$prevCount < [llength $lines]} {
            set newLines [lrange $lines $prevCount end]
            foreach nl $newLines {
                # Skip empty or whitespace-only lines
                if {[string trim $nl] eq ""} { continue }
                # Skip echoed script/comment lines beginning with '#'
                if {[regexp {^\s*#} $nl]} { continue }
                # Match common Vivado error severity tokens
                if {[regexp -nocase {(^|\s)(ERROR:|FATAL:)} $nl]} {
                    lappend aggregated [list $lf $nl]
                }
            }
        }
        # Update snapshot count for this file for subsequent tests
        set log_line_counts($lf) [llength $lines]
    }
    return $aggregated
}

# Classify error lines into categories for concise summary
proc classify_error_lines {error_tuples} {
    set counts [dict create assertion 0 compile 0 sim 0 other 0]
    foreach tup $error_tuples {
        set line [lindex $tup 1]
        if {[regexp -nocase {assertion|assertion violation|assert } $line]} {
            dict incr counts assertion
        } elseif {[regexp -nocase {xvhdl|xvlog|xelab|elaborat|compile|parser} $line]} {
            dict incr counts compile
        } elseif {[regexp -nocase {xsim|simulation} $line]} {
            dict incr counts sim
        } else {
            dict incr counts other
        }
    }
    # Build readable fragment only including non-zero categories
    set fragments {}
    foreach cat {assertion compile sim other} {
        set val [dict get $counts $cat]
        if {$val > 0} { lappend fragments "[string totitle $cat]:$val" }
    }
    if {[llength $fragments] > 0} {
        return "[join $fragments { }]"
    } else {
        return ""
    }
}

puts ""
puts "=============================================================================="
puts "                         TESTBENCH EXECUTION"
puts "=============================================================================="
puts ""

# Isolation / cleanup modes (opt-in via environment variables):
#   VIVADO_TEST_ISOLATE=1  -> Re-open project fresh for each testbench
#   VIVADO_TEST_CLEAN=1    -> Remove simulation xsim directory before each run
set isolate_tests 0
if {[info exists ::env(VIVADO_TEST_ISOLATE)] && $::env(VIVADO_TEST_ISOLATE) eq "1"} {
    set isolate_tests 1
    puts "[INFO] Per-test project isolation ENABLED (VIVADO_TEST_ISOLATE=1)"
}
set clean_each 0
if {[info exists ::env(VIVADO_TEST_CLEAN)] && $::env(VIVADO_TEST_CLEAN) eq "1"} {
    set clean_each 1
    puts "[INFO] Per-test simulation directory cleanup ENABLED (VIVADO_TEST_CLEAN=1)"
}

# Capture and copy relevant simulation log artifacts for deeper inspection.
proc capture_sim_logs {entity_name run_timestamp per_test_log_dir} {
    set sim_root "./vivado_project/CNN.sim/sim_1/behav/xsim"
    set copied {}
    if {![file exists $sim_root]} { return [list $copied {} ""] }
    # Create per-test directory
    set test_dir [format "%s/%s_%s" $per_test_log_dir $entity_name $run_timestamp]
    if {![file exists $test_dir]} { file mkdir $test_dir }
    # Copy core sim logs if present
    set patterns [list "elaborate.log" "simulate.log" "xvhdl.log" "xvlog.log" "xelab.log" "xsim.log"]
    foreach p $patterns {
        set src "$sim_root/$p"
        if {[file exists $src]} {
            set dest "$test_dir/$p"
            catch {file copy -force $src $dest}
            lappend copied $dest
        }
    }
    # Extract error-bearing lines with one-line context
    set error_entries {}
    foreach f $copied {
        set fp [open $f r]
        set content [split [read $fp] "\n"]
        close $fp
        for {set i 0} {$i < [llength $content]} {incr i} {
            set line [lindex $content $i]
            if {[string trim $line] eq ""} { continue }
            if {[regexp {^\s*#} $line]} { continue }
            if {[regexp -nocase {ERROR:|FATAL:|assertion violation|assert } $line]} {
                set prev ""; set next ""
                if {$i > 0} { set prev [lindex $content [expr {$i-1}]] }
                if {$i < [llength $content]-1} { set next [lindex $content [expr {$i+1}]] }
                lappend error_entries [list $f $line $prev $next]
            }
        }
    }
    set summary_file ""
    if {[llength $error_entries] > 0} {
        set summary_file "$test_dir/error_summary.log"
        set sfp [open $summary_file w]
        puts $sfp "Testbench: $entity_name"
        puts $sfp "Timestamp: $run_timestamp"
        puts $sfp "Error entries: [llength $error_entries]"
        puts $sfp "--- Contextual Errors ---"
        set idx 1
        foreach e $error_entries {
            puts $sfp "[$idx] [file tail [lindex $e 0]]: [string trim [lindex $e 1]]"
            set prev [string trim [lindex $e 2]]
            set next [string trim [lindex $e 3]]
            if {$prev ne ""} { puts $sfp "     Prev: $prev" }
            if {$next ne ""} { puts $sfp "     Next: $next" }
            incr idx
        }
        close $sfp
    }
    return [list $copied $error_entries $summary_file $test_dir]
}

# Run each testbench
foreach tb $all_testbenches {
    set entity_name [lindex $tb 0]
    set file_path [lindex $tb 1]
    set module_path [file dirname $file_path]
    
    puts [format {Running %-25s [%s]} "$entity_name:" $module_path]
    
    set start_time [clock seconds]

    # Optional per-test isolation: close & reopen project, refresh log baseline
    if {$isolate_tests} {
        catch {close_sim}
        catch {close_project}
        if {[file exists "./vivado_project/CNN.xpr"]} {
            open_project "./vivado_project/CNN.xpr"
        } else {
            puts "  >> SKIPPED - Project missing during isolation reopen"
            lappend results [list $entity_name "SKIP" "Project missing on reopen" 0 $module_path]
            incr skip_count
            puts ""
            continue
        }
        # Recreate log file list in case new logs appear
        set log_files [list]
        set project_log_candidates [glob -nocomplain "./vivado_project/*.log"]
        foreach lf $project_log_candidates { lappend log_files $lf }
        if {[file exists "./vivado.log"]} { lappend log_files "./vivado.log" }
        reset_log_snapshot log_files log_line_counts
    } else {
        # Non-isolated mode: still refresh log baseline immediately before this test
        reset_log_snapshot log_files log_line_counts
    }
    
    # Try to set the testbench as top module
    if {[catch {
        set_property top $entity_name [get_fileset sim_1]
        update_compile_order -fileset sim_1
        # Clean compile state for sim_1 to avoid leftover design units
        catch {reset_run sim_1}
    } error]} {
        puts "  >> SKIPPED - Failed to set as top module"
        puts "     Reason: [string range $error 0 60]..."
        lappend results [list $entity_name "SKIP" "Failed to set top module: $error" 0 $module_path]
        incr skip_count
        puts ""
        continue
    }
    
    # Launch simulation
    set sim_error_occurred 0
    set sim_error_message ""
    set test_dir ""
    if {[catch {
        # Close any existing simulation
        catch {close_sim}
        # Optional clean of simulation artifacts
        if {$clean_each} {
            set sim_dir "./vivado_project/CNN.sim/sim_1/behav/xsim"
            if {[file exists $sim_dir]} { catch {file delete -force -- $sim_dir} }
        }
        # Launch new simulation with timeout
        if {$clean_each} {
            launch_simulation -mode behavioral -clean
        } else {
            launch_simulation -mode behavioral
        }
        # Timeout (adjust if needed)
        set sim_timeout 30000000  ;# 30 seconds in nanoseconds
        run $sim_timeout
        set current_sim_time [current_time]
        catch {close_sim}
        set elapsed_time [expr [clock seconds] - $start_time]
        # Scan logs for errors introduced during this simulation
        set new_errors [scan_new_log_errors log_files log_line_counts]
        # Capture sim logs (even if no errors, for traceability)
        set cap [capture_sim_logs $entity_name $run_timestamp $per_test_log_dir]
        set sim_logs_copied [lindex $cap 0]
        set sim_log_errors  [lindex $cap 1]
        set sim_summary_file [lindex $cap 2]
        set test_dir [lindex $cap 3]
        # Merge sim_log_errors into new_errors for unified classification
        foreach se $sim_log_errors {
            # Convert extended tuple to basic form (file line)
            lappend new_errors [list [lindex $se 0] [lindex $se 1]]
        }
        if {[llength $new_errors] > 0} {
            # Mark as failure due to log detected errors
            set classification [classify_error_lines $new_errors]
            set first_error [lindex [lindex $new_errors 0] 1]
            puts "  >> FAILED - Log errors detected (total [llength $new_errors])"
            puts "     Category counts: $classification"
            puts "     First error: [string range $first_error 0 120]"
            puts "     Duration: ${elapsed_time}s | Sim time: $current_sim_time"
            set sim_error_occurred 1
            set sim_error_message "Log errors ([llength $new_errors]) $classification"
            # Root log summarizing merged errors
            if {$test_dir eq ""} { set test_dir $per_test_log_dir }
            set test_error_log "$test_dir/root_errors.log"
            set efp [open $test_error_log w]
            puts $efp "Testbench: $entity_name"
            puts $efp "Timestamp: $run_timestamp"
            puts $efp "Merged errors: [llength $new_errors]"
            puts $efp "Classification: $classification"
            if {[llength $sim_logs_copied] > 0} {
                puts $efp "Copied sim logs:"; foreach sl $sim_logs_copied { puts $efp "  - $sl" }
            }
            if {$sim_summary_file ne ""} { puts $efp "Sim error summary: $sim_summary_file" }
            puts $efp "--- ERROR LINES ---"
            foreach e $new_errors { puts $efp "[file tail [lindex $e 0]]: [lindex $e 1]" }
            close $efp
            # Prepare concise detail lines
            set detail_lines {}
            set max_err_lines 3
            set idx 0
            foreach e $new_errors {
                if {$idx >= $max_err_lines} { break }
                set lf   [lindex $e 0]
                set line [lindex $e 1]
                lappend detail_lines "[file tail $lf]: $line"
                incr idx
            }
            if {$sim_summary_file ne ""} {
                set sim_error_message "$sim_error_message | [join $detail_lines { | }] | logs: $test_error_log, $sim_summary_file"
            } else {
                set sim_error_message "$sim_error_message | [join $detail_lines { | }] | log: $test_error_log"
            }
        } else {
            puts "  >> PASSED - Simulation completed successfully"
            puts "     Duration: ${elapsed_time}s | Sim time: $current_sim_time"
            # For passes, still write a minimal trace file for reproducibility
            if {$test_dir eq ""} {
                # Create a directory even on pass (optional; comment to disable)
                set test_dir [format "%s/%s_%s" $per_test_log_dir $entity_name $run_timestamp]
                if {![file exists $test_dir]} { file mkdir $test_dir }
            }
            set pass_log "$test_dir/pass_trace.log"
            set pfp [open $pass_log w]
            puts $pfp "Testbench: $entity_name"
            puts $pfp "Timestamp: $run_timestamp"
            puts $pfp "Result: PASS"
            puts $pfp "Sim time: $current_sim_time"
            if {[llength $sim_logs_copied] > 0} {
                puts $pfp "Copied sim logs:"; foreach sl $sim_logs_copied { puts $pfp "  - $sl" }
            }
            close $pfp
        }
    } error]} {
        set elapsed_time [expr [clock seconds] - $start_time]
        set sim_error_occurred 1
        set sim_error_message $error
        puts "  >> FAILED - [string range $error 0 60]..."
        puts "     Duration: ${elapsed_time}s"
        # Scan logs even on Tcl exception to capture underlying messages
        set new_errors [scan_new_log_errors log_files log_line_counts]
        # Attempt simulation log capture in exception path too
        set cap [capture_sim_logs $entity_name $run_timestamp $per_test_log_dir]
        set sim_log_errors [lindex $cap 1]
        foreach se $sim_log_errors { lappend new_errors [list [lindex $se 0] [lindex $se 1]] }
        if {[llength $new_errors] > 0} {
            set first_error [lindex [lindex $new_errors 0] 1]
            puts "     Log first error: [string range $first_error 0 80]"
        }
        catch {close_sim}
    }

    # Record result depending on simulation / log status
    if {$sim_error_occurred} {
        lappend results [list $entity_name "FAIL" $sim_error_message $elapsed_time $module_path]
        incr fail_count
    } else {
        lappend results [list $entity_name "PASS" "Simulation completed" $elapsed_time $module_path]
        incr pass_count
    }
    
    puts ""
}

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
    
    # Format status with consistent width
    switch $status {
        "PASS" { set status_text "PASS" }
        "FAIL" { set status_text "FAIL" }
        "SKIP" { set status_text "SKIP" }
        default { set status_text $status }
    }
    
    puts [format "%-30s %-8s %-10s %-20s %s" $short_name $status_text $duration $short_location $short_message]
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
set report_file "testbench_report_$timestamp.log"

set fp [open $report_file w]
puts $fp "TESTBENCH EXECUTION REPORT"
puts $fp "Generated: [clock format [clock seconds]]"
puts $fp "Project: CNN FPGA Implementation"
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