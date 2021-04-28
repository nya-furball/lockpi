#!/bin/bash

# modified shell to avoid bugs for now
# return to sh once posix compliant
# #!/bin/sh

# Lockpi Installer:
# Headlessly install linux distributions through a x86 computer onto
# an SD card used to boot raspberry pis.

# NOTES:
# PLEASE BACK UP YOUR DATA WHEN USING THIS SCRIPT!
# The authors and contributors of this program will not be liable for 
# any damage incurred while using this script should you chose to use it.

# TODO
# POSIX COMPLIANCE! (read -. and echo -.)
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
# LUKS max iterations on pi hardware
# Arch comptiability
# command line args instead of prompt



# TODO TESTS:



checkroot(){
	if [ "$EUID" -ne 0 ]
		then echo "Please run as root";
		exit;
	fi
}

# VARS
TARGET_BLOCK_DEVICE="";
USE_LUKS=1;
IMAGE=???;
echo "";

# check for prereqs
prereq(){
	#local prereqs=("lsblk" "sed" "mount" "umount" "mke2fs" "mkfs.fat" "cryptsetup" "bsdtar" );
	
	# simple check for now bc we're pushing the code out fast
	if [ ! -e /usr/bin/qemu-arm-static ]; then {
		echo "qemu-arm-static not found. please install it!";
		exit 1;
	}
	fi;
	
}

# guided prompts
prompts(){
	# used for parsing, TODO
	#read -e -p "Path to installation image: " IMAGE;
	
	read -e -p "Path to decompressed installation image (.img): " IMAGE_IMG;
	echo "LIST OF BLOCK DEVICES:";
	lsblk -i -o 'NAME,LABEL,MODEL,SIZE,TYPE';
	read -e -p "Enter full block device path to install (/dev/???): " TARGET_BLOCK_DEVICE;
	
	# passphrase entry and confirmation loop
	LUKS_PASSPHRASE="";
	local LUKS_PASSPHRASE_BUFFER="";
	stty -echo;
	while [ -z "${LUKS_PASSPHRASE}" -o "${LUKS_PASSPHRASE}" != "${LUKS_PASSPHRASE_BUFFER}" ]; do {
		printf "Enter LUKS passphrase: " 
		read LUKS_PASSPHRASE_BUFFER;
		printf "\n";
		
		printf "Confirm LUKS passphrase: " 
		read LUKS_PASSPHRASE;
		printf "\n";
	}
	done;
	stty echo;
	
	# confirmation
	printf "\nInstallation target: ${TARGET_BLOCK_DEVICE}\n";
	echo "WARNING: ALL DATA WILL BE LOST ON TARGET.";
	confirmation "Type UPPER CASE YES to proceed: " "YES";
	if [ $? -eq "1" ]; then {
		exit;
	}
	fi;
}

