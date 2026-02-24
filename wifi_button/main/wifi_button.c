#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_http_server.h"
#include <string.h>
#include <stdio.h>
#include <stdint.h>

#define WIFI_SSID   "IR-Remote"     // Name des WLAN-Hotspots
#define WIFI_PASS   "12345678"      // Passwort (min. 8 Zeichen), oder "" für offenes Netz
#define WIFI_AP_CHANNEL   1
#define WIFI_AP_MAX_CONN  4

// ==================== FPGA GPIO-Mapping ====================
// Serielles 2-Pin Protokoll (Software-SPI, MSB first):
//
//   GPIO  4  →  FPGA DATA   (serieller Datenpin)
//   GPIO  5  →  FPGA CLK    (Clock, steigende Flanke = Bit sampeln)
//
// Frame: 12 Bit, MSB zuerst
//   Bit [11:6] = Slot-Adresse (0–63)  [5:4]=remote_id (0..3), [3:0]=slot_num (0..9)
//   Bit  [5:3] = Kommando:  001 = PLAY,  010 = REC
//   Bit  [2:0] = Magic:    0b101  (FPGA-seitige Validierung)
//
// Beispiel: Slot 13 (Remote 1, Slot 3), PLAY:
//   [11:6]=001101  [5:3]=001  [2:0]=101  → 0b001101_001_101 = 0x34D
//
// Timing: CLK_HALF_MS pro Halbperiode (1 ms → ~500 Baud)

#define FPGA_DATA_PIN     4
#define FPGA_CLK_PIN      5

#define CLK_HALF_MS       1

#define CMD_PLAY          0x01  // Bit [5:3] = 0b001
#define CMD_REC           0x02  // Bit [5:3] = 0b010
#define FRAME_MAGIC       0x05  // Bit [2:0] = 0b101

#define REMOTE_COUNT      4
#define SLOTS_PER_REMOTE  10
#define SLOT_COUNT        (REMOTE_COUNT * SLOTS_PER_REMOTE)  // 40 Slots gesamt

static const char* TAG = "ir_remote";

// ==================== Recorded-Status (Bitmask, Bit N = Slot N) ====================
static uint64_t recorded_slots = 0;  // bleibt bis Neustart im RAM (bis 64 Slots)

// ==================== Slot-Namen ====================
#define SLOT_NAME_MAX 24
static char slot_names[SLOT_COUNT][SLOT_NAME_MAX];  // "" = kein Name gesetzt

