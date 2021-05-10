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
# Update cleanup procedures
#	detect if ${MOUNTDIR} is empty
#	stty echoctl shenanigans
# Other distro support:
#	CHROOT SCRIPTS FOR:
#		debian
#			unlock issues
#		kali
#		arch
#	install_config
# prompts():
#	DISTRO prompt and empty detection
# FUCKING POSIX COMPLIANCE
#	check for /run/shm
# Support PC distros:
#	Debian
#		WHERE THE FUCK IS ADIANTUM?!
#	Arch
#		qemu-arm-static shenanigans
# backup configs
#	actual script
#	chroot script
# detect_version(); # detect distro version
# parse_img(); # intelligent decompression

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


# TODO TESTS:
# Other distro support:
#	install_configure_setup(); # debian
#	mount_disk(); # debian


# commented out bc debian support is buggy
#DISTRO_SUPPORTED="raspios debian";
DISTRO_SUPPORTED="raspios";

HELP="Usage:
Standalone: (follow on screen prompts)
./lockpi.sh
Args:
./lockpi.sh [ARGUMENTS]

ARGUMENTS and OPTIONS
[-h],[--help]			: Print help
[-d {BLOCK_DEVICE}]		: target block device path (/dev/???)
[-i {IMAGE}]			: decompressed installation image (.img)
[-D {DISTRO}]			: distro, see DISTRO LIST for supported options

DISTRO LIST:
The following distros are supported:
$(printf "${DISTRO_SUPPORTED}"|tr ' ' "\n" |sed -E -e 's/(^.)/\t\1/g' )
Please type in the option EXACTLY as the list.

NOTE:
The option -D has no effect for now. 
This option will have effect after Debian/Multi distro support.
"


# DO NOT EDIT HERE! USE CLI INTERFACE OR INTERACTIVE PROMPT!
# VARS:
IMAGE_IMG="";
TARGET_BLOCK_DEVICE="";
LUKS_PASSPHRASE="";
DISTRO="";
LUKS_MAPPER="";
CHROOT_SCRIPT_LOCATION="";
ERROR_LOG="";

# CLI arguments interface
# parse arguments
# prototype:
#	parse_args;
ARG_ARGV="$@"
ARG_COUNT="$#";
parse_args(){
	local index=1;
	local buffer_opt="";
	local buffer_arg="";
	while [ ${index} -le ${ARG_COUNT} ]; do {
		buffer_opt="$(printf "%s" "${ARG_ARGV}" | cut -f ${index} -d ' ')";
		buffer_arg="$(printf "%s" "${ARG_ARGV}" | cut -f $((${index}+1)) -d ' ')";
		case "${buffer_opt}" in
			"-d")
				# target device
				index=$((${index}+1));
				TARGET_BLOCK_DEVICE="${buffer_arg}";
				;;
			"-i")
				# installation image
				index=$((${index}+1));
				IMAGE_IMG="${buffer_arg}";
				;;
			"-D")
				# distro
				index=$((${index}+1));
				DISTRO="${buffer_arg}";
				;;
			"-h"|"--help")
				# print help
				printf "%s" "${HELP}";
				exit 0;
				;;
			*)
				printf "Incorrect/too many args. Use -h for help.\n";
				exit 0;
				;;
		esac;
		index=$((${index}+1));
	}
	done;
}




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


