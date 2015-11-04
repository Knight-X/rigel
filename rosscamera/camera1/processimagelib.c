
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <assert.h>
#include <stdbool.h>
#include "processimagelib.h"


void write_mmio(volatile Conf* conf, int offset, uint32_t data, int verbose) {
    if(verbose) {
        printf("MMIO WRITE: 0x%x to offset %x\n",data,offset);
        fflush(stdout);
    }
    conf->mmio[offset] = data;
}

uint32_t read_mmio(volatile Conf* conf, int offset, int verbose) {
    uint32_t data = conf->mmio[offset];
    if (verbose) {
        printf("MMIO READ: 0x%x from addr %x\n",data,offset);
        fflush(stdout);
    }
    return data;
}

void poll_mmio(volatile Conf* conf, int offset, uint32_t val) {
    uint32_t data;
    do {
        data = read_mmio(conf,offset,0);
    } while (data != val);
}

void print_debug_regs(volatile Conf* conf) {
    read_mmio(conf, MMIO_DEBUG(0),1);
    read_mmio(conf, MMIO_DEBUG(1),1);
    read_mmio(conf, MMIO_DEBUG(2),1);
    read_mmio(conf, MMIO_DEBUG(3),1);
}

// cam_data should contain the cam addr in the lowest byte
uint32_t read_cam_reg(volatile Conf* conf, uint32_t cam_data) {

    //cam data should only contain 8 bits
    if (cam_data & 0xFFFFFF00) {
        printf("ERROR: Bad cam addr! needs to be 1 byte\n");
        exit(1);
    }
    cam_data = (cam_data<<8); //bit 16 needs to be 0
    uint32_t cam_resp_cnt = read_mmio(conf, MMIO_CAM_RESP_CNT,0);
    //printf("cam_resp_cnt=%d\n",cam_resp_cnt);
    write_mmio(conf,MMIO_CAM_CMD, cam_data,0);
    // Wait for response (CAM_RESP_CNT will increment
    //poll_mmio(conf, MMIO_CAM_RESP_CNT, cam_resp_cnt+1);
    uint32_t cnt = 0;
    do {
        cnt = read_mmio(conf, MMIO_CAM_RESP_CNT,0);
    } while (cnt != cam_resp_cnt+1);
    read_mmio(conf, MMIO_DEBUG(0),0);
    
    uint32_t cam_resp = read_mmio(conf, MMIO_CAM_RESP,0);
    printf("RD: Addr 0x%02x, data 0x%02x\n",cam_data>>8,(cam_resp)&0x000000FF);
    //Error checking
    // first 16:8 bits should be the same as cam_data;
    if ((cam_data & 0x0001FF00)!=(cam_resp & 0x0001FF00)) {
        printf("ERROR: cam response is not the same as cam_data!!\n");
        //exit(1);
    }
    //check that the error is not set
    if ((cam_data & 0x00020000) != (cam_resp & 0x00020000) ) {
        printf("ERROR: Cam response reports an error! Did you write before checking the response??\n");
        //exit(1);
    }
    fflush(stdout);
    return (cam_resp & 0x000000FF);
}

void write_cam_reg(volatile Conf* conf, uint32_t cam_data) {
    //cam data should only contain 16 bits
    if (cam_data & 0xFFFF0000) {
        printf("ERROR:Bad cam reg data! %x should be 1byte addr, 1byte data\n",cam_data);
        exit(1);
    }
    cam_data |= 0x10000; //bit 16 is the write cmd
    uint32_t cam_resp_cnt = read_mmio(conf, MMIO_CAM_RESP_CNT,0);
    write_mmio(conf,MMIO_CAM_CMD, cam_data,0);
    // Wait for response (CAM_RESP_CNT will increment
    uint32_t cnt = 0;
    do {
        cnt = read_mmio(conf, MMIO_CAM_RESP_CNT,1);
    } while (cnt != cam_resp_cnt+1);
    read_mmio(conf, MMIO_DEBUG(0),0);
    uint32_t cam_resp = read_mmio(conf, MMIO_CAM_RESP,0);
    printf("WR: Addr 0x%02x, data 0x%02x\n",(cam_data>>8)&0x000000FF,(cam_resp)&0x000000FF);
    //Error checking
    // first 16 bits should be the same as cam_data;
    if ((cam_data & 0x0001FFFF)!=(cam_resp & 0x0001FFFF)) {
        printf("ERROR: cam response is not the same as cam_data!!\n");
        //exit(1);
    }
    //check that the error is not set
    if ((cam_data & 0x00020000) != (cam_resp & 0x00020000) ) {
        printf("ERROR:Cam response reports an error! Did you write before checking the response??\n");
        //exit(1);
    }
    fflush(stdout);
}
void write_cam_safe(volatile Conf* conf, uint32_t cam_data) {
    write_cam_reg(conf,cam_data);
    uint32_t cam_a = 0x000000FF & (cam_data>>8);
    uint32_t cam_d = 0x000000FF & (cam_data);
    uint32_t rd = read_cam_reg(conf,cam_a);
    if(cam_d != rd) {
        printf("ERROR:\nExpt: %08x\nRead:%08x\n",cam_data,rd);
        exit(1);
    }
}


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
    printf("Saving image %s, at address %p, with numbytes %d, bytes written %d\n",filename,address, numbytes,outlen);
    fclose(outfile);
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