// ==================== HTML-Seite ====================
static const char HTML_STYLE[] =
    "<!DOCTYPE html><html><head>"
    "<meta charset='UTF-8'>"
    "<meta name='viewport' content='width=device-width, initial-scale=1'>"
    "<title>IR Remote - FPGA Slot Control</title>"
    "<style>"
    "  :root{--bg:#0c1220;--panel:#121b2e;--panel-2:#17233b;--border:#2b3a57;--text:#e8eef9;"
    "        --muted:#98a7c4;--accent:#4da3ff;--accent-2:#2f7cd6;--danger:#d64d62;--danger-2:#b93b50}"
    "  *{box-sizing:border-box;margin:0;padding:0}"
    "  body{font-family:'Segoe UI','Helvetica Neue',Arial,sans-serif;color:var(--text);min-height:100vh;"
    "       background:radial-gradient(900px 500px at 0% -10%,#1a2d52 0%,rgba(26,45,82,0) 60%),"
    "                  linear-gradient(180deg,#0b1324 0%,#0d1629 100%);padding:28px 16px}"
    "  .page{width:100%;max-width:760px;margin:0 auto}"
    "  .header{background:linear-gradient(180deg,#15233d 0%,#101a2d 100%);border:1px solid var(--border);"
    "          border-radius:16px;padding:22px 20px;margin-bottom:18px;box-shadow:0 14px 30px rgba(0,0,0,.28)}"
    "  h1{font-size:1.65rem;font-weight:700;letter-spacing:.01em}"
    "  .sub{margin-top:6px;font-size:.95rem;color:var(--muted)}"
    "  .remote-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}"
    "  .remote-card{display:block;text-decoration:none;color:var(--text);background:var(--panel);"
    "               border:1px solid var(--border);border-radius:14px;padding:16px;transition:all .16s ease}"
    "  .remote-card:hover{transform:translateY(-1px);border-color:var(--accent);background:var(--panel-2)}"
    "  .remote-icon{display:flex;justify-content:center;margin-bottom:10px}"
    "  .remote-card .label{font-size:1.02rem;font-weight:600;margin-bottom:6px}"
    "  .remote-card .slots{font-size:.88rem;color:var(--muted)}"
    "  .toolbar{display:flex;justify-content:flex-start;margin-bottom:18px}"
    "  .back{display:inline-flex;align-items:center;gap:8px;text-decoration:none;padding:11px 18px;"
    "        font-size:1rem;font-weight:600;color:var(--text);"
    "        background:var(--panel);border:1px solid var(--border);border-radius:12px;"
    "        transition:all .16s ease}"
    "  .back:hover{border-color:var(--accent);background:var(--panel-2);transform:translateX(-2px)}"
    "  .back-arrow{font-size:1.2rem;line-height:1}"
    "  .action-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}"
    "  .slot-block{background:var(--panel);border:1px solid var(--border);border-radius:14px;padding:14px}"
    "  .slot-block h3{font-size:1rem;font-weight:600;margin-bottom:12px}"
    "  .btn{display:block;width:100%;text-decoration:none;text-align:center;padding:11px 0;border-radius:10px;"
    "       font-size:.92rem;font-weight:700;letter-spacing:.01em;transition:filter .16s ease;margin-bottom:10px}"
    "  .btn:last-child{margin-bottom:0}"
    "  .play{background:var(--accent);color:#041326}"
    "  .play:hover{filter:brightness(1.06)}"
    "  .rec{background:var(--danger);color:#ffffff}"
    "  .rec:hover{filter:brightness(1.06)}"
    "  .rec-done{background:#1a7a4a;color:#ffffff;border:2px solid #25a868}"
    "  .rec-done:hover{filter:brightness(1.08)}"
    "  .badge{display:inline-flex;align-items:center;gap:5px;margin-top:8px;padding:5px 10px;"
    "         background:#1a7a4a33;border:1px solid #25a868;border-radius:8px;"
    "         font-size:.82rem;color:#25a868;font-weight:600}"
    "  @keyframes spin{to{transform:rotate(360deg)}}"
    "  .spin{display:inline-block;width:13px;height:13px;border:2px solid rgba(255,255,255,.35);"
    "        border-top-color:#fff;border-radius:50%;animation:spin .7s linear infinite;"
    "        vertical-align:middle;margin-right:2px}"
    "  @media (max-width:560px){"
    "    h1{font-size:1.4rem}"
    "    .remote-grid,.action-grid{grid-template-columns:1fr}"
    "  }"
    "  .slot-name-row{display:flex;gap:6px;margin-bottom:10px;align-items:center}"
    "  .slot-name-input{flex:1;background:#0d1729;border:1px solid var(--border);border-radius:8px;"
    "                   color:var(--text);font-size:.88rem;padding:6px 10px;outline:none;min-width:0}"
    "  .slot-name-input:focus{border-color:var(--accent)}"
    "  .save-btn{flex-shrink:0;background:var(--panel-2);border:1px solid var(--border);border-radius:8px;"
    "            color:var(--muted);font-size:.82rem;font-weight:600;padding:6px 10px;cursor:pointer;"
    "            transition:all .16s ease;white-space:nowrap}"
    "  .save-btn:hover{border-color:var(--accent);color:var(--accent)}"
    "  .save-btn.saved{border-color:#25a868;color:#25a868}"
    "</style>"
    "<script>"
    "function vib(pattern){if(navigator.vibrate)navigator.vibrate(pattern);}"
    "function doRec(btn,url,back){"
    "  vib([80]);"
    "  fetch(url);"
    "  btn.innerHTML='<span class=\"spin\"></span> Recording...';"
    "  btn.style.background='#b87a00';"
    "  btn.style.border='2px solid #f0a500';"
    "  btn.style.pointerEvents='none';"
    "  setTimeout(function(){window.location.href=back;},3000);"
    "  return false;"
    "}"
    "function doRename(slot,btn){"
    "  var inp=document.getElementById('n'+slot);"
    "  var name=inp.value.trim().substring(0,23);"
    "  fetch('/rename/'+slot,{method:'POST',headers:{'Content-Type':'text/plain'},body:name})"
    "  .then(function(r){if(r.ok){"
    "    btn.textContent='✓ Saved';btn.classList.add('saved');"
    "    var h3=btn.closest('.slot-block').querySelector('h3');"
    "    if(h3)h3.textContent=name||('Slot '+slot);"
    "    setTimeout(function(){btn.textContent='Save';btn.classList.remove('saved');},2000);"
    "  }});"
    "}"
    "</script>"
    "</head><body><main class='page'>";

