#!/usr/bin/env bash
# Enhanced converter: cpu-x (German) -> Closer CPU-Z TXT parity
# Usage: src/convert_more.sh path/to/cpu-x.txt > out.txt

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
BEGIN{ FS=":"; cores=0; threads=0; coreSpeed=""; multiplier=""; bus="" }
{
  line=$0;
  # capture DIMM lines (look for GiB and DDR)
  if (line ~ /GiB/ && line ~ /DDR/) {
    mem_modules[++mcount] = trim(line);
  }
  if (index(line, ":")>0) {
    key = trim(substr(line,1,index(line,":")-1));
    val = trim(substr(line,index(line,":")+1));
    data[key]=val;
    # common normalized keys
    if (key ~ /Kerne|Cores/) cores = val+0;
    if (key ~ /Threads/) threads = val+0;
    if (key ~ /Kerngeschwindigkeit|Core Speed/) coreSpeed = val;
    if (key ~ /Multiplikator|Multiplier/) multiplier = val;
    if (key ~ /Bustakt|Bus/) bus = val;
    if (key ~ /L1 Data/) l1d = val;
    if (key ~ /L1 Instruction/) l1i = val;
    if (key ~ /L2 cache/ || key ~ /L2/) l2 = val;
    if (key ~ /L3 cache/ || key ~ /L3/) l3 = val;
    if (key ~ /Hersteller|Manufacturer/) manufacturer = val;
    if (key ~ /Spezifikation|Specification|Name/) name = val;
    if (key ~ /BIOS/) bios = val;
    if (key ~ /Motherboard|Board|Mainboard/) board = val;
  }
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

  # Memory SPD-like section from captured mem_modules
  if (mcount>0) {
    print "Memory SPD";
    print "-------------------------------------------------------------------------";
    for (i=1;i<=mcount;i++) printf("%-30s%s\n", sprintf("DIMM %d", i-1), mem_modules[i]);
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
