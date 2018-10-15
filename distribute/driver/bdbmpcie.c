#include <linux/init.h>

#include <linux/module.h>

#include <linux/pci.h>
#include <linux/pci_ids.h>
#include <linux/interrupt.h>

#include <linux/highmem.h>

#include <linux/spinlock.h>
#include <linux/spinlock_types.h>

#include <linux/fs.h>
#include <linux/cdev.h>

#include <linux/sched.h>
#include <linux/wait.h>
#include <linux/delay.h>
#include <linux/poll.h>

//must match one in PcieCtrl
#define DMA_ADDR_OFFSET 32


MODULE_AUTHOR("Sang-Woo Jun");
MODULE_LICENSE("Dual BSD/GPL");

static struct pci_device_id pcie_ids[] = {
	{ PCI_DEVICE(PCI_VENDOR_ID_XILINX, 0x7028) },
	{ 0, },
};
MODULE_DEVICE_TABLE(pci, pcie_ids);

static irqreturn_t interrupt_handler(int irq, void *p);

static struct pci_dev *pcidev = NULL;

static unsigned int chrdev_major = 0;
static unsigned int chrdev_minor = 0;

static unsigned int ioctl_alloc_dma = 0;
static unsigned int ioctl_refresh_link = 1;

static unsigned long bar0_addr;
static unsigned long bar0_size = 1024*1024;
static void* bar0_ptr;
static unsigned int irq;










//TODO: unmap dma, free table on unload!
struct page** dma_pages = NULL;
unsigned int dma_pages_count = 0;
void* dma_addr = NULL;
unsigned long mmap_buffersize = 1024*1024;
static int create_dma_buffer(unsigned int bufcount) {
	int i;
	int bufidx = 0;
	unsigned int gfp_mask = GFP_KERNEL | __GFP_DMA;
	dma_addr_t bus_addr;
	u8* bar0_data;
	bar0_data = (u8*)bar0_ptr;


	printk(KERN_ALERT "BlueDBM DMA buffer alloc request: %d pages\n", bufcount);

	if ( dma_pages != NULL ) {
		printk(KERN_ALERT "BlueDBM DMA buffer already exist! Strange!\n");
		/*
		// this will not be called since we're only allocing buffers at init
		//void* pageaddr = kmap(dma_pages[0]);
		//unsigned long* lpa = (unsigned long*)pageaddr;
		//int i = 0;
		//for ( i = 0; i < 8; i++ ) {
		//	printk(KERN_ALERT "BlueDBM DMA buffer exists! %lx %lx %lx %lx\n", 
		//		lpa[i*4+0], lpa[i*4+1], lpa[i*4+2], lpa[i*4+3]);
		//}
		//kunmap(dma_pages[0]);


		for ( i = 0; i < dma_pages_count; i++ ) {
			unsigned int page_addr = (unsigned long)page_address(dma_pages[i]);
			pci_unmap_single(pcidev, page_addr, PAGE_SIZE, DMA_BIDIRECTIONAL);
			free_page(page_addr);
		}
		kfree(dma_pages);
	*/	
	}
	dma_pages = kmalloc(sizeof(struct page*)*bufcount, GFP_KERNEL);
	if ( dma_pages == NULL ) {
		printk(KERN_ERR "BlueDBM DMA dma_pages alloc failed! \n" );
		return 1;
	}

	for ( bufidx = 0; bufidx < bufcount; bufidx++ ) {
		void __iomem *maddr = NULL;
		struct page *pages = alloc_page(gfp_mask);
		if ( pages == NULL ) {
			printk(KERN_ERR "BlueDBM DMA buffer alloc failed! \n" );
			return 1;
		}
		maddr = page_address(pages);
		dma_pages[bufidx] = pages;

		bus_addr = pci_map_single(pcidev, maddr, PAGE_SIZE, DMA_BIDIRECTIONAL);
		iowrite32(bus_addr, &bar0_data[DMA_ADDR_OFFSET + 4*bufidx]);
		wmb();

		if ( pci_dma_mapping_error(pcidev, bus_addr) ) {
			return 1;
		}
	}
	dma_pages_count = bufcount;

	printk(KERN_ALERT "BlueDBM DMA buffer alloc successful\n");
	return 0;
}











