#!/usr/bin/tclsh

set PROMPT "\033\[90mcli>\033\[0m "
set is_running 1
set err_msg ""

set cmds [dict create]
set cmds_histo [list]

#lappend auto_path ~/work/libs/tcl
#package require readcmd

source readcmd.tcl

######################################################################
# COMMAND: show version
######################################################################
namespace eval mod_version {
proc cmd_show_ver {args} {
	puts "0.2"
}
}
dict set cmds show _descr "show info"
dict set cmds show version _ ::mod_version::cmd_show_ver
dict set cmds show version _descr "show program version"


######################################################################
# COMMAND: echo
######################################################################
namespace eval mod_echo {
proc cmd_echo {args} {
	puts "[join $args]"
}
}
dict set cmds echo _ ::mod_echo::cmd_echo
dict set cmds echo _descr "print specified arguments"


######################################################################
# COMMAND: say
######################################################################
proc say {args} {
	if {[dict exists $args to]} {
		set to [dict get $args to]
	} else {
		set to "everybody"
	}
	if {![dict exists $args msg]} {
		return
	}
	puts "[dict get $args msg], [dict get $args to]!"
}

proc say_acl {prms wtc} {
	set ret [dict create \
	  "to" [dict create \
	    _descr "to whom say"\
	    "<PERSON>" [dict create _descr "to whom say"]\
	    "" ""]\
	  "msg" [dict create \
	    _descr "what to say"\
	    "<MESSAGE>" [dict create _descr "what to say"]\
	    "" ""]]

	set i 0
	while {$i < [llength $prms]} {
		set p [lindex $prms $i]
		if {![dict exists $ret $p]} {
			return ""
		}
		incr i 2
		if {$i > [llength $prms]} {
			set ret [dict get $ret $p]
		} else {
			set ret [dict remove $ret $p]
		}
	}

	return $ret
}
dict set cmds say _ ::say
dict set cmds say _descr "say some message to somebody"
dict set cmds say _acl_hdlr ::say_acl


######################################################################
# COMMANDS ROUTINES
######################################################################
proc split_cmd {cmd} {
	global cmds
	set cmd_path $cmd

	while {[llength $cmd_path] > 0} {
		if {[dict exists $cmds {*}$cmd_path _]} {
			return [list \
			  [dict get $cmds {*}$cmd_path _]\
			  [lrange $cmd [llength $cmd_path] end]]
		}
		set cmd_path [lrange $cmd_path 0 end-1]
	}

	return ""
}


######################################################################
# MAIN
######################################################################
readcmd::term_set_raw

while {$is_running} {
	set cmd [readcmd::read_sync $readcmd::kbindings $PROMPT "exit" $cmds_histo $cmds]
	puts ""
	if {$cmd ne ""} {
		lappend cmds_histo $cmd
	}
	lassign [split_cmd $cmd] hdlr prms
	if {$hdlr ne ""} {
		puts "cmd hdlr is $hdlr for: '$cmd'"
		$hdlr {*}$prms
	}
	if {$cmd eq "exit"} {
		set is_running 0
	} elseif {$hdlr eq ""} {
		puts "Unknown command: $cmd"
	}
}

readcmd::term_unset_raw
