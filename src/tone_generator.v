module tone_generator
  (
   input       clk,
   input       clk_div16_en,
   input       reset,
   input [9:0] freq,
   output      audio_out
   );

   reg [9:0]   count;
   reg         tone;

   parameter init = 0;
   
   // Half-period is the register value, in clk/16 ticks:
   // f = clk / (32 * freq). Zero holds the output high (no tone).
   always @(posedge clk or posedge reset)
     if(reset)
       begin
          count <= init;
          tone  <= 1'b0;
       end
     else if (clk_div16_en)
       begin
          if (freq == 0)
            begin
               count <= 0;
               tone  <= 1'b1;
            end
          else if (count <= 1)
            begin
               count <= freq;
               tone  <= !tone;
            end
          else
            count <= count - 1'b1;
       end

   // assign output
   assign audio_out = tone;

endmodule
