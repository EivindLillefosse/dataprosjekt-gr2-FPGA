# run-single-testbench.tcl
# Run one VHDL testbench with the same logging, classification and isolation features
# provided by run-all-testbenches.tcl.
#
# Usage examples:
#   vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs top_tb
#   vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs weight_memory_controller_tb
#   (Optional) set env vars before invoking:
#       $env:VIVADO_TEST_CLEAN = 1          # Clean simulation artifacts before run
#       $env:VIVADO_TEST_TIMEOUT_NS = 30000000  # Override timeout (nanoseconds)
#       $env:VIVADO_TEST_ISOLATE = 1        # Close/reopen project before run (redundant for single)
#
# Exit codes:
#   0 -> PASS
#   1 -> FAIL (errors/assertions)
#   2 -> SKIP / Not Found / Setup error

proc usage {} {
	puts "Usage: (inside Vivado)"
	puts "  vivado -mode batch -source ./scripts/run-single-testbench.tcl -tclargs <testbench_entity>"
	puts "Environment variables:"
	puts "  VIVADO_TEST_CLEAN=1           Clean simulation dir before run"
	puts "  VIVADO_TEST_ISOLATE=1         Force project reopen (generally redundant here)"
	puts "  VIVADO_TEST_TIMEOUT_NS=<ns>   Override sim timeout (default 30000000 ns)"
}

if {[llength $argv] < 1} {
	puts "ERROR: Missing testbench entity name."
	usage
	exit 2
}

set tb_name [lindex $argv 0]
puts "Requested testbench: $tb_name"

# Close any open project to start clean if isolation requested
catch {close_project}

if {[file exists "./vivado_project/CNN.xpr"]} {
	open_project "./vivado_project/CNN.xpr"
	puts "Project opened successfully"
} else {
	puts "ERROR: Project file ./vivado_project/CNN.xpr not found!"
	exit 2
}

# Derive potential testbench file path if not absolute: search src tree
proc find_testbench_file {name} {
	set patterns [list "./src/**/${name}.vhd" "./src/**/${name}.vhdl"]
	foreach pat $patterns {
		set matches [glob -nocomplain $pat]
		if {[llength $matches] > 0} {
			return [lindex $matches 0]
		}
	}
	return ""
}

set tb_file [find_testbench_file $tb_name]
if {$tb_file eq ""} {
	puts "WARNING: Could not locate file for entity $tb_name (continuing, Vivado may still know it)."
} else {
	puts "Found testbench file: $tb_file"
}

# Timestamp & directories
set run_timestamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set per_test_log_dir "./testbench_logs"
if {![file exists $per_test_log_dir]} { file mkdir $per_test_log_dir }
set test_dir [format "%s/%s_%s" $per_test_log_dir $tb_name $run_timestamp]
file mkdir $test_dir

# Environment options
set isolate_tests 0
if {[info exists ::env(VIVADO_TEST_ISOLATE)] && $::env(VIVADO_TEST_ISOLATE) eq "1"} {
	set isolate_tests 1
	puts "[INFO] Isolation enabled (single run)."
}
set clean_each 0
if {[info exists ::env(VIVADO_TEST_CLEAN)] && $::env(VIVADO_TEST_CLEAN) eq "1"} {
	set clean_each 1
	puts "[INFO] Clean simulation dir enabled."
}

set timeout_ns 30000000
if {[info exists ::env(VIVADO_TEST_TIMEOUT_NS)]} {
	if {[string is integer -strict $::env(VIVADO_TEST_TIMEOUT_NS)]} {
		set timeout_ns $::env(VIVADO_TEST_TIMEOUT_NS)
		puts "[INFO] Timeout overridden to $timeout_ns ns"
	} else {
		puts "[WARN] Ignoring non-integer VIVADO_TEST_TIMEOUT_NS=$::env(VIVADO_TEST_TIMEOUT_NS)"
	}
}

# Log monitoring utilities (mirrors multi-test script)
set log_files [list]
set project_log_candidates [glob -nocomplain "./vivado_project/*.log"]
foreach lf $project_log_candidates { lappend log_files $lf }
if {[file exists "./vivado.log"]} { lappend log_files "./vivado.log" }

array set log_line_counts {}

proc reset_log_snapshot {log_filesVar lineCountsVar} {
	upvar $log_filesVar log_files
	upvar $lineCountsVar log_line_counts
	foreach lf $log_files {
		if {[file exists $lf]} {
			set fp [open $lf r]; set lines [split [read $fp] "\n"]; close $fp
			set log_line_counts($lf) [llength $lines]
		} else { set log_line_counts($lf) 0 }
	}
}

