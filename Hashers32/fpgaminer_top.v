/*
* MJ hashers22 version
*
* v04 added halt_in and changed behaviour so held in poweron_reset until reset
*     is pressed. Pressing halt reapplies the initial poweron_reset hold state.
* v03 single sha256 hasher alternates on phase
* v02 standard dual sha256 hashers which DOES NOT FIT in EP4CE22 (DE0-Nano)
*
* Copyright (c) 2011 fpgaminer@bitcoin-mining.com
*
*
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
* 
*/


`timescale 1ns/1ps

module fpgaminer_top (osc_clk, reset_in, halt_in, LEDS_out);

	// The LOOP_LOG2 parameter is now ignored and we hard configure LOOP=3

	`ifdef CONFIG_LOOP_LOG2
		parameter LOOP_LOG2 = `CONFIG_LOOP_LOG2;
	`else
		parameter LOOP_LOG2 = 1;
	`endif

	// No need to adjust these parameters
	localparam [5:0] LOOP = (6'd1 << LOOP_LOG2);
	localparam [31:0] GOLDEN_NONCE_OFFSET = (32'd1 << (6 - LOOP_LOG2)) + 32'd1;

	input osc_clk;
	input reset_in;
	input halt_in;
	output [7:0] LEDS_out;

	//// 
	reg [255:0] state = 0;
	reg [127:0] data = 0;
	reg [31:0] nonce = 32'h95000000;
	reg poweron_reset = 0;

	assign LEDS_out = nonce[31:24];

	//// PLL ... before clk_enable
	wire hash_clk;
	`ifndef SIM
		main_pll pll_blk (osc_clk, hash_clk);
	`else
	 	assign hash_clk = osc_clk;
	`endif
	
	//// Hashers
	
	// MJ NB There are two sha256_transform blocks each with 1..64 sha256_digester's depending on LOOP_LOG2
	// so we have a total of 2..128 stages, but we also have a counter cnt which cycles depending on the
	// number of stages. Hence the output is available after (approx) 128 clocks in ALL LOOP_LOG2 configurations.
	// But we only increment the nonce each time cnt==0, so we process nonces at a slower rate (takes more clocks)
	// for higher LOOP_LOG2 values. This explains why GOLDEN_NONCE_OFFSET reduces as 133, 66, 33, 17, 9, 5 etc
	
	wire [255:0] hash;
	reg [6:0] cnt = 7'd0;
	reg feedback = 1'b0;
	reg internal_feedback = 1'b0;
	reg feedback_d1 = 1'b0;

	// MJ SHA256. NB this is the second of two rounds hashing an 80 byte message (the block header), padded
	// to 128 bytes (JSON data field) and hashed in two rounds of 64 bits each. The first is round is done by
	// the JSON server, giving us midstate. We insert the nonce into the correct position in the second 64
	// 64 bytes of data then SHA256 hash it with midstate. NB sha256_transform performs the internal SHA256
	// transform, it is NOT the complete SHA256 algorithm (which involves multiple rounds of sha256_transform).

	// Using just ONE sha256_transform which alternates according to phase to perform the two SHA256 transforms.
	sha256_transform #(.LOOP(LOOP), .NUM_ROUNDS(64)) uut (
		.clk(hash_clk),
		.feedback(internal_feedback),
		.fb_second(cnt[LOOP_LOG2]),
		.cnt(cnt[5:0] & (LOOP-7'd1)),
		.rx_state_1(state),
		.rx_input_1({384'h000002800000000000000000000000000000000000000000000000000000000000000000000000000000000080000000, data}),
		.tx_hash(hash)
	);


	//// Virtual Wire Control
	reg [255:0] midstate_buf = 0, data_buf = 0;
	wire [255:0] midstate_vw, data2_vw;
	reg reset = 0;
	wire reset_vw;
	`ifndef SIM
		virtual_wire # (.PROBE_WIDTH(0), .WIDTH(256), .INSTANCE_ID("STAT")) midstate_vw_blk(.probe(), .source(midstate_vw));
		virtual_wire # (.PROBE_WIDTH(0), .WIDTH(256), .INSTANCE_ID("DAT2")) data2_vw_blk(.probe(), .source(data2_vw));
		virtual_wire # (.PROBE_WIDTH(0), .WIDTH(1), .INSTANCE_ID("REST")) reset_vw_blk(.probe(), .source(reset_vw));
	`endif

	`ifndef SIM
	`endif

	//// Virtual Wire Output
	reg [31:0] golden_nonce = 0;
	
	`ifndef SIM
		virtual_wire # (.PROBE_WIDTH(32), .WIDTH(0), .INSTANCE_ID("GNON")) golden_nonce_vw_blk (.probe(golden_nonce), .source());
		virtual_wire # (.PROBE_WIDTH(32), .WIDTH(0), .INSTANCE_ID("NONC")) nonce_vw_blk (.probe(nonce), .source());
	`endif

	//// Control Unit
	reg is_golden_ticket = 1'b0;
	//reg reset_d1 = 1'b1;
	//wire reset = !reset_in;
	
	wire [6:0] cnt_next;
	wire [31:0] nonce_next;
	wire feedback_next;
	wire internal_feedback_next;


	
		//// Control Unit
	assign cnt_next = reset ? 7'd0 : (cnt + 7'd1) & {(LOOP-1), 1'b1};
	// On the first count (cnt==0), load data from previous stage (no feedback)
	// on 1..LOOP-1, take feedback from current stage
	// This reduces the throughput by a factor of (LOOP), but also reduces the design size by the same amount
	assign feedback_next = (cnt_next != {(LOOP_LOG2){1'b0}});
	assign internal_feedback_next = ((cnt_next & {1'b1, (LOOP-1)}) != {(LOOP_LOG2){1'b0}});

	
	// On the first count (cnt==0), load data from previous stage (no feedback)
	// on 1..LOOP-1, take feedback from current stage
	// This reduces the throughput by a factor of (LOOP), but also reduces the design size by the same amount

	assign nonce_next =
		(reset | poweron_reset) ? 32'h95000000 :
		feedback_next ? nonce : (nonce + 32'd1);


	always @ (posedge hash_clk)
	begin
		`ifdef SIM
			//midstate_buf <= 256'h2b3f81261b3cfd001db436cfd4c8f3f9c7450c9a0d049bee71cba0ea2619c0b5;
			//data_buf <= 256'h00000000000000000000000080000000_00000000_39f3001b6b7b8d4dc14bfc31;
			//nonce <= 30411740;
		`else
			reset <= reset_vw;
			midstate_buf <= midstate_vw;
			data_buf <= data2_vw;
		`endif

		// MJ These register updates occur on posedge hash_clk

		// We hold poweron_reset until reset is pressed. Pressing halt reapplies the initial
		// poweron_reset hold state.
		poweron_reset <= reset ? 1'd0 : (halt_in ? poweron_reset : 1'd1);	// halt_in is active low
		//reset_d1 <= reset | poweron_reset;

		cnt <= cnt_next;
		feedback <= feedback_next;
		internal_feedback <= internal_feedback_next;
		feedback_d1 <= feedback;

		// Give new data to the hasher
		state <= midstate_buf;
		data <= {nonce_next, data_buf[95:0]};
		nonce <= nonce_next;

		// Check to see if the last hash generated is valid.
		is_golden_ticket <= (hash[255:224] == 32'ha41f32e7) && !feedback_d1;
		if(is_golden_ticket)
			begin
			// TODO: Find a more compact calculation for this
			//if (LOOP == 1)
			golden_nonce <= nonce - 32'd66;
			//else
			//	golden_nonce <= nonce - GOLDEN_NONCE_OFFSET;
			`ifdef SIM
					$display ("GOLDEN NONCE: %8x\nhash: %64x\n", nonce, hash);
			`endif
			end // if (is_golden_ticket)
	end
endmodule

