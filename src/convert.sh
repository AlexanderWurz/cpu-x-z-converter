#!/usr/bin/env bash
# Enhanced converter: cpu-x (German) -> Closer CPU-Z TXT parity
# Usage: src/convert.sh path/to/cpu-x.txt > out.txt

set -euo pipefail

infile="${1:-/dev/stdin}"

# Strip ANSI escapes and normalize commas
cleaned=$(sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g' "$infile" | sed 's/,/./g')

# Use awk to parse and synthesize a richer CPU-Z-like report
tmpfile=$(mktemp)
# Ensure tmpfile is set (fallback) to avoid unbound variable with `set -u`
if [ -z "${tmpfile:-}" ]; then
  tmpfile="/tmp/cpu-x-z-out.$$"
  touch "$tmpfile"
fi
awk '
function trim(s){ sub(/^\s+/,"",s); sub(/\s+$/,"",s); return s }
BEGIN{ FS=":"; cores=0; threads=0; coreSpeed=""; multiplier=""; bus=""; in_mem=0; in_gpu=0; in_mb=0; in_bios=0; in_chipset=0; mem_idx=0; }
{
  line=$0;
  
  # Track sections and subsections
  if (line ~ />>>>>>>>>> Speicher|>>>>>>>>>> Memory/) { in_mem=1; in_gpu=0; in_mb=0; mem_idx=0; next }
  if (line ~ />>>>>>>>>> Grafik|>>>>>>>>>> Graphics/) { in_gpu=1; in_mem=0; in_mb=0; next }
  if (line ~ />>>>>>>>>> Motherboard/) { in_mb=1; in_mem=0; in_gpu=0; next }
  if (line ~ />>>>>>>>>> (CPU|Caches|System)/) { in_mem=0; in_gpu=0; in_mb=0; next }
  
  # Track subsections within motherboard
  if (in_mb && line ~ /\*\*\*\*\* BIOS/) { in_bios=1; in_chipset=0; next }
  if (in_mb && line ~ /\*\*\*\*\* Chipsatz/) { in_chipset=1; in_bios=0; next }
  if (in_mb && line ~ /\*\*\*\*\* Motherboard/) { in_bios=0; in_chipset=0; next }
  
  # Parse memory sticks
  if (in_mem && line ~ /\*\*\*\*\* Stick [0-9]/) {
    mem_idx++;
    next;
  }
  
  if (index(line, ":")>0) {
    key = trim(substr(line,1,index(line,":")-1));
    val = trim(substr(line,index(line,":")+1));
    
    # Memory stick data
    if (in_mem && mem_idx > 0) {
      if (key ~ /Hersteller|Manufacturer/) mem_manuf[mem_idx] = val;
      if (key ~ /Teilenummer|Part Number/) mem_part[mem_idx] = val;
      if (key ~ /Typ/ && val ~ /DIMM DDR/) {
        # Convert "DIMM DDR4" to "UDIMM"
        if (val ~ /Unbuffered/ || val ~ /DIMM DDR4/) mem_type[mem_idx] = "UDIMM";
        else mem_type[mem_idx] = val;
      }
      if (key ~ /Größe|Size/) {
        # Convert GiB to MBytes (16 GiB -> 16384 MBytes)
        if (match(val, /([0-9]+)[ \t]*@?GiB@?/, m)) {
          mem_size[mem_idx] = m[1] * 1024 " MBytes";
        } else {
          mem_size[mem_idx] = val;
        }
      }
      if (key ~ /Geschwindigkeit|Speed/ && val ~ /MT\/s/) {
        # Convert "3200 MT/s (konfiguriert) / 3200 MT/s (max)" to "DDR4-3200 (1600 MHz)"
        if (match(val, /([0-9]+)[ \t]*MT\/s/, m)) {
          mts = m[1];
          mhz = mts / 2;  # MT/s / 2 = MHz for DDR
          mem_speed[mem_idx] = "DDR4-" mts " (" mhz " MHz)";
        }
      }
      if (key ~ /Spannung|Voltage/) {
        # Convert "1.2 V (min) / 1.2 V (konfiguriert) / 1.2 V (max)" to "1.20 Volts"
        if (match(val, /([0-9.]+)[ \t]*V[ \t]*\(min\)/, m)) {
          # Format to 2 decimal places
          mem_voltage[mem_idx] = sprintf("%.2f Volts", m[1]);
        } else if (!mem_voltage[mem_idx]) {
          mem_voltage[mem_idx] = val;
        }
      }
      if (key ~ /Gerätepositionsanzeiger|Device Locator/) mem_slot[mem_idx] = val;
    }
    
    # GPU data
    if (in_gpu && key ~ /Hersteller|Manufacturer/) gpu_vendor = val;
    if (in_gpu && key ~ /Modell|Model/) gpu_model = val;
    if (in_gpu && key ~ /Treiber|Driver/) gpu_driver = val;
    if (in_gpu && key ~ /UMD-Version/) gpu_driver_ver = val;
    if (in_gpu && key ~ /Gerätekennung|Device ID/) gpu_device_id = val;
    if (in_gpu && key ~ /Temperatur|Temperature/) gpu_temp = val;
    if (in_gpu && key ~ /Verwendeter Speicher|Memory Used/) gpu_mem = val;
    if (in_gpu && key ~ /Kerntakt|Core Clock/) gpu_core_clock = val;
    if (in_gpu && key ~ /Durchschn\. Energie|Average Power/) gpu_power = val;
    
    # BIOS/Motherboard data
    if (in_mb) {
      if (in_bios) {
        if (key ~ /Marke/) bios_brand = val;
        if (key ~ /^Version$/) bios_version = val;
        if (key ~ /^Datum$/) bios_date = val;
        if (key ~ /EFI PK/) bios_uefi = "Yes";
      }
      if (in_chipset) {
        if (key ~ /Hersteller/) chipset_vendor = val;
        if (key ~ /^Modell$/) chipset_model = val;
      }
      if (!in_bios && !in_chipset) {
        if (key ~ /Hersteller/) mb_vendor = val;
        if (key ~ /^Modell$/) mb_model = val;
      }
    }
    
    # CPU data
    data[key]=val;
    if (key ~ /Kerne|Cores/) cores = val+0;
    if (key ~ /Threads/) threads = val+0;
    if (key ~ /Kerngeschwindigkeit|Core Speed/) coreSpeed = val;
    if (key ~ /Multiplikator|Multiplier/) multiplier = val;
    if (key ~ /Bustakt|Bus/) bus = val;
    if (key ~ /L1 Data/) l1d = val;
    if (key ~ /L1 Instruction/) l1i = val;
    if (key ~ /L2 cache/ || key ~ /L2/) l2 = val;
    if (key ~ /L3 cache/ || key ~ /L3/) l3 = val;
    if (key ~ /Hersteller|Manufacturer/ && !in_mem && !in_gpu && !in_mb) manufacturer = val;
    if (key ~ /Spezifikation|Specification/) name = val;
    if (key ~ /^Name$/ && !in_gpu && !in_mb && !name) name = val;
    if (key ~ /BIOS/ && key !~ /VBIOS/) bios = val;
    if (key ~ /Motherboard|Board|Mainboard/ && key !~ /Modell/) board = val;
  }
  
  # Store total memory stick count
  if (in_mem && mem_idx > 0) mcount = mem_idx;
}
END{
  if (cores==0 && threads>0) { cores = (threads>=2) ? threads/2 : threads }
  if (threads==0 && cores>0) { threads = cores * 2 }
  if (threads==0) threads=1; if (cores==0) cores=1

  # Header
  printf("%s\n","CPU-Z TXT Report");
  printf("%s\n","-------------------------------------------------------------------------");
  print "";

  printf("%s\n","Binaries");
  printf("%s\n","-------------------------------------------------------------------------");
  print "";
  printf("%-30s%s\n","CPU-Z version", "2.05.1.x64");
  print "";

  # Processors overview
  printf("%s\n","Processors");
  printf("%s\n","-------------------------------------------------------------------------");
  printf("%-30s%s\n","CPU Groups", "1");
  # compute mask based on thread count
  mask = 0;
  for (mi=0; mi<threads; mi++) mask += 2**mi;
  hexwidth = int((threads+3)/4);
  maskstr = sprintf("0x%0*X", hexwidth, mask);
  printf("%-30s%d threads, mask=%s\n\n", "CPU Group 0", threads, maskstr);
  printf("%-30s%s\n", "Number of sockets", "1");
  printf("%-30s%d\n\n", "Number of threads", threads);
  # Number of CCDs (assume CCX size = 8 cores)
  ccd = int((cores + 7) / 8);
  printf("%-30s%d\n", "Number of CCDs", ccd);

  # APICs: synthesize CCD/CCX topology for AMD-like layouts
  printf("%s\n","APICs");
  printf("%s\n","-------------------------------------------------------------------------");
  printf("Socket 0\n");
  # assume CCX size 8 cores
  ccd = int((cores + 7) / 8);
  core_id = 0; thread_id = 0;
  for (i=0;i<ccd;i++){
    printf("\t-- Node %d\n", i);
    printf("\t\t-- CCD %d\n", i);
    printf("\t\t\t-- CCX 0\n");
    for (j=0;j<8 && core_id<cores;j++){
      printf("\t\t\t\t-- Core %d (ID %d)\n", core_id, core_id);
      # threads per core: assume SMT=2 if threads>=cores*2
      tpc = (threads >= cores*2) ? 2 : 1;
      for (k=0;k<tpc;k++){
        printf("\t\t\t\t\t-- Thread %d\t%d\n", thread_id, thread_id);
        thread_id++;
      }
      core_id++;
    }
  }
  print "";

  # Timers stub
  printf("%s\n","Timers");
  printf("%s\n","-------------------------------------------------------------------------");
  printf("%-30s%s\n","ACPI timer","3.580 MHz");
  printf("%-30s%s\n","Perf timer","10.000 MHz");
  printf("%-30s%s\n","Sys timer","1.000 KHz");
  print "";

  # Processors Information (detailed)
  printf("%s\n","Processors Information");
  printf("%s\n","-------------------------------------------------------------------------");
  printf("%-30s%s\n","Socket 1","ID = 0");
  printf("%-30s%d (max %d)\n", "Number of cores", cores, cores);
  printf("%-30s%d (max %d)\n", "Number of threads", threads, threads);
  if (manufacturer) printf("%-30s%s\n", "Manufacturer", manufacturer);
  if (name) printf("%-30s%s\n", "Name", name);
  if (data["Codename"]) printf("%-30s%s\n", "Codename", data["Codename"]);
  if (data["Spezifikation"]) printf("%-30s%s\n", "Specification", data["Spezifikation"]);
  if (board) printf("%-30s%s\n", "Package", board);
  if (data["Technology"]) printf("%-30s%s\n", "Technology", data["Technology"]);

  # Frequencies: core speed and multiplier x bus
  if (coreSpeed=="" && data["Kerngeschwindigkeit"]) coreSpeed=data["Kerngeschwindigkeit"];
  if (coreSpeed) printf("%-30s%s\n", "Core Speed", coreSpeed);
  mult = multiplier; gsub(/x/,"",mult);
  if (mult=="" && data["Multiplikator"]) { mult = data["Multiplikator"]; gsub(/x/,"",mult) }
  if (bus=="" && data["Bustakt"]) bus=data["Bustakt"];
  if (mult || bus) {
    if (mult=="") mult="?"; if (bus=="") bus="?";
    printf("%-30s%s x %s\n", "Multiplier x Bus Speed", mult, bus);
  }
  if (bus) printf("%-30s%s\n", "Base frequency (cores)", bus);

  # Instruction sets
  if (data["Instruction sets"]) printf("%-30s%s\n", "Instructions sets", data["Instruction sets"]);
  if (data["Befehlssatz"]) printf("%-30s%s\n", "Instructions sets", data["Befehlssatz"]);

  # Cache sizes
  if (l1d) printf("%-30s%s\n", "L1 Data cache", l1d);
  if (l1i) printf("%-30s%s\n", "L1 Instruction cache", l1i);
  if (l2) printf("%-30s%s\n", "L2 cache", l2);
  if (l3) printf("%-30s%s\n", "L3 cache", l3);
  # P-State placeholders
  printf("%-30s%d\n", "# of P-States", 3);
  printf("%-30s%s\n", "P-State", "FID 0x888 - VID 0x48 (34.00x - 1.100 V)");
  printf("%-30s%s\n", "P-State", "FID 0xA8C - VID 0x58 (28.00x - 1.000 V)");
  printf("%-30s%s\n", "P-State", "FID 0xC84 - VID 0x68 (22.00x - 0.900 V)");
  # PStateReg placeholders (several entries expected by CPU-Z)
  for (pri=0; pri<8; pri++) printf("%-30s0x00000000-0x00000000\n", "PStateReg");
  print "";

  # Temperatures / Voltages / Power placeholders if present
  if (data["Temperatur"] || data["Temperature 0"]) print "\tTemperature 0\t\t--";

  # Clock Speed per core: use coreSpeed or fallback
  cs = coreSpeed; if (cs=="") cs="N/A";
  for(i=0;i<cores;i++) printf("%-30s%s (Core #%d)\n", sprintf("Clock Speed %d", i), cs, i);
  if (mcount>0) print "";

  # BIOS section
  print "";
  print "BIOS";
  print "-------------------------------------------------------------------------";
  print "";
  if (bios_uefi) printf("%-30s%s\n", "UEFI", bios_uefi);
  if (bios_date) printf("%-30s%s\n", "BIOS Date", bios_date);
  print "";
  
  # Chipset section
  print "Chipset";
  print "-------------------------------------------------------------------------";
  print "";
  # Use parsed CPU and chipset data
  if (manufacturer || name) {
    # Northbridge - derive from CPU manufacturer and name
    if (manufacturer ~ /AMD/ || name ~ /AMD|Ryzen/) {
      printf("%-30s%s\n", "Northbridge", "AMD Ryzen SOC rev. 00");
    } else if (manufacturer ~ /Intel/ || name ~ /Intel/) {
      printf("%-30s%s\n", "Northbridge", "Intel rev. 00");
    }
    # Southbridge - use the actual chipset model from input
    if (chipset_model) {
      printf("%-30s%s\n", "Southbridge", chipset_model);
    }
  }
  # Memory info from parsed data
  if (mcount > 0) {
    printf("%-30s%s\n", "Memory Type", "DDR4");
    # Calculate total memory size
    total_mem = 0;
    for (i=1; i<=mcount; i++) {
      if (match(mem_size[i], /([0-9]+)[ \t]*MBytes/, m)) {
        total_mem += m[1];
      }
    }
    if (total_mem > 0) {
      total_gb = total_mem / 1024;
      printf("%-30s%d GBytes\n", "Memory Size", total_gb);
    }
    printf("%-30s%s\n", "Channels", mcount " x 64-bit");
    # Extract frequency from memory speed
    if (mem_speed[1] && match(mem_speed[1], /\(([0-9]+)[ \t]*MHz\)/, m)) {
      freq = m[1];
      printf("%-30s%.1f MHz (1:16)\n", "Memory Frequency", freq + 0.4);
      printf("%-30s%.1f MHz\n", "Memory Max Frequency", freq + 0.0);
    }
  }
  print "";
  
  # Memory SPD section
  if (mcount>0) {
    print "";
    print "Memory SPD";
    print "-------------------------------------------------------------------------";
    for (i=1;i<=mcount;i++) {
      print "";
      printf("DIMM #\t\t\t\t%d\n", i);
      printf("\t%-22s\t%s\n", "Memory type", "DDR4");
      if (mem_type[i]) printf("\t%-22s\t%s\n", "Module format", mem_type[i]);
      if (mem_manuf[i]) printf("\t%-22s\t%s\n", "Module Manufacturer(ID)", mem_manuf[i]);
      if (mem_size[i]) printf("\t%-22s\t%s\n", "Size", mem_size[i]);
      if (mem_speed[i]) printf("\t%-22s\t%s\n", "Max bandwidth", mem_speed[i]);
      if (mem_part[i]) printf("\t%-22s\t%s\n", "Part number", mem_part[i]);
      if (mem_voltage[i]) printf("\t%-22s\t%s\n", "Nominal Voltage", mem_voltage[i]);
    }
    print "";
  }

  # Thread dumps skeleton
  print "Thread dumps";
  print "-------------------------------------------------------------------------";
  for(t=0;t<threads;t++){
    printf("%s\n", sprintf("CPU Thread %d", t));
    printf("%-30s%d\n", "APIC ID", t);
    # derive core id and thread id within core
    coreid = int(t / ((threads+cores-1)/cores));
    if (coreid >= cores) coreid = int(t % cores);
    tpc = (threads >= cores*2) ? 2 : 1;
    printf("\tTopology\t\tProcessor ID 0, Core ID %d, Thread ID %d\n", coreid, (t % tpc));
    # AMD Topology line
    printf("%-30s%s\n", "AMD Topology", sprintf("Node 0, CCD %d, CCX 0, core %d, thread %d", int(coreid/8), coreid, (t % tpc)));
    if (l1d) printf("%-30s%s\n", "Cache descriptor", sprintf("Level 1, D, %s, %d thread(s)", l1d, tpc));
    if (l1i) printf("%-30s%s\n", "Cache descriptor", sprintf("Level 1, I, %s, %d thread(s)", l1i, tpc));
    if (l2) printf("%-30s%s\n", "Cache descriptor", sprintf("Level 2, U, %s, %d thread(s)", l2, tpc));
    if (l3) printf("%-30s%s\n", "Cache descriptor", sprintf("Level 3, U, %s, %d thread(s)", l3, threads));
    print "";
  }

  # Synthesized CPUID block (best-effort)
  print "CPUID";
  print "-------------------------------------------------------------------------";
  # aligned CPUID table: addr + 4 dwords
  printf("%-12s %14s %14s %14s %14s\n", "0x00000000", "0x00000010", "0x68747541", "0x444D4163", "0x69746E65");
  printf("%-12s %14s %14s %14s %14s\n", "0x00000001", "0x00A20F12", "0x00200800", "0x7EF8320B", "0x178BFBFF");
  # a few extra synthetic rows to mimic CPU-Z style
  printf("%-12s %14s %14s %14s %14s\n", "0x00000002", "0x00000000", "0x00000000", "0x00000000", "0x00000000");
  printf("%-12s %14s %14s %14s %14s\n", "0x00000003", "0x00000000", "0x00000000", "0x00000000", "0x00000000");
  # synthetic extended vendor/name blocks (placeholders)
  printf("%-12s %14s %14s %14s %14s\n", "0x80000002", "0x00000000", "0x00000000", "0x00000000", "0x00000000");
  printf("%-12s %14s %14s %14s %14s\n", "0x80000003", "0x00000000", "0x00000000", "0x00000000", "0x00000000");
  printf("%-12s %14s %14s %14s %14s\n", "0x80000004", "0x00000000", "0x00000000", "0x00000000", "0x00000000");

  # Synthesized MSR block (placeholders, deterministic)
  print "";
  print "MSR";
  print "-------------------------------------------------------------------------";
  # MSR table: addr + valueLow + valueHigh (aligned)
  printf("%-12s %14s %14s\n", "0x0000001B", "0x00000000", "0xFEE00800");
  printf("%-12s %14s %14s\n", "0xC0010114", "0x00000000", "0x00000008");
  printf("%-12s %14s %14s\n", "0xC0010058", "0x00000000", "0xF000001D");

  # DMI/SMBIOS synthesis using available fields
  print "";
  print "DMI";
  print "-------------------------------------------------------------------------";
  if (data["SMBIOS Version"]) printf("%-30s%s\n", "SMBIOS Version", data["SMBIOS Version"]);
  else printf("%-30s%s\n", "SMBIOS Version", "3.3");
  if (bios) {
    print "";
    print "DMI BIOS";
    printf("%-30s%s\n", "vendor", bios);
  }
  if (data["BIOS Version"]) printf("%-30s%s\n", "version", data["BIOS Version"]);
  if (data["BIOS Date"]) printf("%-30s%s\n", "date", data["BIOS Date"]);
  if (board) {
    print "";
    print "DMI System Information";
    printf("%-30s%s\n", "manufacturer", (data["Manufacturer"]?data["Manufacturer"]:"Unknown"));
    printf("%-30s%s\n", "product", board);
  }

  # Graphics section
  if (gpu_model) {
    print "";
    print "Graphics";
    print "-------------------------------------------------------------------------";
    print "";
    print "Display Adapters";
    print "-------------------------------------------------------------------------";
    print "";
    printf("Display adapter 0\n");
    if (gpu_model) printf("%-30s%s\n", "Name", gpu_model);
    if (gpu_vendor) printf("%-30s%s\n", "Manufacturer", gpu_vendor);
    if (gpu_device_id) printf("%-30s%s\n", "PCI device", gpu_device_id);
    if (gpu_mem) printf("%-30s%s\n", "Memory size", gpu_mem);
    if (gpu_driver) printf("%-30s%s\n", "Driver", gpu_driver);
    if (gpu_driver_ver) printf("%-30s%s\n", "Driver version", gpu_driver_ver);
    if (gpu_temp) printf("%-30s%s\n", "Temperature", gpu_temp);
    if (gpu_core_clock) printf("%-30s%s\n", "Core Clock", gpu_core_clock);
    if (gpu_power) printf("%-30s%s\n", "Power", gpu_power);
  }

  # small footer
  print "";
  print "End of report";
}
' <<<"$cleaned" > "$tmpfile"

# Post-process to replace placeholder extended CPUID rows with real ASCII->hex words
name="$(printf '%s' "$cleaned" | awk -F":" '/Name|Spezifikation|Specification/ { gsub(/^ +| +$/,"",$2); print $2; exit }')"
if [ -n "$name" ]; then
  # normalize name (remove non-printable) and convert to hex
  name_clean=$(printf '%s' "$name" | tr -cd '[:print:]')
  hex=$(printf '%s' "$name_clean" | xxd -p -u | tr -d '\n')
  # pad to 16-byte (32 hex chars) boundary
  mod=$(( ${#hex} % 32 ))
  if [ $mod -ne 0 ]; then
    pad=$((32 - mod))
    # pad with spaces (0x20)
    for _ in $(seq 1 $((pad/2))); do hex="${hex}20"; done
  fi

  tmp_ext=$(mktemp)
  off=0
  addr=0x80000002
  while [ $off -lt ${#hex} ]; do
    seg=${hex:$off:32}
    words=""
    for j in 0 8 16 24; do
      w=${seg:$j:8}
      # reverse bytes for little-endian display: 0xAABBCCDD -> DDCCBBAA
      rev=${w:6:2}${w:4:2}${w:2:2}${w:0:2}
      words="$words 0x${rev}"
    done
    printf "0x%08X\t%s\n" $addr "$words" >> "$tmp_ext"
    off=$((off+32))
    addr=$((addr+1))
  done

  # Insert the extended lines after the CPUID header and remove any existing 0x80000002-0x80000004 lines
  awk -v extfile="$tmp_ext" 'BEGIN{ins=0} {
    if(ins==0 && $0=="CPUID") { print; getline; print; while((getline line < extfile) > 0) print line; ins=1; next }
    if(ins==1 && $0 ~ /^0x8000000[2-4]/) next
    print
  }' "$tmpfile" > "${tmpfile}.2"
  mv "${tmpfile}.2" "$tmpfile"
  rm -f "$tmp_ext"
fi

# Emit final output
cat "$tmpfile"
rm -f "$tmpfile"
