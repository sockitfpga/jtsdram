/*  This file is part of JT_FRAME.
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
    Date: 28-12-2020 */

module jtframe_reset(
    input       clk_sys,
    input       clk_rom,

    input       downloading,
    input       dip_flip,
    input       soft_rst,
    input       rst_req,

    // clk_sys:
    output  reg rst,
    output  reg rst_n,
    // clk_rom:
    output  reg game_rst,
    output  reg game_rst_n
);

localparam MAIN_RSTW = 4,
           GAME_RSTW = 8;

reg [MAIN_RSTW-1:0] rst_cnt={MAIN_RSTW{1'b1}};
reg [GAME_RSTW-1:0] game_rst_cnt;
reg [MAIN_RSTW-1:0] rst_rom; // rst in clk_rom domain
reg                 last_dwn, dwn_done;


always @(negedge clk_sys) begin
    if( rst_cnt[0] ) begin
        rst     <= 1;
        rst_n   <= 0;
        rst_cnt <= rst_cnt >> 1;
    end else begin
        rst     <= 0;
        rst_n   <= 1;
    end
end

`ifdef JTFRAME_NOROM
    initial begin
        dwn_done <= 1;
    end
`else
    always @(posedge clk_sys, posedge rst) begin
        if( rst ) begin
            dwn_done <= 0;
            last_dwn <= 0;
        end else begin
            last_dwn <= downloading;
            if( downloading )
                dwn_done <= 0;
            else if( last_dwn ) dwn_done <= 1;
        end
    end
`endif


`ifdef JTFRAME_FLIP_RESET
    reg last_dip_flip, rst_flip;
    always @(posedge clk_sys) begin
        last_dip_flip <= dip_flip;
        rst_flip      <= last_dip_flip!=dip_flip;
    end
`else
    wire rst_flip = 0;
`endif

always @(posedge clk_sys, posedge rst ) begin
    if( rst ) begin
        rst_rom <= {MAIN_RSTW{1'b1}};
    end else begin
        if( !dwn_done | rst | rst_req
        | rst_flip | soft_rst )
            rst_rom <= {MAIN_RSTW{1'b1}};
        else
            rst_rom <= rst_rom >> 1;
    end
end

always @(negedge clk_rom) begin
    if( rst_rom[0] ) begin
        game_rst_cnt   <= {GAME_RSTW{1'b1}};
        game_rst_n     <= 0;
        game_rst       <= 1;
    end else begin
        if( game_rst_cnt[0] ) begin
            game_rst_cnt <= game_rst_cnt >> 1;
            game_rst_n   <= 0;
            game_rst     <= 1;
        end else begin
            game_rst_n <= 1;
            game_rst   <= 0;
        end
    end
end

endmodule