// ==================== Hauptseite: 4 Remote-Karten ====================
static void build_home_html(char* buf, size_t buf_size) {
    static const char* remote_names[] = { "Remote 1", "Remote 2", "Remote 3", "Remote 4" };
    int pos = 0;

#define SNPRINTF_SAFE(buf, size, pos, ...) do { \
    int _n = snprintf((buf)+(pos), (size_t)(pos) < (size) ? (size)-(pos) : 0, __VA_ARGS__); \
    if (_n > 0) (pos) += _n; \
} while(0)

    SNPRINTF_SAFE(buf, buf_size, pos, "%s", HTML_STYLE);
    SNPRINTF_SAFE(buf, buf_size, pos,
        "<section class='header'>"
        "<h1>IR Remote Control</h1>"
        "<p class='sub'>FPGA Slot Control auf ESP32-C3</p>"
        "</section>"
        "<section class='remote-grid'>");

    for (int r = 0; r < REMOTE_COUNT; r++) {
        int first_slot = r * SLOTS_PER_REMOTE;
        int last_slot  = first_slot + SLOTS_PER_REMOTE - 1;

        // Zähle wie viele Slots dieses Remotes bereits recorded sind
        int rec_count = 0;
        for (int s = first_slot; s <= last_slot; s++) {
            if ((recorded_slots >> s) & 1) rec_count++;
        }

        char badge_buf[96] = "";
        if (rec_count == SLOTS_PER_REMOTE)
            snprintf(badge_buf, sizeof(badge_buf), "<div class='badge'>&#10003; Alle Slots gespeichert</div>");
        else if (rec_count > 0)
            snprintf(badge_buf, sizeof(badge_buf), "<div class='badge'>&#10003; %d/%d Slots gespeichert</div>", rec_count, SLOTS_PER_REMOTE);

        SNPRINTF_SAFE(buf, buf_size, pos,
            "<a href='/remote/%d' class='remote-card'>"
            "<div class='remote-icon'>"
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 72' width='32' height='58'>"
            "<rect x='4' y='0' width='32' height='72' rx='10' ry='10' fill='#1e2d47' stroke='#3a5080' stroke-width='2'/>"
            "<rect x='12' y='8' width='16' height='10' rx='3' fill='#4da3ff' opacity='.85'/>"
            "<circle cx='14' cy='30' r='4' fill='#4da3ff'/>"
            "<circle cx='26' cy='30' r='4' fill='#4da3ff'/>"
            "<circle cx='14' cy='43' r='4' fill='#4da3ff'/>"
            "<circle cx='26' cy='43' r='4' fill='#4da3ff'/>"
            "<circle cx='14' cy='56' r='4' fill='#d64d62'/>"
            "<circle cx='26' cy='56' r='4' fill='#d64d62'/>"
            "</svg>"
            "</div>"
            "<div class='label'>%s</div>"
            "<div class='slots'>Slots %d &ndash; %d</div>"
            "%s"
            "</a>",
            r, remote_names[r], first_slot, last_slot, badge_buf);
    }

    SNPRINTF_SAFE(buf, buf_size, pos,
        "</section>"
        "</main></body></html>");

#undef SNPRINTF_SAFE
}

