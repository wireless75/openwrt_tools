#!/bin/sh
#
# wlink_heal.sh
#
# Purpose: heal WAN wifi link, switching between 2 or 3 configuration presets.
#
# Syntax:
# sheal [--checkfix|--check|--next|--default]
# --check: tests if connection is working
# --next: changes connection to the next one
# --checkfix: tests connection, and if not working, changes to the next.
# --default: set default configuration (wireless1)
#
# Steps:
#
# 1) Script installation
#	scp wlink_heal.sh root@myrouter:/etc
#
# 2) Prepare configuration files, e.g. 
#	cd /etc/config
#	mv wireless wireless1
#	cp wireless1 wireless2
#	cp wireless1 wireless3
#	(now, edit wireless2 and wireless3 for adding the two additional
#	 configuration files; note that you'll lose "wireless" file, don't
#	 worry, as wlink_heal.sh use symlinks to point wireless1/2/3)
#
# 3) Enable cron (if not already enabled):
#	mkdir -p /var/spool/cron
#	/etc/init.d/cron start
#	/etc/init.d/cron enable
#
# 4) Add jobs
#	crontab -e
#	After "crontab -e", add following two lines to the file (without the # nor tab):
#	*/5 * * * * /etc/wlink_heal.sh --checkfix
#	0 7 * * * /etc/wlink_heal.sh --default
#	(check -and fix- connection every 5 minutes, and switch to default connection
#	 everyday at 7:00am)
#
# 5) Reboot
#	Just in case the router don't start cron properly
#
# Observations:
#
# - You can call also use the script from the command line or from other scripts, e.g.:
#	/etc/wlink_heal.sh --check
#	/etc/wlink_heal.sh --next
#	/etc/wlink_heal.sh --default
#	/etc/wlink_heal.sh --checkfix
#
# Reference:
# - http://wiki.openwrt.org/doc/howto/notuci.config
#
# OpenWRT ships with sh (Bourne Shell) and not bash, so no bash goodies are used.
#
# 20150105: cleanup
#

# Constants:
WCFG_PATH=/etc/config
COUNTER=/tmp/sheal.cnt
COUNTER_AUX=/tmp/sheal.cnt.aux
COUNTER_MAX=10
CONF=$WCFG_PATH/wireless CONF1=wireless1 CONF2=wireless2 CONF3=wireless3
LAST_OP_LOG=/tmp/sheal.txt
CHECK=0
CHG_NEXT=0

# Functions:

return_ok() {
	echo -n 0 >$COUNTER
	exit 0
}

reload_wifi() {
	echo "Wifi setup for $CONF ($(grep -i option.ssid $CONF | head -1 | awk -F \' '{print $2}'))..."
	wifi
	echo "Wifi setup done."
}

set_wifi_conf() {
	if [ -f $WCFG_PATH/$1 ] ; then ln -s $1 $CONF ; reload_wifi ; return_ok ; fi
}

check_ping() {
	if ping -c 1 -w 10 $1 ; then echo "$(date): ping $1 ok" >>$LAST_OP_LOG ; return_ok ; else echo "$(date): ping $1 error" >>$LAST_OP_LOG ; fi
	echo "ping $1"
}

reset_counter() {
	echo -n 0 >$COUNTER
}

reboot_device() {
	echo REBOOTING...
	reset_counter
	reboot
}

echo -n >$LAST_OP_LOG

CURRENT=$(ls -lrta $WCFG_PATH | grep lrwxrwxrwx | awk -F " -> " '{print $2}' | tr '\n' ' ' | awk '{print $1}')

# COMMAND: set default configuration
if [ x"$1" = x"--default" ] ; then
	if [ x"$CURRENT" = x"$CONF1" ] ; then
		echo "Already set to $CONF1"
		exit 0
	fi
	if [ -f $WCFG_PATH/$CONF1 ] ; then
		rm -f $CONF
		ln -s $CONF1 $CONF
		echo "Default configuration set."
		exit 0
	fi
	echo "Error: can not set default configuration. Missing file: $WCFG_PATH/$CONF1"
	exit 1
fi

if [ x"$1" = x"--check" ] ; then CHECK=1 ; fi              
if [ x"$1" = x"--next" ] ; then CHG_NEXT=1 ; fi            
if [ x"$1" = x"--checkfix" ] ; then CHECK=1 CHG_NEXT=1 ; fi

# COMMAND: --check or first part of --checkfix
if [ x"$CHECK" = x"1" ] ; then
	for i in eff.org gnu.org kernel.org slashdot.org ; do check_ping $i ; done
	echo "Error: ping error. Conection not available."
	if [ x"$CHG_NEXT" = x"0" ] ; then
		exit 1
	fi
fi

# COMMAND: --next or second part of --checkfix
if [ x"$CHG_NEXT" = x"1" ] ; then
	# Init counter, if missing:
	if [ ! -f $COUNTER ] ; then reset_counter ; fi

	# check case of no configuration set:
	if [ ! -f $CONF ] ; then
		for i in $CONF1 $CONF2 $CONF3 ; do set_wifi_conf $i ; done
		echo "Missing configuration"
		exit 1
	fi

	# Change connection:
	NEXT=
	echo "conf: $CONF , current: $CURRENT, cf1: $CONF1, cf2: $CONF2, cf3: $CONF3"
	# Case of two:
	#if [ x"$CURRENT" = x"$CONF1" ] ; then NEXT=$CONF2 ; fi
	#if [ x"$CURRENT" = x"$CONF2" ] ; then NEXT=$CONF1 ; fi
	# Case of three:
	if [ x"$CURRENT" = x"$CONF1" ] ; then NEXT=$CONF2 ; fi
	if [ x"$CURRENT" = x"$CONF2" ] ; then NEXT=$CONF3 ; fi
	if [ x"$CURRENT" = x"$CONF3" ] ; then NEXT=$CONF1 ; fi
	if [ x"$NEXT" = x"" ] ; then exit 1 ; fi
	rm -f $CONF
	ln -s $NEXT $CONF

	# Increment error counter:
	echo -n $(expr $(cat $COUNTER) + 1)>$COUNTER_AUX
	mv -f $COUNTER_AUX $COUNTER

	# If error count reaches max errors: reboot
	if [ $(cat $COUNTER) -gt $COUNTER_MAX ] ; then reboot_device ; fi

	# Set wifi configuration:
	reload_wifi
	exit $?
fi

echo 'Error: unknown command'
echo 'Syntax: sheal [--checkfix|--check|--next|--default]'

