#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>

#include <sys/syscall.h>
#include <sys/reboot.h>
#include <linux/reboot.h>

#include <sys/dir.h>
#include <dirent.h>

#include <string.h>

#define XILINX_DEVICE 0x7028
#define XILINX_VENDOR 0x10ee
#define XILINX_SUBSYSTEM 0x7

/* Remember the effective and real UIDs. */
static uid_t euid, ruid;


void
do_setuid (void)
{
	int status;

#ifdef _POSIX_SAVED_IDS
	status = seteuid (euid);
#else
	status = setreuid (ruid, euid);
#endif
	if (status < 0) {
		fprintf (stderr, "Couldn't set uid.\n");
		exit (status);
	}
}

void
undo_setuid (void)
{
	int status;

#ifdef _POSIX_SAVED_IDS
	status = seteuid (ruid);
#else
	status = setreuid (euid, ruid);
#endif
	if (status < 0) {
		fprintf (stderr, "Couldn't set uid.\n");
		exit (status);
	}
}

int read_pci_file_hex(char* dname, char* fname) {
	char path[128];
	char buf[128];
	sprintf( path, "/sys/bus/pci/devices/%s/%s", dname, fname );
	FILE* fdev = fopen(path, "r");
	if ( !fdev ) return 0;

	fgets(buf, 128, fdev);
	int c = strtol(buf, NULL, 16);
	return c;
}

void
unload_driver() {
	int ret = syscall(__NR_delete_module, "bdbmpcie", 0);
	if ( ret != 0 ) {
		printf( "delete_module returned %d\n", ret );
	} else {
		printf( "unloaded driver\n" );
	}
}

bool
rescan_pcie_device(char* dname) {
/*
echo 1 > /sys/bus/pci/<your PCI bus number>/remove
echo 1 > /sys/bus/pci/rescan

// it sets Command register (offset 4) to 7 (memory/IO/bus master enable bit)
// https://forums.xilinx.com/t5/PCI-Express/Is-it-possible-to-do-enumeration-without-restart-the-PC/td-p/740999
setpci -s <your PCI bus number> 04.w=7
*/

	char dpath[128];
	sprintf( dpath, "/sys/bus/pci/devices/%s/remove", dname );
	FILE* fdev = fopen(dpath, "w");
	if ( !fdev ) {
		fprintf(stderr, "error: failed to open sys file to remove\n" );
		return false;
	}
	fprintf(fdev, "1\n");
	fclose(fdev);

	FILE* fscan = fopen("/sys/bus/pci/rescan", "w");
	if ( !fscan ) {
		fprintf(stderr, "error: failed to open sys file to rescan\n" );
		return false;
	}
	fprintf(fdev, "1\n");
	fclose(fdev);

	char cpath[128];
	sprintf( cpath, "/sys/bus/pci/devices/%s/config", dname );
	FILE* fconf = fopen(cpath, "wb");
	if ( !fconf ) {
		fprintf(stderr, "error: failed to open sys file to config\n" );
		return false;
	}
	fseek(fconf, 4, SEEK_SET);
	uint16_t cmd = 7;
	size_t ret = fwrite(&cmd, sizeof(uint16_t), 1, fconf);

	if ( ret != 1 ) {
		fprintf( stderr, "error: fwrite to config file returned %ld\n", ret );
		return false;
	}

	return true;
}

bool is_pcie_device(char* dname) {
	int device = read_pci_file_hex(dname, (char*)"device");
	int vendor = read_pci_file_hex(dname, (char*)"vendor");
	int subsystem_device = read_pci_file_hex(dname, (char*)"subsystem_device");

	if ( device == XILINX_DEVICE && vendor == XILINX_VENDOR && subsystem_device == XILINX_SUBSYSTEM ) {
		printf ( "%x %x %x\n", vendor, device, subsystem_device );
		return true;
	}
	return false;
}

bool find_pcie_device(char** id) {
	DIR *dp;
	struct dirent *dirp;
	dp = opendir("/sys/bus/pci/devices");
	while ( (dirp = readdir(dp)) ) {
		bool is = is_pcie_device(dirp->d_name);
		if ( is ) {
			*id = (char*)malloc(sizeof(char) * strlen(dirp->d_name)+1);
			strncpy(*id, dirp->d_name, strlen(dirp->d_name));
			return true;
		}
	}
	return false;
}


int
main (int argc, char** argv)
{
	ruid = getuid ();
	euid = geteuid ();
	undo_setuid ();

	printf( "BluespecPCIe rescan tool\n" ); fflush(stdout);

	/*
	Functions:
	*/


	char* loc;
	bool found = find_pcie_device(&loc);
	if ( !found ) {
		printf( "ERROR: BluespecPCIe device not found!\n" ); 
		exit(1);
	}

	printf( "BluespecPCIe device found!\n" );

	do_setuid();
	unload_driver();
	sleep(1);
	bool ret = rescan_pcie_device(loc);
	undo_setuid();
	if ( ret ) { 
		printf( "Rescan successful!\n" );
	} else {
		printf( "Rescan failed...\n" );
	}

}
