//! Hardware probe for the ESP32-S3 camera + AI route.
//!
//! Prints the MAC, reports PSRAM (if any), and scans the two common camera SCCB pin
//! pairs for an OV2640/OV5640 sensor. It replaces the companion firmware while it
//! runs; reflash `firmware/esp32-s3` afterwards.

#![no_std]
#![no_main]

use esp_backtrace as _;
use esp_hal::{
    Blocking,
    delay::Delay,
    efuse::{self, InterfaceMacAddress},
    gpio::DriveMode,
    i2c::master::{Config as I2cConfig, I2c},
    ledc::{
        LSGlobalClkSource, Ledc, LowSpeed,
        channel::{self, ChannelIFace},
        timer::{self, TimerIFace},
    },
    psram::{Psram, PsramConfig},
    time::Rate,
    usb::usb_serial_jtag::UsbSerialJtag,
};
use esp_println::{print, println};

esp_bootloader_esp_idf::esp_app_desc!();

#[esp_hal::main]
fn main() -> ! {
    let peripherals = esp_hal::init(esp_hal::Config::default());
    let _usb = UsbSerialJtag::new(peripherals.USB_DEVICE);
    let delay = Delay::new();

    println!("\r\n=== OmniAccelerANT ESP32-S3 camera probe ===");

    let mut mac = [0u8; 6];
    mac.copy_from_slice(efuse::interface_mac_address(InterfaceMacAddress::Station).as_bytes());
    print!("MAC: ");
    for (index, byte) in mac.iter().enumerate() {
        if index > 0 {
            print!(":");
        }
        print!("{byte:02X}");
    }
    println!();

    let psram = Psram::new(peripherals.PSRAM, PsramConfig::default());
    let (_, size) = psram.raw_parts();
    println!("PSRAM: {size} bytes ({} MiB)", size / 1024 / 1024);
    if size == 0 {
        println!("  no PSRAM reported: on-device camera AI will be very limited");
    }

    // The sensor's SCCB slave often answers only once XCLK runs. The EYE/Freenove
    // boards use GPIO15; the XIAO uses GPIO10 (a second probe run can change this).
    // LEDC gives a clean 10 MHz, the rate the Zephyr ESP32-S3-EYE devicetree uses.
    let mut ledc = Ledc::new(peripherals.LEDC);
    ledc.set_global_slow_clock(LSGlobalClkSource::APBClk);
    let mut xclk_timer = ledc.timer::<LowSpeed>(timer::Number::Timer0);
    xclk_timer
        .configure(timer::config::Config {
            duty: timer::config::Duty::Duty1Bit,
            clock_source: timer::LSClockSource::APBClk,
            frequency: Rate::from_mhz(10),
        })
        .expect("configure XCLK timer");
    let mut xclk_channel = ledc.channel::<LowSpeed>(channel::Number::Channel0, peripherals.GPIO15);
    xclk_channel
        .configure(channel::config::Config {
            timer: &xclk_timer,
            duty_pct: 50,
            drive_mode: DriveMode::PushPull,
        })
        .expect("configure XCLK channel");
    delay.delay_millis(500);
    println!("XCLK: GPIO15 at 10 MHz (LEDC)");

    let found_eye = {
        let mut i2c = I2c::new(peripherals.I2C0, I2cConfig::default())
            .expect("I2C0")
            .with_sda(peripherals.GPIO4)
            .with_scl(peripherals.GPIO5);
        scan(&mut i2c, "SDA=4 SCL=5 (ESP32-S3-EYE / Freenove CAM)")
    };

    if found_eye {
        println!("skipping the XIAO pin pair: a camera already answered");
    } else {
        let mut i2c = I2c::new(peripherals.I2C1, I2cConfig::default())
            .expect("I2C1")
            .with_sda(peripherals.GPIO40)
            .with_scl(peripherals.GPIO39);
        scan(&mut i2c, "SDA=40 SCL=39 (XIAO ESP32S3 Sense)");
    }

    println!("probe done; repeating the PSRAM size every 5 s");
    loop {
        delay.delay_millis(5_000);
        let (_, size) = psram.raw_parts();
        println!("alive; PSRAM {size} bytes");
    }
}

fn scan(i2c: &mut I2c<'_, Blocking>, label: &str) -> bool {
    println!("I2C scan: {label}");
    let mut found = 0u32;
    let mut camera = false;

    for address in 0x08u8..=0x77 {
        let mut byte = [0u8; 1];
        // A bare read is not enough: SCCB sensors ACK a register write first.
        let acknowledged = i2c.write_read(address, &[0x00], &mut byte).is_ok()
            || i2c.read(address, &mut byte).is_ok();
        if !acknowledged {
            continue;
        }
        found += 1;
        println!("  found 0x{address:02X}");

        if let (Ok(pid), Ok(version)) = (
            read_register(i2c, address, 0x0A),
            read_register(i2c, address, 0x0B),
        ) {
            println!("    PID=0x{pid:02X} VER=0x{version:02X}");
            match (pid, version) {
                (0x26, 0x42) => {
                    println!("    -> OV2640");
                    camera = true;
                }
                (0x56, 0x40) => {
                    println!("    -> OV5640");
                    camera = true;
                }
                _ => {}
            }
        }
    }

    if found == 0 {
        println!("  no device acknowledged (a camera may need XCLK before SCCB answers)");
    }
    camera
}

fn read_register(i2c: &mut I2c<'_, Blocking>, address: u8, register: u8) -> Result<u8, ()> {
    let mut value = [0u8; 1];
    i2c.write_read(address, &[register], &mut value)
        .map_err(|_| ())?;
    Ok(value[0])
}
