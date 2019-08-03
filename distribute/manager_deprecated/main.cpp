#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>

#include <sys/reboot.h>
#include <linux/reboot.h>

#include <sys/dir.h>
#include <dirent.h>

#include <string.h>

#define XILINX_DEVICE 0x7028
#define XILINX_VENDOR 0x10ee
#define XILINX_SUBSYSTEM 0x7
#define INSTALL_DIR "/opt/bluespecpcie_manager/"


/* Remember the effective and real UIDs. */

static uid_t euid, ruid;


/* Restore the effective UID to its original value. */

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


/* Set the effective UID to the real UID. */

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
/* Main program. */

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

void restore_config(char* dname) {
	char path[128];
	sprintf( path, "/sys/bus/pci/devices/%s/config", dname );
	FILE* fdev = fopen(path, "wb");
	if ( !fdev ) {
		fprintf(stderr, "error: failed to open config file for restore\n" );
		return;
	}
	char buf[128];
	char backpath[128];
	sprintf(backpath, "%s/pcieconfig", INSTALL_DIR);
	FILE* fback = fopen(backpath, "rb" );
	if ( !fback ) {
		fprintf(stderr, "error: failed to open config backup location\n" );
		return;
	}
	while ( !feof(fdev) ) {
		int cnt = fread(buf, sizeof(char), 128, fback);
		if ( cnt == 0 ) break;

		fwrite(buf, sizeof(char), cnt, fdev);
	}
}
void backup_config(char* dname) {
	char path[128];
	sprintf( path, "/sys/bus/pci/devices/%s/config", dname );
	FILE* fdev = fopen(path, "rb");
	if ( !fdev ) {
		fprintf(stderr, "error: failed to open config file for backup\n%s\n", path );
		return;
	}
	char buf[128];
	char backpath[128];
	sprintf(backpath, "%s/pcieconfig", INSTALL_DIR);
	FILE* fback = fopen(backpath, "wb" );
	if ( !fback ) {
		fprintf(stderr, "error: failed to open config backup location\n" );
		return;
	}
	while ( !feof(fdev) ) {
		int cnt = fread(buf, sizeof(char), 128, fdev);
		if ( cnt == 0 ) break;

		fwrite(buf, sizeof(char), cnt, fback);
	}
}

bool check_rebooted() {
	char path[128];
	sprintf(path, "%s/rebooted", INSTALL_DIR );
	int a = access(path, R_OK);
	if ( a == 0 ) return true;
	else return false;
}
void clear_rebooted() {
	char path[128];
	sprintf(path, "%s/rebooted", INSTALL_DIR );
	unlink(path);
}
void set_rebooted() {
	char path[128];
	sprintf(path, "%s/rebooted", INSTALL_DIR );
	FILE* flag = fopen(path, "w");
	if ( !flag ) {
		fprintf(stderr, "error: failed to open reboot flag location\n");
		return;
	}
	fprintf(flag, "1");
	fclose(flag);
}

bool check_config_exist() {
	char path[128];
	sprintf(path, "%s/pcieconfig", INSTALL_DIR );
	int a = access(path, R_OK);
	if ( a == 0 ) return true;
	else return false;
}

int
main (int argc, char** argv)
{
	ruid = getuid ();
	euid = geteuid ();
	undo_setuid ();

	printf( "BluespecPCIe manager\n" ); fflush(stdout);
	bool cmd_reboot = false;
	bool cmd_exec = false;
	char* cmd_exec_name = NULL;
	int cmd_arg_count = 0;

	if ( argc > 1 ) {
		char* cmd = argv[1];
		if ( cmd[0] == 'r' && strlen(cmd) == 1 ) cmd_reboot = true;
		else {
			cmd_exec_name = cmd;
			cmd_arg_count = argc - 1;
		}
	}

	/*
	Functions:
	1. Check program status
		check reboot flag
		if rebooted, backup config , clear flag

		check device exist
		check config backup exist
		if both, restore config
		else set flag, print reboot ask msg, then reboot
	2. Reboot machine
		check device exist
		check config backup exist
		if both, do nothing
		else set flag, then reboot
	*/

	bool rebooted = check_rebooted();


	char* loc;
	bool found = find_pcie_device(&loc);
	
	printf( "rebooted: %s\n", rebooted ? "true" : "false" );
	printf( "device found: %s\n", found ? "true" : "false" );

	if ( rebooted ) {
		printf( "performing after-reboot process\n" );
		if ( found ) {
			do_setuid();
			backup_config(loc);
		
			clear_rebooted();
			undo_setuid();
		} else {
			printf( "reboot flag set but device not found!\n" );
			printf( "not clearing reboot flag...\n" );
		}
	}
	
	bool config_exist = check_config_exist();
	printf( "config exists: %s\n", config_exist ? "true" : "false" );

	int retval = 0;

	if ( found && config_exist ) {
		printf( "device discovered, restoring pcie config\n" );
		// restore config
		do_setuid();
		restore_config(loc);
		undo_setuid();

		char** args = (char**)malloc(sizeof(char*)*cmd_arg_count+1);
		args[cmd_arg_count] = 0;
		for ( int i = 0; i < cmd_arg_count; i++ ) {
			args[i] = argv[i+1];
		}

		if ( cmd_exec ) {
			execvp(cmd_exec_name, args);
		}

		retval = 0;
	} else  {
		printf( "device not discovered, setting reboot flag...\n" );
		// set reboot flag

		if ( cmd_reboot ) {
			printf( "rebooting machine...\n" );
			do_setuid();
			set_rebooted();
			undo_setuid();
			do_setuid();
			reboot(LINUX_REBOOT_CMD_RESTART);
			undo_setuid();
			retval = 1;
		} else {
			printf( "not rebooting. %s r to reboot\n", argv[0] );
			retval = 1;
		}
	}

	return retval;
}
