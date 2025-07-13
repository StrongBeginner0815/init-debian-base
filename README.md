# init-debian-base
Script to run inside FAI-ISO - initializes the new Debian OS with elementary tools and runs "init.sh"-called Scripts on USB-Devices

# Status
PLEASE DONT USE THIS - IT IS UNDER HEAVY DEVELOPEMENT AND WILL POSSIBLY NOT WORK!

# Flow
1. download_init_script.sh - Downloads the Script "init_and_reboot.sh" and sets it as autostart for next boot
2. init_and_reboot.ah - Initializes the System (makes new sudo user, Rescricts root-user, installs packages, ...) and downloads the Script "USB-init.sh" and sets it as autostart for next boot and deletes itself out of the autostart
3. USB-init.sh - Runs Scripts on USB-Storages and deletes itself out of the autostart
4. USB-init-01-install-docker.sh - Installs Docker