# prototype:
# confirmation "PROMPT" "EXPECTED_RESPONSE";
confirmation(){
	local INPUT;
	read -p "$1" INPUT
	if [ -z "$(echo ${INPUT}|grep $2)" ]; then {
		return 1;
	} ;
	else {
		return 0;
	}
	fi;
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
format(){
	echo -e "o\np\nn\np\n1\n\n+200M\nt\nc\nn\np\n2\n\n\nw\n" | fdisk "${TARGET_BLOCK_DEVICE}";
	if [ -z $(echo $TARGET_BLOCK_DEVICE|grep mmcblk) ]; then {
		BOOTPART="${TARGET_BLOCK_DEVICE}1";
		ROOTPART="${TARGET_BLOCK_DEVICE}2";
	} ;
	else {
		BOOTPART="${TARGET_BLOCK_DEVICE}p1";
		ROOTPART="${TARGET_BLOCK_DEVICE}p2";
	} 
	fi;
	mkfs.vfat "${BOOTPART}";
	if [ -z $(echo ${USE_LUKS}|grep 1) ]; then {
		mkfs.ext4 "${ROOTPART}";
	} ;
	else {
		#LUKS_MAPPER="$(echo ${ROOTPART}|sed -E -e 's/[/]dev[/]*//g' -e 's/(^.)/luks_\1/')";
		LUKS_MAPPER="crypt_pi";
		#cryptsetup -y -v luksFormat --type=luks2 --sector-size=4096 -c xchacha12,aes-adiantum-plain64 -s 256 -h sha512 "${ROOTPART}";
		echo ${LUKS_PASSPHRASE} | cryptsetup luksFormat --force-password --type=luks2 --sector-size=4096 -c xchacha12,aes-adiantum-plain64 -s 256 -h sha512 "${ROOTPART}";
		#cryptsetup open "${ROOTPART}" "${LUKS_MAPPER}";
		echo ${LUKS_PASSPHRASE} | cryptsetup open "${ROOTPART}" "${LUKS_MAPPER}";
		mkfs.ext4 "/dev/mapper/${LUKS_MAPPER}";
	}
	fi;
}

mount_disk(){
	MOUNTDIR="$(mktemp -d)";
	mkdir "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT";
	chmod og-rwx "${MOUNTDIR}/BOOT" "${MOUNTDIR}/ROOT";
	mount "${BOOTPART}" "${MOUNTDIR}/BOOT";
	if [ -z $(echo ${USE_LUKS}|grep 1) ]; then {
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
	if [ -z "$(echo $isDebian|grep 1)" ]; then {
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
	if [ -z "$(echo $isDebian|grep 1)" ]; then {
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
	echo "Dropping into a shell on installation target.";
	echo 'Type "exit" to end customization in chroot shell: ';
	LANG=C chroot "${MOUNTDIR}/ROOT" ; #qemu-arm-static /bin/bash;
}

# installation

# this is legacy code. borked.
install_arch(){
	bsdtar -xpf "${IMAGE}" -C "${MOUNTDIR}/ROOT";
	mv ${MOUNTDIR}/ROOT/boot/* "${MOUNTDIR}/BOOT";
	umount "${MOUNTDIR}/BOOT";
	mount "${BOOTPART}" "${MOUNTDIR}/ROOT/boot/";

	# borked
	sed -E -e 's/^HOOKS=[(](.*)[)]/HOOKS=(\1 encrypt)/' -i "${MOUNTDIR}/ROOT/etc/mkinitcpio.conf"
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
	echo -e "${LUKS_MAPPER}\tPARTUUID=${UUID_ROOTPART}\tnone\tluks" |tee "${MOUNTDIR}/ROOT/etc/crypttab";
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
	echo "Done";
}



# distro specific scripts
CHROOT_SCRIPT_RASPIOS='#!/bin/bash

# return to sh once POSIX compliant
# #!/bin/sh

# TODO:
# Auto setup initramfs images and different versions using initramfs_config.txt

# install cryptsetup and initramfs tools for encrypted root
apt-get update; apt-get install cryptsetup busybox rsync initramfs-tools -y;
sed -E -e "s/^#CRYPTSETUP=/CRYPTSETUP=y/" -i /etc/cryptsetup-initramfs/conf-hook;


# ---- Auto setup initramfs, not implemented yet
# configure config.txt to use different initramfs images for each pi version
#echo -e "# configuration for initrd, edit if using 64bit kernel.\ninclude initramfs_config.txt" |tee -a /boot/config.txt;

# generate initramfs images
#for VERSION in $(ls /lib/modules/); do
#	mkinitramfs -o /boot/initramfs-"${VERSION}".gz "${VERSION}";
#done
# ----

# ask user for kernel version:
VERSION="";
echo "The following kernel versions are available: ";
ls /lib/modules/;
read -p "Select kernel version for initrd: " VERSION;

# generate and use initramfs
echo -e "\n# use initrd to unlock encrypted root\ninitramfs initramfs.gz followkernel" |tee -a /boot/config.txt;
mkinitramfs -o /boot/initramfs.gz "${VERSION}";

# disable initial resize
sed -E -e "s/ [!-z]*init_resize.sh//" -i /boot/cmdline.txt;
rm /etc/init.d/resize*fs_once /etc/rc3.d/S01resize*fs_once;
'

# used with version detection. 
# Only raspios supported for now
CHROOT_SCRIPT_LOCATION="/dev/shm/distro_install.sh";
install_configure_setup(){
	echo "${CHROOT_SCRIPT_RASPIOS}" > "${CHROOT_SCRIPT_LOCATION}";
	chmod +x "${CHROOT_SCRIPT_LOCATION}";
}

# run distro specific chroot setup
armchroot_run_setup(){
	# modified, return to sh once POSIX compliant
	#LANG=C chroot "${MOUNTDIR}/ROOT" qemu-arm-static /bin/sh -c ${CHROOT_SCRIPT_LOCATION};
	LANG=C chroot "${MOUNTDIR}/ROOT" qemu-arm-static /bin/bash -c ${CHROOT_SCRIPT_LOCATION};
}




# main();
checkroot;
prereq;
prompts;

# disk setup
format;
get_uuids;
mount_disk;

# distro common installation
install_img;
install_configure_disks;
# distro specific setup
install_configure_setup;

# chroot and run distro scripts in chroot
armchroot_prep;
armchroot_run_setup;
armchroot;

# cleanup
echo "Syncing disk. Please wait.";
sync;
armchroot_cleanup;
cleanup;
