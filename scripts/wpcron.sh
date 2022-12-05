#!/bin/bash
#
# run the wp cli cronjobs as the same php user
# */2 * * * * cd /home/scripts/wpcron.sh > /dev/null 2>&1
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

	# no splitting
	echo "Running WP-CLI as user ${SHUSER} and group ${SHGROUP} on ${D}"; 
	cd ${D} && /usr/bin/sudo -u ${SHUSER} -g ${SHGROUP} /usr/bin/wp cron event run --due-now > ${D}/wp-content/cron.log
	cd ${D} && /usr/bin/sudo -u ${SHUSER} -g ${SHGROUP} /usr/bin/wp action-scheduler run > ${D}/wp-content/cron-scheduler.log

done

