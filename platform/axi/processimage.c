/*
 * This test application is to read/write data directly from/to the device 
 * from userspace. 
 * 
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <assert.h>
#include <stdbool.h>

void usage(void) {
	printf("*argv[0] -g <GPIO_ADDRESS> -i|-o <VALUE>\n");
	printf("    -g <GPIO_ADDR>   GPIO physical address\n");
	printf("    -i               Input from GPIO\n");
	printf("    -o <VALUE>       Output to GPIO\n");
	return;
}

typedef struct {
    int cmd;
    int src;
    int dest;
    unsigned int len;
} Conf;

FILE* openImage(char* filename, int* numbytes){
  FILE* infile = fopen(filename, "rb");
  if(infile==NULL){
    printf("File not found %s\n",filename);
    exit(1);
  }
  fseek(infile, 0L, SEEK_END);
  *numbytes = ftell(infile);
  fseek(infile, 0L, SEEK_SET);

  return infile;
}

void loadImage(FILE* infile,  volatile void* address, int numbytes){
  int outlen = fread(address, sizeof(char), numbytes, infile);
  if(outlen!=numbytes){
    printf("ERROR READING\n");
  }

  fclose(infile);
}

bool isPowerOf2(unsigned int x) {
  return x && !(x & (x - 1));
}

// we don't have a standard library... so reimplement this badly
unsigned int mylog2(unsigned int x){
  printf("mylog2\n");
  unsigned int res = 0;
  // find highest true bit
  while(x=x>>1){printf("H%d\n",x);res++;}
  return res;
}

int saveImage(char* filename,  volatile void* address, int numbytes){
  FILE* outfile = fopen(filename, "wb");
  if(outfile==NULL){
    printf("could not open for writing %s\n",filename);
    exit(1);
  }
  int outlen = fwrite(address,1,numbytes,outfile);
  if(outlen!=numbytes){
    printf("ERROR WRITING\n");
  }

  fclose(outfile);
}

int main(int argc, char *argv[]) {
	unsigned gpio_addr = 0x70000000;
	unsigned copy_addr = atoi(argv[1]);

  if(argc!=10){
    printf("ERROR< insufficient args. Should be: addr inputFilename outputFilename scaleNumerator scaleDenom inputBytesPerPixel outputBytesPerPixel outputW outH\n");
    exit(1);
  }

  // dirty tricks: we want to support both upsamples and downsamples.
  // We use 4 bits to store the amount we shift the input size.
  // So, can shift the input size by 2^4-1=15 bits.
  // When shift==0, we shift by 8 bits left, resulting in a 256x upsample.
  // When shift==8, we shift an aggreagte of 0 bits.
  // when shift=15, we shift an aggregate of 7 bits, 128x downsample.
  unsigned int scaleN = atoi(argv[4]);
  unsigned int scaleD = atoi(argv[5]);

  unsigned int inputBytesPerPixel = atoi(argv[6]);
  unsigned int outputBytesPerPixel = atoi(argv[7]);

  unsigned int outputW = atoi(argv[8]);
  unsigned int outputH = atoi(argv[9]);

  //unsigned int downsample = downsampleX*downsampleY;
  //unsigned int downsampleShift = mylog2(downsample);
  //printf("DSX %d DSY %d DS %d DSS %d\n",downsampleX,downsampleY,downsample,downsampleShift);
  //  assert(scaleN==1 || scaleD==1);
  // b/c we send the shift, only power of two scales are supported
  //  assert(isPowerOf2(scaleN) && isPowerOf2(scaleD));
  
  int downsampleShift=0;
  //  if(scaleN==1){
    // a downsample
  //    downsampleShift = mylog2(scaleD)+8;
  //  }else if(scaleD==1){
    // a upsample
  //    downsampleShift = 8-mylog2(scaleN);
  //  }
  //assert( downsampleShift>=0 && downsampleShift<16 );
  printf("Scale %d/%d, shift:%d\n",scaleN,scaleD,downsampleShift);
  
	unsigned page_size = sysconf(_SC_PAGESIZE);

	printf("GPIO access through /dev/mem. %d\n", page_size);

	if (gpio_addr == 0) {
		printf("GPIO physical address is required.\n");
		usage();
		return -1;
	}
	
	int fd = open ("/dev/mem", O_RDWR | O_SYNC );
	if (fd < 1) {
		perror(argv[0]);
		return -1;
  }

  unsigned lenInRaw;
  FILE* imfile = openImage(argv[2], &lenInRaw);
  printf("file LEN %d\n",lenInRaw);
  
  //unsigned ln = (lenInRaw*scaleN*outputBytesPerPixel);
  //unsigned ld = (scaleD*inputBytesPerPixel);
  //assert(ln%ld==0);
  //unsigned lenOutRaw = ln/ld;

  unsigned int lenIn = lenInRaw;
  unsigned int lenOut = outputW*outputH*outputBytesPerPixel;

  if (lenIn%(8*16)!=0){
    lenIn = lenInRaw + (8*16-(lenInRaw % (8*16)));
  }

  //if (lenOut%(8*16)!=0){
  //  lenOut = lenOutRaw + (8*16-(lenOutRaw % (8*16)));
  //}
 

  // extra axi burst of metadata
  lenOut = lenOut + 128;

  // we pad out the length to 128 bytes as required, but just leave it filled with garbage.
  // pad the smallest of the input/output, and upscale the padded size
  //  if(lenOutRaw<=lenInRaw){ // a downscale
  //    lenOut = lenOutRaw + (8*16-(lenOutRaw % (8*16)));
  ///    lenIn = (lenOut*scaleD*inputBytesPerPixel)/(scaleN*outputBytesPerPixel);
  //  }else{ // scaleD==1, a upsample
  //    lenIn = lenInRaw + (8*16-(lenInRaw % (8*16)));
  //    lenOut = (lenIn*scaleN*outputBytesPerPixel)/(scaleD*inputBytesPerPixel);
  //  }

  printf("LENOUT %d\n", lenOut);
  assert(lenIn % (8*16) == 0);
  printf("LENIN %d\n",lenIn);
  assert(lenOut % (8*16) == 0);

  printf("mapping %08x\n",copy_addr);
  void * ptr = mmap(NULL, lenIn+lenOut, PROT_READ|PROT_WRITE, MAP_SHARED, fd, copy_addr);
  if(ptr==(void *) -1){
    printf("Error mmaping\n");
    exit(1);
  }

  loadImage( imfile, ptr, lenInRaw );
  //memset(ptr+len,0,len);
  // zero out the output region
  for(int i=0; i<lenOut; i++){ *(unsigned char*)(ptr+lenIn+i)=0; }
  //saveImage("before.raw",ptr,len);

  // mmap the device into memory 
  // This mmaps the control region (the MMIO for the control registers).
  // Image data is located at addr 'copy_addr'
  void * gpioptr = mmap(NULL, page_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, gpio_addr);
  if(gpioptr==(void *) -1){
    printf("Error mmaping gpio\n");
    exit(1);
  }
  
  // this sleep is needed for the z100, but not the z20
  sleep(2);

  volatile Conf * conf = (Conf*) gpioptr;

  conf->src = copy_addr;
  conf->dest = copy_addr + lenIn;
  unsigned int lenPacked = lenIn | (downsampleShift << 28);
  printf("LEN PACKED %d\n",lenPacked);
  conf->len = lenPacked;
  conf->cmd = 3;

  //usleep(10000);
  sleep(2); // this sleep needs to be 2 for the z100, but 1 for the z20

  saveImage(argv[3],ptr+lenIn,lenOut);
  //saveImage(argv[3],ptr,lenRaw);

  return 0;
}


