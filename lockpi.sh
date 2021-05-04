#!/bin/sh

# modified shell to avoid bugs for now
# return to sh once posix compliant
##!/bin/bash

# Lockpi Installer:
# Headlessly install linux distributions through a x86 computer onto
# an SD card used to boot raspberry pis.

# NOTES:
# PLEASE BACK UP YOUR DATA WHEN USING THIS SCRIPT!
# The authors and contributors of this program will not be liable for 
# any damage incurred while using this script should you chose to use it.

# TODO
# FUCKING POSIX COMPLIANCE
#	check for /run/shm
#	blkid and lsblk for get_uuid()
# Support PC distros:
#	Debian
#		WHERE THE FUCK IS ADIANTUM?!
#		CHROOT shenanigans
#	Arch
#		qemu-arm-static shenanigans
# backup configs
#	actual script
#	chroot script
# detect_version(); # detect distro version
# parse_img(); # intelligent decompression
# Other distro support:
#	install_configure_setup(); # debian, kali, arch specific scripts
# Tweaks:
#	headless setup:
#		disable tty1 and disable-bt for console
#		luks-dropbear and systemd ssh.service
#	selectable discard
#	tmpfs for caches
#	NUKE rpi MS repo (only for raspios)
#	include initramfs_config.txt for raspios, different initramfs for different kernels
# nuke resize.sh on initial install
#	kali (systemd)
#	debian (systemd?)

# Arch comptiability
#	fix install_arch() no crypt_pi error after unlock
# command line args instead of prompt



# TODO TESTS:


# HELPER FUNCTIONS
checkroot(){
	if [ "$(id -u)" -ne 0 ]; then 
		echo "Please run as root";
		exit 1;
	fi
}

# POSIX compliant read -p "" $VAR
# prototype:
#	read_p "PROMPT" VARIABLE NAME
read_p(){
	printf "%s" "$1";
	read $2;
}


# VARS
IMAGE=???;
#echo "";

# check for prereqs
prereq(){
	#local prereqs=( "lsblk" "blkid" "sed" "mount" "umount" "mke2fs" "mkfs.fat" "cryptsetup" "qemu-arm-static" );
	# note:
	# leaving out bsdtar as arch is not supported rn
	
	# simple check for now bc we're pushing the code out fast
	#if [ ! -e /usr/bin/qemu-arm-static ]; then {
	#	echo "qemu-arm-static not found. please install it!";
	#	exit 1;
	#}
	#fi;
	
	#for i in "${prereqs[@]}"; do {
	#	echo "$i";
	#} 
	#done;
	
	# check if relevant programs exist
	local prereqs="lsblk blkid sed mount umount mke2fs mkfs.fat cryptsetup qemu-arm-static rsync kmod diceware blkdiscard";
	#local prereqLength=$(echo "${prereqs}"|wc -w);
	local prereqLength=$(printf "%s" "${prereqs}"|wc -w);
	local currentItem="";
	#for i in $(seq 1 ${prereqLength}) ; do {
	#	currentItem="$(echo ${prereqs}| cut -f $i -d' ')";
	#	which "${currentItem}" 1>/dev/null || { printf "\nPrerequesites not met!\nYou don't have ${currentItem}.\nPlease check you have the following:\n${prereqs}\n\n"; exit 1; };
	#}
	#done;
	for currentItem in ${prereqs}; do {
		#which "${currentItem}" 1>/dev/null || { printf "\nPrerequesites not met!\nYou don't have ${currentItem}.\nPlease check you have the following:\n${prereqs}\n\n"; exit 1; };
		which "${currentItem}" 1>/dev/null || { printf "\nPrerequesites not met\!\nYou don't have %s.\nPlease check you have the following:\n%s\n\n" "${currentItem}" "${prereqs}"; exit 1; };

	}
	done
	
	# check if kernel supports adiantum cipher
	# Note:
	#	WHY THE FUCK DOES DEBIAN NOT SUPPORT ADIANTUM?!
	#cat /proc/crypto | egrep -Eq 'name[ \t]*:[ \t]*adiantum(xchacha12,aes)';
	kmod list|cut -f1 -d' '|grep -iq adiantum;
	if [ $? -eq 1 ]; then {
		echo "Your kernel doesn't support the Adiantum Cipher right now.";
		echo "Please either: "
		echo "1: Load the kernel module 'adiantum' using modprobe";
		echo "OR";
		echo "2: Install a kernel that supports adiantum (likely at least version 5.x).";
		exit 1;
	}
	fi;
}

