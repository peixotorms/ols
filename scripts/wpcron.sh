#!/bin/bash
#
# run the wp cli cronjobs as the same php user
# */2 * * * * /home/scripts/wpcron.sh > /dev/null 2>&1
#

# Backup Directories ########################
echo "Starting cron jobs..."

# get wp cli location
if [[ -f "/usr/local/bin/wp" ]]; then
         WPCLILOC="/usr/local/bin/wp"
elif [[ -f "/usr/bin/wp" ]]; then
         WPCLILOC="/usr/bin/wp"
else
         WPCLILOC=$(/usr/bin/which wp) # requires path on cronjobs, usually
fi

# get sudo location
SUDOLOC=$(/usr/bin/which sudo)

# find sites
for D in $(find /home/sites/*/www -name 'wp-config.php' -print0 | xargs -0 -n1 dirname); do

        # get user/group
        SHUSER=$(/usr/bin/stat -c "%U" ${D})
        SHGROUP=$(/usr/bin/stat -c "%G" ${D})

        # no splitting
        echo "Running WP-CLI as user ${SHUSER} and group ${SHGROUP} on ${D}";
        echo "Started cron on $(date)" >> ${D}/wp-content/cron.log
        cd ${D}; ${SUDOLOC} -u ${SHUSER} -g ${SHGROUP} ${WPCLILOC} cron event run --due-now --allow-root >> ${D}/wp-content/cron.log
        echo "Ended cron on $(date)" >> ${D}/wp-content/cron.log

        # limit
        echo "$(tail -3600 ${D}/wp-content/cron.log)" > ${D}/wp-content/cron.log

done
