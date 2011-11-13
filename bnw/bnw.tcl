package require msgcat

option add *bnw.nick			red		widgetDefault
option add *bnw.tag 			ForestGreen	widgetDefault
option add *bnw.club 			orange	widgetDefault
option add *bnw.my	    		gray		widgetDefault
option add *bnw.number  		blue		widgetDefault
option add *bnw.private_foreground	blue		widgetDefault
option add *bnw.private_background	#FF9A15		widgetDefault

namespace eval bnw {
variable options
variable bnw_nicknames
variable chat_things

::msgcat::mcload [file join [file dirname [info script]] msgs]

if {![::plugins::is_registered bnw]} {
    ::plugins::register bnw \
              -namespace [namespace current] \
              -source [info script] \
              -description [::msgcat::mc "Whether the BNW plugin is loaded."] \
              -loadcommand [namespace code load] \
              -unloadcommand [namespace code unload]
    return
    }

        custom::defgroup Plugins [::msgcat::mc "Plugins options."] -group Tkabber

        set group "BNW"
        custom::defgroup $group \
                [::msgcat::mc "BNW settings."] \
                -group Plugins

        custom::defvar options(main_jid) "bnw.im" \
                [::msgcat::mc "Main BNW JID. This used for forwarding things from other chats."] \
                -group $group \
                -type string
        custom::defvar options(nick) "" \
                [::msgcat::mc "Your BNW nickame."] \
                -group $group \
                -type string
        custom::defvar options(special_update_bnw_tab) 1 \
                [::msgcat::mc "Only private messages and replies to your comments is personal message."] \
                -group $group \
                -type boolean

proc load {} {
    ::richtext::entity_state bnw_numbers 1
    ::richtext::entity_state bnw 1
    ::richtext::entity_state bnw_ligth 1

    hook::add draw_message_hook        [namespace current]::ignore_server_messages 0
    hook::add draw_message_hook        [namespace current]::handle_message 21
    hook::add chat_window_click_hook   [namespace current]::insert_from_window
    hook::add rewrite_message_hook     [namespace current]::rewrite_bnw_message 20
    hook::add chat_send_message_hook   [namespace current]::rewrite_send_bnw_message 19

    hook::add draw_message_hook [namespace current]::update_bnw_tab 8
    hook::remove draw_message_hook ::plugins::update_tab::update 8

    hook::add draw_message_hook [namespace current]::add_number_of_messages_from_bnw_to_title 18
    hook::remove draw_message_hook ::::ifacetk::add_number_of_messages_to_title 18

    hook::add generate_completions_hook [namespace current]::bnw_commands_comps 99
}

proc unload {} {
    hook::remove draw_message_hook        [namespace current]::ignore_server_messages 0
    hook::remove draw_message_hook        [namespace current]::handle_message 21
    hook::remove chat_window_click_hook   [namespace current]::insert_from_window
    hook::remove rewrite_message_hook     [namespace current]::rewrite_bnw_message 20
    hook::remove chat_send_message_hook   [namespace current]::rewrite_send_bnw_message 19

    hook::remove draw_message_hook [namespace current]::update_bnw_tab 8
    hook::add draw_message_hook ::plugins::update_tab::update 8

    hook::remove draw_message_hook [namespace current]::add_number_of_messages_from_bnw_to_title 18
    hook::add draw_message_hook ::::ifacetk::add_number_of_messages_to_title 18

    hook::remove generate_completions_hook [namespace current]::bnw_commands_comps 99

    ::richtext::entity_state bnw_numbers 0
    ::richtext::entity_state bnw 0
    ::richtext::entity_state bnw_ligth 0
}

proc is_bnw_jid {jid} {
    set jid [::xmpp::jid::removeResource $jid]
    set node [::xmpp::jid::node $jid]
    return [expr [cequal $jid "bnw.im"]]
}

proc is_bnw {chatid} {
    set jid [chat::get_jid $chatid]
    return [is_bnw_jid $jid]
}

proc handle_message {chatid from type body x} {
    if {![is_bnw $chatid]} return

    ::richtext::property_add {BNW} {}

    set chatw [chat::chat_win $chatid]
    set jid [chat::get_jid $chatid]

    set tags {}
    if {![cequal $jid $from]} {
        lappend tags BNWMY
    }

    ::richtext::render_message $chatw $body $tags
    return stop
}

proc is_personal_bnw_message {from body} {
    variable options

    set reply_to_my_comment 0

    set private_msg [regexp {^PM from @.+:\n} $body]
    set reply_to_comment [regexp {Reply by @[^\n ]+:\n>.+\n\n@([^\n ]+) .+\n\n#\d?([A-Z]+\d*)+/\[A-Z0-9]+ \(\d+\) http://bnw.im/p/[A-Z0-9]+#[A-Z0-9]+$} $body -> reply_to_nick]

    if {$reply_to_comment} {
        set reply_to_my_comment [cequal $options(nick) $reply_to_nick]
    }

    return [expr $private_msg || $reply_to_my_comment]
}

proc update_bnw_tab {chatid from type body x} {
    variable options
    if {![expr [is_bnw_jid $from] && [cequal $type "chat"] && $options(special_update_bnw_tab)]} {
        ::plugins::update_tab::update $chatid $from $type $body $x
        return
    }

    # See ${PATH_TO_TKABBER}/plugins/chat/update_tab.tcl
    foreach xelem $x {
        ::xmpp::xml::split $xelem tag xmlns attrs cdata subels
        if {[string equal $tag ""] && [string equal $xmlns tkabber:x:nolog]} {
            return
        }
    }

    set cw [chat::winid $chatid]

    if {[is_personal_bnw_message $from $body]} {
        tab_set_updated $cw 1 mesg_to_user
    } else {
        tab_set_updated $cw 1 message
    }
}

proc ignore_server_messages {chatid from type body x} {
    if {[is_bnw $chatid] && $from == ""} {
        return stop;
    }
}

proc add_number_of_messages_from_bnw_to_title {chatid from type body x} {
    variable options
    if {![expr [is_bnw_jid $from] && [cequal $type "chat"] && $options(special_update_bnw_tab)]} {
        ::ifacetk::add_number_of_messages_to_title $chatid $from $type $body $x
        return
    }

    # See ${PATH_TO_TKABBER}/ifacetk/iface.tcl
    foreach xelem $x {
        ::xmpp::xml::split $xelem tag xmlns attrs cdata subels
        if {[string equal $tag ""] && [string equal $xmlns tkabber:x:nolog]} {
            return
        }
    }

    if {[::ifacetk::chat_window_is_active $chatid]} return
    if {$from == ""} return

    variable ::ifacetk::number_msg
    variable ::ifacetk::personal_msg

    incr number_msg($chatid)

    if {[is_personal_bnw_message $from $body]} {
        incr personal_msg($chatid)
    }

    ::ifacetk::update_chat_title $chatid
    ::ifacetk::update_main_window_title
}

proc rewrite_bnw_message \
     {vxlib vfrom vid vtype vis_subject vsubject \
      vbody verr vthread vpriority vx} {
    upvar 2 $vfrom from
    upvar 2 $vtype type
    upvar 2 $vbody body
    upvar 2 $vx x

    if {![is_bnw_jid $from] || ![cequal $type "chat"]} {
        return
    }

#############################
# Remove jabber:x:oob element
    set newx {}

    foreach xe $x {
        ::xmpp::xml::split $xe tag xmlns attrs cdata subels

        if {![cequal $xmlns "jabber:x:oob"]} {
            lappend newx $xe
        }
    }

    set x $newx
}

proc rewrite_send_bnw_message {chatid user body type} {
    if {![is_bnw $chatid] || ![cequal $type "chat"]} {
        return
    }

    if {[regexp {^S (#\d?([A-Z]+\d*)+)\+\s*$} $body -> thing]} {
        set xlib [chat::get_xlib $chatid]
        set jid [chat::get_jid $chatid]

        chat::add_message $chatid $user $type $body {}
        message::send_msg $xlib $jid -type chat -body "S $thing"
        message::send_msg $xlib $jid -type chat -body "$thing+"

        return stop
    }
}

proc insert_from_window {chatid w x y} {
    variable options
    set thing ""
    set cw [chat::chat_win $chatid]
    set ci [chat::input_win $chatid]
    set jid [::xmpp::jid::removeResource [chat::get_jid $chatid]]


    set tags [$cw tag names "@$x,$y"]

    if {[set idx [lsearch -glob $tags BNW-*]] >= 0} {
        set thing [string range [lindex $tags $idx] 4 end]
    }

    if {$thing == ""} return

    if {![is_bnw_jid $jid]} {
        set xlib [chat::get_xlib $chatid]
        set mainchat [chat::chatid $xlib $options(main_jid)]

        if {[chat::is_opened $mainchat]} {
            chat::activate $mainchat
        } else {
            chat::open_to_user $xlib $options(main_jid)
        }

        set ci [chat::input_win $mainchat]
    }

    $ci insert insert "$thing "
    focus -force $ci
    return stop
}

proc bnw_commands_comps {chatid compsvar wordstart line} {
    if {![is_bnw $chatid]} return

    upvar 0 $compsvar comps
    variable chat_things
    variable commands

    if {!$wordstart} {
       set comps [concat $commands $comps]
    } else {
if {0} {
        # This code don't work.
        # See ${PATH_TO_TKABBER}/plugins/chat/completion.tcl at line 94.
        # Idea: use *rename* for procedure completion::complete.
        set q 0
        foreach cmd $commands {
            if {[string equal -length [string length $cmd] $cmd $line]} {
                set q 1
                break
            }
	    }

        if {!$q} return
}
    }

    if {[info exist chat_things($chatid)]} {
       set comps [concat $chat_things($chatid) $comps]
    }
}

variable commands {HELP NICK LOGIN S U ON OFF D BL PM CARD PING}
proc correct_command {chatid user body type} {
   # Maybe once I'll get arount to it 
}

# --------------
# RichText stuff

proc configure_bnw {w} {
    set options(bnw.nick) [option get $w bnw.nick Text]
    set options(bnw.tag) [option get $w bnw.tag Text]
    set options(bnw.club) [option get $w bnw.club Text]
    set options(bnw.my) [option get $w bnw.my Text]

    $w tag configure BNWNICK -foreground $options(bnw.nick)
    $w tag configure BNWTAG -foreground $options(bnw.tag)
    $w tag configure BNWCLUB -foreground $options(bnw.club)
    $w tag configure BNWMY -foreground $options(bnw.my)
}

proc configure_bnw_numbers {w} {
    set options(bnw.number) [option get $w bnw.number Text]

    $w tag configure BNWNUM -foreground $options(bnw.number)
}

proc configure_bnw_ligth {w} {
    set options(bnw.private_foreground) [option get $w bnw.private_foreground Text]
    set options(bnw.private_background) [option get $w bnw.private_background Text]

    $w tag configure BNWLIGTH -foreground $options(bnw.private_foreground)
    $w tag configure BNWLIGTH -background $options(bnw.private_background)
}

proc spot_bnw_ligth {what at startVar endVar} {
    set matched [regexp -indices -start $at -- \
    {(^PM)(?: from @.+:\n)} $what -> bounds]

    if {!$matched} { return false }

    upvar 1 $startVar uStart $endVar uEnd
    lassign $bounds uStart uEnd
    return true
}

proc spot_bnw {what at startVar endVar} {
    # WTF IS THIS?
    set matched [regexp -indices -start $at -- \
    {(?:\s|\n|\A|\(|\>)(@[\w@.-]+|[*!][\w?!+'/.-@]+)(?:(\.(\s|\n))?)} $what -> bounds]

    if {!$matched} { return false }

    upvar 1 $startVar uStart $endVar uEnd
    lassign $bounds uStart uEnd
    return true
}

proc spot_bnw_numbers {what at startVar endVar} {
    set matched [regexp -indices -start $at -- \
    {(?:\s|\n|\A|\(|\>)(#\d?([A-Z]+\d*)+(/[A-Z0-9]+)?)(?:(\.(\s|\n))?)} $what -> bounds]
    if {!$matched} { return false }

    upvar 1 $startVar uStart $endVar uEnd
    lassign $bounds uStart uEnd
    return true
}

proc process_bnw {atLevel accName} {
    if {[::richtext::property_exists {BNW}]} {
        return [process $atLevel $accName bnw]
    }
}

proc process_bnw_numbers {atLevel accName} {
    return [process $atLevel $accName bnw_numbers]
}

proc process_bnw_ligth {atLevel accName} {
    if {[::richtext::property_exists {BNW}]} {
       return [process $atLevel $accName bnw_ligth]
    }
}

proc process {atLevel accName what} {
    upvar #$atLevel $accName chunks

    set out {}

    foreach {s type tags} $chunks {
        if {[lsearch -regexp $type (text)|(bnw_ligth)]<0} {
            # pass through
            lappend out $s $type $tags
            continue
        }

        if {[expr [lsearch -exact $type bnw_ligth]>=0]} {
        lappend tags BNWLIGTH
        }

        set index 0; set uStart 0; set uEnd 0
        while {[eval {spot_$what $s $index uStart uEnd}]} {
            if {$uStart - $index > 0} {
                # Write out text before current thing, if any:
                lappend out [string range $s $index [expr {$uStart - 1}]] $type $tags
            }

            set thing [string range $s $uStart $uEnd]
            # Write out current thing:
            lappend out $thing $what $tags
            set index [expr {$uEnd + 1}]
        }
        # Write out text after the last thing, if any:
        if {[string length $s] - $index > 0} {
        lappend out [string range $s $index end] $type $tags
        }
    }
    set chunks $out
}

proc render_bnw {w type thing tags args} {
    if {[expr [lsearch -exact $tags BNWLIGTH]<0]} {
       if {[cequal [string index $thing 0] "#" ]} {
          set type BNWNUM
          } else {
                 if {[cequal [string index $thing 0] "*" ]} {
                    set type BNWTAG
                    } else {
                           if {[cequal [string index $thing 0] "!" ]} {
                               set type BNWCLUB
                               } else {
                                      if {[cequal [string index $thing 0] "@" ]} {
                                        set type BNWNICK
                                      }
                                      }
                           }
                 }
    } else {
           if {[lsearch -exact $tags BNWLIGTH]>=0} {
               set type BNWLIGTH
           }
    }

#################
            variable chat_things
            set cw [join [lrange [split $w .] 0 end-1] .]
            set chatid [chat::winid_to_chatid $cw]
            if {![info exist chat_things($chatid)]} {
                set chat_things($chatid) [list $thing]
            } else {
                set chat_things($chatid) [linsert $chat_things($chatid) 0 $thing]
            }
#################

    set id BNW-$thing
    $w insert end $thing [lfuse $tags [list $id $type BNW]]
    return $id
}

proc render_bnw_ligth {w type thing tags args} {
    set id BNWLIGTH-$thing
    $w insert end $thing [lfuse $tags [list $id $type BNWLIGTH]]
    return $id
}

::richtext::register_entity bnw_numbers \
    -configurator [namespace current]::configure_bnw_numbers \
    -parser [namespace current]::process_bnw_numbers \
    -renderer [namespace current]::render_bnw \
    -parser-priority 53

::richtext::register_entity bnw_ligth \
    -configurator [namespace current]::configure_bnw_ligth \
    -parser [namespace current]::process_bnw_ligth \
    -renderer [namespace current]::render_bnw_ligth \
    -parser-priority 81

::richtext::register_entity bnw \
    -configurator [namespace current]::configure_bnw \
    -parser [namespace current]::process_bnw \
    -renderer [namespace current]::render_bnw \
    -parser-priority 85
}
# vi:ts=4:et