# guided prompts
IMAGE_IMG="";
TARGET_BLOCK_DEVICE="";
LUKS_PASSPHRASE="";
prompts(){
	# reminder to unfreeze
	echo "If you accidentally pressed ctrl+S, press ctrl+Q to unfreeze.";
	echo "";
	
	# used for parsing, TODO
	#read -e -p "Path to installation image: " IMAGE;
	while [ "${IMAGE_IMG}" = "" ]; do {
		read_p "Path to decompressed installation image (.img): " IMAGE_IMG;
	}
	done;
	
	echo "LIST OF BLOCK DEVICES:";
	lsblk -i -o 'NAME,LABEL,MODEL,SIZE,TYPE';
	while [ "${TARGET_BLOCK_DEVICE}" = "" ]; do {
		read_p "Enter full block device path to install (/dev/???): " TARGET_BLOCK_DEVICE;
	}
	done;
	
	# passphrase entry and confirmation loop
	#LUKS_PASSPHRASE="";
	#local LUKS_PASSPHRASE_BUFFER="";
	#stty -echo;
	#while [ -z "${LUKS_PASSPHRASE}" -o "${LUKS_PASSPHRASE}" != "${LUKS_PASSPHRASE_BUFFER}" ]; do {
	#	printf "Enter LUKS passphrase: " 
	#	read LUKS_PASSPHRASE_BUFFER;
	#	printf "\n";
	#	
	#	printf "Confirm LUKS passphrase: " 
	#	read LUKS_PASSPHRASE;
	#	printf "\n";
	#}
	#done;
	#stty echo;
	
	# Configure a firstboot LUKS keyslot with 10 word diceword passphrase (128 bit entropy)
	LUKS_PASSPHRASE="$(diceware -w en_eff -d' ' -n 10 --no-caps)";
	
	# confirmation
	printf "\nInstallation target: %s\n" "${TARGET_BLOCK_DEVICE}";
	printf "Installation image: %s\n" "${IMAGE_IMG}";
	echo "WARNING: ALL DATA WILL BE LOST ON TARGET.";
	#confirmation "Type UPPER CASE YES to proceed: " "YES";
	#if [ $? -eq "1" ]; then {
	#	exit 1;
	#}
	#fi;
	if ! confirmation "Type UPPER CASE YES to proceed: " "YES"; then exit 1; fi;
}

# prototype:
# confirmation "PROMPT" "EXPECTED_RESPONSE";
confirmation(){
	local INPUT;
	printf "%s" "$1";
	#read INPUT;
	#printf %s "$INPUT" | grep -Fq "$2";
	#return $?;
	
	read INPUT && printf "%s\\n" "$INPUT" | grep -Fiq $2;
}

# prototype:
# detect_version "/PATH/TO/IMAGE";
isDebian="0";
isArch="0";
detect_version(){
	# only support raspios/raspbian for now
	return 0;
}

