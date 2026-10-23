`default_nettype none
module sdram_card_loader
(
  input  wire        clk,
  input  wire        cpuClockEnable,
  input  wire        reset,

  input  wire        byte_wstrb,
  input  wire [7:0]  byte_data,

  input  wire        set_mapper,
  input  wire        mapper_cm,

  input  wire [31:0] rom_length,
  input  wire        finalize,

  output wire        weB,
  output wire [23:0] addrB,
  output wire [7:0]  dinB,

  output reg         load_done,
  output reg         codemasters,
  output reg  [31:0] rom_len
);

  reg        old_ce = 1'b0;
  reg [1:0]  loader_write = 2'd0;
  reg        loader_cnt = 1'b0;
  reg [23:0] write_addr = 24'd0;
  reg [7:0]  write_data = 8'd0;

  assign weB   = loader_write != 2'd0;
  assign addrB = write_addr;
  assign dinB  = write_data;

  always @(posedge clk) begin
    old_ce <= cpuClockEnable;

    if (reset) begin
      loader_write <= 2'd0;
      loader_cnt   <= 1'b0;
      write_addr   <= 24'd0;
      load_done    <= 1'b0;
      codemasters  <= 1'b0;
      rom_len      <= 32'd0;
    end else begin
      if (!cpuClockEnable && old_ce && loader_write == 2'd1) begin
        loader_write <= 2'd2;
        loader_cnt   <= 1'b1;
      end
      if (loader_write == 2'd2 && loader_cnt)
        loader_cnt <= 1'b0;
      if (loader_write == 2'd2 && !loader_cnt) begin
        loader_write <= 2'd0;
        write_addr   <= write_addr + 24'd1;
      end

      if (set_mapper)
        codemasters <= mapper_cm;

      if (byte_wstrb && loader_write == 2'd0) begin
        write_data   <= byte_data;
        loader_write <= 2'd1;
      end

      if (finalize && !load_done) begin
        rom_len   <= rom_length;
        load_done <= 1'b1;
      end
    end
  end

endmodule
`default_nettype wire
