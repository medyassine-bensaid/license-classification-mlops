import os
import pandas as pd
import requests
import json
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset, TargetDriftPreset
from datetime import datetime

# --- Configuration ---
# In a real system, these would be fetched from a database or log store.
# For this example, we'll use local CSV files.
# The CronJob's volume mounts will provide these files to the container.
REFERENCE_DATA_PATH = "/data/reference_data.csv"
PRODUCTION_DATA_PATH = "/data/production_traffic.csv"
REPORT_OUTPUT_PATH = f"/reports/drift_report_{datetime.now().strftime('%Y-%m-%d')}.html"

def send_slack_alert(message: str):
    """Sends a formatted message to a Slack channel via a webhook."""
    webhook_url = os.getenv("SLACK_WEBHOOK_URL")
    if not webhook_url:
        print("WARNING: SLACK_WEBHOOK_URL environment variable not set. Skipping alert.")
        return
    
    headers = {'Content-Type': 'application/json'}
    payload = {'text': message}
    
    try:
        response = requests.post(webhook_url, data=json.dumps(payload), headers=headers)
        response.raise_for_status()
        print("Slack alert sent successfully.")
    except requests.exceptions.RequestException as e:
        print(f"ERROR: Failed to send Slack alert: {e}")

def generate_and_alert_on_drift():
    """
    Generates a data drift report using Evidently AI and sends a Slack
    alert if significant drift is detected.
    """
    print(f"Loading reference data from: {REFERENCE_DATA_PATH}")
    reference_df = pd.read_csv(REFERENCE_DATA_PATH)

    print(f"Loading production data from: {PRODUCTION_DATA_PATH}")
    production_df = pd.read_csv(PRODUCTION_DATA_PATH)

    # For TargetDriftPreset, we need a 'prediction' and 'target' column.
    # We will simulate this for the example.
    # In reality, you'd join your inference logs with ground truth labels.
    
    print("Generating drift report...")
    drift_report = Report(metrics=[
        DataDriftPreset(),
        # TargetDriftPreset(), # Enable this when you have ground truth labels
    ])
    
    # We need to ensure columns match for comparison
    common_columns = list(set(reference_df.columns) & set(production_df.columns))
    drift_report.run(reference_data=reference_df[common_columns], current_data=production_df[common_columns])
    
    # Save the visual HTML report to a persistent volume for inspection
    report_dir = os.path.dirname(REPORT_OUTPUT_PATH)
    os.makedirs(report_dir, exist_ok=True)
    drift_report.save_html(REPORT_OUTPUT_PATH)
    print(f"Drift report saved to {REPORT_OUTPUT_PATH}")

    # --- Alerting Logic ---
    report_dict = drift_report.as_dict()
    drift_details = report_dict['metrics'][0]['result']
    
    drift_detected = drift_details['dataset_drift']
    drift_score = drift_details['share_of_drifted_columns']
    num_drifted_columns = drift_details['number_of_drifted_columns']

    if drift_detected:
        message = (
            f":warning: *Production Model Drift Alert!* \n\n"
            f"> *Project:* `license-classification`\n"
            f"> *Drift Detected:* `{drift_detected}`\n"
            f"> *Drift Score (Share of Drifted Columns):* `{drift_score:.2%}`\n"
            f"> *Number of Drifted Columns:* `{num_drifted_columns}`\n\n"
            f"A full report has been generated and is available for review in the MLOps dashboard."
        )
        send_slack_alert(message)
    else:
        print("No significant data drift detected.")
        # Optionally send a success message
        # send_slack_alert(":white_check_mark: Daily model monitoring check passed for `license-classification`. No data drift detected.")

if __name__ == "__main__":
    generate_and_alert_on_drift()