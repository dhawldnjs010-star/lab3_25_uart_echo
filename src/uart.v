`timescale 1ns/1ps

// LAB3-25 · uart.v (uart_rx + uart_tx)
`timescale 1ns/1ps

// ============================================================================
// uart_rx : 비동기 UART 수신기
//   - rx는 FPGA clk와 무관하게 바뀌는 비동기 입력이므로 2단 플립플롭(sync)으로
//     먼저 동기화한 뒤에 start bit 검출 -> 비트 중앙 샘플링 -> stop bit 확인
//     순서로 동작하는 FSM을 둔다.
//   - DIV = 1비트 구간의 clk 카운트(반올림한 CLK_HZ/BAUD). top에서 넘겨준다.
// ============================================================================
module uart_rx #(
    parameter integer DIV = 5208
) (
    input  wire       clk,
    input  wire       rst_p,
    input  wire       rx,
    output reg  [7:0] data,
    output reg         valid,
    output reg         framing_error
);
    // 비동기 입력을 clk 도메인으로 2단 동기화 (메타스테이블 방지)
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync;

    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0] state;
    integer   timer;
    reg [2:0] bitno;
    reg [7:0] shift;

    always @(posedge clk) begin
        if (rst_p) begin
            sync          <= 2'b11;
            state         <= IDLE;
            timer         <= 0;
            bitno         <= 0;
            shift         <= 0;
            data          <= 0;
            valid         <= 0;
            framing_error <= 0;
        end else begin
            sync  <= {sync[0], rx};
            valid <= 0;
            case (state)
                IDLE: begin
                    if (!sync[1]) begin          // start bit 하강 검출
                        timer <= DIV/2 - 1;       // 다음 샘플이 비트 "중앙"에 오도록 반 비트만 대기
                        state <= START;
                    end
                end
                START: begin
                    if (timer != 0) begin
                        timer <= timer - 1;
                    end else if (sync[1]) begin  // 중앙에서 다시 1이면 노이즈로 보고 취소
                        state <= IDLE;
                    end else begin
                        timer <= DIV - 1;
                        bitno <= 0;
                        state <= DATA;
                    end
                end
                DATA: begin
                    if (timer != 0) begin
                        timer <= timer - 1;
                    end else begin
                        shift[bitno] <= sync[1];  // LSB-first 샘플링
                        timer        <= DIV - 1;
                        if (bitno == 3'd7) state <= STOP;
                        else bitno <= bitno + 1'b1;
                    end
                end
                STOP: begin
                    if (timer != 0) begin
                        timer <= timer - 1;
                    end else begin
                        data <= shift;
                        if (sync[1]) begin
                            valid <= 1;            // stop bit == 1 : 정상 프레임
                        end else begin
                            framing_error <= 1;     // stop bit 위반
                        end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

// ============================================================================
// uart_tx : UART 송신기
//   - shift 레지스터에 {stop=1, data[7:0], start=0} 10비트를 적재하고
//     DIV clk마다 한 비트씩 LSB부터 내보낸다. remaining==0이면 idle(=1)이고
//     새 valid를 받을 준비(ready)가 된 상태다.
// ============================================================================
module uart_tx #(
    parameter integer DIV = 5208
) (
    input  wire       clk,
    input  wire       rst_p,
    input  wire       valid,
    input  wire [7:0] data,
    output wire        ready,
    output wire         tx
);
    reg [9:0] shift;
    reg [3:0] remaining;
    integer   timer;

    assign ready = (remaining == 0);
    assign tx    = ready ? 1'b1 : shift[0];

    always @(posedge clk) begin
        if (rst_p) begin
            shift     <= 10'h3ff;
            remaining <= 0;
            timer     <= 0;
        end else if (ready) begin
            if (valid) begin
                shift     <= {1'b1, data, 1'b0};  // {stop, data[7:0], start}
                remaining <= 4'd10;
                timer     <= DIV - 1;
            end
        end else if (timer != 0) begin
            timer <= timer - 1;
        end else begin
            timer     <= DIV - 1;
            shift     <= {1'b1, shift[9:1]};
            remaining <= remaining - 1'b1;
        end
    end
endmodule
