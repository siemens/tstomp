# Stomp.test

package require tcltest

namespace import -force ::tcltest::*

# namespace import overrides debug command
# so we have to reoverride the command
proc debug {args} {
	puts "[lindex $args 0]"
}

# add current to directory for requiring tStomp
lappend auto_path ./

# Software under test
package require tStomp

# Setting ServerURL
set ::serverURL stomp://system:manager@localhost:61613
# overwrite by env Variable
if {$::env(stompServerURL)!=""} {
	set ::serverURL $::env(stompServerURL)
}
set ::failoverServerURL "failover:(stomp:tcp://invalid:invalid@localhost:99999,$::serverURL)"


set ::runs 0

proc getNewQueue {} {
	set queue "/queue/tstomp.test."
	append queue [string trim [clock clicks] -]
	return $queue
}

proc getTopic {} {
	set topic "/topic/tstomp.testtopic"
	return $topic
}

proc stompcallback {messageNvList} {
	puts "------------------------------"
	array set temp $messageNvList
	foreach name [array names temp] {
		set ::$name $temp(${name})

		puts "#-#-# $name $temp(${name})"
	}
	puts "------------------------------"
}

# to skip tests - add them here:
#tcltest::configure -skip [list Stomp_handleLine Stomp_connect Stomp_disconnect Stomp_Send Stomp_Double_Header Stomp_subscribe Stomp_unsubscribe Stomp_durably_subscribe Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_successful_connection Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_connection_lost]