static int __init pcie_probe (struct pci_dev *dev, const struct pci_device_id *id) {
	u16 vendor_id, device_id;
	u32 bar0;
	u8 interrupt_no, interrupt_pin;
	u8* bar0_data;
	unsigned int r32;
	int i;
	u16 device_cmd;

	int rc = 0;
	int ret = 0;
	int capability_pos = 0;
	
	pcidev = dev;

	pci_read_config_word(dev, PCI_COMMAND, &device_cmd);
	printk(KERN_ERR "BlueDBM PCIe driver enabling device cmd %x\n", device_cmd );
	
	/*
	capability_pos = pci_find_capability(dev, PCI_CAP_ID_EXP);
	if ( capability_pos ) {
		u16 linkctrl;
		pci_read_config_word(dev, capability_pos + PCI_EXP_LNKCTL, &linkctrl);
		linkctrl |= PCI_EXP_LNKCTL_RL;
		pci_write_config_word(dev, capability_pos + PCI_EXP_LNKCTL, linkctrl);
		printk(KERN_ALERT "Set PCI_ECP_LNKCTL_RL to retain link. 5GT/s?");
	}
	*/

	rc = pci_enable_device(dev);
	if ( rc ) {
		printk(KERN_ERR "BlueDBM PCIe driver pci_enable_device() failed\n" );
		goto probe_fail_enable;
	}
	if ( !(pci_resource_flags(dev, 0) & IORESOURCE_MEM) ) {
		printk(KERN_ERR "BlueDBM PCIe driver incorrect BAR configuration\n" );
		rc = 1;
		goto probe_fail;
	}
	pci_read_config_word(dev, 0, &vendor_id);
	pci_read_config_word(dev, 2, &device_id);
	printk(KERN_ALERT "BlueDBM PCIe driver detected device %x %x", vendor_id, device_id);



	bar0_addr = pci_resource_start(dev, 0);
	pci_read_config_dword(dev, 0x10, &bar0);
	printk(KERN_ALERT "BAR0: %x @ %lx\n", bar0, bar0_addr);
	
	rc = pci_request_regions(dev, "bdbm_bar0");
	if ( rc ) {
		printk(KERN_ERR "BlueDBM PCIe driver pci_request_regions failed\n" );
		goto probe_fail;
	}


	bar0_ptr = pci_iomap(dev,0,1024*1024);
	bar0_data = (u8*)bar0_ptr;
	if ( bar0_data == 0 ) {
		printk(KERN_ERR "BlueDBM PCIe driver failed to map BAR 0\n" );
		rc = 1;
		goto probe_fail_release_region;
	}


/*
	//FIXME disabling interrupts
	pci_enable_msi(dev);
	pci_read_config_byte(dev,PCI_INTERRUPT_LINE, &interrupt_no);
	pci_read_config_byte(dev,PCI_INTERRUPT_PIN, &interrupt_pin);
	irq = dev->irq;
	
	//request_irq(interrupt_no, interrupt_handler, 0, "bdbmpcie", 0);
	ret = request_irq(irq, interrupt_handler, 0, "bdbmpcie", dev);
	if ( ret ) {
		printk(KERN_ALERT "request_irq failed with value %d\n", ret );
	} else {
		printk(KERN_ALERT "Interrupt id %x pin %x irq: %d\n", interrupt_no, interrupt_pin, irq);
	}
*/

	pci_set_master(dev);


	mmiowb();

	for ( i = 0; i < 3; i++ ) {
		//r64 = ioread64(&bar0_data[i*8]);
		//iowrite32(0xdeadbeef, &bar0_data[i*4]);
		//wmb();
		
		r32 = ioread32(&bar0_data[i*4]);
		printk(KERN_ALERT "PCIe read: %x (%d)\n", r32, i);
	}
/*
	pci_release_regions(dev);
	pci_disable_device(dev);
	for ( i = 0; i < 32; i++ ) {
		r32 = ioread32(&bar0_data[i*4]);
		printk(KERN_ALERT "PCIe read: %x (%d)\n", r32, i);
	}

	bar0_ptr = ioremap(bar0_addr, 1024*1024); // 1MB...
	request_mem_region(bar0_addr, 1024*1024, "bdbm bar0");
	r32 = ioread32(bar0_ptr);
	iowrite32(0xdeadbeef, bar0_ptr);
	wmb();
	r32n = ioread32(bar0_ptr);
	
	printk(KERN_ALERT "PCIe read: %x @ %x\n", r32, r32n);
	*/
	create_dma_buffer(mmap_buffersize/(1024*4)); // 1 MB / 4KB pages


	return 0;

probe_fail_release_region:
	pci_release_regions(dev);
probe_fail:
	pci_disable_device(dev);
probe_fail_enable:
	return rc;
}

