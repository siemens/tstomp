#!/bin/sh
#\
exec tclsh "$0" "$@"

package require tcltest

namespace import -force ::tcltest::*

# namespace import overrides debug command
# so we have to reoverride the command
proc debug {args} {
	puts "[lindex $args 0]"
}

# Software under test
package require tStomp

# Setting serverAddress and serverPort
set ::serverAddress localhost
set ::serverPort 61613

foreach {key value} $argv {
	switch -exact $key {
		-serverAddress {
			set ::serverAddress $value
		}
		-serverPort {
			set ::serverPort $value
		}
	}
}

tStomp ::s $::serverAddress $::serverPort

set ::runs 0

proc getNewQueue {} {
	set queue "/queue/test."
	append queue [string trim [clock clicks] -]
	return $queue
}

proc stompcallback {messageNvList} {

	puts "------------------------------"
	foreach {name value} [join $messageNvList] {
		set ::$name $value
		puts "#-#-# $name '$value'"

	}
	puts "------------------------------"

}



test Stomp_connect {} -body {
	puts "## Stomp_connect"
	# Connect
	catch {delete object ::s}
	tStomp ::s $::serverAddress $::serverPort
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result
	if {$::result == "NOT CONNECTED"} {
		error "In testcase 'Stomp_connect' Connection failed"
		puts "### NOT CONNECTED"
	}

	if ![::s getIsConnected] {
		error "In testcase 'Stomp_connect' Not Connected"
	}
	
	# two connects to same socket not possible
	if {[catch {::s connect {set ::result CONNECTED}}] == 0} {
		error "In testcase 'Stomp_connect' Connect twice possible"
	}

	# disconnect
	if {[::s disconnect] != 1} {
		error "In testcase 'Stomp_connect Disconnect failed'"
	}

	# second connect with new script
	::s connect {set ::result2 CONNECTED}
	after 5000 [list set ::result2 "NOT CONNECTED"]
	vwait ::result2
	if {$::result2 == "NOT CONNECTED"} {
		error "In testcase 'Stomp_connect' Connection two failed"
		puts "### NOT CONNECTED"
	}

	return 1	
} -result "1"


test Stomp_disconnect {} -body {
	puts "## Stomp_disconnect"
	catch {delete object ::s}
	tStomp ::s $::serverAddress $::serverPort

	# disconnect
	if {[catch {::s disconnect}] == 0} {
		error "In testcase 'Stomp_disconnect' Disconnect faild"
	}

	if [::s getIsConnected] {
		error "In testcase 'Stomp_disconnect' Still connected. Seems like disconnect doesn't work exactly"
	}

	return 1
} -result "1"


test Stomp_Send {} -body {
	puts "## Stomp_Send"
	set queue [getNewQueue]
	# Connect
	catch {delete object ::s}
	tStomp ::s $::serverAddress $::serverPort
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result

	if {[::s send $queue "Stomp_Send"] != 1} {
		error "In testcase 'Stomp_Send' Send to queue faild"
	} else {
		set res 1
	}

	# disconnect
	if {[::s disconnect] != 1} {
		error "In testcase 'Stomp_send' Disconnect faild"
	}
	
	return $res
} -result "1"


test Stomp_subscribe {} -body {
	puts "## Stomp_subscribe"
	set queue_subscribe [getNewQueue]
	# Connect
	catch {delete object ::s}
	tStomp ::s $::serverAddress $::serverPort
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result

	# subscribe
	if {[::s subscribe $queue_subscribe {stompcallback $messageNvList}] != 1} {
		error "In testcase 'Stomp_subscribe' Subscrib to queue faild"
	}

	after 1000 [list ::s send $queue_subscribe "Stomp_subscribe"]
	set afterId [after 5000 [list set ::messagebody ERROR]]
	vwait ::messagebody
	catch {after cancel $afterID}

	if {[string match "Stomp_subscribe*" $::messagebody] != 1} {
		error "In testcase 'Stomp_subscribe' getting a message failed"
	}

	# unsubscribe
	if {[::s unsubscribe $queue_subscribe] != 1} {
		error "In testcase 'Stomp_subscribe' Unsubscribe failed"
	}

	# disconnect
	if {[::s disconnect] != 1} {
		error "In testcase 'Stomp_subscribe' Disconnect faild"
	}
	
	# subscribe without connection
	if {[catch {::s subscribe $queue_subscribe {stompcallback $messageNvList}}] == 1} {
		error "In testcase 'Stomp_subscribe' subscribe without connection not possible"
	}

	# Connect
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result

	# send
	unset ::messagebody
	::s send $queue_subscribe "Stomp_2subscribe"
	after 5000 [list set ::messagebody ERROR]
	vwait ::messagebody

	if {[string match "Stomp_2subscribe*" $::messagebody] != 1} {
		error "In testcase 'Stomp_subscribe' getting a message failed (connect after subscribe)"
	}

	return 1

} -result "1"


test Stomp_unsubscribe {} -body {
	puts "## Stomp_unsubscribe"
	set queue_unsubscribe [getNewQueue]
	catch {delete object ::s}
	tStomp ::s $::serverAddress $::serverPort

	# unsubscribed
	if {[catch {::s unsubscribe $queue_unsubscribe}] == 0} {
		error "In testcase 'Stomp_unsubscribe' (Not connected and not subscribed) Unsubscribe failed"
	}

	# Connect
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result
	
	# unsubscribe
	if {[catch {::s unsubscribe $queue_unsubscribe}] == 0} {
		error "In testcase 'Stomp_unsubscribe' (Not subscribed) Unsubscribe failed"
	}
	
	# subscribe
	::s subscribe $queue_unsubscribe {stompcallback $messageNvList}

	# unsubscribe
	if {[::s unsubscribe $queue_unsubscribe] != 1} {
		error "In testcase 'Stomp_unsubscribe' (Connected and subscribed) Unsubscribe failed"
	}

	# unsubscribe
	if {[catch {::s unsubscribe $queue_unsubscribe}] == 0} {
		error "In testcase 'Stomp_unsubscribe' (Not subscribed again) Unsubscribe failed"
	}

	::s send $queue_unsubscribe "Stomp_unsubscribe"
	after 2000 [list set ::messagebody unsubscribed]
	vwait ::messagebody


	if {[string match "Stomp_unsubscribe*" $::messagebody]} {
		error "In testcase 'Stomp_unsubscribe' Messagebody contains result of sent message"
	}

	return 1

} -result "1"


test Stomp_handleLine {} -body {
	puts "## Stomp_handleLine"
	set queue_handleLine [getNewQueue]
	catch {delete object ::s}
	tStomp ::s $::serverAddress $::serverPort

	# Connect
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result
	
	# subscribe
	::s subscribe $queue_handleLine {stompcallback $messageNvList}

# list of line (from socket) and expected result
set message [list \
[list [list CONNECTED]								[list CONNECTED] [list ]] \
[list [list heart-beat:0,0]							[list CONNECTED] [list heart-beat 0,0]] \
[list [list session:ID:desw138x-38000-1339169069006-7494:231]			[list CONNECTED] [list session "ID:desw138x-38000-1339169069006-7494:231"]] \
[list [list server:ActiveMQ/5.6.0]						[list CONNECTED] [list server ActiveMQ/5.6.0]] \
[list [list version:1.1]							[list CONNECTED] [list version 1.1]] \
[list [list ]									[list CONNECTED] [list ]] \
[list [list 