#!/bin/sh
#\
exec tclsh "$0" "$@"

# EchoTest.tcl
package require tStomp

# to switch of logging:
tStomp::setDebugCmd {puts "$msg"}

proc stompcallback {messageNameValueList} {
	
	#puts "------------------------------"
	#foreach {name value} $messageNameValueList {
	#	set ::$name $value
	#	puts "#-#-# $name '$value'"
	#
	#}
	#puts "------------------------------"	
		
	array set message $messageNameValueList
	
	::s send /queue/JMeterSubscriber $message(messagebody)	
}

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


::s connect {
	puts "connect successful"
	::s subscribe /queue/JMeterPublisher  {stompcallback $messageNvList}
}	
vwait forever
