`include "macros.vh"
module top
  (
    inout [53:0] MIO,
    inout PS_SRSTB,
    inout PS_CLK,
    inout PS_PORB,
    inout DDR_Clk,
    inout DDR_Clk_n,
    inout DDR_CKE,
    inout DDR_CS_n,
    inout DDR_RAS_n,
    inout DDR_CAS_n,
    output DDR_WEB,
    inout [2:0] DDR_BankAddr,
    inout [14:0] DDR_Addr,
    inout DDR_ODT,
    inout DDR_DRSTB,
    inout [31:0] DDR_DQ,
    inout [3:0] DDR_DM,
    inout [3:0] DDR_DQS,
    inout [3:0] DDR_DQS_n,
    inout DDR_VRN,
    inout DDR_VRP,

    // Camera IO
    input [9:2] CAM_DIN,
    input CAM_VSYNC,
    input CAM_HREF,
    output CAM_PWDN,
    input CAM_PCLK,
    output CAM_XCLK,
    output CAM_SIO_C,
    inout CAM_SIO_D,   //TODO This needs a 4.7k pullup
 
    output VGA_VS_n,
    output VGA_HS_n,
  
    output [7:0] LED,

    output [2:0] VGA_red,
    output [2:0] VGA_green,
    output [1:0] VGA_blue
   
    //output [7:0] VGA_red,
    //output [7:0] VGA_green,
    //output [7:0] VGA_blue



  );

    


    `include "ps7_include.v";

    wire FCLK0;
    BUFG bufg0(.I(FCLKCLK[0]),.O(FCLK0));
    wire FCLK1;
    BUFG bufg1(.I(FCLKCLK[1]),.O(FCLK1));
    
    wire rst_n;
    assign ARESETN = FCLKRESETN[0];
    assign rst_n = ARESETN;
    
    wire CLK_25M;
    wire CLK_24M;
    wire CLK_48M;
   
      
    ClkCtrl clks(
        .CLKIN_100M(FCLK0),
        .CLKIN_96M(FCLK1),
        .CLK_25M(CLK_25M),
        .CLK_24M(CLK_24M),
        .CLK_48M(CLK_48M),
        .rst_n(rst_n)
    );
    
    reg [31:0] debug_cnt;
    `REG(CLK_25M, debug_cnt, 2, debug_cnt+1'b1)


    wire XCLK_DIV;
    
    wire [31:0] MMIO_CMD;
  
    // debug counters
    
    wire [31:0] cam_debug[3:0];
    wire [31:0] STREAMBUF_NBYTES;
    wire [31:0] STREAMBUF_ADDR;
    wire [31:0] FRAME_BYTES;
    wire [31:0] VGABUF_ADDR;
    
    wire [7:0] display_debug;
    //assign LED[7:0] = display_debug[7:0];
    //assign LED[7:4] = cam_debug[0][25:22];
    //assign LED[3:0] = cam_debug[1][25:22];
    
    wire [16:0] rw_cmd;
    wire rw_cmd_valid;
    wire [17:0] rw_resp;
    wire rw_resp_valid;
    MMIO_slave mmio(
        .fclk(FCLK0),
        .rst_n(rst_n),
        .S_AXI_ACLK(S2M_GP0_AXI_ACLK),
        .S_AXI_ARADDR(S2M_GP0_AXI_ARADDR), 
        .S_AXI_ARID(S2M_GP0_AXI_ARID),  
        .S_AXI_ARREADY(S2M_GP0_AXI_ARREADY), 
        .S_AXI_ARVALID(S2M_GP0_AXI_ARVALID), 
        .S_AXI_AWADDR(S2M_GP0_AXI_AWADDR), 
        .S_AXI_AWID(S2M_GP0_AXI_AWID), 
        .S_AXI_AWREADY(S2M_GP0_AXI_AWREADY), 
        .S_AXI_AWVALID(S2M_GP0_AXI_AWVALID), 
        .S_AXI_BID(S2M_GP0_AXI_BID), 
        .S_AXI_BREADY(S2M_GP0_AXI_BREADY), 
        .S_AXI_BRESP(S2M_GP0_AXI_BRESP), 
        .S_AXI_BVALID(S2M_GP0_AXI_BVALID), 
        .S_AXI_RDATA(S2M_GP0_AXI_RDATA), 
        .S_AXI_RID(S2M_GP0_AXI_RID), 
        .S_AXI_RLAST(S2M_GP0_AXI_RLAST), 
        .S_AXI_RREADY(S2M_GP0_AXI_RREADY), 
        .S_AXI_RRESP(S2M_GP0_AXI_RRESP), 
        .S_AXI_RVALID(S2M_GP0_AXI_RVALID), 
        .S_AXI_WDATA(S2M_GP0_AXI_WDATA), 
        .S_AXI_WREADY(S2M_GP0_AXI_WREADY), 
        .S_AXI_WSTRB(S2M_GP0_AXI_WSTRB), 
        .S_AXI_WVALID(S2M_GP0_AXI_WVALID),
        .MMIO_READY(1'b1),
        .MMIO_CMD(MMIO_CMD),
        .STREAMBUF_NBYTES(STREAMBUF_NBYTES[31:0]),
        .STREAMBUF_ADDR(STREAMBUF_ADDR[31:0]),
        .FRAME_BYTES(FRAME_BYTES),
        .VGABUF_ADDR(VGABUF_ADDR),
        .MMIO_STATUS(32'h0),
        .debug0(cam_debug[0]),
        .debug1(cam_debug[3]),
        .debug2(debug_cnt),
        .debug3(wfd_cnt[31:0]),
        .rw_cmd(rw_cmd[16:0]),  //{rw,addr,data}
        .rw_cmd_valid(rw_cmd_valid), 
        .rw_resp(rw_resp[17:0]),// {err,rw,addr,data}
        .rw_resp_valid(rw_resp_valid),
        
        .MMIO_IRQ()
    );

    wire wr_sync; // Allows you to sync frames
    wire wr_frame_valid;
    wire wr_frame_ready;
    wire [31:0] wr_FRAME_BYTES;
    wire [31:0] wr_BUF_ADDR;
    wire wr_frame_done;

    //Read interface (VGA)
    wire rd_sync; // allows you to sync frame reads
    wire rd_frame_valid;
    wire rd_frame_ready;
    wire [31:0] rd_FRAME_BYTES;
    wire [31:0] rd_BUF_ADDR;
    wire rd_frame_done;

    assign wr_sync = 1;
    assign rd_sync = 1;

    wire [1:0] wr_ptr;
    wire [1:0] wr_cs;
    wire [1:0] rd_cs;
    wire [1:0] rd_ptr;
    wire [1:0] wr_astate;
    wire [1:0] rd_astate;

    assign LED[7:4] = {wr_cs[1:0], wr_astate[1:0]};
    assign LED[3:0] = {rd_cs[1:0], rd_astate[1:0]};
    
    tribuf_ctrl tribuf_ctrl_inst(

        .fclk(FCLK0),
        .rst_n(rst_n),

        //MMIO interface
        .MMIO_CMD(MMIO_CMD[31:0]),
        .FRAME_BYTES(FRAME_BYTES[31:0]),
        .TRIBUF_ADDR(VGABUF_ADDR[31:0]),

        //Write interface (final renderer)
        
        .wr_sync(wr_sync),
        .wr_frame_valid(wr_frame_valid),
        .wr_frame_ready(wr_frame_ready),
        .wr_FRAME_BYTES(wr_FRAME_BYTES[31:0]),
        .wr_BUF_ADDR(wr_BUF_ADDR[31:0]),
        .wr_frame_done(wr_frame_done),
        //Read interface (VGA)
        .rd_sync(rd_sync),
        .rd_frame_valid(rd_frame_valid),
        .rd_frame_ready(rd_frame_ready),
        .rd_FRAME_BYTES(rd_FRAME_BYTES[31:0]),
        .rd_BUF_ADDR(rd_BUF_ADDR[31:0]),
        .rd_frame_done(rd_frame_done),

        .debug_wr_ptr(wr_ptr[1:0]),
        .debug_wr_cs(wr_cs[1:0]),
        .debug_rd_cs(rd_cs[1:0]),
        .debug_rd_ptr(rd_ptr[1:0])
    );

    reg [31:0] wfd_cnt;
    `REG(FCLK0, wfd_cnt[31:0], 0, wfd_cnt + wr_frame_done)

    wire startall;
    wire stopall;
    assign startall = (MMIO_CMD == `CMD_START);
    assign stopall = (MMIO_CMD == `CMD_STOP);

    wire [63:0] cam2dramw_data;
    wire cam2dramw_valid;
    wire cam2dramw_burst_valid;
    wire cam2dramw_ready;

    CamOV7660 camOV7660_inst(
        //general
        .fclk(FCLK0),
        .CLK_24M(CLK_24M),
        .CLK_48M(CLK_48M),
        .rst_n(rst_n),
        // Camera IO
        .CAM_DIN(CAM_DIN[9:2]),
        .CAM_VSYNC(CAM_VSYNC),
        .CAM_HREF(CAM_HREF),
        .CAM_PWDN(CAM_PWDN),
        .CAM_PCLK(CAM_PCLK),
        .CAM_XCLK(CAM_XCLK),
        .CAM_SIO_C(CAM_SIO_C),
        .CAM_SIO_D(CAM_SIO_D),
        //Camera register setup
        
        .rw_cmd(rw_cmd[16:0]),  //{rw,addr,data}
        .rw_cmd_valid(rw_cmd_valid), 
        .rw_resp(rw_resp[17:0]),// {err,rw,addr,data}
        .rw_resp_valid(rw_resp_valid),
        
        //camera stream ctrl
        .cam_cmd(`CMD_START),
        .cam_cmd_valid(startall),
        .cam_cmd_ready(),
        //camera output
        
        .sdata_burst_valid(cam2dramw_burst_valid),
        .sdata_valid(cam2dramw_valid),
        .sdata_ready(cam2dramw_ready),
        .sdata(cam2dramw_data[63:0]),
        
        // debug signals
        .debug0(cam_debug[0]),
        .debug1(cam_debug[1]),
        .debug2(cam_debug[2]),
        .debug3(cam_debug[3])
    );


    DramWriter cam_writer1(
        .fclk(FCLK0),
        .rst_n(rst_n),
        
        .M2S_AXI_ACLK(M2S_HP0_AXI_ACLK),
        .M2S_AXI_AWADDR(M2S_HP0_AXI_AWADDR),
        .M2S_AXI_AWREADY(M2S_HP0_AXI_AWREADY),
        .M2S_AXI_AWVALID(M2S_HP0_AXI_AWVALID),
        .M2S_AXI_WDATA(M2S_HP0_AXI_WDATA),
        .M2S_AXI_WREADY(M2S_HP0_AXI_WREADY),
        .M2S_AXI_WVALID(M2S_HP0_AXI_WVALID),
        .M2S_AXI_WLAST(M2S_HP0_AXI_WLAST),
        .M2S_AXI_WSTRB(M2S_HP0_AXI_WSTRB),
        
        .M2S_AXI_BRESP(M2S_HP0_AXI_BRESP),
        .M2S_AXI_BREADY(M2S_HP0_AXI_BREADY),
        .M2S_AXI_BVALID(M2S_HP0_AXI_BVALID),
        
        .M2S_AXI_AWLEN(M2S_HP0_AXI_AWLEN),
        .M2S_AXI_AWSIZE(M2S_HP0_AXI_AWSIZE),
        .M2S_AXI_AWBURST(M2S_HP0_AXI_AWBURST),
        
        .wr_frame_valid(wr_frame_valid),
        .wr_frame_ready(wr_frame_ready),
        .wr_FRAME_BYTES(wr_FRAME_BYTES[31:0]),
        .wr_BUF_ADDR(wr_BUF_ADDR[31:0]),
    
        .debug_astate(wr_astate[1:0]),


        .din_burst_valid(cam2dramw_burst_valid),
        .din_valid(cam2dramw_valid),
        .din_ready(cam2dramw_ready),
        .din(cam2dramw_data[63:0])
    );
    


    wire [31:0] cur_vga_addr;
    wire [7:0] VGA_red_full;
    wire [7:0] VGA_green_full;
    wire [7:0] VGA_blue_full;

    wire [31:0] vga_cmd;
    wire vga_cmd_valid;
    assign vga_cmd = startall ? `CMD_START : stopall ? `CMD_STOP : 32'h0;
    assign vga_cmd_valid = startall | stopall;
    
    wire dramr2display_burst_ready;
    wire dramr2display_valid;
    wire dramr2display_ready;
    wire [63:0] dramr2display_data;

    
    DramReader vga_reader(
        .fclk(FCLK0),
        .rst_n(rst_n),
        
        .M2S_AXI_ACLK(), // clock is already driven
        .M2S_AXI_ARADDR(M2S_HP0_AXI_ARADDR),
        .M2S_AXI_ARREADY(M2S_HP0_AXI_ARREADY),
        .M2S_AXI_ARVALID(M2S_HP0_AXI_ARVALID),
        .M2S_AXI_RDATA(M2S_HP0_AXI_RDATA),
        .M2S_AXI_RREADY(M2S_HP0_AXI_RREADY),
        .M2S_AXI_RRESP(M2S_HP0_AXI_RRESP),
        .M2S_AXI_RVALID(M2S_HP0_AXI_RVALID),
        .M2S_AXI_RLAST(M2S_HP0_AXI_RLAST),
        .M2S_AXI_ARLEN(M2S_HP0_AXI_ARLEN),
        .M2S_AXI_ARSIZE(M2S_HP0_AXI_ARSIZE),
        .M2S_AXI_ARBURST(M2S_HP0_AXI_ARBURST),
        
        .rd_frame_valid(rd_frame_valid),
        .rd_frame_ready(rd_frame_ready),
        .rd_FRAME_BYTES(rd_FRAME_BYTES[31:0]),
        .rd_BUF_ADDR(rd_BUF_ADDR[31:0]),

        .debug_astate(rd_astate[1:0]),

        .dout_burst_ready(dramr2display_burst_ready),
        .dout_ready(dramr2display_ready),
        .dout_valid(dramr2display_valid),
        .dout(dramr2display_data[63:0])
    );
 
    
    
    
    display vga_display(
        .fclk(FCLK0),
        .rst_n(rst_n),
        .vgaclk(CLK_25M),
        
        .vga_cmd(vga_cmd),
        .vga_cmd_valid(vga_cmd_valid),
        .vga_cmd_ready(),

        .VGA_VS_n(VGA_VS_n),
        .VGA_HS_n(VGA_HS_n),
        .VGA_red(VGA_red_full[7:0]),
        .VGA_green(VGA_green_full[7:0]),
        .VGA_blue(VGA_blue_full[7:0]),
    
        .sdata_burst_ready(dramr2display_burst_ready),
        .sdata_valid(dramr2display_valid),
        .sdata_ready(dramr2display_ready),
        .sdata(dramr2display_data[63:0]),

        .debug(display_debug[7:0])
    );
    
    assign VGA_red[2:0] = VGA_red_full[7:5];
    assign VGA_green[2:0] =VGA_green_full[7:5];
    assign VGA_blue[1:0] = VGA_blue_full[7:6];


/*
  always @(posedge FCLK0 or negedge ARESETN) begin
    if(ARESETN == 0)
        LED <= 0;
    else if(MMIO_VALID)
        LED <= {MMIO_CMD[1:0],STREAM_SRC[2:0],STREAM_DEST[2:0]};
  end

  wire [63:0] pipelineInput;
  wire       pipelineInputValid;
   
  wire [64:0] pipelineOutputPacked;
  wire [63:0] pipelineOutput;
//  assign pipelineOutput = pipelineOutputPacked[63:0];   
  wire pipelineOutputValid;
//  assign pipelineOutputValid = pipelineOutputPacked[64];
   
  wire       pipelineReady;
  wire      downstreamReady;

  ___PIPELINE_TAPS
    
  ___PIPELINE_MODULE_NAME  #(.INPUT_COUNT(___PIPELINE_INPUT_COUNT),.OUTPUT_COUNT(___PIPELINE_OUTPUT_COUNT)) pipeline(.CLK(FCLK0),.reset(MMIO_READY),.ready(pipelineReady),.ready_downstream(downstreamReady),.process_input({pipelineInputValid,___PIPELINE_INPUT}),.process_output(pipelineOutputPacked));

   UnderflowShim #(.WAIT_CYCLES(___PIPELINE_WAIT_CYCLES)) OS(.CLK(FCLK0),.RST(MMIO_READY),.lengthOutput(lengthOutput),.inp(pipelineOutputPacked[63:0]),.inp_valid(pipelineOutputPacked[64]),.out(pipelineOutput),.out_valid(pipelineOutputValid));
  */

endmodule : top

//-----------------------------------------------------------------------------
// system.v
//-----------------------------------------------------------------------------

// The axi bus expects the number of valid data items to exactly match the # of addresses we send.
// This module checks for underflow (too few valid data items). If there are too few, it inserts DEADBEEFs to make it correct.
// lengthOutput is in bytes

module UnderflowShim(input CLK, input RST, input [31:0] lengthOutput, input [63:0] inp, input inp_valid, output [63:0] out, output out_valid);
   parameter WAIT_CYCLES = 2048;
   
   reg [31:0] outCnt;
   reg [31:0] outLen;

   reg        fixupMode;
   reg [31:0]  outClks = 0;
   
   
   always@(posedge CLK) begin
     if (RST) begin 
        outCnt <= 32'd0;
        outLen <= lengthOutput;
        fixupMode <= 1'b0;
        outClks <= 32'd0;
     end else begin
        outClks <= outClks + 32'd1;
        
        if(inp_valid || fixupMode) begin outCnt <= outCnt+32'd8; end // AXI does 8 bytes per clock
        if(outClks > WAIT_CYCLES) begin fixupMode <= 1'b1; end
     end
   end

   assign out = (fixupMode) ? (64'hDEAD_BEEF) : (inp);
   assign out_valid = (RST)?(1'b0):((fixupMode)?(outCnt<outLen):(inp_valid));
endmodule // OutputShim



