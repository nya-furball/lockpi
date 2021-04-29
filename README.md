# lockpi
Encrypted installer for raspberry pis. Install raspios and other raspberry pi linux distros onto a microSD card fully encrypted using your PC headlessly.<br/><br/>

### DISCLAIMER:
This software is still in alpha development stage. IT IS BROKEN FOR MOST WORKFLOWS due issues described below. Raspios has priority support to push out a usable release first. <br/><br/>

### Prereqs:
You need to have at least ```qemu-user-static``` installed for chroot to work. CHROOT_SCRIPTS along side initramfs scripts provided by the distros are run within the ARM chroot environment on the sdcard. They are used to customize setup for each specific distro and hardware combination this script plans to support. <br/><br/>

### Notes on Distro support:
Only raspios is supported for now due to pushing the first usable release out quickly. We have planned support for: debian, kali, arch.<br/><br/>

### Issues:
There is inconsistent chroot behavior. Setting up an arm chroot environment across multiple distros consistently is currently under investigation. LUKS is also broken for non pi4 hardware due to x86 processors being much more powerful, causing LUKS to use much more hashing than supported on ALL pi hardware. The plan is to use a weak LUKS keyslot that's even supported by pi0 to let users unlock for the first time, force users to add a LUKS keyslot using the hardware they run it on and nuking the weak keyslot after a new one is configured. <br/><br/>

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
