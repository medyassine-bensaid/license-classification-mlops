import pandas as pd
from pathlib import Path

def prepare_data_for_feast(
    input_csv_path: str,
    output_dir: str,
    output_filename: str = "License_Data_With_Timestamp.csv"
):
    print(f"Loading raw data from {input_csv_path}...")
    df = pd.read_csv(input_csv_path, low_memory=False)

    print("Converting date columns to datetime format...")
    date_columns = ['DATE_ISSUED', 'LICENSE_STATUS_CHANGE_DATE', 'APPLICATION_REQUIREMENTS_COMPLETE', 'PAYMENT_DATE']
    for col in date_columns:
        df[col] = pd.to_datetime(df[col], errors='coerce')

    print("Creating the event_timestamp...")
    df['event_timestamp'] = df['DATE_ISSUED'].fillna(df['LICENSE_STATUS_CHANGE_DATE']).fillna(df['APPLICATION_REQUIREMENTS_COMPLETE']).fillna(df['PAYMENT_DATE'])

    print("Creating the created_timestamp...")
    df['created_timestamp'] = df[['APPLICATION_REQUIREMENTS_COMPLETE', 'PAYMENT_DATE']].min(axis=1).fillna(df['event_timestamp'])

    print(f"Original number of rows: {len(df)}")
    df.dropna(subset=['event_timestamp', 'created_timestamp', 'LICENSE_ID', 'LICENSE_STATUS'], inplace=True)
    print(f"Number of rows after cleaning: {len(df)}")
    
    df['LICENSE_ID'] = df['LICENSE_ID'].astype(int)

    output_path = Path(output_dir) / output_filename
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    print(f"Saving timestamped data to {output_path}...")
    df.to_csv(output_path, index=False)
    print("Data preparation for Feast is complete.")

if __name__ == "__main__":
    prepare_data_for_feast(
        input_csv_path="data/License_Data.csv",
        output_dir="feature_repo/data"
    )