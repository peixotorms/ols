#!/bin/bash
#
# run the wp cli cronjobs as the same php user
# */2 * * * * /home/scripts/wpcron.sh > /dev/null 2>&1
#

# Backup Directories ########################
echo "Starting cron jobs..."

# go to the sites directory
cd /home/sites

# find sites
for D in $(find /home/sites/*/ -mindepth 1 -maxdepth 1 -type d -name www); do

	# get user/group
	SHUSER=$(stat -c "%U" ${D})
	SHGROUP=$(stat -c "%G" ${D})
	WPCLILOC=$(which wp)
	SUDOLOC=$(which sudo)
	

	# no splitting
	echo "Running WP-CLI as user ${SHUSER} and group ${SHGROUP} on ${D}"; 
	cd ${D} && ${SUDOLOC} -u ${SHUSER} -g ${SHGROUP} ${WPCLILOC} cron event run --due-now > ${D}/wp-content/cron.log

done

