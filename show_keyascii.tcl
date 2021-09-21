#!/usr/bin/tclsh

source readcmd.tcl

puts "PRESS q TO QUIT"
readcmd::term_set_raw
set c ""
while {$c != 113} {
	set c [scan [read stdin 1] %c]
	if {$c < 32} {
		puts [format "\\x%02x (NON-PRINTABLE)" $c]
	} elseif {$c < 256} {
		puts [format "\\x%02x (%c)" $c $c]
	} elseif {$c < 65536} {
		puts [format "\\u%04x (%c)" $c $c]
	} else {
		puts [format "\\U%08x (%c)" $c $c]
	}
}
readcmd::term_unset_raw