# partitioning
USE_LUKS=1;
LUKS_MAPPER="crypt_pi";
format(){
	# detect if device is SD/MMC
	if [ -z "$(printf ${TARGET_BLOCK_DEVICE} |grep mmcblk)" ]; then {
		BOOTPART="${TARGET_BLOCK_DEVICE}1";
		ROOTPART="${TARGET_BLOCK_DEVICE}2";
	} ;
	else {
		blkdiscard -f "${TARGET_BLOCK_DEVICE}";
		BOOTPART="${TARGET_BLOCK_DEVICE}p1";
		ROOTPART="${TARGET_BLOCK_DEVICE}p2";
	} 
	fi;
	
	# create partitions
	#echo -e "o\np\nn\np\n1\n\n+200M\nt\nc\nn\np\n2\n\n\nw\n" | fdisk "${TARGET_BLOCK_DEVICE}";
	printf "o\np\nn\np\n1\n\n+200M\nt\nc\nn\np\n2\n\n\nw\n\n" | fdisk "${TARGET_BLOCK_DEVICE}";

	mkfs.vfat "${BOOTPART}";
	#if [ -z $(echo ${USE_LUKS}|grep 1) ]; then {
	#	mkfs.ext4 "${ROOTPART}";
	#} ;
	if [ "${USE_LUKS}" != 1 ]; then {
		mkfs.ext4 "${ROOTPART}";
	} ;
	else {
		#LUKS_MAPPER="$(echo ${ROOTPART}|sed -E -e 's/[/]dev[/]*//g' -e 's/(^.)/luks_\1/')";

		#cryptsetup -y -v luksFormat --type=luks2 --sector-size=4096 -c xchacha12,aes-adiantum-plain64 -s 256 -h sha512 "${ROOTPART}";
		#echo ${LUKS_PASSPHRASE} | cryptsetup luksFormat --force-password --type=luks2 --sector-size=4096 -c xchacha12,aes-adiantum-plain64 -s 256 -h sha512 "${ROOTPART}";
		#echo ${LUKS_PASSPHRASE} | cryptsetup luksFormat --force-password --type=luks2 --sector-size=4096 -c xchacha12,aes-adiantum-plain64 -s 256 -h sha512 --pbkdf argon2i --pbkdf-memory 100000 --pbkdf-parallel 1 --pbkdf-force-iterations 4 "${ROOTPART}";
		
		# we are formatting to the lowest denominator: pi0
		# 128 bit entropy passphrase *should* mitigate issues.
		# (in quotes bc cryptography is not the author's forte.)
		# argon2i params:
		#	timecost = 4; most common settings from benchmarks across x86 and pi
		#	memory = 200MB; pi0/w only has 256MB and we have initrd
		#	parallel = 1; pi0/w only has 1 core. more than 1 will FAIL to unlock.
		#echo ${LUKS_PASSPHRASE} | cryptsetup luksFormat --force-password --type=luks2 --sector-size=4096 -c xchacha12,aes-adiantum-plain64 -s 256 -h sha512 --pbkdf argon2i --pbkdf-memory 200000 --pbkdf-parallel 1 --pbkdf-force-iterations 4 "${ROOTPART}";
		printf "%s\n" "${LUKS_PASSPHRASE}"| cryptsetup luksFormat --force-password --type=luks2 --sector-size=4096 -c xchacha12,aes-adiantum-plain64 -s 256 -h sha512 --pbkdf argon2i --pbkdf-memory 200000 --pbkdf-parallel 1 --pbkdf-force-iterations 4 "${ROOTPART}";
		
		#cryptsetup open "${ROOTPART}" "${LUKS_MAPPER}";
		#echo ${LUKS_PASSPHRASE} | cryptsetup open "${ROOTPART}" "${LUKS_MAPPER}";
		printf "%s\n" "${LUKS_PASSPHRASE}"| cryptsetup open "${ROOTPART}" "${LUKS_MAPPER}";
		mkfs.ext4 "/dev/mapper/${LUKS_MAPPER}";
	}
	fi;
}

mount_disk(){
	MOUNTDIR="$(mktemp -d)";
	mkdir "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT";
	chmod og-rwx "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT";
	mount "${BOOTPART}" "${MOUNTDIR}/BOOT";
	#if [ -z $(echo ${USE_LUKS}|grep 1) ]; then {
	#	mount "${ROOTPART}" "${MOUNTDIR}/ROOT";
	#} ;
	if [ "${USE_LUKS}" != 1 ]; then {
		mount "${ROOTPART}" "${MOUNTDIR}/ROOT";
	} ;
	else {
		mount "/dev/mapper/${LUKS_MAPPER}" "${MOUNTDIR}/ROOT";
	}
	fi;
}

