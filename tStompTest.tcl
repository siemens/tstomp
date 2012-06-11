# Method called whenever input arrives on a connection.

package require tStomp
 
 
proc debug {s} {
	set logFileName /tmp/output.log
	set path [file dirname $logFileName]
	if ![file exists $path] {
		file mkdir $path
	}
	set fd [open $logFileName a+]
	puts $fd "[getNow]: $s";
	close $fd
}

proc getNow {} {
	timestamp s f
	return "[clock format $s -format "%Y-%m-%dT%H:%M:%S"].[format %.3d $f]"
}

proc timestamp {{tv_sec_p ""} {tv_msec_p ""}} {
 	if { $tv_sec_p != "" } {
		upvar $tv_sec_p secs
 	}
 	if { $tv_msec_p != "" } {
		upvar $tv_msec_p fract
	}
	set secs [clock seconds]
	set ms [clock clicks -milliseconds]
	set base [expr { $secs * 1000 }]
	set fract [expr { $ms - $base }]
	if { $fract >= 1000 } {
		set diff [expr { $fract / 1000 }]
		incr secs $diff
		incr fract [expr { -1000 * $diff }]
	}
	return $secs.[format %.3d $fract]
}
  
 
proc stompcallback {stompobject messageId destination timestamp expires priority} {
	#puts $stompobject
	puts "MessageID $messageId"
	puts "Destination $destination"
	puts "TimeStamp $timestamp"
	puts "Expires $expires"
	puts "Priority $priority"
	set ::result $destination
}
 
   
proc afterCheck {step wait} {
	puts $step
	switch $step { 
		1 {puts "amOne 1"
			catch {delete object ::s}
			Stomp ::s localhost 61613
			::s setDebug debug 
			::s connect {
			::s send /queue/queue1 test
			::s subscribe /queue/queue1 {stompcallback $this $messageId $destination $timestamp $expires $priority}	
			#::s disconnect
			}
		}
		2 {puts "amTwo 2"
			::s send /queue/queue1 hello2}
		3 {puts "amThree 3"
			if {$::result!="/queue/queue1"} {error "expecting queue1"}}
		
	}
	incr step
	if { $step < 3 } {
		after $wait "afterCheck $step $wait"
    	}
}

afterCheck 1 1000;

