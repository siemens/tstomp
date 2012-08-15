#!/bin/sh
#\
exec tclsh "$0" "$@"

# EchoTest.tcl
package require tStomp

set i 1

proc stompcallback {stompobject messageId destination timestamp expires priority messagebody} {
	# puts "MessageID $messageId"
	# puts "Destination $destination"
	# puts "TimeStamp $timestamp"
	# puts "Expires $expires"
	# puts "Priority $priority"
	# puts "Message $messagebody"
		
	puts "$::i $messageId $messagebody"
	set message "$::i stompcallbackmessage"
	::s send /queue/StompSubscriber $message
	incr ::i
	#::s subscribe /topic/StompPub {stompcallback $this $messageId $destination $timestamp $expires $priority $messagebody}	
	
}

tStomp ::s localhost 61613
::s connect {
	puts "connect successful"
	::s subscribe /queue/JMeterPublisher  {stompcallback $this $messageId $destination $timestamp $expires $priority $messagebody}
}	
vwait forever
