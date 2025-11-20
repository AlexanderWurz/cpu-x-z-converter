#!/usr/bin/env bash
# Simple converter: cpu-x (German) -> CPU-Z-like TXT report
# Usage: src/convert.sh path/to/cpu-x.txt > out.txt

set -euo pipefail

infile="${1:-/dev/stdin}"

# Read, strip ANSI escapes, normalize decimal commas to dots
cleaned=$(sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g' "$infile" | sed 's/,/./g')

awk '
function trim(s) { sub(/^\s+/, "", s); sub(/\s+$/, "", s); return s }
BEGIN {
  FS = ":";
}
# capture key:value lines into an associative array
{ if ($0 ~ /:/) {
    key = trim($1);
    # reconstruct value in case it contains ":"
    $1 = ""; val = trim(substr($0,2));
    gsub(/^[ \\t]+/, "", val);
    data[key] = val;
  } else {
    # also keep raw lines per-section (not used heavily)
  }
}
END {
  # Header
  print "CPU-Z TXT Report";
  print "-------------------------------------------------------------------------";
  print "";

  # Binaries stub
  print "Binaries";
  print "-------------------------------------------------------------------------";
  print "";
  print "CPU-Z version\t\t\t2.06.0.x64";
  print "";

  # Basic Processors block
  print "Processors";
  print "-------------------------------------------------------------------------";
  threads = ("Threads" in data) ? data["Threads"] : (("Threads " in data) ? data["Threads "] : "");
  cores = ("Kerne" in data) ? data["Kerne"] : (("Cores" in data) ? data["Cores"] : "");
  if (threads == "") threads = (cores != "") ? cores : "1";
  print "CPU Groups\t\t\t1";
  printf("CPU Group 0\t\t\t%s threads, mask=0xFFFFFFFF\n\n", threads);
  print "Number of sockets\t\t1";
  printf("Number of threads\t\t%s\n\n", threads);

  # Processors Information
  print "Processors Information";
  print "-------------------------------------------------------------------------";
  printf("Socket 1\t\t\tID = 0\n");
  if (cores != "") printf("\tNumber of cores\t\t%s (max %s)\n", cores, cores);
  if (threads != "") printf("\tNumber of threads\t%s (max %s)\n", threads, threads);

  if ("Hersteller" in data) printf("\tManufacturer\t\t%s\n", data["Hersteller"]);
  if ("Spezifikation" in data) printf("\tName\t\t\t%s\n", data["Spezifikation"]);
  else if ("Model" in data) printf("\tName\t\t\t%s\n", data["Model"]);
  else if ("Produkt" in data) printf("\tName\t\t\t%s\n", data["Produkt"]);

  if ("Codename" in data) printf("\tCodename\t\t\t%s\n", data["Codename"]);

  # Package / socket guesses
  if ("Stecker" in data) printf("\tPackage \t\t\t%s\n", data["Stecker"]);
  if ("Technology" in data) printf("\tTechnology\t\t\t%s\n", data["Technology"]);

  # Frequencies
  if ("Kerngeschwindigkeit" in data) printf("\tCore Speed\t\t%s\n", data["Kerngeschwindigkeit"]);
  if ("Multiplikator" in data) {
    m = data["Multiplikator"]; gsub(/x/,"",m);
    if ("Bustakt" in data) printf("\tMultiplier x Bus Speed\t%s x %s\n", m, data["Bustakt"]);
    else printf("\tMultiplier x Bus Speed\t%s\n", m);
  }
  if ("Bustakt" in data) printf("\tBase frequency (cores)\t%s\n", data["Bustakt"]);

  # Instruction sets if present
  if ("Instruction sets" in data) printf("\tInstructions sets\t%s\n", data["Instruction sets"]);
  if ("Befehlssatz" in data) printf("\tInstructions sets\t%s\n", data["Befehlssatz"]);

  # Caches: try common keys
  if ("L1 Data cache" in data) printf("\tL1 Data cache\t\t%s\n", data["L1 Data cache"]);
  if ("L1 Instruction cache" in data) printf("\tL1 Instruction cache\t%s\n", data["L1 Instruction cache"]);
  if ("L2 cache" in data) printf("\tL2 cache\t\t%s\n", data["L2 cache"]);
  if ("L3 cache" in data) printf("\tL3 cache\t\t%s\n", data["L3 cache"]);

  # Motherboard / BIOS
  if ("Motherboard" in data) printf("\tMotherboard\t\t%s\n", data["Motherboard"]);
  if ("BIOS" in data) printf("\tBIOS\t\t\t%s\n", data["BIOS"]);
  if ("BIOS Version" in data) printf("\tBIOS Version\t\t%s\n", data["BIOS Version"]);

  # Memory summary
  if ("Arbeitsspeicher" in data) printf("\tMemory\t\t\t%s\n", data["Arbeitsspeicher"]);
  if ("Total Memory" in data) printf("\tMemory\t\t\t%s\n", data["Total Memory"]);

  print "";
  print "Timers";
  print "-------------------------------------------------------------------------";
  print "\tACPI timer\t\t3.580 MHz";
  print "\tPerf timer\t\t10.000 MHz";
  print "\tSys timer\t\t1.000 KHz";
}
' <<<"$cleaned"

# End