static void pcie_remove( struct pci_dev *dev) {
	printk(KERN_ALERT "Removing BlueDBM PCIe driver\n");

	int i;
	u8* bar0_data;
	bar0_data = (u8*)bar0_ptr;
	for ( i = 0; i < dma_pages_count; i++ ) {
		//unsigned int page_addr = (unsigned long)page_address(dma_pages[i]);
		//pci_unmap_single(pcidev, page_addr, PAGE_SIZE, DMA_BIDIRECTIONAL);
		pci_unmap_single(pcidev, bar0_data[DMA_ADDR_OFFSET + 4*i], PAGE_SIZE, DMA_BIDIRECTIONAL);
		__free_page(dma_pages[i]);
	}
	if (dma_pages != NULL) kfree(dma_pages);
	printk(KERN_ALERT "Freed DMA pages\n");

	pci_clear_master(dev);
	printk(KERN_ALERT "Cleared PCIe master\n");

/*
	disable_irq(irq);
	free_irq(irq, dev);
	printk(KERN_ALERT "Disabled and freed irq\n");

	pci_disable_msi(dev); 
	printk(KERN_ALERT "Disabled MSI\n");
*/
	pci_iounmap(dev, bar0_ptr);
	printk(KERN_ALERT "IOunmap\n");

	pci_release_regions(dev);
	printk(KERN_ALERT "pci_release_regions\n");

	pci_disable_device(dev);
	printk(KERN_ALERT "pci_disable_device\n");
}

static struct pci_driver pci_driver = {
	.name = "bdbmpcie",
	.id_table = pcie_ids,
	.probe = pcie_probe,
	.remove = __exit_p(pcie_remove),
};



/*
// BEGIN mmap buffer for DMA in userspace
static dev_t chrdev_buffer;
static struct cdev cdev_buffer;
static struct class *class_buffer = NULL;

static int cdev_buffer_open(struct inode *inode, struct file *filp) {
	return 0;
}

static int cdev_buffer_mmap(struct file *filp, struct vm_area_struct *vma) {
	return 0;
}

struct file_operations chrdev_fops_buffer = {
	.owner = THIS_MODULE,
	.open = cdev_buffer_open,
	.mmap = cdev_buffer_mmap
};

static int chrdev_buffer_init(void) {
}
*/




/*
static long bdbm_ioctl(struct file* filp, unsigned int cmd, unsigned long arg) {
	if ( cmd == ioctl_alloc_dma ) {
		//FIXME buffers are created by default
		//return create_dma_buffer(arg);
		
		void* pageaddr = kmap(dma_pages[0]);
		unsigned long* lpa = (unsigned long*)pageaddr;
		int i = 0;
		for ( i = 0; i < 8; i++ ) {
			printk(KERN_ALERT "BlueDBM DMA buffer exists! %lx %lx %lx %lx\n", 
				lpa[i*4+0], lpa[i*4+1], lpa[i*4+2], lpa[i*4+3]);
		}
		kunmap(dma_pages[0]);
	}
	if ( cmd == ioctl_refresh_link ) {
		u16 pci_cfg;
		int cpos = 0;
		printk(KERN_ALERT "BlueDBM refresh link IOCTL called\n");
		cpos = pci_pcie_cap(pcidev);
		pci_read_config_word(pcidev, cpos + PCI_EXP_LNKCTL, &pci_cfg);
		//pci_cfg |= PCI_EXP_LNKCTL_RL;
		pci_write_config_word(pcidev, cpos + PCI_EXP_LNKCTL, pci_cfg|PCI_EXP_LNKCTL_LD);
		mdelay(125);
		pci_write_config_word(pcidev, cpos + PCI_EXP_LNKCTL, pci_cfg|PCI_EXP_LNKCTL_RL);
		mdelay(125);
	}
	return 0;
}
*/

