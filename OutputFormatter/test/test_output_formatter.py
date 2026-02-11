import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock


# Hilfsfunktion: Hex-Zeichen erzeugen
def hex_to_ascii(val):
    return format(val, "02X")


@cocotb.test()
async def test_all_combinations(dut):
    """
    Tests all address/command combinations (0x00..0xFF)
    """

    # Start clock: 1 ns period
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())

    # Reset
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    dut.decode_error.value = 0
    dut.address.value = 0
    dut.command.value = 0
    dut.uart_ready.value = 1  # UART always ready

    await Timer(100, unit="ns")
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    await RisingEdge(dut.clk)

    total_tests = 0

    for addr in range(256):
        for cmd in range(256):
            total_tests += 1

            # Apply inputs
            dut.address.value = addr
            dut.command.value = cmd
            dut.decode_error.value = 0
            dut.valid_in.value = 1

            await RisingEdge(dut.clk)
            dut.valid_in.value = 0

            # Expected string
            expected = f"A:{hex_to_ascii(addr)} C:{hex_to_ascii(cmd)}\n"

            received_chars = ""

            # Collect UART output (10 chars)
            while len(received_chars) < len(expected):
                await RisingEdge(dut.clk)
                if dut.uart_tx_req.value == 1:
                    received_chars += chr(int(dut.uart_data.value))

            # Check result
            if received_chars != expected:
                raise cocotb.result.TestFailure(
                    f"Mismatch!\n"
                    f"Address: 0x{addr:02X}, Command: 0x{cmd:02X}\n"
                    f"Expected: {expected}\n"
                    f"Got:      {received_chars}"
                )

    dut._log.info(f"All {total_tests} combinations tested successfully!")

@cocotb.test()
async def test_single_input(dut):
    """Testet, dass ein einzelnes valid_in korrekt gepuffert wird"""
    
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    dut.address.value = 0
    dut.command.value = 0
    await Timer(50, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Testinput setzen
    dut.address.value = 0x12
    dut.command.value = 0x34
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)

    # Prüfen, ob UART startet (FSM IDLE → SEND_A)
    assert dut.uart_tx_req.value == 1 or dut.uart_data.value == ord("A"), \
        f"FSM hat UART nicht korrekt gestartet. uart_tx_req={dut.uart_tx_req.value}, uart_data={dut.uart_data.value}"
    
    dut._log.info("Single input buffering test passed")

@cocotb.test()
async def test_single_input(dut):
    """Testet, dass ein einzelnes valid_in korrekt gepuffert wird"""
    
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    dut.address.value = 0
    dut.command.value = 0
    await Timer(50, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Testinput setzen
    dut.address.value = 0x12
    dut.command.value = 0x34
    dut.valid_in.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)

    # Prüfen, ob UART startet (FSM IDLE → SEND_A)
    assert dut.uart_tx_req.value == 1 or dut.uart_data.value == ord("A"), \
        f"FSM hat UART nicht korrekt gestartet. uart_tx_req={dut.uart_tx_req.value}, uart_data={dut.uart_data.value}"
    
    dut._log.info("Single input buffering test passed")


@cocotb.test()
async def test_decode_error(dut):
    """Prüft Verhalten bei decode_error=1"""
    
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    dut.address.value = 0
    dut.command.value = 0
    dut.decode_error.value = 0
    await Timer(50, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    dut.address.value = 0x55
    dut.command.value = 0xAA
    dut.valid_in.value = 1
    dut.decode_error.value = 1
    await RisingEdge(dut.clk)
    dut.valid_in.value = 0
    dut.decode_error.value = 0

    # Prüfen, ob UART trotzdem gesendet wird
    expected = "A:55 C:AA\n"
    received = ""
    while len(received) < len(expected):
        await RisingEdge(dut.clk)
        if dut.uart_tx_req.value == 1:
            received += chr(int(dut.uart_data.value))

    assert received == expected, f"Decode error handling failed! output={received}"
    dut._log.info(f"Decode error test passed, output={received}")

@cocotb.test()
async def test_uart_backpressure(dut):
    """Prüft Verhalten bei uart_ready=0"""
    
    cocotb.start_soon(Clock(dut.clk, 1, unit="ns").start())
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    dut.uart_ready.value = 0
    await Timer(50, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    dut.address.value = 0x01
    dut.command.value = 0x02
    dut.valid_in.value = 1
    # Warten bis uart_tx_req aktiv wird, max 10 Zyklen
    for _ in range(10):
        await RisingEdge(dut.clk)
        if dut.uart_tx_req.value == 1:
            break
        else:
            assert False, "uart_tx_req wurde nicht aktiviert, obwohl uart_ready=1"

    dut._log.info("UART backpressure test passed after enabling uart_ready")
