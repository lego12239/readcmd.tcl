# A command line editing library.
# Copyright (C) 2021 Oleg O. Nemanov <lego12239@yandex.ru>
# Made for Z-Wave.Me project.
#
# This code is licensed under BSD 2-clause license.

package provide readcmd 0.9

namespace eval readcmd {
variable dbg_fname ""
variable dbg_chan ""
variable stty_path "/bin/stty"
variable conf_fname "$::env(HOME)/.readcmd.conf /etc/readcmd.conf"
variable kbindings [dict create]


######################################################################
# DEBUG UTILS
######################################################################
proc dbg_init {fname} {
	variable dbg_chan

	if {$fname eq ""} {
		proc [namespace current]::dbg_out {msg} {}
		return
	}
	set dbg_chan [open $fname w]
}

proc dbg_out {msg} {
	variable dbg_chan

	puts $dbg_chan $msg
	flush $dbg_chan
}

######################################################################
# TERMINAL UTILS
######################################################################
# Turn on a raw mode for an input stream
# Current terminal settings is returned to caller. This data can be
# passed to term_unset_raw proc.
proc term_set_raw {} {
	set term_prms [term_get_prms]
	exec [set [namespace current]::stty_path] raw -echo <@stdin
	return $term_prms
}

# Turn off a raw mode for an input stream
#  prms  - a saved terminal settings that are returned from term_set_raw call
#
# If there is no prms argument, then try to unset raw mode.
# Otherwise, configure a terminal to saved settings.
proc term_unset_raw {{prms ""}} {
	if {$prms ne ""} {
		term_set_prms $prms
	} else {
		exec [set [namespace current]::stty_path] -raw echo pass8 <@stdin
	}
}

# Get current terminal settings.
proc term_get_prms {} {
	return [exec stty --save <@stdin]
}

# Set terminal settings to specified one.
#  prms  - a term_get_prms return value
proc term_set_prms {prms} {
	exec stty $prms <@stdin
}

# pos is a 0 based position from a line start.
proc term_curpos_set {_tinfo pos} {
	upvar $_tinfo tinfo
	# Add start position to pos and make it 0 based
	set pos [expr {[dict get $tinfo cs] - 1 + $pos}]
	set r [expr {[dict get $tinfo rs] + $pos / [dict get $tinfo cmax]}]
	# make c 1 based
	set c [expr {($pos % [dict get $tinfo cmax]) + 1}]
	set rscroll [expr {$r - [dict get $tinfo rmax]}]
	if {$rscroll > 0} {
		puts -nonewline "\x1b\[${rscroll}S"
		dict incr tinfo rs -$rscroll
		incr r -$rscroll
	}
	dict set tinfo rc $r
	dict set tinfo cc $c
	puts -nonewline "\x1b\[${r};${c}H"
	flush stdout
#	dbg_out "SET: rmax: [dict get $tinfo rmax], cmax: [dict get $tinfo cmax], r: $r, c: $c, scroll: $rscroll"
}

# DO NOT USE! UNFINISHED!
# Change cursor position by specified offset
proc _term_curpos_move {_tinfo off} {
	upvar $_tinfo tinfo

	set r [dict get $tinfo rc]
	set c [expr {[dict get $tinfo cc] + $off}]
	if {$c > [dict get $tinfo cmax]} {
		set r [expr {$r + ($c - 1)/[dict get $tinfo cmax]}]
		set c [expr {($c - 1) % [dict get $tinfo cmax] + 1}]
		set rscroll [expr {$r - [dict get $tinfo rmax]}]
		if {$rscroll > 0} {
			puts -nonewline "\x1b\[${rscroll}S"
			dict incr tinfo rs -$rscroll
			incr r -$rscroll
		}
	}
	dict set tinfo rc $r
	dict set tinfo cc $c
	puts -nonewline "\x1b\[${r};${c}H"
	flush stdout
}

proc term_write_chars {_tinfo chars} {
	upvar $_tinfo tinfo

	set c [expr {[dict get $tinfo cc] + [string length $chars] - 1}]
	if {$c > [dict get $tinfo cmax]} {
		set r [expr {[dict get $tinfo rc] + ($c - 1)/[dict get $tinfo cmax]}]
		set rscroll [expr {$r - [dict get $tinfo rmax]}]
		if {$rscroll > 0} {
			dict incr tinfo rs -$rscroll
			dict incr tinfo rc -$rscroll
		}
	}
#	dbg_out "WRITE: cc: [dict get $tinfo cc], len: [string length $chars], c: $c"
	puts -nonewline "\x1b7\x1b\[J${chars}\x1b8"
	flush stdout
}

proc term_clean_screen {_tinfo} {
	upvar $_tinfo tinfo

	dict set tinfo rs 1
	dict set tinfo cs 1
	dict set tinfo rc 1
	dict set tinfo cc 1
	puts -nonewline "\x1b\[2J\x1b\[1;1H"
	flush stdout
}


######################################################################
# CLI INPUT/OUTPUT
#######################################################
proc rcmd_char_rm_prevchar {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	if {$cpos > 0} {
		set cmd [string replace $cmd ${cpos}-1 ${cpos}-1]
		incr cpos -1
		incr len -1
		term_curpos_set tinfo $cpos
		term_write_chars tinfo [string range $cmd $cpos end]
	}
	return 0
}

proc rcmd_char_rm_curchar {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	if {$len eq 0} {
		return 3
	}
	if {$cpos < $len} {
		set cmd [string replace $cmd $cpos $cpos]
		incr len -1
		term_write_chars tinfo [string range $cmd $cpos end]
	}
	return 0
}

proc rcmd_cur_move_nextchar {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	if {$cpos < $len} {
		incr cpos
		term_curpos_set tinfo $cpos
	}
	return 0
}

proc rcmd_cur_move_prevchar {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	if {$cpos > 0} {
		incr cpos -1
		term_curpos_set tinfo $cpos
	}
	return 0
}

proc rcmd_cur_move_atstart {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set cpos 0
	term_curpos_set tinfo $cpos
	return 0
}

proc rcmd_cur_move_atend {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set cpos $len
	term_curpos_set tinfo $cpos
	return 0
}

proc rcmd_term_key {_cmd _len _cpos tok_rex _tinfo data} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	if {$data eq "3"} {
		rcmd_char_rm_curchar cmd len cpos $tok_rex tinfo
	}
	return 0
}

