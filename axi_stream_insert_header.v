module axi_stream_insert_header #(
    parameter DATA_WD = 32,
    parameter DATA_BYTE_WD = DATA_WD / 8,
    parameter BYTE_CNT_WD = $clog2(DATA_BYTE_WD)
) (
    input clk,
    input rst_n,
    // AXI Stream input original data
    input valid_in,
    input [DATA_WD-1 : 0] data_in,
    input [DATA_BYTE_WD-1 : 0] keep_in,
    input last_in,
    output reg ready_in,
    // The header to be inserted to AXI Stream input
    input valid_insert,
    input [DATA_WD-1 : 0] data_insert,
    input [DATA_BYTE_WD-1 : 0] keep_insert,
    input [BYTE_CNT_WD-1 : 0] byte_insert_cnt,
    output reg ready_insert,
    // AXI Stream output with header inserted
    output reg valid_out,
    output wire [DATA_WD-1 : 0] data_out,
    output reg [DATA_BYTE_WD-1 : 0] keep_out,
    output reg last_out,
    input ready_out
);

    /* signal used for asynchronous reset and synchronous release.*/
    reg [1:0] reset; 

    reg last_lst_in, lst_in; // last_in should be pipelined twice.

    /* handshake flags */
    reg handshake_data, handshake_header;
    wire handshake_transmitter;

    /* 2-level pipeline */
    reg [DATA_WD-1 : 0] merged_data;
    reg [2*DATA_WD-1 : 0] header_data;

    /* flags for start data */
    reg start;

    /* effective bytes */
    reg [BYTE_CNT_WD-1 : 0] cnt;
    reg [DATA_BYTE_WD-1 : 0] strobe;

    wire [DATA_BYTE_WD-1:0] reversal;

    assign data_out = merged_data;

    genvar i;
    generate
        for(i=0; i<DATA_BYTE_WD; i=i+1) begin: REVERSAL 
            assign reversal[i] = strobe[DATA_BYTE_WD-1-i];
        end
    endgenerate
    
    /* asynchronous reset and synchronous release */
    always @(posedge clk, negedge rst_n) begin
        if(~rst_n) reset <= 2'd0;
        else reset <= {1'b1, reset[1]};
    end

    // flag behavior
    always @(posedge clk, negedge reset[0]) begin
        if(~reset[0]) start <= 1'b1;
        else if(start & valid_out & ready_out) start <= 1'b0;
        else if(last_out) start <= 1'b1;
    end

    always @(posedge clk, negedge reset[0]) begin
        if(~reset[0]) last_lst_in <= 1'b0;
        else if(ready_in & valid_in) last_lst_in <= lst_in;
    end

    /* signal behaviors for transimitter component. */
    always @(posedge clk,  negedge reset[0]) begin

        // output valid_out
        if(~reset[0]) valid_out <= 1'b0;
        else if(ready_out & valid_out) valid_out <= 1'b0;
        else if(start & handshake_data & handshake_header || ~start & handshake_data) valid_out <= 1'b1;

        // output keep_out
        if(~reset[0]) keep_out <= 'd0;
        else if(~last_lst_in) keep_out <= {DATA_BYTE_WD{1'b1}};
        else if(last_lst_in) keep_out <= reversal;

        // output data_out
        if(~reset[0]) merged_data <= 'd0;
        else if(start & handshake_data & handshake_header || ~start & handshake_data)
            merged_data <= header_data[8*(DATA_BYTE_WD+cnt)-1 -: DATA_WD];

        // output last_out
        if(~reset[0]) last_out <= 1'b0;
        else if(valid_out & ready_out) last_out <= last_lst_in;

    end

    assign handshake_transmitter = valid_out & ready_out;

    /* signal behaviors for 2 receiver components. */
    always @(posedge clk, negedge reset[0]) begin

        /* data_in receiver */
            // output ready_in
        if(~reset[0]) ready_in <= 1'b1;
        else if(ready_in & valid_in) ready_in <= 1'b0;
        else if(handshake_transmitter) ready_in <= 1'b1;

            // intermediate pipelined flag signal handshake_data
        if(~reset[0]) handshake_data <= 1'b0;
        else if(ready_in & valid_in) handshake_data <= 1'b1;

            // intermediate pipelined lst_in
        if(~reset[0]) lst_in <= 1'b0;
        else if(ready_in & valid_in) lst_in <= last_in;

        /* data_insert receiver */
            // output ready_insert
        if(~reset[0]) ready_insert <= 1'b1;
        else if(ready_insert & valid_insert) ready_insert <= 1'b0;
        else if(start & handshake_transmitter) ready_insert <= 1'b1;

            // intermediate pipelined flag signal handshake_header
        if(~reset[0]) handshake_header <= 1'b0;
        else if(ready_insert & valid_insert) handshake_header <= 1'b1;

            // intermdediate pipelined signal strobe and cnt
        if(~reset[0]) cnt <= 'd0;
        else if(start) cnt <= byte_insert_cnt;

        if(~reset[0]) strobe <= 'd0;
        else if(start) strobe <= keep_insert;
        

        /* shared registers for header and data */
        if(~reset[0]) header_data <= 'd0;
        else if(start) begin 
           if(valid_in & ready_in) header_data[2*DATA_WD-1:DATA_WD] <= data_insert;
           if(valid_insert & ready_insert) header_data[DATA_WD-1:0] <= data_in;
        end
        else if(~start & valid_in & ready_in) header_data <= {header_data[DATA_WD-1:0], data_in};
    end



endmodule