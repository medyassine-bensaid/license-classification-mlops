import argparse
import pandas as pd
from feast import FeatureStore

def generate_data(feast_repo_path: str, output_path: str):
    store = FeatureStore(repo_path=feast_repo_path)
    entity_df = store.get_batch_source("license_features_view").to_df()
    entity_df = entity_df[["event_timestamp", "license_id", "LICENSE_STATUS"]]
    
    print("Generating training dataset from Feast...")
    training_data = store.get_historical_features(
        entity_df=entity_df,
        features=store.get_feature_view("license_features_view"),
    ).to_df()

    training_data.to_csv(output_path, index=False)
    print(f"Training dataset created successfully at {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--feast_repo", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    generate_data(feast_repo_path=args.feast_repo, output_path=args.output)