# check for prereqs
prereq(){
	# check if relevant programs exist
	local prereqs="sleep lsblk blkid sed mount umount mke2fs mkfs.fat cryptsetup qemu-arm-static rsync kmod diceware blkdiscard";
	local prereqLength=$(printf "%s" "${prereqs}"|wc -w);
	local currentItem="";
	
	for currentItem in ${prereqs}; do {
		which "${currentItem}" 1>/dev/null || { 
			printf "\nPrerequesites not met!";
			printf "\nYou don't have %s.\n" "${currentItem}"; 
			printf "Please check you have the following:\n%s\n\n"  "${prereqs}"; 
			printf "See the section \"Prerequisites\" in the README for details.\n";
			exit 1; 
		};

	}
	done
	
	# check if kernel supports adiantum cipher
	# Note:
	#	WHY THE FUCK DOES DEBIAN NOT SUPPORT ADIANTUM?!
	kmod list|cut -f1 -d' '|grep -iq adiantum || modprobe adiantum;
	if [ $? != 0 ]; then {
		echo "Your kernel doesn't support the Adiantum Cipher right now.";
		echo "Please either: "
		echo "1: Use a supported installation distro.";
		echo "OR";
		echo "2: Install a kernel that supports adiantum (likely at least version 4.21).";
		exit 1;
	}
	fi;
}

# guided prompts
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
	
	# force raspios bc debian support is buggy
	DISTRO="raspios";
	
	
	# Configure a firstboot LUKS keyslot with 10 word diceword passphrase (128 bit entropy)
	LUKS_PASSPHRASE="$(diceware -w en_eff -d' ' -n 10 --no-caps)";
	
	# confirmation
	printf "\nInstallation target: %s\n" "${TARGET_BLOCK_DEVICE}";
	printf "Installation image: %s\n" "${IMAGE_IMG}";
	# commented out bc debian support is buggy
	#printf "Installation distro: %s\n" "${DISTRO}";
	echo "WARNING: ALL DATA WILL BE LOST ON TARGET.";
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
detect_version(){
	# only support raspios/raspbian for now
	return 0;
}

