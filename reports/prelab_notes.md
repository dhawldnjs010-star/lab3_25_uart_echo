# LAB3-25 · PC-FPGA UART 에코 — 실험 전 보고서 (prelab_notes)

학번 2025440084 · 상혁 · 전자전기컴퓨터공학부 · 전자전기컴퓨터설계실험Ⅱ
설계 top module: `lab3_uart_echo`

## 1. 회로 목적

PC(터미널)에서 9600 8N1(8 data bit, no parity, 1 stop bit) 포맷으로 한 바이트를 FPGA로
전송하면, FPGA는 그 바이트를 그대로(echo) 같은 UART 포맷으로 되돌려 송신하고, 동시에
마지막으로 수신한 바이트 값을 보드의 LED[7:0]에 표시한다. 최상위 입력 클록은
`clk_50mhz`(50MHz) 하나뿐이며, 모든 순차 로직은 이 clk만 사용한다(분주 신호를 다른
always 블록의 clock으로 쓰지 않음).

## 2. 블록 흐름

```
uart_rxd(PC->FPGA, 비동기)
   │
   ▼
[uart_rx]  2단 동기화(sync[1:0]) → start bit 하강 검출 → 반비트 대기 후
           비트 중앙 샘플링(FSM: IDLE→START→DATA(x8)→STOP)
   │  rx_data[7:0], rx_valid, rx_framing_error
   ▼
[에코 제어 always 블록 (top)]
   rx_valid 시 last_data<=rx_data(LED 갱신),
   tx_ready면 tx_data<=rx_data, tx_valid<=1
   │  tx_data[7:0], tx_valid, tx_ready
   ▼
[uart_tx]  shift={stop=1,data[7:0],start=0} 적재 후
           DIV clk마다 1비트씩 LSB부터 순차 출력
   │
   ▼
uart_txd(FPGA->PC) ,  led[7:0] = last_data
```

- `uart_rx`, `uart_tx`는 `DIV`(1비트 구간의 clk 카운트) 파라미터만 공유하는 독립
  모듈이며 top(`lab3_uart_echo`)이 두 모듈을 인스턴스화하고 수신→송신 데이터 경로를
  제어한다.
- rx가 한 바이트를 수신 완료(`rx_valid`)하는 순간 LED는 무조건 갱신되고, 그 시점에
  tx가 유휴(`tx_ready`) 상태면 곧바로 송신을 시작한다(설계상 echo는 한 클록 지연으로
  개시).

## 3. 파라미터 계산

- 반올림 분주비 공식: `DIV = (CLK_HZ + BAUD/2) / BAUD` (정수 나눗셈으로 반올림 구현)
- **실제 보드 값**: `CLK_HZ = 50,000,000`, `BAUD = 9,600`
  `DIV = (50,000,000 + 4,800) / 9,600 = 50,004,800 / 9,600 = 5208.83… → 5208`
  (1비트 구간 ≈ 5208 × 20ns = 104.16 µs, 이론 비트시간 1/9600 ≈ 104.17 µs와 거의 일치)
- **시뮬레이션 전용 값** (검증 속도를 위해 TB에서만 CLK_HZ/BAUD를 축소 override):
  `SIM_CLK_HZ = 800`, `SIM_BAUD = 100`
  `DIV = (800 + 50) / 100 = 850 / 100 = 8.5 → 8`
  clk 주기는 실제와 동일한 20ns 형식을 유지(`always #10 clk_50mhz = ~clk_50mhz;`)하고
  BAUD만 줄여 프레임 하나(10비트)가 80 clk(1.6µs)만에 끝나도록 했다. 실보드 100배
  가까운 5208 대신 8을 사용하므로 시뮬레이션 시간이 크게 단축된다.
- 한 프레임의 길이는 start(1) + data(8) + stop(1) = 10비트이므로,
  실제 보드 기준 한 바이트 송수신 시간 ≈ 10 × 104.17 µs ≈ 1.04 ms.

## 4. 상태/타이밍 표

### 4-1. `uart_rx` FSM 상태표

| 상태 | 진입 조건 | 동작 | 다음 상태 |
|---|---|---|---|
| IDLE | reset 해제 후 기본 | `sync[1]`(동기화된 rx) 감시, 1→0 하강이면 시작 | `sync[1]==0` → START |
| START | IDLE에서 하강 검출 | `DIV/2-1` 카운트(반비트) 대기 후 `sync[1]` 재확인 | 0이면 DATA, 1(노이즈)이면 IDLE |
| DATA | START 확정 | `DIV-1` 카운트마다 `sync[1]`을 `shift[bitno]`에 LSB-first로 저장, bitno 0→7 | bitno==7 완료 시 STOP |
| STOP | DATA 8비트 완료 | `DIV-1` 카운트 후 `sync[1]` 확인: 1이면 `data<=shift, valid<=1`, 0이면 `framing_error<=1` | IDLE |

