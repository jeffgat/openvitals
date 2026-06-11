use std::{fs, path::Path};

use open_vitals_core::{
    OpenVitalsError,
    metrics::SleepV1Input,
    report::write_json_report,
    sleep_validation::{
        SleepStageLabelValidationOptions, validate_sleep_v1_stage_labels_for_store,
    },
    store::OpenVitalsStore,
    tool_args::{args, path_value, value},
};

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(2);
    }
}

fn run() -> open_vitals_core::OpenVitalsResult<()> {
    let args = args();
    let Some(database_path) = value(&args, "--db")? else {
        return Err(OpenVitalsError::message(
            "missing --db <open_vitals.sqlite>",
        ));
    };
    let Some(input_path) = path_value(&args, "--input")? else {
        return Err(OpenVitalsError::message(
            "missing --input <open_vitals.sleep-v1-input.json>",
        ));
    };
    let output = path_value(&args, "--output")?;
    let defaults = SleepStageLabelValidationOptions::default();
    let options = SleepStageLabelValidationOptions {
        min_label_confidence: optional_f64(&args, "--min-label-confidence")?
            .unwrap_or(defaults.min_label_confidence),
        min_overlap_fraction: optional_f64(&args, "--min-overlap-fraction")?
            .unwrap_or(defaults.min_overlap_fraction),
    };
    let input = read_json::<SleepV1Input>(&input_path)?;
    let store = OpenVitalsStore::open(Path::new(&database_path))?;
    let report = validate_sleep_v1_stage_labels_for_store(&store, &input, options)?;
    write_json_report(&report, output.as_deref())?;
    if report.pass {
        Ok(())
    } else {
        std::process::exit(1);
    }
}

fn optional_f64(args: &[String], name: &str) -> open_vitals_core::OpenVitalsResult<Option<f64>> {
    value(args, name)?.map_or(Ok(None), |raw| {
        raw.parse::<f64>().map(Some).map_err(|error| {
            OpenVitalsError::message(format!("invalid {name} value {raw}: {error}"))
        })
    })
}

fn read_json<T: serde::de::DeserializeOwned>(path: &Path) -> open_vitals_core::OpenVitalsResult<T> {
    let raw = fs::read_to_string(path).map_err(|source| OpenVitalsError::io(path, source))?;
    serde_json::from_str(&raw).map_err(|source| OpenVitalsError::json(path, source))
}