static int bdbm_open(struct inode *inode, struct file *filp) {
	return 0;
}
static int bdbm_mmap(struct file *filp, struct vm_area_struct *vma) {
	// First 1MB of the vmem is mapped to the BAR0 address space
	// Next nMB is mapped to the pre-defined page buffer

	unsigned long off = vma->vm_pgoff << PAGE_SHIFT;
	unsigned long vsize = vma->vm_end - vma->vm_start;
	
	//unsigned long bar0_psize = bar0_size - off; // 1MB - offset
	unsigned long physical = bar0_addr + off;

	int i = 0;
	//vma->vm_flags |= VM_RESERVED;

	/*
	if ( vsize > psize ) {
		printk(KERN_ALERT "BlueDBM character device mmap out of bounds\n");
		return -EINVAL;
	}
	*/

	// map BAR0, if applicable
	if ( off < bar0_size ) {
		unsigned int intvsize = bar0_size - off;
		// these are required for io maps, but is it okay for the buffer as well?
		vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
		vma->vm_flags |= VM_IO;
		if ( vsize < intvsize ) intvsize = vsize;
		remap_pfn_range(vma, vma->vm_start, physical>>PAGE_SHIFT, intvsize, vma->vm_page_prot);

		printk(KERN_ALERT "BlueDBM character device mmap to bar0 %lx success physical: %lx off: %lx\n", bar0_addr, physical, off);
	}

	// map buffer, if applicable
	if ( off+vsize > bar0_size ) {
		unsigned int buffoff = bar0_size - off;
		for ( i = 0; i < dma_pages_count; i++ ) {
			unsigned int pageoff = bar0_size + PAGE_SIZE*i;
			if ( pageoff >= off && pageoff+PAGE_SIZE < off+vsize ) {
				unsigned long vmstart = vma->vm_start + buffoff + (PAGE_SIZE*i);
				int res;
				res = vm_insert_page(vma, vmstart, dma_pages[i]);
				//printk(KERN_ALERT "BlueDBM character device mmap page %d %d\n", i, res);
			}
		}
	}


	//remap_pfn_range(vma, vma->vm_start, physical>>PAGE_SHIFT, vsize, vma->vm_page_prot);
	printk(KERN_ALERT "BlueDBM character device mmap from %lx to %lx\n", vma->vm_start, vma->vm_end);
	return 0;
}

DECLARE_WAIT_QUEUE_HEAD(bdbm_poll_wait_queue);

struct semaphore sem_interrupt; //mutex

static DEFINE_SPINLOCK(bdbm_irq_lock);
static unsigned int bdbm_irq_count = 0;
static unsigned int bdbm_irq_ack = 0;
static irqreturn_t interrupt_handler(int irq, void *p) {
	unsigned long flags;
	printk(KERN_ALERT "Interrupt called at irq %d\n", irq);


	spin_lock_irqsave(&bdbm_irq_lock, flags);
	bdbm_irq_count++;
	spin_unlock_irqrestore(&bdbm_irq_lock, flags);

	wake_up(&bdbm_poll_wait_queue);
	return 0;
}


static unsigned int bdbm_poll (struct file *filp, poll_table *wait) {
	unsigned int mask = 0;
	poll_wait(filp, &bdbm_poll_wait_queue, wait);
	//TODO
	if ( bdbm_irq_count > bdbm_irq_ack ) {
		//spin_lock(&bdbm_irq_lock);
		bdbm_irq_ack = bdbm_irq_count;
		//spin_unlock(&bdbm_irq_lock);

		mask |= POLLIN | POLLRDNORM;
	}

	return mask;
}
struct file_operations chrdev_fops = {
	.owner = THIS_MODULE,
	.open = bdbm_open,
	.mmap = bdbm_mmap,
	//.unlocked_ioctl = bdbm_ioctl,
	//.compat_ioctl = bdbm_ioctl,
	.poll = bdbm_poll
};