// ==================== Remote-Detailseite ====================
static void build_remote_html(char* buf, size_t buf_size, int remote_idx) {
    static const char* remote_names[] = { "Remote 1", "Remote 2", "Remote 3", "Remote 4" };
    int first_slot = remote_idx * SLOTS_PER_REMOTE;
    int last_slot  = first_slot + SLOTS_PER_REMOTE - 1;
    int pos = 0;

#define SNPRINTF_SAFE(buf, size, pos, ...) do { \
    int _n = snprintf((buf)+(pos), (size_t)(pos) < (size) ? (size)-(pos) : 0, __VA_ARGS__); \
    if (_n > 0) (pos) += _n; \
} while(0)

    SNPRINTF_SAFE(buf, buf_size, pos, "%s", HTML_STYLE);
    SNPRINTF_SAFE(buf, buf_size, pos,
        "<div class='toolbar'><a href='/' class='back'><span class='back-arrow'>&#8592;</span> Back to overview</a></div>"
        "<section class='header'>"
        "<h1>%s</h1>"
        "<p class='sub'>Slots %d &ndash; %d</p>"
        "</section>"
        "<section class='action-grid'>",
        remote_names[remote_idx], first_slot, last_slot);

    for (int i = 0; i < SLOTS_PER_REMOTE; i++) {
        int slot = first_slot + i;
        int is_recorded = (recorded_slots >> slot) & 1;
        const char* name = slot_names[slot][0] ? slot_names[slot] : "";
        char slot_label[32];
        if (name[0])
            snprintf(slot_label, sizeof(slot_label), "%s", name);
        else
            snprintf(slot_label, sizeof(slot_label), "Slot %d", slot);
        SNPRINTF_SAFE(buf, buf_size, pos,
            "<div class='slot-block'>"
            "<h3>%s</h3>"
            "<div class='slot-name-row'>"
            "<input id='n%d' class='slot-name-input' type='text' maxlength='23'"
            " placeholder='Name...' value='%s'>"
            "<button class='save-btn' onclick='doRename(%d,this)'>Save</button>"
            "</div>"
            "<a href='/replay/%d' class='btn play' onclick=\"vib([30,20,30])\">&#9654; PLAY</a>"
            "<a href='#' class='btn %s' onclick=\"return doRec(this,'/record/%d','/remote/%d')\">%s REC</a>"
            "</div>",
            slot_label,
            slot, name,
            slot,
            slot,
            is_recorded ? "rec-done" : "rec",
            slot, slot / SLOTS_PER_REMOTE,
            is_recorded ? "&#10003;" : "&#9679;");
    }

    SNPRINTF_SAFE(buf, buf_size, pos,
        "</section>"
        "</main></body></html>");

#undef SNPRINTF_SAFE
}
// ==================== Serielles Frame senden ====================
// Baut das 12-Bit Frame und taktet es bit-seriell über DATA/CLK zum FPGA.
static void fpga_send_frame(int slot, uint8_t cmd) {
    // 12-Bit Frame zusammenbauen:
    //   [11:6] = slot[5:0]  ([5:4]=remote_id, [3:0]=slot_num)
    //   [5:3]  = cmd[2:0]
    //   [2:0]  = magic
    uint16_t frame = (uint16_t)(((slot & 0x3F) << 6) | ((cmd & 0x07) << 3) | (FRAME_MAGIC & 0x07));

    ESP_LOGI(TAG, "TX Frame: slot=%d cmd=%s → 0x%03X",
             slot, (cmd == CMD_PLAY) ? "PLAY" : "REC", frame);

    // CLK idle LOW, DATA idle LOW
    gpio_set_level(FPGA_CLK_PIN,  0);
    gpio_set_level(FPGA_DATA_PIN, 0);
    vTaskDelay(pdMS_TO_TICKS(CLK_HALF_MS));

    // 12 Bits senden, MSB zuerst
    for (int i = 11; i >= 0; i--) {
        int bit = (frame >> i) & 1;

        // Datenbit anlegen (vor steigender Flanke)
        gpio_set_level(FPGA_DATA_PIN, bit);
        vTaskDelay(pdMS_TO_TICKS(CLK_HALF_MS));

        // Steigende Flanke – FPGA sampelt hier
        gpio_set_level(FPGA_CLK_PIN, 1);
        vTaskDelay(pdMS_TO_TICKS(CLK_HALF_MS));

        // Fallende Flanke
        gpio_set_level(FPGA_CLK_PIN, 0);
        vTaskDelay(pdMS_TO_TICKS(CLK_HALF_MS));
    }

    // Leitungen zurück auf idle LOW
    gpio_set_level(FPGA_DATA_PIN, 0);
    gpio_set_level(FPGA_CLK_PIN,  0);
}

