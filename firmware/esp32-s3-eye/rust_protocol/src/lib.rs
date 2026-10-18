//! Rust side of the ESP32-S3-EYE camera firmware: the same framed USB protocol as the
//! companion, with one extra device->host message for on-device camera detections.
//!
//! Build as a `staticlib` for `xtensa-esp32s3-none-elf` and link it into the ESP-WHO
//! C++ app; the C++ detection callback calls [`omni_proto_on_detections`].

#![no_std]

use core::ffi::c_void;
use core::sync::atomic::{AtomicBool, AtomicI32, AtomicU16};

use kataglyphis_esp32_proto::{
    encode, Chip, Decoder, DeviceInfo, Message, Telemetry, COMMAND_SET_LED,
    COMMAND_SET_TELEMETRY_PERIOD, MAX_FRAME, PROTOCOL_VERSION,
};

#[repr(C)]
struct UsbSerialJtagConfig {
    tx_buffer_size: usize,
    rx_buffer_size: usize,
}

unsafe extern "C" {
    fn usb_serial_jtag_driver_install(config: *const UsbSerialJtagConfig) -> i32;
    fn usb_serial_jtag_read_bytes(buf: *mut u8, length: u32, ticks_to_wait: u32) -> i32;
    fn usb_serial_jtag_write_bytes(buf: *const u8, length: u32, ticks_to_wait: u32) -> i32;
    fn xTaskCreatePinnedToCore(
        task: Option<unsafe extern "C" fn(*mut c_void)>,
        name: *const u8,
        stack_depth: u32,
        params: *mut c_void,
        priority: u32,
        handle: *mut *mut c_void,
        core_id: i32,
    ) -> i32;
    fn xTaskGetTickCount() -> u32;
    fn vTaskDelay(ticks: u32);
    fn esp_efuse_mac_get_default(mac: *mut u8) -> i32;
    fn esp_get_free_heap_size() -> u32;
    fn gpio_set_level(gpio_num: i32, level: u32) -> i32;
}

static SEQUENCE: AtomicU16 = AtomicU16::new(0);
static PENDING: AtomicBool = AtomicBool::new(false);
static PENDING_COUNT: AtomicU16 = AtomicU16::new(0);
static PENDING_SCORE: AtomicU16 = AtomicU16::new(0);
static LAST_COUNT: AtomicU16 = AtomicU16::new(0);
static TELEMETRY_PERIOD_MS: AtomicU16 = AtomicU16::new(1000);
static USB_DRIVER_STATUS: AtomicI32 = AtomicI32::new(-1);

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

/// Called once from `app_main`; creates the protocol task.
#[no_mangle]
pub extern "C" fn omni_proto_start() {
    static TASK_NAME: &[u8] = b"omni_proto\0";
    unsafe {
        xTaskCreatePinnedToCore(
            Some(task),
            TASK_NAME.as_ptr(),
            12 * 1024,
            core::ptr::null_mut(),
            5,
            core::ptr::null_mut(),
            i32::MAX,
        );
    }
}

/// Called from the ESP-WHO detect callback (detect task); coalesces successive results.
#[no_mangle]
pub extern "C" fn omni_proto_on_detections(count: u32, score_permille: u32) {
    let count = count.min(u16::MAX as u32) as u16;
    let score = score_permille.min(1000) as u16;
    PENDING_COUNT.store(count, core::sync::atomic::Ordering::Relaxed);
    PENDING_SCORE.store(score, core::sync::atomic::Ordering::Relaxed);
    LAST_COUNT.store(count, core::sync::atomic::Ordering::Relaxed);
    PENDING.store(true, core::sync::atomic::Ordering::Release);
}

