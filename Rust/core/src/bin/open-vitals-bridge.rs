use std::io::{self, BufRead, Read, Write};

use open_vitals_core::bridge::handle_bridge_request_json;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(2);
    }
}

fn run() -> open_vitals_core::OpenVitalsResult<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|arg| arg == "--stdio") {
        run_stdio()
    } else {
        run_single_request()
    }
}

fn run_stdio() -> open_vitals_core::OpenVitalsResult<()> {
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();
    for line in stdin.lock().lines() {
        let request =
            line.map_err(|source| open_vitals_core::OpenVitalsError::io("<stdin>", source))?;
        if request.trim().is_empty() {
            continue;
        }
        writeln!(stdout, "{}", handle_bridge_request_json(&request))
            .map_err(|source| open_vitals_core::OpenVitalsError::io("<stdout>", source))?;
        stdout
            .flush()
            .map_err(|source| open_vitals_core::OpenVitalsError::io("<stdout>", source))?;
    }
    Ok(())
}

fn run_single_request() -> open_vitals_core::OpenVitalsResult<()> {
    let mut request = String::new();
    io::stdin()
        .read_to_string(&mut request)
        .map_err(|source| open_vitals_core::OpenVitalsError::io("<stdin>", source))?;
    if request.trim().is_empty() {
        return Err(open_vitals_core::OpenVitalsError::message(
            "open-vitals-bridge expects a bridge request JSON object on stdin or --stdio JSONL mode",
        ));
    }
    println!("{}", handle_bridge_request_json(&request));
    Ok(())
}