proc scan_new_log_errors {log_filesVar lineCountsVar} {
	upvar $log_filesVar log_files
	upvar $lineCountsVar log_line_counts
	set aggregated {}
	foreach lf $log_files {
		if {![file exists $lf]} { continue }
		set fp [open $lf r]; set lines [split [read $fp] "\n"]; close $fp
		set prevCount 0
		if {[info exists log_line_counts($lf)]} { set prevCount $log_line_counts($lf) }
		if {$prevCount < [llength $lines]} {
			set newLines [lrange $lines $prevCount end]
			foreach nl $newLines {
				if {[string trim $nl] eq ""} { continue }
				if {[regexp {^\s*#} $nl]} { continue }
				if {[regexp -nocase {(^|\s)(ERROR:|FATAL:)} $nl]} {
					lappend aggregated [list $lf $nl]
				}
			}
		}
		set log_line_counts($lf) [llength $lines]
	}
	return $aggregated
}

proc classify_error_lines {error_tuples} {
	set counts [dict create assertion 0 compile 0 sim 0 other 0]
	foreach tup $error_tuples {
		set line [lindex $tup 1]
		if {[regexp -nocase {assertion|assertion violation|assert } $line]} { dict incr counts assertion }
		elseif {[regexp -nocase {xvhdl|xvlog|xelab|elaborat|compile|parser} $line]} { dict incr counts compile }
		elseif {[regexp -nocase {xsim|simulation} $line]} { dict incr counts sim }
		else { dict incr counts other }
	}
	set fragments {}
	foreach cat {assertion compile sim other} {
		set val [dict get $counts $cat]
		if {$val > 0} { lappend fragments "[string totitle $cat]:$val" }
	}
	if {[llength $fragments] > 0} { return "[join $fragments { }]" } else { return "" }
}

proc capture_sim_logs {entity_name run_timestamp test_dir} {
	set sim_root "./vivado_project/CNN.sim/sim_1/behav/xsim"
	set copied {}
	if {![file exists $sim_root]} { return [list $copied {} ""] }
	set patterns [list "elaborate.log" "simulate.log" "xvhdl.log" "xvlog.log" "xelab.log" "xsim.log"]
	foreach p $patterns {
		set src "$sim_root/$p"
		if {[file exists $src]} {
			set dest "$test_dir/$p"
			catch {file copy -force $src $dest}
			lappend copied $dest
		}
	}
	set error_entries {}
	foreach f $copied {
		set fp [open $f r]; set content [split [read $fp] "\n"]; close $fp
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
		puts $sfp "Testbench: $entity_name"; puts $sfp "Timestamp: $run_timestamp"; puts $sfp "Error entries: [llength $error_entries]"
		puts $sfp "--- Contextual Errors ---"
		set idx 1
		foreach e $error_entries {
			puts $sfp "[$idx] [file tail [lindex $e 0]]: [string trim [lindex $e 1]]"
			set prev [string trim [lindex $e 2]]; set next [string trim [lindex $e 3]]
			if {$prev ne ""} { puts $sfp "     Prev: $prev" }
			if {$next ne ""} { puts $sfp "     Next: $next" }
			incr idx
		}
		close $sfp
	}
	return [list $copied $error_entries $summary_file]
}

reset_log_snapshot log_files log_line_counts

set start_time [clock seconds]
set sim_error_occurred 0
set sim_error_message ""

if {[catch {
	# Isolation (close/open) if requested (already opened; mainly for parity)
	if {$isolate_tests} {
		catch {close_sim}; catch {close_project}
		open_project "./vivado_project/CNN.xpr"
		reset_log_snapshot log_files log_line_counts
	}
	# Set top
	set_property top $tb_name [get_fileset sim_1]
	update_compile_order -fileset sim_1
	catch {reset_run sim_1}
	# Clean simulation dir if requested
	if {$clean_each} {
		set sim_dir "./vivado_project/CNN.sim/sim_1/behav/xsim"
		if {[file exists $sim_dir]} { catch {file delete -force -- $sim_dir} }
	}
	catch {close_sim}
	# Launch simulation
	if {$clean_each} { launch_simulation -mode behavioral -clean } else { launch_simulation -mode behavioral }
	run $timeout_ns
	set current_sim_time [current_time]
	catch {close_sim}
	set elapsed_time [expr [clock seconds] - $start_time]
	# Gather logs
	set new_errors [scan_new_log_errors log_files log_line_counts]
	set cap [capture_sim_logs $tb_name $run_timestamp $test_dir]
	set sim_logs_copied [lindex $cap 0]
	set sim_log_errors  [lindex $cap 1]
	set sim_summary_file [lindex $cap 2]
	foreach se $sim_log_errors { lappend new_errors [list [lindex $se 0] [lindex $se 1]] }
	if {[llength $new_errors] > 0} {
		set classification [classify_error_lines $new_errors]
		set first_error [lindex [lindex $new_errors 0] 1]
		puts "  >> FAILED - Log errors detected (total [llength $new_errors])"
		puts "     Category counts: $classification"
		puts "     First error: [string range $first_error 0 120]"
		puts "     Duration: ${elapsed_time}s | Sim time: $current_sim_time"
		set sim_error_occurred 1
		set sim_error_message "Log errors ([llength $new_errors]) $classification"
		set root_log "$test_dir/root_errors.log"
		set efp [open $root_log w]
		puts $efp "Testbench: $tb_name"; puts $efp "Timestamp: $run_timestamp"; puts $efp "Merged errors: [llength $new_errors]"; puts $efp "Classification: $classification"
		if {[llength $sim_logs_copied] > 0} { puts $efp "Copied sim logs:"; foreach sl $sim_logs_copied { puts $efp "  - $sl" } }
		if {$sim_summary_file ne ""} { puts $efp "Sim error summary: $sim_summary_file" }
		puts $efp "--- ERROR LINES ---"; foreach e $new_errors { puts $efp "[file tail [lindex $e 0]]: [lindex $e 1]" }
		close $efp
		# Detail snippet
		set detail_lines {}; set max_err_lines 3; set idx 0
		foreach e $new_errors { if {$idx >= $max_err_lines} { break }; lappend detail_lines "[file tail [lindex $e 0]]: [lindex $e 1]"; incr idx }
		if {$sim_summary_file ne ""} { set sim_error_message "$sim_error_message | [join $detail_lines { | }] | logs: $root_log, $sim_summary_file" } else { set sim_error_message "$sim_error_message | [join $detail_lines { | }] | log: $root_log" }
	} else {
		puts "  >> PASSED - Simulation completed successfully"
		puts "     Duration: ${elapsed_time}s | Sim time: $current_sim_time"
		set pass_log "$test_dir/pass_trace.log"
		set pfp [open $pass_log w]
		puts $pfp "Testbench: $tb_name"; puts $pfp "Timestamp: $run_timestamp"; puts $pfp "Result: PASS"; puts $pfp "Sim time: $current_sim_time"
		if {[llength $sim_logs_copied] > 0} { puts $pfp "Copied sim logs:"; foreach sl $sim_logs_copied { puts $pfp "  - $sl" } }
		close $pfp
	}
} error]} {
	set elapsed_time [expr [clock seconds] - $start_time]
	set sim_error_occurred 1
	set sim_error_message $error
	puts "  >> FAILED - [string range $error 0 100]..."
	puts "     Duration: ${elapsed_time}s"
	set new_errors [scan_new_log_errors log_files log_line_counts]
	set cap [capture_sim_logs $tb_name $run_timestamp $test_dir]
	set sim_log_errors [lindex $cap 1]
	foreach se $sim_log_errors { lappend new_errors [list [lindex $se 0] [lindex $se 1]] }
	if {[llength $new_errors] > 0} {
		set first_error [lindex [lindex $new_errors 0] 1]
		puts "     Log first error: [string range $first_error 0 100]"
	}
}

# Write summary report
set report_file [format "single_testbench_report_%s_%s.log" $tb_name $run_timestamp]
set fp [open $report_file w]
puts $fp "SINGLE TESTBENCH EXECUTION REPORT"
puts $fp "Generated: [clock format [clock seconds]]"
puts $fp "Testbench: $tb_name"
puts $fp "Timestamp: $run_timestamp"
if {$sim_error_occurred} {
	puts $fp "Result: FAIL"
	puts $fp "Details: $sim_error_message"
} else {
	puts $fp "Result: PASS"
	puts $fp "Details: Simulation completed"
}
puts $fp "Artifacts directory: $test_dir"
close $fp

puts "Summary report: $report_file"
if {$sim_error_occurred} { exit 1 } else { exit 0 }
