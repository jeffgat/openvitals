use std::fs;

use open_vitals_core::{
    OpenVitalsError,
    capture_correlation::{
        CaptureCorrelationOptions, CaptureCorrelationReport,
        DEFAULT_MIN_OWNED_CAPTURES_PER_SUMMARY, run_capture_correlation_for_store,
    },
    metric_readiness::{MetricInputReadinessOptions, run_metric_input_readiness},
    report::write_json_report,
    store::OpenVitalsStore,
    tool_args::{args, flag, path_value, value},
};

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(2);
    }
}

fn run() -> open_vitals_core::OpenVitalsResult<()> {
    let args = args();
    let output = path_value(&args, "--output")?;
    let correlation = if let Some(path) = path_value(&args, "--capture-correlation")? {
        let raw = fs::read_to_string(&path).map_err(|source| OpenVitalsError::io(&path, source))?;
        serde_json::from_str::<CaptureCorrelationReport>(&raw)
            .map_err(|source| OpenVitalsError::json(&path, source))?
    } else {
        let database_path = path_value(&args, "--database")?
            .ok_or_else(|| OpenVitalsError::message("--database is required"))?;
        let store = OpenVitalsStore::open(&database_path)?;
        run_capture_correlation_for_store(
            &store,
            &database_path.display().to_string(),
            &value(&args, "--start")?.unwrap_or_else(|| "0000".to_string()),
            &value(&args, "--end")?.unwrap_or_else(|| "9999".to_string()),
            CaptureCorrelationOptions {
                min_owned_captures_per_summary: optional_usize(&args, "--min-owned-captures")?
                    .unwrap_or(DEFAULT_MIN_OWNED_CAPTURES_PER_SUMMARY),
                require_owned_captures: flag(&args, "--require-owned-captures"),
            },
        )?
    };
    let report = run_metric_input_readiness(
        &correlation,
        MetricInputReadinessOptions {
            require_scores_ready: flag(&args, "--require-scores-ready"),
        },
    );
    let pass = report.pass;

    write_json_report(&report, output.as_deref())?;
    if pass {
        Ok(())
    } else {
        std::process::exit(1);
    }
}

fn optional_usize(args: &[String], name: &str) -> open_vitals_core::OpenVitalsResult<Option<usize>> {
    Ok(value(args, name)?
        .map(|raw| {
            raw.parse::<usize>()
                .map_err(|source| OpenVitalsError::message(format!("invalid {name}: {source}")))
        })
        .transpose()?)
}