### 4-2. `uart_tx` 상태(remaining 카운터 기반)

| remaining | tx 출력 | 의미 |
|---|---|---|
| 0 (ready=1) | 1 (idle high) | 새 `valid`를 받으면 `shift<={1,data,0}`, remaining<=10 적재 |
| 10..1 | `shift[0]` | DIV clk마다 1비트씩 우측 시프트하며 start→data[0..7]→stop 순서로 출력 |

### 4-3. 프레임 타이밍 (비트 중앙 샘플링 기준, N=DIV)

```
비트폭(clk):     |<--N-->|<--N-->|<--N-->|...|<--N-->|<--N-->|
비트:            | start | d0    | d1 …  d7  | stop  |
샘플 시점(중앙): 0.5N     1.5N    2.5N …      8.5N     9.5N
```
TB의 `receive_and_check`는 `negedge uart_txd`(start 하강) 시점을 0으로 놓고
`DIV/2` 대기 후 start bit를, 이후 `DIV`씩 이동하며 data[0..7], 마지막으로 stop bit를
각각 비트 "중앙"에서 샘플링한다.

## 5. RTL · TB · XDC 역할

| 파일 | 역할 |
|---|---|
| `src/lab3_uart_echo.v (uart.v 포함)` | `uart_rx`(비동기 수신+2단 동기화+FSM), `uart_tx`(시프트 송신), `lab3_uart_echo`(top: 두 모듈 연결 + 에코 제어 + LED) 3개 module을 포함하는 합성 가능 RTL |
| `sim/tb_uart_echo.sv` | `tb_design`(simulation_top): DUT에 실제 UART 프레임 파형을 직접 생성해 인가(`send_byte`)하고, tx 출력의 start/data/stop 비트를 각각 비트 단위로 검사(`receive_and_check`)하는 자기검사 테스트벤치. 불일치 시 `$fatal`, 각 검사 통과마다 `$display("PASS: …")`, 종료 시 `LAB3_UART_ECHO_PASS checks=%0d` 요약, `$dumpfile/$dumpvars`로 `wave.vcd` 생성, `#200000` 후 강제 `$fatal`로 확정적 종료 보장 |
| `constraints/lab3_uart_echo.xdc` | top 포트(`clk_50mhz, rst_p, uart_rxd, uart_txd, led[7:0]`)에 대한 `PACKAGE_PIN`/`IOSTANDARD LVCMOS33` 지정, `create_clock`(20.000ns 주기), rst/rx 비동기 입력에 대한 `set_false_path`. Icarus 시뮬레이션에는 사용되지 않고 Vivado 합성·구현 단계에서만 적용됨 |

## 6. TB 자극 → 기대 결과 표

| 자극(바이트) | 프레임(2진, start-d0..d7-stop) | 기대 tx 출력 | 기대 LED | 결과 |
|---|---|---|---|---|
| 0x41 ('A') | 0-10000010-1 | start=0, data=0x41, stop=1 | 0x41 | PASS |
| 0x5A ('Z') | 0-01011010-1 | start=0, data=0x5A, stop=1 | 0x5A | PASS |
| 0x0A (LF)  | 0-01010000-1 | start=0, data=0x0A, stop=1 | 0x0A | PASS |
| (공통) | — | `dut.rx_framing_error` == 0 (3바이트 전 구간) | — | PASS |

바이트당 4개 검사(start bit, stop bit, echo data, LED) × 3바이트 = 12 checks.

## 7. Icarus PASS 결과 핵심 로그

```
PASS: start bit = 0 (expected=0x41)
PASS: stop bit = 1 (expected=0x41)
PASS: echo data 0x41 == expected 0x41
PASS: led 0x41 == expected 0x41
PASS: start bit = 0 (expected=0x5a)
PASS: stop bit = 1 (expected=0x5a)
PASS: echo data 0x5a == expected 0x5a
PASS: led 0x5a == expected 0x5a
PASS: start bit = 0 (expected=0x0a)
PASS: stop bit = 1 (expected=0x0a)
PASS: echo data 0x0a == expected 0x0a
PASS: led 0x0a == expected 0x0a
LAB3_UART_ECHO_PASS checks=12
```
`python3 tools/fpga_lab.py simulate` 실행 결과 `build/sim/result.json`의 `status`는
`"SIMULATED"`, 새 `wave.vcd`가 정상 생성됨(`$enddefinitions`/`$var` 포함, 시간 진행 확인됨).

## 8. 한 항목 수정 실험과 복구 결과

