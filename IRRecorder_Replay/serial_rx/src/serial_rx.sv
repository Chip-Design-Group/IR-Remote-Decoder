//------------------------------------------------------------------------------
// File: serial_rx.sv
// Purpose:
//   Empfängt das 8-Bit serielle Frame vom ESP32-C3 (Software-SPI, MSB first).
//   Gibt record_req / replay_req als 1-Takt-Impuls aus, passend zu
//   ir_recorder.sv und ir_replay_fsm.sv.
//
// Protokoll (ESP32-Seite):
//   GPIO4 = DATA,  GPIO5 = CLK
//   CLK Halbperiode = 1 ms  →  ~500 Baud
//   Frame: [7:5] = slot,  [4:3] = cmd (01=PLAY, 10=REC),  [2:0] = magic (101)
//
// Instanziiert edge_detector zweimal:
//   u_clk_sync  – synchronisiert CLK-Eingang, liefert steigende Flanke
//   u_data_sync – synchronisiert DATA-Eingang, liefert synchronisiertes Bit
//------------------------------------------------------------------------------

`timescale 1ns/1ps

module serial_rx (
    input  logic        clk,        // FPGA-Systemtakt (z.B. 10 MHz)
    input  logic        rst_n,      // aktiv-LOW Reset

    // Asynchrone Eingänge vom ESP32
    input  logic        clk_in,     // ESP32 GPIO5 – serieller Clock
    input  logic        data_in,    // ESP32 GPIO4 – serielle Daten

    // Ausgänge – 1-Takt-Impuls je Kommando
    output logic        replay_req,          // → ir_replay_fsm.replay_req
    output logic        record_req,          // → ir_recorder.record_req
    output logic [2:0]  slot_addr            // → target_slot
);

    // ------------------------------------------------------------------
    // Interne Signale
    // ------------------------------------------------------------------
    logic clk_rise;       // steigende Flanke des synchronisierten CLK
    logic data_sync;      // synchronisiertes DATA-Bit

    logic [7:0] shift_reg;
    logic [3:0] bit_cnt;  // 0..8

    // ------------------------------------------------------------------
    // Instanz 1: CLK synchronisieren + steigende Flanke erkennen
    // ------------------------------------------------------------------
    edge_detector u_clk_sync (
        .clk          (clk),
        .rst_n        (rst_n),
        .ir_in_async  (clk_in),
        .ir_in_sync   (),          // nicht benötigt
        .edge_rise    (clk_rise),
        .edge_fall    ()
    );

    // ------------------------------------------------------------------
    // Instanz 2: DATA synchronisieren (Flanke wird nicht benötigt)
    // ------------------------------------------------------------------
    edge_detector u_data_sync (
        .clk          (clk),
        .rst_n        (rst_n),
        .ir_in_async  (data_in),
        .ir_in_sync   (data_sync),
        .edge_rise    (),
        .edge_fall    ()
    );

    // ------------------------------------------------------------------
    // Schieberegister: bei jeder steigenden CLK-Flanke ein Bit einlesen
    // ------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 8'h00;
            bit_cnt    <= 4'd0;
            replay_req <= 1'b0;
            record_req <= 1'b0;
            slot_addr  <= 3'd0;
        end else begin
            // Ausgänge defaultmäßig LOW (Impuls nur 1 Takt lang)
            replay_req <= 1'b0;
            record_req <= 1'b0;

            if (clk_rise) begin
                // MSB first: Bits von links nach rechts einschieben
                shift_reg <= {shift_reg[6:0], data_sync};
                bit_cnt   <= bit_cnt + 1'd1;

                if (bit_cnt == 4'd7) begin
                    // 8. Bit gerade eingelesen → Frame auswerten
                    // shift_reg enthält nach diesem Takt die kompletten 8 Bit
                    // Wir werten den neuen Wert direkt aus:
                    automatic logic [7:0] frame = {shift_reg[6:0], data_sync};

                    // Magic-Prüfung: Bit [2:0] muss 3'b101 sein
                    if (frame[2:0] == 3'b101) begin
                        slot_addr <= frame[7:5];

                        case (frame[4:3])
                            2'b01: replay_req <= 1'b1;  // PLAY
                            2'b10: record_req <= 1'b1;  // REC
                            default: ;                   // unbekannt, ignorieren
                        endcase
                    end

                    bit_cnt <= 4'd0;  // bereit für nächsten Frame
                end
            end
        end
    end

endmodule