proc rcmd_cur_move_prevword {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set m [regexp -indices -inline -all $tok_rex [string range $cmd 0 $cpos-1]]
	if {[llength $m] > 0} {
		set cpos [lindex $m end 0]
	} else {
		set cpos 0
	}
	term_curpos_set tinfo $cpos
	return 0
}

proc rcmd_cur_move_nextword {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set m [regexp -indices -inline -all $tok_rex [string range $cmd $cpos end]]
#	dbg_out $m
	if {[llength $m] > 0} {
		incr cpos [lindex $m 0 1]
		incr cpos
	} else {
		set cpos $len
	}
	term_curpos_set tinfo $cpos
	return 0
}

proc rcmd_word_rm_prev {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set epos $cpos
	set m [regexp -indices -inline -all $tok_rex [string range $cmd 0 $cpos-1]]
	if {[llength $m] > 0} {
		set cpos [lindex $m end 0]
	} else {
		set cpos 0
	}

	if {$epos != $cpos} {
		set cmd [string replace $cmd $cpos ${epos}-1]
		set len [expr {$len - ($epos - $cpos)}]
	}

	term_curpos_set tinfo $cpos
	term_write_chars tinfo [string range $cmd $cpos end]
	return 0
}

proc rcmd_word_rm_cur {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set epos $cpos
	set m [regexp -indices -inline -all $tok_rex [string range $cmd $cpos end]]
	if {[llength $m] > 0} {
		incr epos [lindex $m 0 1]
		incr epos
	} else {
		set epos $len
	}

	if {$epos != $cpos} {
		set cmd [string replace $cmd $cpos ${epos}-1]
		set len [expr {$len - ($epos - $cpos)}]
	}

	term_write_chars tinfo [string range $cmd $cpos end]
	return 0
}