// ==================== HTTP Handler: Startseite ====================
static esp_err_t root_handler(httpd_req_t* req) {
    char* buf = malloc(16384);
    if (!buf) { httpd_resp_send_500(req); return ESP_FAIL; }
    build_home_html(buf, 16384);
    httpd_resp_set_type(req, "text/html");
    httpd_resp_send(req, buf, HTTPD_RESP_USE_STRLEN);
    free(buf);
    return ESP_OK;
}

// ==================== HTTP Handler: Remote-Detailseite ====================
static esp_err_t remote_handler(httpd_req_t* req) {
    // URI: /remote/N  (N = 0..3)
    const char* p = strrchr(req->uri, '/');
    int remote = p ? atoi(p + 1) : -1;
    if (remote < 0 || remote > 3) { httpd_resp_send_404(req); return ESP_FAIL; }
    char* buf = malloc(24576);
    if (!buf) { httpd_resp_send_500(req); return ESP_FAIL; }
    build_remote_html(buf, 24576, remote);
    httpd_resp_set_type(req, "text/html");
    httpd_resp_send(req, buf, HTTPD_RESP_USE_STRLEN);
    free(buf);
    return ESP_OK;
}

// ==================== HTTP Handler: Replay (PLAY) ====================
static esp_err_t replay_handler(httpd_req_t* req) {
    const char* p = strrchr(req->uri, '/');
    int slot = p ? atoi(p + 1) : -1;
    if (slot < 0 || slot >= SLOT_COUNT) { httpd_resp_send_404(req); return ESP_FAIL; }

    fpga_send_frame(slot, CMD_PLAY);

    char location[24];
    snprintf(location, sizeof(location), "/remote/%d", slot / SLOTS_PER_REMOTE);
    httpd_resp_set_status(req, "303 See Other");
    httpd_resp_set_hdr(req, "Location", location);
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

// ==================== HTTP Handler: Record (REC) ====================
static esp_err_t record_handler(httpd_req_t* req) {
    const char* p = strrchr(req->uri, '/');
    int slot = p ? atoi(p + 1) : -1;
    if (slot < 0 || slot >= SLOT_COUNT) { httpd_resp_send_404(req); return ESP_FAIL; }

    fpga_send_frame(slot, CMD_REC);

    // Slot als "recorded" markieren
    recorded_slots |= (1ULL << slot);

    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

// ==================== HTTP Handler: Rename (POST) ====================
static esp_err_t rename_handler(httpd_req_t* req) {
    const char* p = strrchr(req->uri, '/');
    int slot = p ? atoi(p + 1) : -1;
    if (slot < 0 || slot >= SLOT_COUNT) { httpd_resp_send_404(req); return ESP_FAIL; }

    // Body einlesen (max. SLOT_NAME_MAX - 1 Zeichen)
    char body[SLOT_NAME_MAX] = {0};
    int len = req->content_len;
    if (len >= SLOT_NAME_MAX) len = SLOT_NAME_MAX - 1;
    if (len > 0) httpd_req_recv(req, body, len);
    body[len] = '\0';

    // Name speichern
    strncpy(slot_names[slot], body, SLOT_NAME_MAX - 1);
    slot_names[slot][SLOT_NAME_MAX - 1] = '\0';

    ESP_LOGI(TAG, "Slot %d umbenannt → \"%s\"", slot, slot_names[slot]);
    httpd_resp_send(req, "OK", 2);
    return ESP_OK;
}

// ==================== HTTP-Server starten ====================
static void start_webserver(void) {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.lru_purge_enable = true;
    config.max_uri_handlers = 12;
    config.uri_match_fn = httpd_uri_match_wildcard;
    httpd_handle_t server = NULL;

    if (httpd_start(&server, &config) != ESP_OK) {
        ESP_LOGE(TAG, "HTTP-Server konnte nicht gestartet werden!");
        return;
    }

    httpd_uri_t uri_root    = { .uri = "/",          .method = HTTP_GET,  .handler = root_handler    };
    httpd_uri_t uri_remote  = { .uri = "/remote/*",  .method = HTTP_GET,  .handler = remote_handler  };
    httpd_uri_t uri_replay  = { .uri = "/replay/*",  .method = HTTP_GET,  .handler = replay_handler  };
    httpd_uri_t uri_record  = { .uri = "/record/*",  .method = HTTP_GET,  .handler = record_handler  };
    httpd_uri_t uri_rename  = { .uri = "/rename/*",  .method = HTTP_POST, .handler = rename_handler  };

    httpd_register_uri_handler(server, &uri_root);
    httpd_register_uri_handler(server, &uri_remote);
    httpd_register_uri_handler(server, &uri_replay);
    httpd_register_uri_handler(server, &uri_record);
    httpd_register_uri_handler(server, &uri_rename);

    ESP_LOGI(TAG, "HTTP-Server gestartet – IR Slot Control bereit");
}

// ==================== FPGA GPIO-Pins initialisieren ====================
static void fpga_gpio_init(void) {
    const gpio_num_t output_pins[] = { FPGA_DATA_PIN, FPGA_CLK_PIN };
    gpio_config_t io_conf = {
        .mode         = GPIO_MODE_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE
    };
    for (int i = 0; i < 2; i++) {
        io_conf.pin_bit_mask = (1ULL << output_pins[i]);
        gpio_config(&io_conf);
        gpio_set_level(output_pins[i], 0);
    }
    ESP_LOGI(TAG, "FPGA GPIO-Pins initialisiert (DATA=GPIO%d, CLK=GPIO%d)",
             FPGA_DATA_PIN, FPGA_CLK_PIN);
}

// ==================== Wi-Fi Event Handler ====================
static void wifi_event_handler(void* arg, esp_event_base_t event_base,
                               int32_t event_id, void* event_data) {
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_AP_STACONNECTED) {
        wifi_event_ap_staconnected_t* e = (wifi_event_ap_staconnected_t*) event_data;
        ESP_LOGI(TAG, "Geraet verbunden - MAC: %02x:%02x:%02x:%02x:%02x:%02x, AID=%d",
                 e->mac[0], e->mac[1], e->mac[2], e->mac[3], e->mac[4], e->mac[5], e->aid);
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_AP_STADISCONNECTED) {
        wifi_event_ap_stadisconnected_t* e = (wifi_event_ap_stadisconnected_t*) event_data;
        ESP_LOGI(TAG, "Geraet getrennt - MAC: %02x:%02x:%02x:%02x:%02x:%02x, AID=%d",
                 e->mac[0], e->mac[1], e->mac[2], e->mac[3], e->mac[4], e->mac[5], e->aid);
    }
}

// ==================== Main ====================
void app_main(void) {
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }

    fpga_gpio_init();

    esp_netif_init();
    esp_event_loop_create_default();
    esp_netif_create_default_wifi_ap();   // AP-Netzwerk-Interface

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    esp_wifi_init(&cfg);

    esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL);

    wifi_config_t wifi_config = {
        .ap = {
            .ssid           = WIFI_SSID,
            .ssid_len       = strlen(WIFI_SSID),
            .channel        = WIFI_AP_CHANNEL,
            .password       = WIFI_PASS,
            .max_connection = WIFI_AP_MAX_CONN,
            .authmode       = WIFI_AUTH_WPA2_PSK,
        },
    };
    // Offenes Netz wenn kein Passwort gesetzt
    if (strlen(WIFI_PASS) == 0) {
        wifi_config.ap.authmode = WIFI_AUTH_OPEN;
    }

    esp_wifi_set_mode(WIFI_MODE_AP);
    esp_wifi_set_config(WIFI_IF_AP, &wifi_config);
    esp_wifi_start();

    ESP_LOGI(TAG, "SoftAP gestartet. SSID: \"%s\"  Passwort: \"%s\"", WIFI_SSID, WIFI_PASS);
    ESP_LOGI(TAG, ">>> Webseite: http://192.168.4.1 <<<");

    start_webserver();
}
