# init-debian-base
A few scripts for automated installing Debian and further things.

## download_init_script.sh
Script to run inside FAI.me-ISO - downloads the real init-script.

## init_and_reboot.sh
Initializes the new Debian OS with elementary tools, sets a new user, disables some root-abilities, sends the new credentials to a cred-server in the local network, gets the USB-init.sh-script and sets it to autostart and finally reboots.

## USB-init.sh
Runs "USB-init-*.sh"-called scripts on USB-Devices (or other block-devices with mountable partitions).

### USB-init-01-install-docker.sh
Installs docker and packs all users (but root) into the docker-group.


# Development Status
PLEASE DONT USE THIS - IT IS UNDER HEAVY DEVELOPEMENT AND WILL POSSIBLY NOT WORK OR MIGHT DESTROY YOUR SYSTEM!

# License
See file "LICENSE"