proc rcmd_str_rm_tail {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set cmd [string replace $cmd $cpos end]
	set len [string length $cmd]
	term_write_chars tinfo [string range $cmd $cpos end]

	return 0
}

proc rcmd_str_rm_head {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	if {$cpos > 0} {
		set cmd [string replace $cmd 0 ${cpos}-1]
		set len [string length $cmd]
		set cpos 0
		term_curpos_set tinfo 0
		term_write_chars tinfo [string range $cmd $cpos end]
	}

	return 0
}

proc rcmd_str_accept {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	return 1
}

proc rcmd_str_cancel {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	return 2
}

proc rcmd_scrn_clean {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	upvar $_tinfo tinfo

	term_clean_screen tinfo
	return 4
}

proc rcmd_histo_prev {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	return 5
}

proc rcmd_histo_next {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	return 6
}

proc rcmd_word_autocomplete {_cmd _len _cpos tok_rex _tinfo {data ""}} {
	return 7
}

# enter
dict set kbindings "\x0a" [namespace current]::rcmd_str_accept
# ctrl-c
dict set kbindings "\x03" [namespace current]::rcmd_str_cancel
# backspace
dict set kbindings "\x08" [namespace current]::rcmd_char_rm_prevchar
dict set kbindings "\x7f" [namespace current]::rcmd_char_rm_prevchar
# ctrl-d
dict set kbindings "\x04" [namespace current]::rcmd_char_rm_curchar
# ctrl-f
dict set kbindings "\x06" [namespace current]::rcmd_cur_move_nextchar
# right
dict set kbindings "\x1b\x5b\x43" [namespace current]::rcmd_cur_move_nextchar
# ctrl-b
dict set kbindings "\x02" [namespace current]::rcmd_cur_move_prevchar
# left
dict set kbindings "\x1b\x5b\x44" [namespace current]::rcmd_cur_move_prevchar
# delete
dict set kbindings "\x1b\x5b\x7e" [namespace current]::rcmd_term_key
dict set kbindings "\x7e" [namespace current]::rcmd_term_key
# alt-b
dict set kbindings "\x1b\x62" [namespace current]::rcmd_cur_move_prevword
# alt-f
dict set kbindings "\x1b\x66" [namespace current]::rcmd_cur_move_nextword
# ctrl-w
dict set kbindings "\x17" [namespace current]::rcmd_word_rm_prev
# alt-backspace
dict set kbindings "\x1b\x08" [namespace current]::rcmd_word_rm_prev
# alt-d
dict set kbindings "\x1b\x64" [namespace current]::rcmd_word_rm_cur
# ctrl-a
dict set kbindings "\x01" [namespace current]::rcmd_cur_move_atstart
# ctrl-e
dict set kbindings "\x05" [namespace current]::rcmd_cur_move_atend
# ctrl-k
dict set kbindings "\x0b" [namespace current]::rcmd_str_rm_tail
# ctrl-u
dict set kbindings "\x15" [namespace current]::rcmd_str_rm_head
# ctrl-l
dict set kbindings "\x0c" [namespace current]::rcmd_scrn_clean
# ctrl-p
dict set kbindings "\x10" [namespace current]::rcmd_histo_prev
# up
dict set kbindings "\x1b\x5b\x41" [namespace current]::rcmd_histo_prev
# ctrl-n
dict set kbindings "\x0e" [namespace current]::rcmd_histo_next
# down
dict set kbindings "\x1b\x5b\x42" [namespace current]::rcmd_histo_next
# tab
dict set kbindings "\x09" [namespace current]::rcmd_word_autocomplete