# arm chroot prep and cleanup
armchroot_prep(){
	mount --bind /dev/ "${MOUNTDIR}/ROOT/dev";
	mount --bind /dev/pts "${MOUNTDIR}/ROOT/dev/pts";
	mount --bind /dev/shm "${MOUNTDIR}/ROOT/dev/shm";
	mount -t sysfs sysfs "${MOUNTDIR}/ROOT/sys";
	mount -t proc proc "${MOUNTDIR}/ROOT/proc";
	#if [ -z "$(echo $isDebian|grep 1)" ]; then {
	#	mount --bind "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT/boot";
	#} ;
	if [ "${isDebian}" != 1 ]; then {
		mount --bind "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT/boot";
	} ;
	else {
		mount --bind "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT/boot/firmware";
	}
	fi;
	mv "${MOUNTDIR}/ROOT/etc/resolv.conf" "${MOUNTDIR}/ROOT/etc/resolv.conf_bak";
	cp -L /etc/resolv.conf "${MOUNTDIR}/ROOT/etc/resolv.conf";
	cp "$(which qemu-arm-static)" "${MOUNTDIR}/ROOT/usr/bin";
}
armchroot_cleanup(){
	umount "${MOUNTDIR}/ROOT/dev/pts";
	umount "${MOUNTDIR}/ROOT/dev/shm";
	umount "${MOUNTDIR}/ROOT/dev";
	umount "${MOUNTDIR}/ROOT/sys";
	umount "${MOUNTDIR}/ROOT/proc";
	#if [ -z "$(echo $isDebian|grep 1)" ]; then {
	#	umount "${MOUNTDIR}/ROOT/boot";
	#} ;
	if [ "${isDebian}" != 1 ]; then {
		umount "${MOUNTDIR}/ROOT/boot";
	} ;
	else {
		umount "${MOUNTDIR}/ROOT/boot/firmware";
	}
	fi;
	rm "${MOUNTDIR}/ROOT/etc/resolv.conf";
	mv "${MOUNTDIR}/ROOT/etc/resolv.conf_bak" "${MOUNTDIR}/ROOT/etc/resolv.conf";
	rm "${MOUNTDIR}/ROOT/usr/bin/qemu-arm-static";
}
armchroot(){
	#echo "Dropping into a shell on installation target.";
	#echo 'Type "exit" to end customization in chroot shell: ';
	printf 'Dropping into a shell on installation target.\n';
	printf 'Type "exit" to end customization in chroot shell: \n';
	LANG=C chroot "${MOUNTDIR}/ROOT" ; #qemu-arm-static /bin/bash;
}

# installation
IMAGE_ARCH="";
# this is legacy code. borked.
install_arch(){
	bsdtar -xzpf "${IMAGE_ARCH}" -C "${MOUNTDIR}/ROOT";
	mv ${MOUNTDIR}/ROOT/boot/* "${MOUNTDIR}/BOOT";
	#umount "${MOUNTDIR}/BOOT";
	#mount "${BOOTPART}" "${MOUNTDIR}/ROOT/boot/";
}

# parse and decompress selected image
parse_img(){
	return 0;
}

# copy distro disk image files
install_img(){
	# mount .img file as loop device
	LOOPDEV="$(losetup -v -P --show -f ${IMAGE_IMG})";
	mkdir "${MOUNTDIR}/ROOT_IMG" "${MOUNTDIR}/BOOT_IMG";
	mount "${LOOPDEV}p1" "${MOUNTDIR}/BOOT_IMG";
	mount "${LOOPDEV}p2" "${MOUNTDIR}/ROOT_IMG";
	
	# copy distro to target disk
	rsync -ahHAXxq "${MOUNTDIR}/ROOT_IMG/" "${MOUNTDIR}/ROOT/";
	rsync -ahq "${MOUNTDIR}/BOOT_IMG/" "${MOUNTDIR}/BOOT/";
	
	# cleanup
	umount "${LOOPDEV}p1";
	umount "${LOOPDEV}p2";
	losetup -d ${LOOPDEV};
}

# setup common cmdline, fstab and crypttab 
install_configure_disks(){
	# backup original configs
	cp -a "${MOUNTDIR}/BOOT/cmdline.txt" "${MOUNTDIR}/BOOT/cmdline.txt_bak";
	cp -a "${MOUNTDIR}/ROOT/etc/fstab" "${MOUNTDIR}/ROOT/etc/fstab_bak";
	cp -a "${MOUNTDIR}/ROOT/etc/crypttab" "${MOUNTDIR}/ROOT/etc/crypttab_bak";
	
	# cmdline
	sed -E -e "s/root=[!-Z]+ /root=\/dev\/mapper\/${LUKS_MAPPER} cryptdevice=PARTUUID=${UUID_ROOTPART}:crypt /" -i "${MOUNTDIR}/BOOT/cmdline.txt";
	# fstab
	sed -E -e "s/.*([ \t]+\/[ \t]+.*)/UUID=${UUID_LUKS_MAP}\1/" -i "${MOUNTDIR}/ROOT/etc/fstab";
	sed -E -e "s/.*([ \t]+\/boot[/]*.*[ \t]+.*)/PARTUUID=${UUID_BOOTPART}\1/" -i "${MOUNTDIR}/ROOT/etc/fstab";
	# crypttab
	#echo -e "${LUKS_MAPPER}\tPARTUUID=${UUID_ROOTPART}\tnone\tluks" |tee "${MOUNTDIR}/ROOT/etc/crypttab";
	printf "%s\tPARTUUID=%s\tnone\tluks\n" "${LUKS_MAPPER}" "${UUID_ROOTPART}" |tee "${MOUNTDIR}/ROOT/etc/crypttab";
}

get_uuids(){
	UUID_LUKS_MAP="$(blkid|grep ${LUKS_MAPPER}|sed -E -e 's/.*UUID="([0-9a-zA-Z-]+)".*/\1/')";
	UUID_BOOTPART="$(blkid|grep ${BOOTPART}|sed -E -e 's/.*PARTUUID="([0-9a-zA-Z-]+)".*/\1/')";
	UUID_ROOTPART="$(blkid|grep ${ROOTPART}|sed -E -e 's/.*PARTUUID="([0-9a-zA-Z-]+)".*/\1/')";
}