static dev_t chrdev;
static struct cdev cdev;
static struct class *class = NULL;

static int chrdev_init(void) {
	printk(KERN_ALERT "BlueDBM PCIe chrdev_init\n" );
	int res = 0;
	struct device *device = NULL;
	
	u8* bar0_data;
	u32 r32;

	res = alloc_chrdev_region(&chrdev, 0, 1, "bdbm_regs");
	if ( res < 0 ) {
		return -1;
	}

	cdev_init(&cdev, &chrdev_fops);

	chrdev_major = MAJOR(cdev.dev);
	chrdev_minor = MINOR(cdev.dev);
	/*
	ioctl_alloc_dma = _IOW(chrdev_major, 0, unsigned long);
	printk(KERN_ALERT "IOCTL command - alloc: %x\n", ioctl_alloc_dma );
*/
	res = cdev_add(&cdev, chrdev, 1);

	if ( res ) {
		unregister_chrdev_region(chrdev, 1);
		return res;
	}
	class = class_create(THIS_MODULE, "bdbmpcie");
	device = device_create(class, NULL, chrdev, NULL, "bdbm_regs0");

	//create_dma_buffer(mmap_buffersize/(1024*4)); // 1MB
	
	/*
	// writing ioctl command id to config address
	bar0_data = (u8*)bar0_ptr;
	iowrite32(ioctl_alloc_dma, &bar0_data[4]);
	wmb();
	r32 = ioread32(&bar0_data[4]);
	printk(KERN_ALERT "IOCTL number written: %x\n", r32);
*/

	return 0;
}

static int __init pcie_init(void) {
	int res = 0;
	printk(KERN_ALERT "BlueDBM PCIe driver initializing\n" );
	res = pci_register_driver(&pci_driver);
	if ( res ) {
		printk(KERN_ALERT "BlueDBM PCIe device not found\n");
		return res;
	}
	printk(KERN_ALERT "BlueDBM PCIe register driver success\n" );

	res = chrdev_init();
	if ( res ) {
		printk(KERN_ALERT "BlueDBM character device file creation failed\n");
		return res;
	}
	printk(KERN_ALERT "BlueDBM PCIe driver loaded\n");
	return res;
}

static void __exit pcie_exit(void)
{
	int i;
	u8* bar0_data;
	bar0_data = (u8*)bar0_ptr;
	
	printk(KERN_ALERT "BlueDBM PCIe driver unloading\n");

/*
	for ( i = 0; i < dma_pages_count; i++ ) {
		//unsigned int page_addr = (unsigned long)page_address(dma_pages[i]);
		//pci_unmap_single(pcidev, page_addr, PAGE_SIZE, DMA_BIDIRECTIONAL);
		pci_unmap_single(pcidev, bar0_data[DMA_ADDR_OFFSET + 4*i], PAGE_SIZE, DMA_BIDIRECTIONAL);
		__free_page(dma_pages[i]);
	}
	if (dma_pages != NULL) kfree(dma_pages);
	*/

	printk(KERN_ALERT "BlueDBM PCIe driver unregistering\n");
	pci_unregister_driver(&pci_driver);

	printk(KERN_ALERT "BlueDBM PCIe unregister_chrdev_region\n");
	unregister_chrdev_region(chrdev, 1);

	printk(KERN_ALERT "BlueDBM PCIe cdev_del\n");
	cdev_del(&cdev);
	
	printk(KERN_ALERT "BlueDBM PCIe device_destroy\n");
	device_destroy(class, chrdev);
	
	printk(KERN_ALERT "BlueDBM PCIe class_destroy\n");
	class_destroy(class);
	printk(KERN_ALERT "BlueDBM PCIe driver unloaded\n");
}

module_init(pcie_init);
module_exit(pcie_exit);