unsafe extern "C" fn task(_: *mut c_void) {
    let config = UsbSerialJtagConfig {
        tx_buffer_size: 4096,
        rx_buffer_size: 4096,
    };
    // The console may already have installed the driver; read/write still work if so.
    let status = usb_serial_jtag_driver_install(&config);
    USB_DRIVER_STATUS.store(status, core::sync::atomic::Ordering::Relaxed);

    let mut decoder = Decoder::new();
    let mut buffer = [0u8; 256];
    let mut last_telemetry = xTaskGetTickCount();
    let mut last_camera = last_telemetry;
    let mut last_hello = 0u32;

    loop {
        let read = usb_serial_jtag_read_bytes(buffer.as_mut_ptr(), buffer.len() as u32, 10);
        if read > 0 {
            let bytes = &buffer[..read as usize];
            if !decoder.push(bytes) {
                decoder = Decoder::new();
            }
            while let Some(frame) = decoder.next_frame() {
                match frame.message {
                    Message::HostHello { version } if version == PROTOCOL_VERSION => {
                        send(Message::Hello(device_info()));
                        send(Message::Telemetry(telemetry()));
                    }
                    Message::HostHello { .. } => send(Message::Error { code: 1 }),
                    Message::Ping { id } => send(Message::Pong { id }),
                    Message::SetLed {
                        red,
                        green,
                        blue,
                        blink_ms: _,
                    } => {
                        // The EYE's green LED is GPIO3.
                        let level = u32::from((red | green | blue) != 0);
                        let _ = gpio_set_level(3, level);
                        send(Message::Ack {
                            command: COMMAND_SET_LED,
                        });
                    }
                    Message::SetTelemetryPeriod { ms } => {
                        TELEMETRY_PERIOD_MS.store(ms, core::sync::atomic::Ordering::Relaxed);
                        send(Message::Ack {
                            command: COMMAND_SET_TELEMETRY_PERIOD,
                        });
                    }
                    _ => {}
                }
            }
        }

        let now = xTaskGetTickCount();
        if now.wrapping_sub(last_hello) >= 2000 {
            // The host's Hello is authoritative; repeating ours keeps the app connected
            // even if the USB Serial/JTAG RX path is unavailable.
            send(Message::Hello(device_info()));
            last_hello = now;
        }
        let period = TELEMETRY_PERIOD_MS.load(core::sync::atomic::Ordering::Relaxed) as u32;
        if period > 0 && now.wrapping_sub(last_telemetry) >= period {
            send(Message::Telemetry(telemetry()));
            last_telemetry = now;
        }

        if PENDING.swap(false, core::sync::atomic::Ordering::AcqRel)
            && now.wrapping_sub(last_camera) >= 100
        {
            send(Message::CameraDetection {
                count: PENDING_COUNT.load(core::sync::atomic::Ordering::Relaxed),
                score_permille: PENDING_SCORE.load(core::sync::atomic::Ordering::Relaxed),
            });
            last_camera = now;
        }

        vTaskDelay(10);
    }
}

fn send(message: Message) {
    let sequence = SEQUENCE.fetch_add(1, core::sync::atomic::Ordering::Relaxed);
    let mut frame = [0u8; MAX_FRAME];
    if let Ok(len) = encode(sequence, &message, &mut frame) {
        let _ = unsafe { usb_serial_jtag_write_bytes(frame.as_ptr(), len as u32, 100) };
    }
}

fn device_info() -> DeviceInfo {
    let mut mac = [0u8; 6];
    let _ = unsafe { esp_efuse_mac_get_default(mac.as_mut_ptr()) };
    DeviceInfo {
        protocol: PROTOCOL_VERSION,
        firmware_major: 0,
        firmware_minor: 2,
        firmware_patch: USB_DRIVER_STATUS
            .load(core::sync::atomic::Ordering::Relaxed)
            .clamp(0, 255) as u8,
        chip: Chip::Esp32S3,
        mac,
        uptime_ms: unsafe { xTaskGetTickCount() },
    }
}

fn telemetry() -> Telemetry {
    Telemetry {
        uptime_ms: unsafe { xTaskGetTickCount() },
        free_heap: unsafe { esp_get_free_heap_size() },
        temperature_centi_c: 0,
        flags: 0,
        detection_count: LAST_COUNT.load(core::sync::atomic::Ordering::Relaxed),
    }
}