test Stomp_connect {} -body {
	puts "## Stomp_connect"


	# Connect
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL
	::s connect {
		if {$isConnected} {
			set ::result "CONNECTED"
		} else {
			set result "NOT CONNECTED"
		}
	}

	unset -nocomplain -- ::result
	set afterId [after 5000 {set ::result "NOT CONNECTED"; puts "Excute after!"}]
	vwait ::result
	catch {after cancel $afterId}

	if {$::result == "NOT CONNECTED"} {
		puts "### NOT CONNECTED $::result"
		error "In testcase 'Stomp_connect' Connection failed"
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
	::s connect {set ::result2 "CONNECTED"}

	unset -nocomplain -- ::result2
	set afterId [after 5000 {set ::result2 "NOT CONNECTED"}]
	vwait ::result2
	catch {after cancel $afterId}

	if {$::result2 == "NOT CONNECTED"} {
		puts "### NOT CONNECTED $::result"
		error "In testcase 'Stomp_connect' Connection two failed"
	}

	return 1	
} -result "1"

test Stomp_disconnect {} -body {
	puts "## Stomp_disconnect"
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL

	# disconnect
	if {[catch {::s disconnect}] == 0} {
		error "In testcase 'Stomp_disconnect' Disconnect failed"
	}

	if [::s getIsConnected] {
		error "In testcase 'Stomp_disconnect' Still connected. Seems like disconnect doesn't work exactly"
	}

	return 1
} -result "1"

test Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_successful_connection {} -body {
	puts "##  Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_successful_connection "


	# GIVEN:
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL

	# WHEN connecting with heartBeat callback script:
	::s connect {puts "successfully connected"} -heartBeatScript {set ::result "HEARTBEAT"}  -heartBeatExpected 1000


	# THEN we expect that it is called within 5sec:
	unset -nocomplain -- ::result
	set afterId [after 10000 {set ::result "NO HEARTBEAT"; puts "Excute after!"}]
	vwait ::result
	catch {after cancel $afterId}

	if {$::result == "NO HEARTBEAT"} {
		puts "### NO HEARTBEAT $::result"
		error "In testcase 'Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_successful_connection' no heartbeat"
	}

	return 1
} -result 1

test Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_connection_lost {} -body {
	puts "## Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_connection_lost"


	# GIVEN:
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL
	
	# do the connect with a quick supervision 
	::s connect {set ::result "CONNECTED"} -supervisionTime 5 -heartBeatScript {puts "heart beat";if {!$isConnected} {set ::result2 "DISCONNECTION NOTICED"} else {set ::result3 "CONNECTION NOTICED"}}  -heartBeatExpected 1000

	unset -nocomplain -- ::result
	set afterId [after 5000 {set ::result "NOT CONNECTED"; puts "Excute after!"}]
	vwait ::result
	catch {after cancel $afterId}

	if {$::result == "NOT CONNECTED"} {
		puts "### NOT CONNECTED $::result"
		error "In testcase 'Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_connection_lost' Connection failed"
	}

	if {![::s getIsConnected]} {
		error "In testcase 'Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_connection_lost' Not Connected"
	}

	# ... at this point: connection is established - "green" :)

	unset -nocomplain -- ::result2
	
	# WHEN simulating a failure:
	puts "running testConnectionFailure"
	::s testConnectionFailure


	# THEN connection failure has to be noticed:
	puts "wait up to 15s for heart beat timeout..."
	set afterId [after 15000 {set ::result2 "NO DISCONNECTION NOTICED"}]
	vwait ::result2
	catch {after cancel $afterId}

	if {$::result2 == "NO DISCONNECTION NOTICED"} {
		puts "### $::result2"
		error "In testcase 'Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_connection_lost' heartbeat did not notice connection failure"
	}

	
	# THEN we expect a reconnection heart beat later:
	unset -nocomplain -- ::result3

	puts "wait up to 15s for heart beat with connection..."
	set afterId [after 15000 {set ::result3 "NO CONNECTION NOTICED"}]
	vwait ::result3
	catch {after cancel $afterId}

	if {$::result3 == "NO CONNECTION NOTICED"} {
		puts "### $::result3"
		error "In testcase 'Stomp_heartBeat_should_call_heartBeatScript_somewhen_after_connection_lost' heartbeat did not notice reconnection"
	}

	return 1	
} -result "1"

test Stomp_connect_should_failover_from_invalid_to_next_valid_broker {} -body {
	puts "## Stomp_connect_should_failover_to_next_broker"

	# GIVEN:
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::failoverServerURL

	# WHEN:
	::s connect {set ::result "CONNECTED"} 

	unset -nocomplain -- ::result
	set afterId [after 5000 {set ::result "NOT CONNECTED"; puts "Excute after!"}]
	vwait ::result
	catch {after cancel $afterId}

	# THEN:
	if {$::result == "NOT CONNECTED"} {
		puts "### NOT CONNECTED $::result"
		error "In testcase 'Stomp_connect_should_failover_to_next_broker' Connection failed"
	}

	if {![::s getIsConnected]} {
		error "In testcase 'Stomp_connect_should_failover_to_next_broker' Not Connected"
	}

	return 1	
} -result "1"

test Stomp_connect_should_fail_if_all_brokers_are_invalid {} -body {
	puts "## Stomp_connect_should_fail_if_all_brokers_are_invalid"

	# GIVEN:
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s "failover:(stomp:tcp://invalid:invalid@localhost:99999,stomp:tcp://invalid:invalid@localhost:99999)"
	set err ""

	# WHEN:
	set r [catch {::s connect {set ::result "CONNECTED"}} err]
	
	if {[string first "connection to '{localhost 99999 invalid invalid} {localhost 99999 invalid invalid}' not possible." $err]!=0} {
		error "expected error message not matched"
	}

	return $r

} -result "1"

test Stomp_Send {} -body {
	puts "## Stomp_Send"
	set queue [getNewQueue]
	# Connect
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result

	if {[::s send $queue "Stomp_Send"] != 1} {
		error "In testcase 'Stomp_Send' Send to queue failed"
	} else {
		set res 1
	}

	# disconnect
	if {[::s disconnect] != 1} {
		error "In testcase 'Stomp_send' Disconnect failed"
	}
	
	return $res
} -result "1"

test Stomp_Double_Header {} -body {
	puts "## Stomp_Double_Header_diffValue"
	set queue [getNewQueue]
	# Connect
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result

	if {[catch {[::s send -correlationId 1 -headers [list correlation-id 2] $queue "Stomp_Send"]}] != 1} {
		error "In testcase 'Stomp_Double_Header' different value error failed"
	} else {
		set res 1
	}
	
	# Disconnect
	if {[::s disconnect] != 1} {
		error "In testcase 'Stomp_Double_Header' Disconnect failed"
	}
	
	return $res
}	-result "1"

test Stomp_Double_Header {} -body {
	puts "## Stomp_Double_Header_sameValue"
	set queue [getNewQueue]
	# Connect
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL
	::s connect {set ::result CONNECTED}

	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result
	
	if {[::s send -correlationId 1 -headers [list correlation-id 1] $queue "Stomp_Send"] != 1} {
		error "In testcase 'Stomp_Double_Header' same value send failed"
	} else {
		set res 1
	}
	
	# Disconnect
	if {[::s disconnect] != 1} {
		error "In testcase 'Stomp_Double_Header' Disconnect failed"
	}
	
	return $res
}	-result "1"

test Stomp_subscribe {} -body {
	puts "## Stomp_subscribe"
	set queue_subscribe [getNewQueue]
	# Connect
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result

	# subscribe
	if {[::s subscribe $queue_subscribe {stompcallback $messageNvList}] != 1} {
		error "In testcase 'Stomp_subscribe' Subscribe to queue failed"
	}

	after 1000 [list ::s send $queue_subscribe "Stomp_subscribe\nIt worked!"]
	set afterId [after 5000 [list set ::messagebody __ERROR__]]
	vwait ::messagebody
	catch {after cancel $afterID}

	if {$::messagebody == "__ERROR__"} {
		error "In testcase 'Stomp_subscribe' getting a message failed"
	} elseif {$::messagebody != "Stomp_subscribe\nIt worked!"} {
		error "Message not equal to sent message. got='$::messagebody' want='Stomp_subscribe\nIt worked!'"
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
	::s send $queue_subscribe "Stomp_2sübscribe"
	after 5000 [list set ::messagebody ERROR]
	vwait ::messagebody

	if {[string match "Stomp_2sübscribe*" $::messagebody] != 1} {
		error "In testcase 'Stomp_subscribe' getting a message failed (connect after subscribe)"
	}

	return 1

} -result "1"

test Stomp_durably_subscribe {} -body {
	puts "## Stomp_durably_subscribe"
	set topic_subscribe [getTopic]
	# Connect
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL
	::s connect {set ::result CONNECTED} {client-id tStompTest}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result

	# subscribe
	if {[::s subscribe $topic_subscribe {stompcallback $messageNvList} {activemq.subscriptionName tStompTest}] != 1} {
		error "In testcase 'Stomp_durably_subscribe' Subscribe to topic failed"
	}

	after 1000 [list ::s send $topic_subscribe "Stomp_durably_subscribe\nIt worked!"]

	set afterId [after 5000 [list set ::messagebody __ERROR__]]
	vwait ::messagebody

	catch {after cancel $afterID}

	if {$::messagebody == "__ERROR__"} {
		error "In testcase 'Stomp_durably_subscribe' getting a message failed"
	} elseif {$::messagebody != "Stomp_durably_subscribe\nIt worked!"} {
		error "Message not equal to sent message. got='$::messagebody' want='Stomp_durably_subscribe\nIt worked!'"
	}

	# unsubscribe
	if {[::s unsubscribe $topic_subscribe {persistent true client-id tStompTest}] != 1} {
		error "In testcase 'Stomp_durably_subscribe' Unsubscribe failed"
	}

	# disconnect
	if {[::s disconnect] != 1} {
		error "In testcase 'Stomp_durably_subscribe' Disconnect faild"
	}
	
	return 1

} -result "1"

test Stomp_unsubscribe {} -body {
	puts "## Stomp_unsubscribe"
	set queue_unsubscribe [getNewQueue]
	catch {delete object ::s}
	catch {rename ::s ""}
	tStomp ::s $::serverURL

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
	catch {rename ::s ""}
	tStomp ::s $::serverURL

	# Connect
	::s connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result
	
	# subscribe
	::s subscribe $queue_handleLine {}

# list of line (from socket) and expected result
set message [list \
[list [list CONNECTED]								[list CONNECTED] {}] \
[list [list heart-beat:0,0]							[list CONNECTED] [list heart-beat 0,0]] \
[list [list session:ID:desw138x-38000-1339169069006-7494:231]			[list CONNECTED] [list session "ID:desw138x-38000-1339169069006-7494:231"]] \
[list [list server:ActiveMQ/5.6.0]						[list CONNECTED] [list server ActiveMQ/5.6.0]] \
[list [list version:1.1]							[list CONNECTED] [list version 1.1]] \
[list {}									[list CONNECTED] {}] \
[list [list "\0"]									[list CONNECTED] {}] \
[list [list MESSAGE]								[list MESSAGE] {}] \
[list [list message-id:ID\cdesw138x-38000-1339169069006-7494\c231\c-1\c1\c1]	[list MESSAGE] [list message-id "ID\cdesw138x-38000-1339169069006-7494\c231\c-1\c1\c1"]] \
[list [list destination:${queue_handleLine}]						[list MESSAGE] [list destination ${queue_handleLine}]] \
[list [list timestamp:1339425951090]						[list MESSAGE] [list timestamp 1339425951090]] \
[list [list expires:0]								[list MESSAGE] [list expires 0]] \
[list [list subscription:5C6E81DE507A8595EAE75291C6B187FD]			[list MESSAGE] [list subscription 5C6E81DE507A8595EAE75291C6B187FD]] \
[list [list persistent:true]							[list MESSAGE] [list persistent true]] \
[list [list priority:4]								[list MESSAGE] [list priority 4]] \
[list {}									[list MESSAGE] {}] \
[list "start line"					[list MESSAGE] {}] \
[list "last line\0"					[list MESSAGE] [list messagebody "start line\nlast line"]] \
[list [list MESSAGE]								[list MESSAGE] {}] \
[list [list message-id:ID\cdesw138x-38000-1339169069006-7494\c231\c-1\c1\c2]	[list MESSAGE] [list message-id "ID\cdesw138x-38000-1339169069006-7494\c231\c-1\c1\c2"]] \
[list [list destination:${queue_handleLine}]						[list MESSAGE] [list destination ${queue_handleLine}]] \
[list [list timestamp:1339426287323]						[list MESSAGE] [list timestamp 1339426287323]] \
[list [list expires:0]								[list MESSAGE] [list expires 0]] \
[list [list subscription:5C6E81DE507A8595EAE75291C6B187FD]			[list MESSAGE] [list subscription 5C6E81DE507A8595EAE75291C6B187FD]] \
[list [list persistent:true]							[list MESSAGE] [list persistent true]] \
[list [list priority:4]								[list MESSAGE] [list priority 4]] \
[list {}									[list MESSAGE] {}] \
[list "start line"					[list MESSAGE] {}] \
[list "last line\0"					[list MESSAGE] [list messagebody "start line\nlast line"]] \
]

	foreach test $message {
		set res [::s testHandleLine [lindex $test 0]]
		puts "============== $res"

		array set resArr [lindex $res 0]

		if {[lindex $test 1] != [lindex $res 1]} {
			error "readCommand is wrong ([lindex $test 1] == [lindex $res 1])"
		}

		set testVar [lindex $test 2]
		if {[string length $testVar]} {
			set varName [lindex $testVar 0]
			set varVal [lindex $testVar 1]

			if {[info exists resArr($varName)]} {
				if {$resArr($varName) != $varVal} {
					error "got='$resArr($varName)' != want='$varVal'"
				}
			} else {
				error "resArr($varName) not existing after handle line [lindex $test 0]"
			}
		}

		array unset resArr
		unset testVar
	}

	return 1

} -result "1"

test Stomp_parseStompUrl_Should_parse_failover_connect_string_correctly {} -body {
	
	set r [tStomp::parseStompUrl failover:(stomp:tcp://system:xxx@localhost:61613,stomp:tcp://system:xxx@centralHost:61613)]
	
	return $r
	
} -result "1 {{localhost 61613 system xxx} {centralHost 61613 system xxx}}"

test Stomp_parseStompUrl_Should_parse_connect_string_correctly {} -body {
	
	set r [tStomp::parseStompUrl stomp:tcp://system:xxx@localhost:61613]
	
	return $r
	
} -result "0 {{localhost 61613 system xxx}}"

test Stomp_parseStompUrl_Should_parse_failover_without_tcp_in_connect_string_correctly {} -body {
	
	set r [tStomp::parseStompUrl failover:(stomp://system:xxx@localhost:61613,stomp:tcp://system:xxx@centralHost:61613)]
	
	return $r
	
} -result "1 {{localhost 61613 system xxx} {centralHost 61613 system xxx}}"


array set testResult [array get ::tcltest::numTests]

cleanupTests

exit $testResult(Failed)
