# lockpi
Encrypted installer for raspberry pis. Install raspios and other raspberry pi linux distros onto a microSD card fully encrypted using your PC headlessly.<br/><br/>

### Notes on Distro support:
Only raspios is supported for now due to pushing the first usable release out quickly. We have planned support for: debian, kali, arch.<br/><br/>

### Notes on initrd Kernel version selection for raspios
The raspios chroot script will ask you to select a kernel to use when generating an initrd. Copy and paste shown kernels according to the table below:

|Model Family|Version|
---|---
|pi0|X.Y.Z+|
|pi1|X.Y.Z+|
|pi2|X.Y.Z-v7+|
|pi3|X.Y.Z-v7+|
|pi4|X.Y.Z-v7l+|
|64bit|X.Y.Z-v8+|