# cleanup
cleanup(){
	umount "${MOUNTDIR}/BOOT/";
	umount "${MOUNTDIR}/ROOT/";
	cryptsetup close "${LUKS_MAPPER}";
	rmdir "${MOUNTDIR}/ROOT" "${MOUNTDIR}/BOOT";
	rm "${CHROOT_SCRIPT_LOCATION}";
}

cleanup_interrupt(){
	printf "\nInterrupted. Cleaning up...\n";
	printf "Installation NOT complete.\n";
	if [ "${MOUNTDIR}" = "" ]; then {
		cryptsetup close "${LUKS_MAPPER}";
		exit 1;
	}
	fi;
	
	armchroot_cleanup;
	cleanup;
	exit 1;
}

configure_traps(){
	# trap signals so user cannot accidentally exit
	trap 'cleanup_interrupt' 1;	# SIGHUP
	trap 'cleanup_interrupt' 2;	# SIGINT, ctrl + c
	trap 'cleanup_interrupt' 3;	# SIGQUIT, ctrl + \
	trap 'cleanup_interrupt' 15;	# SIGTERM
}



# distro specific scripts
CHROOT_SCRIPT_RASPIOS='#!/bin/sh

# return to sh once POSIX compliant
##!/bin/bash

# TODO:
# Auto setup initramfs images and different versions using initramfs_config.txt

# install cryptsetup and initramfs tools for encrypted root
apt-get update; apt-get install cryptsetup busybox rsync initramfs-tools -y;
sed -E -e "s/^#CRYPTSETUP=/CRYPTSETUP=y/" -i /etc/cryptsetup-initramfs/conf-hook;


# ---- Auto setup initramfs, not implemented yet
# configure config.txt to use different initramfs images for each pi version
#echo "# configuration for initrd, edit if using 64bit kernel." |tee -a /boot/config.txt;
#echo "include initramfs_config.txt" |tee -a /boot/config.txt;

# generate initramfs images
#for VERSION in $(ls /lib/modules/); do
#	mkinitramfs -o /boot/initramfs-"${VERSION}".gz "${VERSION}";
#done
# ----

# ask user for kernel version:
VERSION="";
echo "The following kernel versions are available: ";
ls /lib/modules/;
#read -p "Select kernel version for initrd: " VERSION;
printf "Select kernel version for initrd: ";
read VERSION;

# generate and use initramfs
#echo "" |tee -a /boot/config.txt;
#echo "# use initrd to unlock encrypted root" |tee -a /boot/config.txt;
#echo "initramfs initramfs.gz followkernel" |tee -a /boot/config.txt;
echo "" |tee -a /boot/config.txt;
echo "# use initrd to unlock encrypted root" |tee -a /boot/config.txt;
echo "initramfs initramfs.gz followkernel" |tee -a /boot/config.txt;
mkinitramfs -o /boot/initramfs.gz "${VERSION}";

# disable initial resize
sed -E -e "s/ [!-z]*init_resize.sh//" -i /boot/cmdline.txt;
rm /etc/init.d/resize*fs_once /etc/rc3.d/S01resize*fs_once;
'

CHROOT_SCRIPT_ARCH='#!/bin/sh
# initialize pacman and install cryptsetup
#pacman-key --init;
#pacman-key --populate archlinuxarm;
#pacman -Suy --noconfirm;
#pacman -S --noconfirm cryptsetup;

