# lockpi
Encrypted installer for raspberry pis. Install raspios and other raspberry pi linux distros onto a microSD card or USB drive fully encrypted using your PC headlessly.<br/><br/>

### DISCLAIMER:
This software is in beta testing. There will be bugs. Please kindly file an issue and the authors/contributors would do their best to fix them in time.<br/><br/>

### Prerequisites:
For the script to work, you need the following software installed:<br/>
```
coreutils util-linux sed e2fsprogs dosfstools cryptsetup qemu-user-static rsync kmod diceware
```
Use either `apt`, `dnf` or your distro's package manager to install them. <br/><br/>

### How to use it:
Run the script using sudo. Follow the on screen directions and prompts if you are using it standalone. Write down the first time bootup passphrase when the script is done as you will need it to unlock your Pi for the first time. After your first boot, you will be forced to set a new LUKS passphrase. The first boot passphrase WILL BE INVALID AFTER YOU SET YOUR NEW PASSPHRASE! <br/><br/>

Here is the HELPME for arguments and options:
```
Usage:
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
	raspios
Please type in the option EXACTLY as the list.

NOTE:
The option -D has no effect for now. 
This option will have effect after Debian/Multi distro support.
```

### Supported configurations:
The script *should* work with the following:<br/>
Hardware: all of the pi families made as of May 2021<br/>
Installation environment: Debian and Fedora/RH based distros (exception: Debian. see below)<br/>
Target distro: raspios<br/>


### Tested Configurations:
The script has been tested to work with the folloiwng hardware:<br/>
pi0w<br/>
pi4B 4GB<br/>
<br/>
The script has been tested to work on the follwing installation environments:<br/>
Ubuntu 20.04 LTS<br/>
Fedora 34<br/>
<br/>
The script has been tested to work with the follwoing target distros:<br/>
raspios Lite 2021-03-04<br/>



### Notes on Distro/Target support:
Installing on Debian Buster is not officially supported right now as their kernel does not support the `adiantum` cipher module. However, you can compile your own kernel with the `adiantum` module in Debian and use that. <br/>
There is planned support for targets: debian, kali, arch.<br/><br/>

### Issues:
~~Strict POSIX compliance is not achieved yet.~~ POSIX fixes applied, pending comprehensive testing. Multiarch initrd configuration on raspios still needs to be implemented. LUKS container on debian not unlocking due to bad options or botched keyboard layout setup. <br/><br/>

### Notes on initrd Kernel version selection for raspios
The raspios chroot script will ask you to select a kernel to use when generating an initrd. Copy and paste shown kernels according to the table below:<br/>

|Model Family|Version|
---|---
|pi0|X.Y.Z+|
|pi1|X.Y.Z+|
|pi2|X.Y.Z-v7+|
|pi3|X.Y.Z-v7+|
|pi4|X.Y.Z-v7l+|
|64bit|X.Y.Z-v8+|