# Get a command from a user
# args:
#  prompt    - a command prompt
#  histo     - a list with previously entered commands(first is the oldest
#              command, last is the most recent command)
#  cmds      - a dict with available commands, where key is command name
#              and value is a dict with subcommands and so on.
#              If a value dict contain a key " " with "descr" subkey, then
#              it's used as description of a command in a list of possible
#              completions which is showed to a user on tab key(by default).
#              If a value dict contain a key " " with "acl_hdlr" subkey, then,
#              it's used as autocompletion list handler which should return
#              a list of possible completions.
#  exit_cmd  - a command which will be returned when a key handler returns
#              3(by default on ctrl-d press)
#  tok_rex   - a regular expression for token matching
#  kbindings - a dict with a key sequence mapping to handlers
#
# return codes for key handlers:
#  0 - do nothing
#  1 - command editing is done(return)
#  2 - cancel command editing(return with empty command)
#  3 - return with exit command
#  4 - reset read_cmd state to "start" state(show prompt, get terminal size, get terminal cursor position)
#  5 - edit prev command from histo
#  6 - edit next command from histo
#  7 - autocomplete current command word
proc read_sync {{prompt "> "} {histo ""} {cmds ""} {exit_cmd "exit"} {tok_rex {[^[\s]+}} {kbindings_ ""}} {
	set input [list]
	set csiseq_data ""
	set cmd ""
	set cmd_len 0
	set cpos 0
	set histo_idx [llength $histo]
	set code 0
	set terminfo [dict create rs 0 cs 0 rc 0 cc 0 rmax 0 cmax 0]
	set acw ""
	set acl [list]
	#  0 - show prompt, request cursor position info and terminal size info from terminal
	#  1 - show prompt, waiting cursor position info
	#  2 - waiting terminal size info
	#  3 - waiting char/seq (consume buffered user input)
	#  4 - waiting char/seq (consume user input)
	#  100 - finish
	set state 0

	if {[dict size $kbindings_] == 0} {
		variable kbindings
	} else {
		set kbindings $kbindings_
	}

	while {$state != 100} {
		switch $state {
		0 {
		}
		3 {
			if {[llength $input] == 0} {
				set state 4
				continue
			}
			lassign [lindex $input 0] cseq csiseq_data
			set input [lrange $input 1 end]
		}
		default {
			lassign [rcmd_get_cseq] cseq csiseq_data
		}
		}
#		for {set i 0} {$i < [string length $cseq]} {incr i} {
#			puts "[scan [string index $cseq $i] %c]"
#		}
		switch $state {
		0 {
			puts -nonewline $prompt
			# \033\[6n - get cursor position
			# \0337    - save cursor position
			# \033\[r  - reset scrolling region to entire window
			# \033\[999;999H - try to set cursor position to (999,999)
			# \033\[6n - get cursor position(bottom-right corner of a screen)
			# \0338    - restore cursor position
			puts -nonewline "\033\[6n\0337\033\[r\033\[999;999H\033\[6n\0338"
			flush stdout
			set state 1
		}
		1 {
			if {$cseq eq "\x1b\x5b\x52"} {
				set tmp [split $csiseq_data ";"]
				dict set terminfo rs [lindex $tmp 0]
				dict set terminfo cs [lindex $tmp 1]
				dict set terminfo rc [lindex $tmp 0]
				dict set terminfo cc [lindex $tmp 1]
				set state 2
			} else {
				lappend input [list $cseq $csiseq_data]
			}
		}
		2 {
			if {$cseq eq "\x1b\x5b\x52"} {
				set tmp [split $csiseq_data ";"]
				dict set terminfo rmax [lindex $tmp 0]
				dict set terminfo cmax [lindex $tmp 1]
				set state 3

				term_write_chars terminfo $cmd
				term_curpos_set terminfo $cpos
			} else {
				lappend input [list $cseq $csiseq_data]
			}
		}
		3 -
		4 {
			if {[dict exists $kbindings $cseq]} {
				set ret [[dict get $kbindings $cseq] cmd cmd_len cpos $tok_rex terminfo $csiseq_data]
				switch $ret {
				0 {
				}
				1 {
					set state 100
				}
				2 {
					set cmd ""
					set state 100
				}
				3 {
					set cmd $exit_cmd
					set state 100
				}
				4 {
					set state 0
				}
				5 {
					if {$histo_idx > 0} {
						incr histo_idx -1
						set cmd [lindex $histo $histo_idx]
						set cmd_len [string length $cmd]
						set cpos $cmd_len
						term_curpos_set terminfo 0
						term_write_chars terminfo $cmd
						term_curpos_set terminfo $cpos
					}
				}
				6 {
					if {$histo_idx < ([llength $histo] - 1)} {
						incr histo_idx
						set cmd [lindex $histo $histo_idx]
						set cmd_len [string length $cmd]
						set cpos $cmd_len
						term_curpos_set terminfo 0
						term_write_chars terminfo $cmd
						term_curpos_set terminfo $cpos
					}
				}
				7 {
					lassign [rcmd_autocomplete [string range $cmd 0 ${cpos}-1] \
					  $tok_rex $cmds] acw acl
					if {[llength $acl]} {
						puts ""
						foreach i $acl {
							puts [format "%-20s %s" [lindex $i 0] [lindex $i 1]]
						}
						set state 0
					}
					if {$acw ne ""} {
						set cmd [_str_insert $cmd $cpos "$acw"]
						incr cpos [string length $acw]
						incr cmd_len [string length $acw]
						if {$state != 0} {
							term_write_chars terminfo [string range $cmd ${cpos}-[string length $acw] end]
							term_curpos_set terminfo $cpos
						}
					}
				}
				}
			} elseif {([string length $cseq] == 1) && ($cseq >= " ")} {
				# Is this trick with "append" is really measurably for
				# performance?
				if {$cpos == $cmd_len} {
					append cmd $cseq
				} else {
					set cmd [string replace $cmd $cpos $cpos "${cseq}[string index $cmd $cpos]"]
				}
				incr cpos
				incr cmd_len
				term_write_chars terminfo [string range $cmd ${cpos}-1 end]
				term_curpos_set terminfo $cpos
			}
		}
		}
	}

	return $cmd
}

# Read characters sequence.
# This will be 1 printable or control char or a complete escape sequence.
proc rcmd_get_cseq {} {
	set cseq ""
	set csiseq_data ""
	# 0 - wait char
	# 1 - wait CSI or escape sequence
	# 2 - wait CSI escape sequence
	# 3 - finish(got char or escape sequence)
	set state 0

	while {$state != 3} {
		set c [read stdin 1]
		set code [scan $c %c]
		switch $state {
		0 {
			set cseq $c
			if {$code == 27} {
				set state 1
			} else {
				set state 3
			}
		}
		1 {
			append cseq $c
			if {$code == 91} {
				set state 2
				set csiseq_data ""
			} else {
				set state 3
			}
		}
		2 {
			if {($code < 32) || ($code == 127)} {
				set state 3
			} elseif {($code >= 32) && ($code <= 63)} {
				append csiseq_data "$c"
			} elseif {($code >= 64) && ($code <= 126)} {
				set state 3
				append cseq $c
			} else {
				set state 3
			}
		}
		}
	}

	return [list $cseq $csiseq_data]
}

proc rcmd_autocomplete {cmd tok_rex cmds} {
	set cmd_hpath ""
	# word to complete
	set ttc ""
	set wc ""
	set wl [list]

	# Separate completed tokens from uncompleted one
	# After this:
	#   ttc will contain uncompleted token(actually it can be completed token,
	#       but cursor is right after it)
	#   cmd_hpath will be list with completed words
	set m [regexp -indices -inline -all $tok_rex $cmd]
	if {[lindex $m end 1] == [expr {[string length $cmd] - 1}]} {
		set ttc [string range $cmd [lindex $m end 0] [lindex $m end 1]]
		set m [lrange $m 0 end-1]
	}
	foreach e $m {
		lappend cmd_hpath [string range $cmd [lindex $e 0] [lindex $e 1]]
	}

	# Get needed cmd hierarchy according to cmd_hpath
	if {([llength $cmd_hpath] == 0) ||
	    ([dict exists $cmds {*}$cmd_hpath])} {
		if {[dict exists $cmds {*}$cmd_hpath " " acl_hdlr]} {
			set wl [[dict get $cmds {*}$cmd_hpath " " acl_hdlr] "" $ttc]
		} else {
			set wl [_acl_gen_from_dict [dict get $cmds {*}$cmd_hpath] $ttc]
			set wl [lsort -index 0 $wl]
		}
	} else {
		# May be we will find a handler for getting a completion list?
		# This is suitable for commands with parameters.
		set cmd_prms [list]
		for {set n [llength $cmd_hpath]} {$n >= 0} {incr n -1} {
			if {[dict exists $cmds {*}$cmd_hpath " " acl_hdlr]} {
				set wl [[dict get $cmds {*}$cmd_hpath " " acl_hdlr]\
				  $cmd_prms $ttc]
				break
			}
			set cmd_prms [linsert $cmd_prms 0 [lindex $cmd_hpath end]]
			set cmd_hpath [lrange $cmd_hpath 0 end-1]
		}
	}
	if {[llength $wl] == 0} {
		return [list "" {}]
	}

	# Get autocompletion for uncompleted word
	if {[llength $wl] == 0} {
		# wrong uncompleted word
		return [list "" {}]
	} elseif {[llength $wl] == 1} {
		# just 1 variant of possible completion
		return [list "[string range [lindex [lindex $wl 0] 0] [string length $ttc] end]" {}]
	}

	set wc [lindex [lindex $wl 0] 0]
	set wc_len [string length $wc]
	set wl_len [llength $wl]
	for {set idx 0} {$idx < $wc_len} {incr idx} {
		for {set i 1} {$i < $wl_len} {incr i} {
			if {[string index $wc $idx] ne [string index [lindex $wl $i 0] $idx]} {
				break
			}
		}
		if {$i != $wl_len} {
			break
		}
	}
	set wc [string range $wc 0 $idx-1]

	if {[string equal -length [string length $ttc] $ttc $wc]} {
		set wc [string range $wc [string length $ttc] end]
	}

	return [list $wc $wl]
}

proc _acl_gen_from_dict {cmdhier ttc} {
	set wl ""

	set ttc [string map {* \\* ? \\? [ \\[ ] \\] \\ \\\\} $ttc]
	foreach wl_item [dict keys $cmdhier "${ttc}*"] {
		if {$wl_item eq " "} {
			continue
		}
		if {[dict exists $cmdhier $wl_item " " descr]} {
			set wl_item [list "$wl_item " \
			  [dict get $cmdhier $wl_item " " descr]]
		} else {
			set wl_item [list "$wl_item " ""]
		}
		lappend wl $wl_item
	}
	return $wl
}

proc _split {str} {
	apply {args { return $args; }} {*}$str;
}

# M+N as pos isn't supported(only single integer).
proc _str_insert {str pos text} {
	if {$pos <= 0} {
		return "${text}$str"
	} elseif {$pos >= [string length $str]} {
		return "${str}$text"
	}
	return [string replace $str $pos $pos "$text[string index $str $pos]"]
}

proc conf_load {} {
	variable conf_fname

	foreach fname $conf_fname {
		if {[file exists $fname]} {
			source $fname
			break
		}
	}
}

conf_load
dbg_init $dbg_fname
}