# setup cryptsetup and initrd
cp -a /etc/mkinitcpio.conf /etc/mkinitcpio.conf_bak;
sed -E -e "s/^HOOKS=[(](.*)[)]/HOOKS=(\1 encrypt)/" -i /etc/mkinitcpio.conf;
INITRD_KERNEL=$(ls /lib/modules|sed -E -e "/extramodule/d");
rm /boot/initramfs-linux.img;
mkinitcpio -k "${INITRD_KERNEL}" -g /boot/initramfs-linux.img;
pkill -i gpg;
'


# used with version detection. 
# Only raspios supported for now
CHROOT_SCRIPT_LOCATION="/dev/shm/distro_install.sh";
install_configure_setup(){
	#echo "${CHROOT_SCRIPT_RASPIOS}" > "${CHROOT_SCRIPT_LOCATION}";
	printf "%s" "${CHROOT_SCRIPT_RASPIOS}" > "${CHROOT_SCRIPT_LOCATION}";
	chmod +x "${CHROOT_SCRIPT_LOCATION}";
}

# run distro specific chroot setup
armchroot_run_setup(){
	# modified, return to sh once POSIX compliant
	#LANG=C chroot "${MOUNTDIR}/ROOT" qemu-arm-static /bin/sh -c ${CHROOT_SCRIPT_LOCATION};
	LANG=C chroot "${MOUNTDIR}/ROOT" qemu-arm-static /bin/bash -c "${CHROOT_SCRIPT_LOCATION}";
}



# Add hardware capability specific LUKS keyslot.
LUKS_FIRSTBOOT_SCRIPT='#!/bin/sh
# trap signals so user cannot accidentally exit
stty -ctlecho
trap "" 1;	# SIGHUP
trap "" 2;	# SIGINT, ctrl + c
trap "" 3;	# SIGQUIT, ctrl + \
trap "" 15;	# SIGTERM
trap "" 20;	# SIGTSTP, ctrl + Z

# force user into setting up new LUKS keyslot on the hardware
CRYPT_PARTITION=REPLACEMENT_CRYPTPART;


# setup
mount -a;
echo "If you accidentally pressed ctrl+S, press ctrl+Q to unfreeze.";
echo "";

# get correct firstboot pw to add keyslot later
PW_FIRSTBOOT="";
isIncorrect=1;
stty -echo;
while [ "${isIncorrect}" != "0" ]; do {
	printf "Enter firstboot password again: ";
	read PW_FIRSTBOOT;
	printf "\n";
	#echo "${PW_FIRSTBOOT}" | cryptsetup open --test-passphrase "${CRYPT_PARTITION}";
	printf "%s\n" "${PW_FIRSTBOOT}"| cryptsetup open --test-passphrase "${CRYPT_PARTITION}";
	isIncorrect=$?;
	
	if [ "${isIncorrect}" != "0" ]; then {
		echo "Firstboot password incorrect.";
	}
	fi;
	
	# debug
	#echo ${isIncorrect};
	#echo ${PW_FIRSTBOOT};
}
done;
stty echo;


# get new LUKS pw
echo "";
echo "Setting up your new LUKS password.";
echo "Suggestion: use a diceware passphrase with at least 6 words with EFF dictionary.";
PW_LUKS="";
PW_LUKS_BUFFER="";
stty -echo;
while [ "${PW_LUKS}" != "${PW_LUKS_BUFFER}" -o "${PW_LUKS}" = "" ]; do {
	printf "Enter new LUKS passphrase: ";
	read PW_LUKS_BUFFER;
	printf "\n";
	
	printf "Confirm new LUKS passphrase: ";
	read PW_LUKS;
	printf "\n";
}
done;
stty echo;

# debug
#echo "${PW_LUKS_BUFFER}";
#echo "${PW_LUKS}";


# debug
#echo ${PW_FIRSTBOOT} | cryptsetup luksFormat --force-password --type=luks2 --sector-size=4096 -c xchacha12,aes-adiantum-plain64 -s 256 -h sha512 --pbkdf argon2i --pbkdf-memory 200000 --pbkdf-parallel 1 --pbkdf-force-iterations 4 "${CRYPT_PARTITION}";


# add new LUKS keyslot on encrypted partition using entered password and kill firstboot keyslot
printf "%s\n%s\n" "${PW_FIRSTBOOT}" "${PW_LUKS}"| cryptsetup luksAddKey --force-password --type=luks2 -h sha512 --pbkdf argon2i "${CRYPT_PARTITION}";
cryptsetup -q luksKillSlot "${CRYPT_PARTITION}" 0;