**수정 대상**: `src/lab3_uart_echo.v (uart.v 포함)`의 `uart_rx` FSM, `IDLE` 상태에서 START로 넘어갈 때의
샘플링 오프셋. 정상값은 반 비트(`DIV/2-1`)만 대기해 다음 샘플이 start bit **중앙**에
오도록 하는 것인데, 이를 한 비트 전체(`DIV-1`)로 바꿔 샘플링 시점이 비트 중앙에서
크게 벗어나도록 했다(모든 이후 비트 샘플 지점도 함께 밀림).

```verilog
// 정상: timer <= DIV/2 - 1;   (반비트 대기, 비트 중앙 샘플링)
// 오류: timer <= DIV - 1;      (한 비트 전체 대기, 샘플링 지점 어긋남)
```

| 항목 | 기대값 | 실제 결과 |
|---|---|---|
| 정상(수정 전) PASS | `LAB3_UART_ECHO_PASS checks=12` | PASS (checks=12) |
| 수정 후(고의 오류) | FAIL 예상 | **FAIL** — `$fatal`: `echo data mismatch: got 0xe8 expected 0x41` (Time 3610000, `tb_design.receive_and_check`), 종료 코드 1 |
| 복구(원본으로 되돌림) 후 재실행 | PASS 복구 예상 | **PASS 복구 확인** — `LAB3_UART_ECHO_PASS checks=12`, 종료 코드 0 |

TB의 기대값(`expected`)은 RTL 오류에 맞춰 바꾸지 않고 원본 그대로 유지한 채 검사했다.
이 실험은 시작 비트 검출 후 "반 비트 대기"가 UART 수신에서 비트 중앙 샘플링을 보장하는
핵심 타이밍 요소임을 보여준다: 샘플링 오프셋이 어긋나면 노이즈나 에지 근처에서 값을
읽어 잘못된 데이터(0x41 대신 0xE8)가 수신·에코된다.

## 9. 실제 보드 확인 체크리스트

- [ ] 전원을 끈 상태에서 외부 배선(USB-UART 모듈 등)과 공통 GND를 먼저 확인한다.
- [ ] **TX/RX 교차 연결** 확인: PC(USB-UART)의 TXD → FPGA `uart_rxd`(C6), PC의
      RXD ← FPGA `uart_txd`(F6). 같은 이름끼리(TX-TX, RX-RX) 연결하지 않는다.
- [ ] **전압 레벨** 확인: FPGA 측 I/O는 LVCMOS33(3.3V)이므로 USB-UART 모듈이 3.3V
      레벨(RS-232 ±12V나 5V 로직이 아님)인지 확인한다.
- [ ] 터미널을 9600 8N1, local echo off로 설정한다.
- [ ] Hardware Manager → Open Target → Auto Connect → Program Device로 bit 파일을
      보드에 로드한다.
- [ ] 문자 하나(예: 'A')를 입력해 터미널에 같은 문자가 반향되는지, LED[7:0]에 해당
      바이트 값이 표시되는지 확인한다.
- [ ] 서로 다른 문자 여러 개로 반복 확인하고, 결선이 보이는 사진과 동작 영상(입력→출력
      변화가 함께 보이도록)을 촬영해 둔다.
- [ ] Reports → Timing에서 `clk_50mhz` 주기 20.000ns 제약이 만족되는지(setup/hold
      위반 없음) 확인한다.

## 10. 핀 표 요약

| 신호명 (RTL 포트) | PACKAGE_PIN | IOSTANDARD | 비고 |
|---|---|---|---|
| clk_50mhz | B6 | LVCMOS33 | 50MHz 메인 클록, `create_clock -period 20.000` |
| rst_p | K4 | LVCMOS33 | active-high 리셋, `set_false_path` 대상 |
| uart_rxd | C6 | LVCMOS33 | PC→FPGA 수신 (비동기 입력, `set_false_path` 대상) |
| uart_txd | F6 | LVCMOS33 | FPGA→PC 송신 |
| led[0] | N5 | LVCMOS33 | 마지막 수신 바이트 bit0 |
| led[1] | M1 | LVCMOS33 | bit1 |
| led[2] | M3 | LVCMOS33 | bit2 |
| led[3] | M7 | LVCMOS33 | bit3 |
| led[4] | N7 | LVCMOS33 | bit4 |
| led[5] | M2 | LVCMOS33 | bit5 |
| led[6] | M4 | LVCMOS33 | bit6 |
| led[7] | L4 | LVCMOS33 | bit7 |

보드: Combo II-DLD S75 / FPGA part `xc7s75fgga484-1` / MAIN CLOCK F = 50MHz / USB UART 9600 8N1.
