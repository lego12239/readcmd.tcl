package provide readcmd 0.9

# for debug output
#set F [open /dev/pts/0 w]

namespace eval readcmd {
variable stty_bin "/bin/stty"
variable kbindings [dict create]


######################################################################
# TERMINAL UTILS
######################################################################
# Turn on a raw mode for an input stream
# Current terminal settings is returned to caller. This data can be
# passed to term_unset_raw proc.
proc term_set_raw {} {
	set term_prms [exec stty --save <@stdin]
	exec [set [namespace current]::stty_bin] raw -echo <@stdin
	return $term_prms
}

# Turn off a raw mode for an input stream
#  prms  - a saved terminal settings that are returned from term_set_raw call
#
# If there is no prms argument, then try to unset raw mode.
# Otherwise, configure a terminal to saved settings.
proc term_unset_raw {{prms ""}} {
	if {$prms ne ""} {
		exec stty $prms <@stdin
	} else {
		exec [set [namespace current]::stty_bin] -raw echo pass8 <@stdin
	}
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
#	puts $::F "SET: rmax: [dict get $tinfo rmax], cmax: [dict get $tinfo cmax], r: $r, c: $c, scroll: $rscroll"
##	flush $::F
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
#	puts $::F "WRITE: cc: [dict get $tinfo cc], len: [string length $chars], c: $c"
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
proc rcmd_char_rm_prevchar {_cmd _len _cpos _tinfo {data ""}} {
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

proc rcmd_char_rm_curchar {_cmd _len _cpos _tinfo {data ""}} {
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

proc rcmd_cur_move_nextchar {_cmd _len _cpos _tinfo {data ""}} {
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

proc rcmd_cur_move_prevchar {_cmd _len _cpos _tinfo {data ""}} {
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

proc rcmd_cur_move_atstart {_cmd _len _cpos _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set cpos 0
	term_curpos_set tinfo $cpos
	return 0
}

proc rcmd_cur_move_atend {_cmd _len _cpos _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set cpos $len
	term_curpos_set tinfo $cpos
	return 0
}

proc rcmd_term_key {_cmd _len _cpos _tinfo data} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	if {$data eq "3"} {
		rcmd_char_rm_curchar cmd len cpos tinfo
	}
	return 0
}

proc rcmd_cur_move_prevword {_cmd _len _cpos _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	while {$cpos != 0} {
		incr cpos -1
		if {([string index $cmd $cpos] ne " ") &&
		    ($cpos > 0) && ([string index $cmd ${cpos}-1] eq " ")} {
			break
		}
	}
	term_curpos_set tinfo $cpos
	return 0
}

proc rcmd_cur_move_nextword {_cmd _len _cpos _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	while {$cpos != $len} {
		incr cpos
		if {([string index $cmd $cpos] eq " ") &&
		    ([string index $cmd ${cpos}-1] ne " ")} {
			break
		}
	}
	term_curpos_set tinfo $cpos
	return 0
}

proc rcmd_word_rm_prev {_cmd _len _cpos _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set epos $cpos
	while {$cpos != 0} {
		incr cpos -1
		if {([string index $cmd $cpos] ne " ") &&
		    ($cpos > 0) && ([string index $cmd ${cpos}-1] eq " ")} {
			break
		}
	}

	if {$epos != $cpos} {
		set cmd [string replace $cmd $cpos ${epos}-1]
		set len [expr {$len - ($epos - $cpos)}]
	}

	term_curpos_set tinfo $cpos
	term_write_chars tinfo [string range $cmd $cpos end]
	return 0
}

proc rcmd_word_rm_cur {_cmd _len _cpos _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set epos $cpos
	while {$epos != $len} {
		incr epos
		if {([string index $cmd $epos] eq " ") &&
		    ([string index $cmd ${epos}-1] ne " ")} {
			break
		}
	}

	if {$epos != $cpos} {
		set cmd [string replace $cmd $cpos ${epos}-1]
		set len [expr {$len - ($epos - $cpos)}]
	}

	term_write_chars tinfo [string range $cmd $cpos end]
	return 0
}

proc rcmd_str_rm_tail {_cmd _len _cpos _tinfo {data ""}} {
	upvar $_cmd cmd
	upvar $_len len
	upvar $_cpos cpos
	upvar $_tinfo tinfo

	set cmd [string replace $cmd $cpos end]
	set len [string length $cmd]
	term_write_chars tinfo [string range $cmd $cpos end]

	return 0
}

proc rcmd_str_rm_head {_cmd _len _cpos _tinfo {data ""}} {
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

proc rcmd_str_accept {_cmd _len _cpos _tinfo {data ""}} {
	return 1
}

proc rcmd_str_cancel {_cmd _len _cpos _tinfo {data ""}} {
	return 2
}

proc rcmd_scrn_clean {_cmd _len _cpos _tinfo {data ""}} {
	upvar $_tinfo tinfo

	term_clean_screen tinfo
	return 4
}

proc rcmd_histo_prev {_cmd _len _cpos _tinfo {data ""}} {
	return 5
}

proc rcmd_histo_next {_cmd _len _cpos _tinfo {data ""}} {
	return 6
}

proc rcmd_word_autocomplete {_cmd _len _cpos _tinfo {data ""}} {
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

# return codes for key handlers:
#  0 - do nothing
#  1 - command editing is done(return)
#  2 - cancel command editing(return with empty command)
#  3 - return with exit command
#  4 - reset read_cmd state to "start" state(show prompt, get terminal size, get terminal cursor position)
#  5 - edit prev command from histo
#  6 - edit next command from histo
#  7 - autocomplete current command word
proc read_sync {kbindings {prompt "> "} {exit_cmd "exit"} {histo ""} {cmds ""}} {
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
				set ret [[dict get $kbindings $cseq] cmd cmd_len cpos terminfo $csiseq_data]
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
					lassign [rcmd_autocomplete [string range $cmd 0 ${cpos}-1] $cmds] acw acl
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

proc rcmd_autocomplete {cmd cmds} {
	set cmd_hpath ""
	# word to complete
	set wtc ""
	set cmdheir ""
	set wc ""
	set wl [list]

	# Separate completed words from uncompleted one
	# After this:
	#   wtc will contain uncompleted word;
	#   cmd_hpath will be list with completed words
	set cmd_hpath [_split $cmd]
	if {[string index $cmd end] ne " "} {
		set wtc [lindex $cmd_hpath end]
		set cmd_hpath [lrange $cmd_hpath 0 end-1]
	}

	# Get needed cmd hierarchy according to cmd_hpath
	if {[llength $cmd_hpath] == 0} {
		set cmdhier [dict get $cmds]
	} else {
		if {[dict exists $cmds {*}$cmd_hpath]} {
			if {[dict exists $cmds {*}$cmd_hpath _acl_hdlr]} {
				set cmdhier [[dict get $cmds {*}$cmd_hpath _acl_hdlr] ""]
			} else {
				set cmdhier [dict get $cmds {*}$cmd_hpath]
			}
		} else {
			# May be we will find a handler for getting a completion list?
			# This is suitable for commands with parameters.
			for {set n [expr {[llength $cmd_hpath] - 1}]} {$n >= 0} {incr n -1} {
				set tmp_hpath [lrange $cmd_hpath 0 end-$n]
				if {[dict exists $cmds {*}$tmp_hpath _acl_hdlr]} {
					set cmdhier [[dict get $cmds {*}$tmp_hpath _acl_hdlr] \
					  [lrange $cmd_hpath end-[expr {$n - 1}] end]]
					break
				}
			}
			if {[dict size $cmdhier] == 0} {
				return [list "" {}]
			}
		}
	}

	# Get autocompletion words list excluding keys started with "_"
	foreach wl_item [dict keys $cmdhier "${wtc}*"] {
		if {[string index $wl_item 0] eq "_"} {
			continue
		}
		if {[dict exists $cmdhier $wl_item _descr]} {
			set wl_item [list $wl_item [dict get $cmdhier $wl_item _descr]]
		} else {
			set wl_item [list $wl_item ""]
		}
		lappend wl $wl_item
	}


	# Get autocompletion for uncompleted word
	if {[llength $wl] == 0} {
		# wrong uncompleted word
		return [list "" {}]
	} elseif {[llength $wl] == 1} {
		# just 1 variant of possible completion
		return [list "[string range [lindex [lindex $wl 0] 0] [string length $wtc] end] " {}]
	}

	set wtc_len [string length $wtc]
	set wc [string range [lindex [lindex $wl 0] 0] $wtc_len end]
	foreach w $wl {
		for {set i 0} {[string index $wc $i] ne ""} {incr i} {
			if {[string index $wc $i] ne [string index [lindex $w 0] ${wtc_len}+$i]} {
				set wc [string range $wc 0 ${i}-1]
				break
			}
		}
		if {$wc eq ""} {
			break
		}
	}

	return [list $wc $wl]
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
}
