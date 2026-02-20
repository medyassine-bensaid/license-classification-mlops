import argparse
import pandas as pd
from evidently.report import Report
from evidently.metric_preset import DataQualityPreset
import json
from pathlib import Path

def validate_data(reference_data_path: str, new_data_path: str, report_path: str):
    print("Loading data for validation...")
    # For the first run, reference and new data might be the same.
    # In subsequent runs, new_data would be the fresh pull.
    reference_df = pd.read_csv(reference_data_path, low_memory=False)
    new_df = pd.read_csv(new_data_path, low_memory=False)

    print("Generating data quality report...")
    data_quality_report = Report(metrics=[DataQualityPreset()])
    data_quality_report.run(reference_data=reference_df, current_data=new_df)
    
    report_dict = data_quality_report.as_dict()
    
    output_dir = Path(report_path).parent
    output_dir.mkdir(parents=True, exist_ok=True)
    with open(report_path, 'w') as f:
        json.dump(report_dict, f, indent=4)
    print(f"Full data quality report saved to {report_path}")

    # --- QUALITY GATE ---
    # Fail the pipeline if critical quality checks are not met.
    if not report_dict['metrics'][0]['result']['summary']['all_passed']:
        raise ValueError("Data validation failed: Not all quality metrics passed. Check the report.")
        
    print("Data validation successful!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference_data", required=True)
    parser.add_argument("--new_data", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    validate_data(
        reference_data_path=args.reference_data,
        new_data_path=args.new_data,
        report_path=args.report
    )