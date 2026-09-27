`timescale 1ns/1ps

// ============================================================================
// tb_uart_echo : lab3_uart_echo 자기검사 테스트벤치
//   - DUT의 rx 포트(uart_rxd)에 실제 UART 프레임(start=0 -> data[LSB-first] ->
//     stop=1)을 비트 주기 DIV(clk 카운트)에 맞춰 직접 만들어 인가한다.
//   - tx 출력(uart_txd)에서 같은 프레임 포맷(start/data/stop)이 그대로
//     되돌아오는지 비트 단위로 검사하고, LED가 마지막 수신 바이트와 같은지도
//     확인한다. 하나라도 다르면 $fatal로 즉시 실패시킨다.
//   - 시뮬레이션 시간을 줄이기 위해 DUT의 CLK_HZ/BAUD를 아주 작은 값으로
//     override하여 DIV=8로 줄인다. 실제 보드 값(50,000,000 / 9,600 -> DIV=5208)
//     은 시뮬레이션에 쓰지 않고 report의 파라미터 계산에서 별도로 명시한다.
// ============================================================================
module tb_uart_echo;
    localparam integer SIM_CLK_HZ = 800;
    localparam integer SIM_BAUD   = 100;
    localparam integer DIV        = (SIM_CLK_HZ + SIM_BAUD/2) / SIM_BAUD; // = 8

    reg         clk_50mhz = 1'b0;
    reg         rst_p     = 1'b1;
    reg         uart_rxd  = 1'b1;
    wire        uart_txd;
    wire [7:0] led;

    integer checks = 0;
    reg [7:0] observed;

    always #10 clk_50mhz = ~clk_50mhz;   // 20ns 주기(=50MHz 형식) clk 유지

    lab3_uart_echo #(.CLK_HZ(SIM_CLK_HZ), .BAUD(SIM_BAUD)) dut (
        .clk_50mhz (clk_50mhz),
        .rst_p     (rst_p),
        .uart_rxd  (uart_rxd),
        .uart_txd  (uart_txd),
        .led       (led)
    );

    // PC -> FPGA : start(0) -> data[0..7](LSB-first) -> stop(1) 프레임을 직접 생성
    task send_byte(input [7:0] value);
        integer b;
        begin
            uart_rxd = 1'b0;                    // start bit
            repeat (DIV) @(posedge clk_50mhz);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rxd = value[b];              // data bit b, LSB-first
                repeat (DIV) @(posedge clk_50mhz);
            end
            uart_rxd = 1'b1;                    // stop bit
            repeat (DIV) @(posedge clk_50mhz);
        end
    endtask

    // FPGA -> PC : uart_txd에서 start/data/stop 비트를 각각 중앙에서 샘플링하여
    // expected와 정확히 일치하는지 검사한다.
    task receive_and_check(input [7:0] expected);
        integer b;
        begin
            @(negedge uart_txd);                 // start bit 하강 검출
            repeat (DIV/2) @(posedge clk_50mhz); // 비트 중앙까지 대기
            if (uart_txd !== 1'b0)
                $fatal(1, "start bit expected 0, got %b", uart_txd);
            checks = checks + 1;
            $display("PASS: start bit = 0 (expected=0x%02h)", expected);

            observed = 8'h00;
            for (b = 0; b < 8; b = b + 1) begin
                repeat (DIV) @(posedge clk_50mhz); // 다음 비트 중앙으로 이동
                observed[b] = uart_txd;
            end

            repeat (DIV) @(posedge clk_50mhz);     // stop bit 중앙
            if (uart_txd !== 1'b1)
                $fatal(1, "stop bit expected 1, got %b", uart_txd);
            checks = checks + 1;
            $display("PASS: stop bit = 1 (expected=0x%02h)", expected);

            if (observed !== expected)
                $fatal(1, "echo data mismatch: got 0x%02h expected 0x%02h", observed, expected);
            checks = checks + 1;
            $display("PASS: echo data 0x%02h == expected 0x%02h", observed, expected);

            if (led !== expected)
                $fatal(1, "led mismatch: got 0x%02h expected 0x%02h", led, expected);
            checks = checks + 1;
            $display("PASS: led 0x%02h == expected 0x%02h", led, expected);

            repeat (DIV) @(posedge clk_50mhz);     // 다음 프레임 전 idle 여유
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_uart_echo);

        repeat (4) @(posedge clk_50mhz);
        rst_p = 1'b0;

        fork
            send_byte(8'h41);           // 'A'
            receive_and_check(8'h41);
        join

        fork
            send_byte(8'h5A);           // 'Z'
            receive_and_check(8'h5A);
        join

        fork
            send_byte(8'h0A);           // LF
            receive_and_check(8'h0A);
        join

        if (dut.rx_framing_error)
            $fatal(1, "unexpected framing error asserted");

        $display("LAB3_UART_ECHO_PASS checks=%0d", checks);
        $finish;
    end

    // 확정적 종료 보장: TB 로직 오류로 무한 대기하면 timeout으로 강제 종료
    initial begin
        #200000;
        $fatal(1, "timeout: simulation did not finish in time");
    end
endmodule
