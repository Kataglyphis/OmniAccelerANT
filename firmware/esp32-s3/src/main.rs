//! OmniAccelerANT's ESP32-S3 companion firmware: USB Serial/JTAG protocol, BOOT button
//! and one status LED. The protocol crate is shared with the host, so a field added here
//! cannot drift from the Rust bridge.

#![no_std]
#![no_main]

use esp_backtrace as _;
use esp_hal::{
    Blocking,
    delay::Delay,
    efuse::{self, InterfaceMacAddress},
    gpio::{Input, InputConfig, Level, Output, OutputConfig, Pull},
    time::{Duration, Instant},
    usb::usb_serial_jtag::UsbSerialJtag,
};
use kataglyphis_esp32_proto::{
    COMMAND_DETECTION, COMMAND_SET_LED, COMMAND_SET_TELEMETRY_PERIOD, Chip, Decoder, DeviceInfo,
    MAX_FRAME, Message, PROTOCOL_VERSION, TELEMETRY_BUTTON_DOWN, Telemetry, encode,
};

esp_bootloader_esp_idf::esp_app_desc!();

/// The DevKitC-1's BOOT button (GPIO0, active low) and a plain LED on GPIO2. The onboard
/// WS2812 needs a data protocol, not a GPIO, so the status LED is the header pin.
const FIRMWARE: (u8, u8, u8) = (0, 1, 0);
const HELLO_RETRY_MS: u32 = 500;
const DEFAULT_TELEMETRY_MS: u16 = 1000;
const BUTTON_DEBOUNCE_MS: u32 = 20;

#[esp_hal::main]
fn main() -> ! {
    let peripherals = esp_hal::init(esp_hal::Config::default());
    let mut usb = UsbSerialJtag::new(peripherals.USB_DEVICE);
    let mut led = Output::new(peripherals.GPIO2, Level::Low, OutputConfig::default());
    let button = Input::new(
        peripherals.GPIO0,
        InputConfig::default().with_pull(Pull::Up),
    );
    let delay = Delay::new();

    let mut mac = [0u8; 6];
    mac.copy_from_slice(efuse::interface_mac_address(InterfaceMacAddress::Station).as_bytes());

    let start = Instant::now();
    let mut sequence = 0u16;
    let mut decoder = Decoder::new();
    let mut handshaked = false;
    let mut last_hello = start;
    let mut last_telemetry = start;
    let mut telemetry_period = DEFAULT_TELEMETRY_MS;
    let mut button_down = button.is_low();
    let mut button_count = 0u32;
    let mut last_button_edge = start;
    let mut detection_count = 0u16;
    let mut led_until: Option<Instant> = None;

    loop {
        while let Ok(byte) = usb.read_byte() {
            if !decoder.push(&[byte]) {
                decoder = Decoder::new();
            }
        }

        while let Some(frame) = decoder.next_frame() {
            match frame.message {
                Message::HostHello { version } => {
                    if version == PROTOCOL_VERSION {
                        handshaked = true;
                        send(&mut usb, &mut sequence, Message::Hello(info(mac, start)));
                        last_telemetry = Instant::now();
                    } else {
                        send(&mut usb, &mut sequence, Message::Error { code: 1 });
                    }
                }
                Message::Ping { id } => {
                    send(&mut usb, &mut sequence, Message::Pong { id });
                }
                Message::SetLed {
                    red,
                    green,
                    blue,
                    blink_ms,
                } => {
                    let on = (red | green | blue) != 0;
                    set_led(&mut led, on);
                    led_until = (on && blink_ms > 0)
                        .then(|| Instant::now() + Duration::from_millis(blink_ms as u64));
                    send(
                        &mut usb,
                        &mut sequence,
                        Message::Ack {
                            command: COMMAND_SET_LED,
                        },
                    );
                }
                Message::Detection {
                    count,
                    score_permille,
                } => {
                    detection_count = count;
                    let now = Instant::now();
                    if count > 0 {
                        set_led(&mut led, true);
                        let ms = 120 + (score_permille as u64 * 180 / 1000);
                        led_until = Some(now + Duration::from_millis(ms));
                    } else {
                        set_led(&mut led, false);
                        led_until = None;
                    }
                    send(
                        &mut usb,
                        &mut sequence,
                        Message::Ack {
                            command: COMMAND_DETECTION,
                        },
                    );
                }
                Message::SetTelemetryPeriod { ms } => {
                    telemetry_period = ms;
                    send(
                        &mut usb,
                        &mut sequence,
                        Message::Ack {
                            command: COMMAND_SET_TELEMETRY_PERIOD,
                        },
                    );
                }
                _ => {}
            }
        }

        let now = Instant::now();

        if !handshaked && elapsed_ms(now, last_hello) >= HELLO_RETRY_MS {
            send(&mut usb, &mut sequence, Message::Hello(info(mac, start)));
            last_hello = now;
        }

        if handshaked
            && telemetry_period > 0
            && elapsed_ms(now, last_telemetry) >= telemetry_period as u32
        {
            let temperature_centi_c = 0;
            send(
                &mut usb,
                &mut sequence,
                Message::Telemetry(Telemetry {
                    uptime_ms: elapsed_ms(now, start),
                    free_heap: 0,
                    temperature_centi_c,
                    flags: if button_down {
                        TELEMETRY_BUTTON_DOWN
                    } else {
                        0
                    },
                    detection_count,
                }),
            );
            last_telemetry = now;
        }

        let pressed = button.is_low();
        if pressed != button_down && elapsed_ms(now, last_button_edge) >= BUTTON_DEBOUNCE_MS {
            button_down = pressed;
            last_button_edge = now;
            if pressed {
                button_count = button_count.wrapping_add(1);
            }
            send(
                &mut usb,
                &mut sequence,
                Message::Button {
                    pressed,
                    count: button_count,
                },
            );
        }

        if let Some(until) = led_until {
            if now >= until {
                set_led(&mut led, false);
                led_until = None;
            }
        }

        delay.delay_millis(1);
    }
}

fn info(mac: [u8; 6], start: Instant) -> DeviceInfo {
    DeviceInfo {
        protocol: PROTOCOL_VERSION,
        firmware_major: FIRMWARE.0,
        firmware_minor: FIRMWARE.1,
        firmware_patch: FIRMWARE.2,
        chip: Chip::Esp32S3,
        mac,
        uptime_ms: elapsed_ms(Instant::now(), start),
    }
}

fn elapsed_ms(now: Instant, earlier: Instant) -> u32 {
    (now - earlier).as_millis() as u32
}

fn set_led(led: &mut Output<'_>, on: bool) {
    if on {
        led.set_high();
    } else {
        led.set_low();
    }
}

/// Non-blocking on purpose: with no host reading, a blocking write to the USB FIFO would
/// freeze the whole loop, including the button and the LED timers.
fn send(usb: &mut UsbSerialJtag<'_, Blocking>, sequence: &mut u16, message: Message) {
    let mut frame = [0u8; MAX_FRAME];
    let Ok(len) = encode(*sequence, &message, &mut frame) else {
        return;
    };
    for &byte in &frame[..len] {
        if usb.write_byte_nb(byte).is_err() {
            return;
        }
    }
    let _ = usb.flush_tx_nb();
    *sequence = sequence.wrapping_add(1);
}
