#!/bin/bash

echo "Are you sure you want to delete these files? [y/N]: "
read -r response
case "$response" in
    [yY][eE][sS]|[yY])
        exec /bin/rm "$@"
        ;;
    *)
        echo "Aborting deletion."
        ;;
esac