# remove script startup from cmdline. oneshot functionality
sed -E -e "s/[ \t]+init=\/usr\/sbin\/luks_firstboot.sh//g" -i /boot/cmdline.txt;

echo "";
echo "FIRST BOOT PASSWORD WILL BE INVALID AFTER REBOOT!";
echo "USE THE NEW CONFIGURED PASSWORD TO UNLOCK YOUR PI!";
echo "IF YOU LOSE YOUR NEW PASSWORD, THERE IS NO RECOVERY!";
echo "Press enter to reboot.";
read temp;

# debug
#stty echo;
#exit 0;

reboot -f;
'

install_newLUKS(){
	#echo "${LUKS_FIRSTBOOT_SCRIPT}" > "${MOUNTDIR}/ROOT/usr/sbin/luks_firstboot.sh";
	printf "%s" "${LUKS_FIRSTBOOT_SCRIPT}" > "${MOUNTDIR}/ROOT/usr/sbin/luks_firstboot.sh";
	chown root:root "${MOUNTDIR}/ROOT/usr/sbin/luks_firstboot.sh";
	chmod 774 "${MOUNTDIR}/ROOT/usr/sbin/luks_firstboot.sh";
	sed -E -e 's/(.$)/\1 init=\/usr\/sbin\/luks_firstboot.sh/' -i "${MOUNTDIR}/BOOT/cmdline.txt";
	sed -E -e "s/REPLACEMENT_CRYPTPART/\/dev\/disk\/by-partuuid\/${UUID_ROOTPART}/" -i "${MOUNTDIR}/ROOT/usr/sbin/luks_firstboot.sh";
}


# custom function to run tests etc
test_func(){
	printf "%s" "${LUKS_FIRSTBOOT_SCRIPT}" > /tmp/wtf.sh
	
	local prereqs="lsblk blkid sed mount umount mke2fs mkfs.fat cryptsetup qemu-arm-static rsync kmod diceware blkdiscard";
	local prereqLength=$(printf %s "${prereqs}"|wc -w);
	echo $prereqLength;
	
	printf "%s" "${CHROOT_SCRIPT_RASPIOS}" > /tmp/chroot_test.sh
	
	local TARGET_BLOCK_DEVICE=/dev/mmcblk1
	# detect if device is SD/MMC
	if [ -z "$(printf ${TARGET_BLOCK_DEVICE} |grep mmcblk)" ]; then {
		BOOTPART="${TARGET_BLOCK_DEVICE}1";
		ROOTPART="${TARGET_BLOCK_DEVICE}2";
	} ;
	else {
		#blkdiscard -f "${TARGET_BLOCK_DEVICE}";
		BOOTPART="${TARGET_BLOCK_DEVICE}p1";
		ROOTPART="${TARGET_BLOCK_DEVICE}p2";
	} 
	fi;
	printf "BOOTPART: %s\nROOTPART: %s\n" "${BOOTPART}" "${ROOTPART}";
	
	exit 0;
}


# test
#test_func;

# disable accidental suspend from end user
stty -ctlecho
trap '' 20;	# SIGTSTP, ctrl + Z

# main();
checkroot;
prereq;
prompts;

# configure cleanup procedure on interrupts
configure_traps;

# disk setup
format;
get_uuids;
mount_disk;

# distro common installation
install_img;

# debug, testing archinstall
#install_arch;
#echo "install dir: ${MOUNTDIR}";
#read -p "inspect arch install";

install_configure_disks;
# distro specific setup
install_configure_setup;
install_newLUKS;

# debug: testing archinstall
#echo "${CHROOT_SCRIPT_ARCH}" > "${CHROOT_SCRIPT_LOCATION}";
#read -p "inspect archchroot script";

# chroot and run distro scripts in chroot
armchroot_prep;
armchroot_run_setup;
armchroot;

# cleanup
printf "Syncing disk. Please wait.\n";
sync;
armchroot_cleanup;
cleanup;

# Final prompts
stty ctlecho;
echo "";
echo "Installation complete. Eject your SDcard and insert into pi.";
echo "Your first time unlock password: ";
#echo "${LUKS_PASSPHRASE}";
printf "%s\n" "${LUKS_PASSPHRASE}";
