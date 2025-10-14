#!/usr/bin/env tclsh
# Wrapper to run dump_ip_config.tcl's dump_all_ips from the command line
# Usage (PowerShell):
#   vivado -mode batch -source scripts/dump_all_wrapper.tcl -tclargs <out_dir> [skip_prefix1 skip_prefix2 ...]
# Examples:
#   vivado -mode batch -source scripts/dump_all_wrapper.tcl -tclargs .\scripts\ip_manifests
#   vivado -mode batch -source scripts/dump_all_wrapper.tcl -tclargs .\scripts\ip_manifests layer fifo

puts "Running dump_all_wrapper.tcl"

# Defaults
set out_dir "./scripts/ip_manifests"
set skip_prefixes {layer}

# Parse -tclargs (argv/argc)
if {$argc > 0} {
    set out_dir [lindex $argv 0]
}
if {$argc > 1} {
    # collect any remaining argv entries as prefixes to skip
    set skip_prefixes {}
    for {set i 1} {$i < $argc} {incr i} {
        lappend skip_prefixes [lindex $argv $i]
    }
}

puts "Output directory: $out_dir"
puts "Skip prefixes: $skip_prefixes"

# Try to open the default project if it exists, otherwise require an open project
set default_proj "./vivado_project/CNN.xpr"
if {[file exists $default_proj]} {
    puts "Opening project: $default_proj"
    if {[catch {open_project $default_proj} err]} {
        puts "ERROR: failed to open project $default_proj : $err"
        exit 1
    }
} else {
    # If no default project file, ensure a project is already open
    if {[llength [get_projects]] == 0} {
        puts "ERROR: No project found at $default_proj and no project is currently open."
        puts "Open a project or adjust the wrapper to point to your .xpr file."
        exit 1
    } else {
        puts "Using currently open project"
    }
}

# Source the dump script and run the dump
if {[catch {source ./scripts/dump_ip_config.tcl} err]} {
    puts "ERROR: failed to source ./scripts/dump_ip_config.tcl : $err"
    exit 1
}

if {[catch {dump_all_ips $out_dir $skip_prefixes} err]} {
    puts "ERROR: dump_all_ips failed: $err"
    # attempt to close project then exit
    catch {close_project}
    exit 1
}

puts "dump_all_ips completed. Output written to: $out_dir"

# If manifests were written to the out_dir, try to apply them back into ip_repo
if {[file isdirectory $out_dir]} {
    puts "Applying manifests from $out_dir to ./ip_repo"
    if {[catch {apply_ip_manifests $out_dir "./ip_repo"} err]} {
        puts "Warning: apply_ip_manifests failed: $err"
    } else {
        puts "apply_ip_manifests completed"
    }
}

# Close project (optional) and exit
catch {close_project}
exit 0