# partitioning
LUKS_MAPPER="crypt_pi";
format(){
	# detect device name scheme
	case "${TARGET_BLOCK_DEVICE}" in
		/dev/disk/by-id/*|/dev/disk/by-path/*)
			BOOTPART="${TARGET_BLOCK_DEVICE}-part1";
			ROOTPART="${TARGET_BLOCK_DEVICE}-part2";
			;;
		/dev/sd[a-z])		# if you got more than 26 drives connected at once, it's not for your client
			BOOTPART="${TARGET_BLOCK_DEVICE}1";
			ROOTPART="${TARGET_BLOCK_DEVICE}2";
			;;
		/dev/mmcblk[0-9])	# if you got more than 10 SD/MMC blocks attached, it's not for your client
			BOOTPART="${TARGET_BLOCK_DEVICE}p1";
			ROOTPART="${TARGET_BLOCK_DEVICE}p2";
			;;
		/dev/loop*)		# debug. used in testing phase
			BOOTPART="${TARGET_BLOCK_DEVICE}p1";
			ROOTPART="${TARGET_BLOCK_DEVICE}p2";
			;;
		*)
			printf "Disk path input format not supported.\n";
			stty ctlecho;
			exit 1;
			;;
	esac

	blkdiscard -f "${TARGET_BLOCK_DEVICE}";

	# create partitions
	printf "o\np\nn\np\n1\n\n+200M\nt\nc\nn\np\n2\n\n\nw\n\n" | fdisk "${TARGET_BLOCK_DEVICE}";
	
	# sleep 1s for disks to sync up
	sleep 1;
	
	mkfs.vfat "${BOOTPART}";

	# we are formatting to the lowest denominator: pi0
	# 128 bit entropy passphrase *should* mitigate issues.
	# (in quotes bc cryptography is not the author's forte.)
	# argon2i params:
	#	timecost = 4; most common settings from benchmarks across x86 and pi
	#	memory = 200MB; pi0/w only has 256MB and we have initrd
	#	parallel = 1; pi0/w only has 1 core. more than 1 will FAIL to unlock.
	printf "%s\n" "${LUKS_PASSPHRASE}"| cryptsetup luksFormat --force-password --type=luks2 --sector-size=4096 -c xchacha20,aes-adiantum-plain64 -s 256 -h sha512 --pbkdf argon2i --pbkdf-memory 100000 --pbkdf-parallel 1 --pbkdf-force-iterations 4 "${ROOTPART}";
	
	# format mapped LUKS partition as ext4
	printf "%s\n" "${LUKS_PASSPHRASE}"| cryptsetup open "${ROOTPART}" "${LUKS_MAPPER}";
	mkfs.ext4 "/dev/mapper/${LUKS_MAPPER}";
}

mount_disk(){
	MOUNTDIR="$(mktemp -d)";
	mkdir "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT";
	chmod og-rwx "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT";
	mount "${BOOTPART}" "${MOUNTDIR}/BOOT";
	mount "/dev/mapper/${LUKS_MAPPER}" "${MOUNTDIR}/ROOT";
}

# arm chroot prep and cleanup
armchroot_prep(){
	mount --bind /dev/ "${MOUNTDIR}/ROOT/dev";
	mount --bind /dev/pts "${MOUNTDIR}/ROOT/dev/pts";
	mount --bind /dev/shm "${MOUNTDIR}/ROOT/dev/shm";
	mount -t sysfs sysfs "${MOUNTDIR}/ROOT/sys";
	mount -t proc proc "${MOUNTDIR}/ROOT/proc";
	
	#if [ "${isDebian}" != 1 ]; then {
	#	mount --bind "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT/boot";
	#} ;
	#else {
	#	mount --bind "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT/boot/firmware";
	#}
	#fi;
	
	case "${DISTRO}" in
		"debian")
			mount --bind "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT/boot/firmware";
			;;
		*)
			mount --bind "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT/boot";
			;;
	esac
	
	
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

	#if [ "${isDebian}" != 1 ]; then {
	#	umount "${MOUNTDIR}/ROOT/boot";
	#} ;
	#else {
	#	umount "${MOUNTDIR}/ROOT/boot/firmware";
	#}
	#fi;
	
	case "${DISTRO}" in
		"debian")
			umount "${MOUNTDIR}/ROOT/boot/firmware";
			;;
		*)
			umount "${MOUNTDIR}/ROOT/boot";
			;;
	esac
	
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
ERROR_LOG="/tmp/lockpi_rsync.log";
install_img(){
	# mount .img file as loop device
	LOOPDEV="$(losetup -v -P --show -f ${IMAGE_IMG})";
	mkdir "${MOUNTDIR}/ROOT_IMG" "${MOUNTDIR}/BOOT_IMG";
	mount "${LOOPDEV}p1" "${MOUNTDIR}/BOOT_IMG";
	mount "${LOOPDEV}p2" "${MOUNTDIR}/ROOT_IMG";
	
	# copy distro to target disk
	rsync -ahHAXxq "${MOUNTDIR}/ROOT_IMG/" "${MOUNTDIR}/ROOT/" 2>"${ERROR_LOG}";
	rsync -ahq "${MOUNTDIR}/BOOT_IMG/" "${MOUNTDIR}/BOOT/" 2>>"${ERROR_LOG}";
	if [ "$(cat "${ERROR_LOG}" 2>/dev/null)" != "" ]; then { 
		printf "There were errors in rsync copy.\n";
		printf "See %s for errors" "${ERROR_LOG}";
	} 
	fi;
	
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
	printf "%s\tPARTUUID=%s\tnone\tluks\n" "${LUKS_MAPPER}" "${UUID_ROOTPART}" |tee "${MOUNTDIR}/ROOT/etc/crypttab";
}

get_uuids(){
	UUID_LUKS_MAP="$(lsblk --noheadings -o UUID -d /dev/mapper/${LUKS_MAPPER})";
	UUID_BOOTPART="$(lsblk --noheadings -o PARTUUID -d ${BOOTPART})";
	UUID_ROOTPART="$(lsblk --noheadings -o PARTUUID -d ${ROOTPART})";
}



# cleanup
cleanup(){
	umount "${MOUNTDIR}/BOOT/";
	umount "${MOUNTDIR}/ROOT/";
	umount "${MOUNTDIR}/BOOT_IMG";
	umount "${MOUNTDIR}/ROOT_IMG";
	losetup -d "${LOOPDEV}";
	cryptsetup close "${LUKS_MAPPER}";
	rmdir "${MOUNTDIR}/ROOT" "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT_IMG" "${MOUNTDIR}/BOOT_IMG" ;
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
	trap 'cleanup_interrupt' HUP;	# SIGHUP
	trap 'cleanup_interrupt' INT;	# SIGINT, ctrl + c
	trap 'cleanup_interrupt' QUIT;	# SIGQUIT, ctrl + \
	trap 'cleanup_interrupt' TERM;	# SIGTERM
}



# distro specific scripts
CHROOT_SCRIPT_RASPIOS='#!/bin/sh

# trap signals so user cannot accidentally exit
stty -ctlecho
trap "" HUP;	# SIGHUP
trap "" INT;	# SIGINT, ctrl + c
trap "" QUIT;	# SIGQUIT, ctrl + \
trap "" TERM;	# SIGTERM
trap "" TSTP;	# SIGTSTP, ctrl + Z

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

# cleanup
stty ctlecho
'

CHROOT_SCRIPT_DEBIAN='#!/bin/sh

# trap signals so user cannot accidentally exit
stty -ctlecho
trap "" HUP;	# SIGHUP
trap "" INT;	# SIGINT, ctrl + c
trap "" QUIT;	# SIGQUIT, ctrl + \
trap "" TERM;	# SIGTERM
trap "" TSTP;	# SIGTSTP, ctrl + Z

# cryptsetup
#	there a prompt for keyboard locale
apt-get update; apt-get install cryptsetup busybox rsync initramfs-tools -y; 
printf "CRYPTSETUP=y\n" >> /etc/cryptsetup-initramfs/conf-hook;
for i in /etc/default/raspi*-firmware; do
	printf "ROOTPART=\"/dev/mapper/crypt_pi cryptdevice=PARTUUID=UUID_ROOTPART:crypt\"\n" >> "$i";
done;
update-initramfs -u;

# disable resize
systemctl disable rpi-resizerootfs.service

# cleanup
stty ctlecho
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


# used with version selection.
CHROOT_SCRIPT_LOCATION="/dev/shm/distro_install.sh";
install_configure_setup(){
	#echo "${CHROOT_SCRIPT_RASPIOS}" > "${CHROOT_SCRIPT_LOCATION}";
	#printf "%s" "${CHROOT_SCRIPT_RASPIOS}" > "${CHROOT_SCRIPT_LOCATION}";
	#chmod +x "${CHROOT_SCRIPT_LOCATION}";
	
	local script="";
	case "${DISTRO}" in
		"raspios")
			script="${CHROOT_SCRIPT_RASPIOS}";
			;;
		"debian")
			printf "Target distro ${DISTRO} is not supported for now.\n";
			#script="$(printf "%s" "${CHROOT_SCRIPT_DEBIAN}" |sed -E -e "s/UUID_ROOTPART/${UUID_ROOTPART}/")";
			#sed -E -e 's/' -i 
			;;
		"arch")
			printf "Target distro ${DISTRO} is not supported for now.\n";
			cleanup_interrupt;
			;;
		"kali")
			printf "Target distro ${DISTRO} is not supported for now.\n";
			cleanup_interrupt;
			;;
	esac
	printf "%s" "${script}" > "${CHROOT_SCRIPT_LOCATION}";
	chmod +x "${CHROOT_SCRIPT_LOCATION}";
}

# run distro specific chroot setup
armchroot_run_setup(){
	LANG=C chroot "${MOUNTDIR}/ROOT" qemu-arm-static /bin/sh -c ${CHROOT_SCRIPT_LOCATION};
}



# Add hardware capability specific LUKS keyslot.
LUKS_FIRSTBOOT_SCRIPT='#!/bin/sh
# trap signals so user cannot accidentally exit
stty -ctlecho
trap "" HUP;	# SIGHUP
trap "" INT;	# SIGINT, ctrl + c
trap "" QUIT;	# SIGQUIT, ctrl + \
trap "" TERM;	# SIGTERM
trap "" TSTP;	# SIGTSTP, ctrl + Z

# force user into setting up new LUKS keyslot on the hardware
CRYPT_PARTITION=REPLACEMENT_CRYPTPART;


# setup
mount -a;
echo "If you accidentally pressed ctrl+S, press ctrl+Q to unfreeze.";
echo "";

# get correct firstboot pw to add keyslot later
PW_FIRSTBOOT="";
#isIncorrect=1;
isIncorrect=0; # skip get first boot pw from user, read directly from file
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

PW_FIRSTBOOT="$(cat /firstboot.key)"

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
sed -E -e "s/[ \t]+init=\/usr\/sbin\/luks_firstboot.sh//g" -i /boot/cmdline.txt -i /boot/firmware/cmdline.txt;

# remove firstboot key on encrypted volume
rm /firstboot.key;

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
	printf "%s" "${LUKS_PASSPHRASE}" > "${MOUNTDIR}/ROOT/firstboot.key";
	printf "%s" "${LUKS_FIRSTBOOT_SCRIPT}" > "${MOUNTDIR}/ROOT/usr/sbin/luks_firstboot.sh";
	chown root:root "${MOUNTDIR}/ROOT/usr/sbin/luks_firstboot.sh";
	chmod 774 "${MOUNTDIR}/ROOT/usr/sbin/luks_firstboot.sh";
	chown root:root "${MOUNTDIR}/ROOT/firstboot.key";
	chmod 700 "${MOUNTDIR}/ROOT/firstboot.key";
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
	
	#local TARGET_BLOCK_DEVICE=/dev/mmcblk1
	local TARGET_BLOCK_DEVICE="";
	printf "TEST: TARGET_BLOCK_DEVICE=";
	read TARGET_BLOCK_DEVICE;
	printf '\n';
	# detect device name scheme
	case "${TARGET_BLOCK_DEVICE}" in
		/dev/disk/by-id/*|/dev/disk/by-path/*)
			BOOTPART="${TARGET_BLOCK_DEVICE}-part1";
			ROOTPART="${TARGET_BLOCK_DEVICE}-part2";
			;;
		/dev/sd[a-z])
			BOOTPART="${TARGET_BLOCK_DEVICE}1";
			ROOTPART="${TARGET_BLOCK_DEVICE}2";
			;;
		/dev/mmcblk[0-9])
			BOOTPART="${TARGET_BLOCK_DEVICE}p1";
			ROOTPART="${TARGET_BLOCK_DEVICE}p2";
			;;
		*)
			printf "Disk path input format not supported.\n";
			stty ctlecho;
			exit 1;
			;;
	esac
	printf "BOOTPART: %s\nROOTPART: %s\n" "${BOOTPART}" "${ROOTPART}";
	
	exit 0;
}


# MAIN FUNCTION STARTS BELOW!

# test
#test_func;

# parse CLI arguments and options
parse_args;

# disable accidental suspend from end user
stty -ctlecho
trap '' TSTP;	# SIGTSTP, ctrl + Z

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

# debug: testing archinstall
#echo "${CHROOT_SCRIPT_ARCH}" > "${CHROOT_SCRIPT_LOCATION}";
#read -p "inspect archchroot script";

# chroot and run distro scripts in chroot
armchroot_prep;

# trap signals so signals in CHROOT cannot interrupt script
trap '' HUP;	# SIGHUP
trap '' INT;	# SIGINT, ctrl + c
trap '' QUIT;	# SIGQUIT, ctrl + \
trap '' TERM;	# SIGTERM

armchroot_run_setup;
armchroot;

# reconfigure traps
configure_traps;

# install first boot LUKS rekey script
install_newLUKS;

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
