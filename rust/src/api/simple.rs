#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[cfg(not(target_arch = "wasm32"))]
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(target_arch = "wasm32")]
#[flutter_rust_bridge::frb(sync)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

// ✅ Heavy computation - synchron für jetzt
#[flutter_rust_bridge::frb(sync)]
pub fn heavy_computation(input: i32) -> i32 {
    // Einfache Berechnung
    let mut result = input;
    for _ in 0..1000 {
        result = (result * 2) % 1000000;
    }
    result
}

// ✅ Mit echter Async (nur für Non-WASM)
#[cfg(not(target_family = "wasm"))]
#[flutter_rust_bridge::frb()]
pub async fn async_heavy_work(input: i32) -> i32 {
    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    input * 2
}