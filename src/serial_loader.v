`default_nettype none
// USB-serial cartridge loader.
//
// While waiting, sends 'R' immediately and then about every 200 ms.
// Host frame: 'L', 32-bit big-endian length, payload, XOR of the payload.
// Length must be 1 .. 4 MiB. A match replies 'K' and sets load_done.
// Anything else replies 'E' and waits for another frame.
// Baud is 921600 8N1 at a 25 MHz clock (27 cycles per bit).
module serial_loader
(
  input  wire        clk,
  input  wire        cpuClockEnable,
  input  wire        reset,
  input  wire        rxd,
  output wire        txd,
  output reg         load_done,
  output wire        weB,
  output wire [23:0] addrB,
  output wire [7:0]  dinB,
  output reg  [31:0] rom_len
);

  localparam [4:0]  CLKS_PER_BIT = 5'd27;
  localparam [4:0]  HALF_BIT     = 5'd13;
  localparam [22:0] R_PERIOD     = 23'd5000000;   // 200 ms at 25 MHz
  localparam [31:0] MAX_LEN      = 32'h00400000;  // 4 MiB

  localparam [2:0]
    S_WAIT  = 3'd0,
    S_LEN   = 3'd1,
    S_DATA  = 3'd2,
    S_CKSUM = 3'd3,
    S_REPLY = 3'd4,
    S_DONE  = 3'd5;

  // ----------------------------------------------------------------
  // RX synchronizer
  // ----------------------------------------------------------------
  reg rx_meta, rx_sync;
  always @(posedge clk) begin
    rx_meta <= rxd;
    rx_sync <= rx_meta;
  end

  // ----------------------------------------------------------------
  // UART RX. Sample the start bit halfway, then every full bit.
  // ----------------------------------------------------------------
  reg       rx_busy = 1'b0;
  reg [4:0] rx_clk_cnt = 5'd0;
  reg [3:0] rx_bit_idx = 4'd0;
  reg [7:0] rx_shift = 8'd0;
  reg       rx_valid = 1'b0;
  reg [7:0] rx_data = 8'd0;

  always @(posedge clk) begin
    rx_valid <= 1'b0;
    if (reset) begin
      rx_busy    <= 1'b0;
      rx_clk_cnt <= 5'd0;
      rx_bit_idx <= 4'd0;
    end else if (!rx_busy) begin
      if (!rx_sync) begin
        rx_busy    <= 1'b1;
        rx_clk_cnt <= 5'd0;
        rx_bit_idx <= 4'd0;
      end
    end else if (rx_bit_idx == 4'd0) begin
      if (rx_clk_cnt == HALF_BIT) begin
        rx_clk_cnt <= 5'd0;
        if (rx_sync)
          rx_busy <= 1'b0;
        else
          rx_bit_idx <= 4'd1;
      end else
        rx_clk_cnt <= rx_clk_cnt + 5'd1;
    end else if (rx_clk_cnt == CLKS_PER_BIT - 5'd1) begin
      rx_clk_cnt <= 5'd0;
      if (rx_bit_idx <= 4'd8) begin
        rx_shift   <= {rx_sync, rx_shift[7:1]};
        rx_bit_idx <= rx_bit_idx + 4'd1;
      end else begin
        rx_busy <= 1'b0;
        if (rx_sync) begin
          rx_data  <= rx_shift;
          rx_valid <= 1'b1;
        end
      end
    end else
      rx_clk_cnt <= rx_clk_cnt + 5'd1;
  end

  // ----------------------------------------------------------------
  // UART TX. Frame is start, 8 data LSB first, stop.
  // ----------------------------------------------------------------
  reg       tx_busy = 1'b0;
  reg [3:0] tx_bits_left = 4'd0;
  reg [9:0] tx_frame = 10'd0;
  reg [4:0] tx_clk_cnt = 5'd0;
  reg       txd_r = 1'b1;
  reg       tx_start = 1'b0;
  reg [7:0] tx_byte = 8'd0;

  assign txd = txd_r;

  always @(posedge clk) begin
    if (reset) begin
      tx_busy      <= 1'b0;
      txd_r        <= 1'b1;
      tx_clk_cnt   <= 5'd0;
      tx_bits_left <= 4'd0;
    end else if (!tx_busy) begin
      txd_r <= 1'b1;
      if (tx_start) begin
        tx_frame     <= {1'b1, tx_byte, 1'b0};
        tx_bits_left <= 4'd10;
        tx_busy      <= 1'b1;
        tx_clk_cnt   <= 5'd0;
        txd_r        <= 1'b0;
      end
    end else if (tx_clk_cnt == CLKS_PER_BIT - 5'd1) begin
      tx_clk_cnt <= 5'd0;
      if (tx_bits_left == 4'd1) begin
        tx_busy <= 1'b0;
        txd_r   <= 1'b1;
      end else begin
        tx_frame     <= {1'b1, tx_frame[9:1]};
        txd_r        <= tx_frame[1];
        tx_bits_left <= tx_bits_left - 4'd1;
      end
    end else
      tx_clk_cnt <= tx_clk_cnt + 5'd1;
  end

  // ----------------------------------------------------------------
  // Loader protocol and SDRAM port-B write handshake.
  // weB stays asserted across the cpuClockEnable low window, which
  // is when the SDRAM controller serves port B.
  // ----------------------------------------------------------------
  reg        old_ce = 1'b0;
  reg [1:0]  loader_write = 2'd0;
  reg        loader_cnt = 1'b0;
  reg [23:0] loader_addr = 24'd0;
  reg [7:0]  loader_data = 8'd0;

  assign weB   = loader_write != 2'd0;
  assign addrB = loader_addr;
  assign dinB  = loader_data;

  reg [2:0]  state = S_WAIT;
  reg        hold_valid = 1'b0;
  reg [7:0]  hold_data = 8'd0;
  reg [1:0]  len_idx = 2'd0;
  reg [31:0] rom_got = 32'd0;
  reg [7:0]  rom_xor = 8'd0;
  reg        reply_ok = 1'b0;
  reg        reply_armed = 1'b0;
  reg [22:0] beacon_cnt = R_PERIOD;
  wire [31:0] len_next = {rom_len[23:0], hold_data};

  always @(posedge clk) begin
    tx_start <= 1'b0;
    old_ce   <= cpuClockEnable;

    if (reset) begin
      state        <= S_WAIT;
      load_done    <= 1'b0;
      hold_valid   <= 1'b0;
      loader_write <= 2'd0;
      loader_cnt   <= 1'b0;
      loader_addr  <= 24'd0;
      len_idx      <= 2'd0;
      rom_len      <= 32'd0;
      rom_got      <= 32'd0;
      rom_xor      <= 8'd0;
      reply_ok     <= 1'b0;
      reply_armed  <= 1'b0;
      beacon_cnt   <= R_PERIOD;
    end else begin
      if (!cpuClockEnable && old_ce && loader_write == 2'd1) begin
        loader_write <= 2'd2;
        loader_cnt   <= 1'b1;
      end
      if (loader_write == 2'd2 && loader_cnt)
        loader_cnt <= 1'b0;
      if (loader_write == 2'd2 && !loader_cnt)
        loader_write <= 2'd0;

      if (state == S_WAIT) begin
        if (beacon_cnt == R_PERIOD) begin
          if (!tx_busy) begin
            tx_byte    <= 8'h52; // 'R'
            tx_start   <= 1'b1;
            beacon_cnt <= 23'd0;
          end
        end else
          beacon_cnt <= beacon_cnt + 23'd1;
      end

      case (state)
        S_WAIT: begin
          if (hold_valid) begin
            hold_valid <= 1'b0;
            if (hold_data == 8'h4C) begin // 'L'
              state   <= S_LEN;
              len_idx <= 2'd0;
              rom_len <= 32'd0;
            end
          end
        end

        S_LEN: begin
          if (hold_valid) begin
            hold_valid <= 1'b0;
            if (len_idx == 2'd3) begin
              rom_got     <= 32'd0;
              rom_xor     <= 8'd0;
              loader_addr <= 24'd0;
              reply_armed <= 1'b0;
              if (len_next == 32'd0 || len_next > MAX_LEN) begin
                reply_ok <= 1'b0;
                state    <= S_REPLY;
              end else begin
                rom_len <= len_next;
                state   <= S_DATA;
              end
            end else begin
              rom_len <= len_next;
              len_idx <= len_idx + 2'd1;
            end
          end
        end

        S_DATA: begin
          if (hold_valid && loader_write == 2'd0) begin
            hold_valid   <= 1'b0;
            loader_data  <= hold_data;
            loader_addr  <= rom_got[23:0];
            loader_write <= 2'd1;
            rom_xor      <= rom_xor ^ hold_data;
            rom_got      <= rom_got + 32'd1;
            if (rom_got + 32'd1 == rom_len)
              state <= S_CKSUM;
          end
        end

        S_CKSUM: begin
          if (hold_valid && loader_write == 2'd0) begin
            hold_valid  <= 1'b0;
            reply_ok    <= (hold_data == rom_xor);
            reply_armed <= 1'b0;
            state       <= S_REPLY;
          end
        end

        S_REPLY: begin
          if (!reply_armed && !tx_busy && loader_write == 2'd0) begin
            tx_byte     <= reply_ok ? 8'h4B : 8'h45; // 'K' or 'E'
            tx_start    <= 1'b1;
            reply_armed <= 1'b1;
            if (reply_ok)
              load_done <= 1'b1;
          end else if (reply_armed && !tx_busy && !tx_start) begin
            if (reply_ok)
              state <= S_DONE;
            else begin
              state      <= S_WAIT;
              beacon_cnt <= R_PERIOD;
              rom_got    <= 32'd0;
              rom_xor    <= 8'd0;
            end
          end
        end

        default: begin
        end
      endcase

      // One-byte skid so a UART byte is not dropped while a
      // SDRAM write is still finishing.
      if (rx_valid) begin
        hold_data  <= rx_data;
        hold_valid <= 1'b1;
      end
    end
  end

endmodule
`default_nettype wire
