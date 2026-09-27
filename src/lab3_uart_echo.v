`timescale 1ns/1ps

// LAB3-25 · lab3_uart_echo (설계 top)
// ============================================================================
// lab3_uart_echo : LAB3-25 PC-FPGA UART 에코 top module
//   9600 8N1로 받은 한 바이트를 그대로 송신하고 LED에 마지막 수신값을 표시한다.
//   최상위 입력 클록은 clk_50mhz 하나뿐이며 모든 순차 로직은 이 clk만 사용한다.
// ============================================================================
module lab3_uart_echo #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 9_600
) (
    input  wire       clk_50mhz,
    input  wire       rst_p,
    input  wire       uart_rxd,
    output wire        uart_txd,
    output wire [7:0] led
);
    // 반올림: DIV = round(CLK_HZ / BAUD) = (CLK_HZ + BAUD/2) / BAUD (정수 나눗셈)
    localparam integer DIV = (CLK_HZ + BAUD/2) / BAUD;

    wire [7:0] rx_data;
    wire        rx_valid;
    wire        rx_framing_error;
    wire        tx_ready;
    reg         tx_valid;
    reg  [7:0] tx_data;
    reg  [7:0] last_data;

    uart_rx #(.DIV(DIV)) u_rx (
        .clk           (clk_50mhz),
        .rst_p         (rst_p),
        .rx            (uart_rxd),
        .data          (rx_data),
        .valid         (rx_valid),
        .framing_error (rx_framing_error)
    );

    uart_tx #(.DIV(DIV)) u_tx (
        .clk   (clk_50mhz),
        .rst_p (rst_p),
        .valid (tx_valid),
        .data  (tx_data),
        .ready (tx_ready),
        .tx    (uart_txd)
    );

    // 에코 제어: 한 바이트가 정상 수신되면(rx_valid) LED에 즉시 반영하고,
    // TX가 유휴(tx_ready)면 그대로 송신 큐에 넣는다.
    always @(posedge clk_50mhz or posedge rst_p) begin
        if (rst_p) begin
            tx_valid  <= 1'b0;
            tx_data   <= 8'h00;
            last_data <= 8'h00;
        end else begin
            tx_valid <= 1'b0;
            if (rx_valid) begin
                last_data <= rx_data;
                if (tx_ready) begin
                    tx_data  <= rx_data;
                    tx_valid <= 1'b1;
                end
            end
        end
    end

    assign led = last_data;
endmodule
