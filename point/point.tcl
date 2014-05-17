package require msgcat

option add *point.nick			red		widgetDefault
option add *point.tag 			ForestGreen	widgetDefault
option add *point.my	    		gray		widgetDefault
option add *point.number  		blue		widgetDefault
option add *point.private_foreground	blue		widgetDefault
option add *point.private_background	#FF9A15		widgetDefault

namespace eval point {
variable options
variable chat_things

::msgcat::mcload [file join [file dirname [info script]] msgs]

if {![::plugins::is_registered point]} {
    ::plugins::register point \
              -namespace [namespace current] \
              -source [info script] \
              -description [::msgcat::mc "Whether the point plugin is loaded."] \
              -loadcommand [namespace code load] \
              -unloadcommand [namespace code unload]
    return
    }

        custom::defgroup Plugins [::msgcat::mc "Plugins options."] -group Tkabber

        set group "point"
        custom::defgroup $group \
                [::msgcat::mc "point settings."] \
                -group Plugins

        custom::defvar options(main_jid) "p@point.im/point" \
                [::msgcat::mc "Main point JID. This used for forwarding things from other chats."] \
                -group $group \
                -type string
        custom::defvar options(nick) "" \
                [::msgcat::mc "Your point nickame."] \
                -group $group \
                -type string
        custom::defvar options(special_update_point_tab) 1 \
                [::msgcat::mc "Only private messages and replies to your comments is personal message."] \
                -group $group \
                -type boolean

proc load {} {
    ::richtext::entity_state point_numbers 1
    ::richtext::entity_state point 1
    ::richtext::entity_state point_ligth 1

    hook::add draw_message_hook        [namespace current]::ignore_server_messages 0
    hook::add draw_message_hook        [namespace current]::handle_message 21
    hook::add chat_window_click_hook   [namespace current]::insert_from_window
    hook::add rewrite_message_hook     [namespace current]::rewrite_point_message 20
    hook::add chat_send_message_hook   [namespace current]::rewrite_send_point_message 19

    hook::add draw_message_hook [namespace current]::update_point_tab 8
    hook::remove draw_message_hook ::plugins::update_tab::update 8

    hook::add draw_message_hook [namespace current]::add_number_of_messages_from_point_to_title 18
    hook::remove draw_message_hook ::::ifacetk::add_number_of_messages_to_title 18

    hook::add generate_completions_hook [namespace current]::point_commands_comps 99
}

proc unload {} {
    hook::remove draw_message_hook        [namespace current]::ignore_server_messages 0
    hook::remove draw_message_hook        [namespace current]::handle_message 21
    hook::remove chat_window_click_hook   [namespace current]::insert_from_window
    hook::remove rewrite_message_hook     [namespace current]::rewrite_point_message 20
    hook::remove chat_send_message_hook   [namespace current]::rewrite_send_point_message 19

    hook::remove draw_message_hook [namespace current]::update_point_tab 8
    hook::add draw_message_hook ::plugins::update_tab::update 8

    hook::remove draw_message_hook [namespace current]::add_number_of_messages_from_point_to_title 18
    hook::add draw_message_hook ::::ifacetk::add_number_of_messages_to_title 18

    hook::remove generate_completions_hook [namespace current]::point_commands_comps 99

    ::richtext::entity_state point_numbers 0
    ::richtext::entity_state point 0
    ::richtext::entity_state point_ligth 0
}

proc is_point_jid {jid} {
    set jid [::xmpp::jid::removeResource $jid]
    set node [::xmpp::jid::node $jid]
    return [expr [cequal $jid "p@point.im"]]
}

proc is_point {chatid} {
    set jid [chat::get_jid $chatid]
    return [is_point_jid $jid]
}

proc handle_message {chatid from type body x} {
    if {![is_point $chatid]} return

    ::richtext::property_add {point} {}

    set chatw [chat::chat_win $chatid]
    set jid [chat::get_jid $chatid]

    set tags {}
    if {![cequal $jid $from]} {
        lappend tags pointMY
    }

    ::richtext::render_message $chatw $body $tags
    return stop
}

proc is_personal_point_message {from body} {
    variable options

    set reply_to_my_comment 0

    set private_msg [regexp {^P @.+ -> @.+:\n} $body]
    set reply_to_comment [regexp {\n(@.+|@.+ -> @.+):\n>.+\n\n.+\n\n#[a-z]+/\d+ \(\d+\) http://point.im/[a-z]+#\d+$} $body -> reply_to_nick]

    if {$reply_to_comment} {
        set reply_to_my_comment [cequal $options(nick) $reply_to_nick]
    }

    return [expr $private_msg || $reply_to_my_comment]
}

proc update_point_tab {chatid from type body x} {
    variable options
    if {![expr [is_point_jid $from] && [cequal $type "chat"] && $options(special_update_point_tab)]} {
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

    if {[is_personal_point_message $from $body]} {
        tab_set_updated $cw 1 mesg_to_user
    } else {
        tab_set_updated $cw 1 message
    }
}

proc ignore_server_messages {chatid from type body x} {
    if {[is_point $chatid] && $from == ""} {
        return stop;
    }
}

proc add_number_of_messages_from_point_to_title {chatid from type body x} {
    variable options
    if {![expr [is_point_jid $from] && [cequal $type "chat"] && $options(special_update_point_tab)]} {
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

    if {[is_personal_point_message $from $body]} {
        incr personal_msg($chatid)
    }

    ::ifacetk::update_chat_title $chatid
    ::ifacetk::update_main_window_title
}

proc rewrite_point_message \
     {vxlib vfrom vid vtype vis_subject vsubject \
      vbody verr vthread vpriority vx} {
    upvar 2 $vfrom from
    upvar 2 $vtype type
    upvar 2 $vbody body
    upvar 2 $vx x

    if {![is_point_jid $from] || ![cequal $type "chat"]} {
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

proc rewrite_send_point_message {chatid user body type} {
    if {![is_point $chatid] || ![cequal $type "chat"]} {
        return
    }

    if {[regexp {^S #[a-z]+\+\s*$} $body -> thing]} {
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

    if {[set idx [lsearch -glob $tags point-*]] >= 0} {
        set thing [string range [lindex $tags $idx] 6 end]
    }

    if {$thing == ""} return

    if {![is_point_jid $jid]} {
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

proc point_commands_comps {chatid compsvar wordstart line} {
    if {![is_point $chatid]} return

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

variable commands {help login S U off on D BL P ping subs readers}
proc correct_command {chatid user body type} {
   # Maybe once I'll get arount to it 
}

# --------------
# RichText stuff

proc configure_point {w} {
    set options(point.nick) [option get $w point.nick Text]
    set options(point.tag) [option get $w point.tag Text]
    set options(point.my) [option get $w point.my Text]

    $w tag configure pointNICK -foreground $options(point.nick)
    $w tag configure pointTAG -foreground $options(point.tag)
    $w tag configure pointMY -foreground $options(point.my)
}

proc configure_point_numbers {w} {
    set options(point.number) [option get $w point.number Text]

    $w tag configure pointNUM -foreground $options(point.number)
}

proc configure_point_ligth {w} {
    set options(point.private_foreground) [option get $w point.private_foreground Text]
    set options(point.private_background) [option get $w point.private_background Text]

    $w tag configure pointLIGTH -foreground $options(point.private_foreground)
    $w tag configure pointLIGTH -background $options(point.private_background)
}

proc spot_point_ligth {what at startVar endVar} {
    set matched [regexp -indices -start $at -- \
    {(^PM)(?: from @.+:\n)} $what -> bounds]

    if {!$matched} { return false }

    upvar 1 $startVar uStart $endVar uEnd
    lassign $bounds uStart uEnd
    return true
}

proc spot_point {what at startVar endVar} {
    # WTF IS THIS?
    set matched [regexp -indices -start $at -- \
    {(?:\s|\n|\A|\(|\>)(@[\w@.-]+|\*[\w?!+'/.-]+)(?:(\.(\s|\n))?)} $what -> bounds]

    if {!$matched} { return false }

    upvar 1 $startVar uStart $endVar uEnd
    lassign $bounds uStart uEnd
    return true
}

proc spot_point_numbers {what at startVar endVar} {
    set matched [regexp -indices -start $at -- \
    {(?:\s|\n|\A|\(|\>)(#[a-z]+(/\d+)?)(?:(\.(\s|\n))?)} $what -> bounds]
    if {!$matched} { return false }

    upvar 1 $startVar uStart $endVar uEnd
    lassign $bounds uStart uEnd
    return true
}

proc process_point {atLevel accName} {
    if {[::richtext::property_exists {point}]} {
        return [process $atLevel $accName point]
    }
}

proc process_point_numbers {atLevel accName} {
    return [process $atLevel $accName point_numbers]
}

proc process_point_ligth {atLevel accName} {
    if {[::richtext::property_exists {point}]} {
       return [process $atLevel $accName point_ligth]
    }
}

proc process {atLevel accName what} {
    upvar #$atLevel $accName chunks

    set out {}

    foreach {s type tags} $chunks {
        if {[lsearch -regexp $type (text)|(point_ligth)]<0} {
            # pass through
            lappend out $s $type $tags
            continue
        }

        if {[expr [lsearch -exact $type point_ligth]>=0]} {
        lappend tags pointLIGTH
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

proc render_point {w type thing tags args} {
    if {[expr [lsearch -exact $tags pointLIGTH]<0]} {
       if {[cequal [string index $thing 0] "#" ]} {
          set type pointNUM
          } else {
                 if {[cequal [string index $thing 0] "*" ]} {
                    set type pointTAG
                    } else {
                           if {[cequal [string index $thing 0] "@" ]} {
                               set type pointNICK
                               }
                           }
                 }
    } else {
           if {[lsearch -exact $tags pointLIGTH]>=0} {
               set type pointLIGTH
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

    set id point-$thing
    $w insert end $thing [lfuse $tags [list $id $type point]]
    return $id
}

proc render_point_ligth {w type thing tags args} {
    set id pointLIGTH-$thing
    $w insert end $thing [lfuse $tags [list $id $type pointLIGTH]]
    return $id
}

::richtext::register_entity point_numbers \
    -configurator [namespace current]::configure_point_numbers \
    -parser [namespace current]::process_point_numbers \
    -renderer [namespace current]::render_point \
    -parser-priority 53

::richtext::register_entity point_ligth \
    -configurator [namespace current]::configure_point_ligth \
    -parser [namespace current]::process_point_ligth \
    -renderer [namespace current]::render_point_ligth \
    -parser-priority 81

::richtext::register_entity point \
    -configurator [namespace current]::configure_point \
    -parser [namespace current]::process_point \
    -renderer [namespace current]::render_point \
    -parser-priority 85
}
# vi:ts=4:et
