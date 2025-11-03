Using IP manifests and dumping IP configs
========================================

This directory contains a minimal YAML manifest template for `fifo_generator_0` and a helper
Tcl script you can run inside Vivado to dump the full list of CONFIG.* properties.

Workflow
--------
1. Open your Vivado project.
2. In the Vivado Tcl console, source the dumper script:

   source scripts/dump_ip_config.tcl

3. Dump current CONFIG values for the IP into YAML:

   dump_ip_config fifo_generator_0 scripts/ip_manifests/fifo_generator_0_full.yaml

   or dump all IPs:
   dump_all_ips scripts/ip_manifests

4. Edit `fifo_generator_0.yaml` and fill the `config:` map with any CONFIG.* entries you want
   to change. Only include properties you need to override — the rest are left as IP defaults.

5. Generate a small Tcl snippet (or hand-edit) to apply the properties and generate the IP (example below):

   set_property -dict [list \
     CONFIG.DATA_WIDTH {8} \
     CONFIG.Input_Depth {1024} ] [get_ips fifo_generator_0]
   generate_target all [get_ips fifo_generator_0]

6. Re-run `report_property -all [get_ips fifo_generator_0]` to confirm the new values.

Notes
-----
- The dumper writes simple YAML with `id` and a `config:` map. Use it as a starting point.
- Always use absolute paths when passing files to scripts run from outside the project.
