/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 28-2-2019 */

// The best use case is with addr_ok going down and up for each addr change
// but it works too with addr_ok permanently high as long as addr input is
// not changed until the data_ok signal is produced. If the requester cannot
// guarantee that, it should toggle addr_ok for each request

module jtframe_romrq #(parameter
    AW=18,
    DW=8,
    REPACK=0    // do not let data from SDRAM pass thru without repacking (latching) it
                // 0 = data is let pass thru
                // 1 = data gets repacked (adds one clock of latency)
)(
    input               rst,
    input               clk,
    input               clr, // clears the cache
    input [21:0]        offset,
    input [AW-1:0]      addr,
    input               addr_ok,    // signals that value in addr is valid
    input [31:0]        din,
    input               din_ok,
    input               we,
    output reg          req,
    output reg          data_ok,    // strobe that signals that data is ready
    output     [21:0]   sdram_addr,
    output reg [DW-1:0] dout
);

reg [AW-1:0] addr_req;

reg [AW-1:0] cached_addr0;
reg [AW-1:0] cached_addr1;
reg [31:0]   cached_data0;
reg [31:0]   cached_data1;
reg [1:0]    subaddr;
reg [1:0]    good;
reg          hit0, hit1;
wire         passthru;

wire  [21:0] size_ext = { {22-AW{1'b0}}, addr_req };
assign sdram_addr = (DW==8?(size_ext>>1):size_ext ) + offset;
assign passthru   = din_ok && we && !REPACK[0];

always @(*) begin
    case(DW)
        8:  addr_req = {addr[AW-1:2],2'b0};
        16: addr_req = {addr[AW-1:1],1'b0};
        32: addr_req = addr;
    endcase
    // It is important to leave === for simulations, instead of ==
    // It shouldn't have any implication for synthesis
    hit0 = addr_req === cached_addr0 && good[0] && !clr;
    hit1 = addr_req === cached_addr1 && good[1] && !clr;
    req = (clr || ( !(hit0 || hit1) && !we)) && addr_ok;
end

// reg [1:0] ok_sr;

always @(posedge clk, posedge rst)
    if( rst ) begin
        good         <= 'd0;
        cached_data0 <= 'd0;
        cached_data1 <= 'd0;
        cached_addr0 <= 'd0;
        cached_addr1 <= 'd0;
    end else begin
        if( clr ) good <= 2'b00;
        data_ok <= addr_ok && ( hit0 || hit1 || passthru );
        if( we && din_ok ) begin
            cached_data1 <= cached_data0;
            cached_addr1 <= cached_addr0;
            cached_data0 <= din;
            cached_addr0 <= addr_req;
            good <= { good[0], 1'b1 };
        end
    end

always @(*) begin
    subaddr[1] = addr[1];
    subaddr[0] = addr[0];
end

// data_mux selects one of two cache registers
// but if we are getting fresh data, it selects directly the new data
// this saves one clock cycle at the expense of more LUTs
wire [31:0] data_mux = passthru ? din :
    (hit0 ? cached_data0 : cached_data1);

generate
    if(DW==8) begin
        always @(*)
        case( subaddr )
            2'd0: dout = data_mux[ 7: 0];
            2'd1: dout = data_mux[15: 8];
            2'd2: dout = data_mux[23:16];
            2'd3: dout = data_mux[31:24];
        endcase
    end else if(DW==16) begin
        always @(*)
        case( subaddr[0] )
                1'd0: dout = data_mux[15:0];
                1'd1: dout = data_mux[31:16];
        endcase
    end else always @(*) dout = data_mux;
endgenerate

`ifdef JTFRAME_SDRAM_STATS
jtframe_romrq_stats u_stats(
    .clk    ( clk       ),
    .rst    ( rst       ),
    .req    ( req       ),
    .we     ( we        ),
    .din_ok ( din_ok    ),
    .data_ok( data_ok   )
);
`endif

`ifdef SIMULATION
reg [AW-1:0] last_addr;
reg          waiting, last_req;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        waiting <= 0;
        last_req <= 0;
    end else begin
        last_req <= req;
        if( req && !last_req ) begin
            if( waiting ) begin
                $display("ERROR: %m new request without finishing the previous");
                $finish;
            end
            last_addr <= addr;
            waiting <= 1;
        end
        if( din_ok ) waiting <= 0;
        if( waiting && !addr_ok ) begin
            $display("ERROR: %m data request interrupted");
            $finish;
        end
        if( addr != last_addr && addr_ok) begin
            if( waiting ) begin
                $display("ERROR: %m address changed");
                $finish;
            end else waiting <= !hit0 && !hit1;
        end
    end
end
`endif

endmodule // jtframe_romrq

////////////////////////////////////////////////////////////////
module jtframe_romrq_stats(
    input clk,
    input rst,
    input req,
    input we,
    input din_ok,
    input data_ok
);

// latency data
integer cur, longest, shortest, total, acc_cnt;
reg cnt_en, last_req, first;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        cur      <= 0;
        longest  <= 0;
        shortest <= 10000;
        cnt_en   <= 0;
        last_req <= 0;
        acc_cnt  <= 0;
        total    <= 0;
        first    <= 1;
    end else begin
        last_req <= req;
        if(req && !last_req) begin
            cur <= 1;
            cnt_en <= 1;
            acc_cnt <= acc_cnt+1;
        end
        if( cnt_en ) begin
            cur <= cur+1;
            if( (we && din_ok) || data_ok ) begin
                if( !first ) begin
                    if(cur>longest) longest <= cur;
                    if(cur<shortest) shortest <= cur;
                    total <= total + cur;
                end
                first  <= 0;
                cnt_en <= 0;
            end
        end
    end
end

initial begin
    forever begin
        #16_666_667;
        if( !first )
            $display("Latency %m %2d - %2d - %2d",
                shortest, total/acc_cnt, longest );
    end
end

endmodule