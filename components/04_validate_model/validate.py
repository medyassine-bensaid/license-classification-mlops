import argparse
import mlflow
import pandas as pd
import yaml
from sklearn.metrics import accuracy_score

def validate_model(config_path: str, run_id: str, test_data_path: str):
    with open(config_path) as f:
        config = yaml.safe_load(f)

    mlflow.set_tracking_uri(config['mlflow_tracking_uri'])
    
    print(f"Loading model from run ID: {run_id}")
    logged_model_uri = f'runs:/{run_id}/model'
    model = mlflow.sklearn.load_model(logged_model_uri)

    print("Loading test data for validation...")
    test_df = pd.read_csv(test_data_path)
    X_test = test_df.drop(columns=["event_timestamp", "license_id", "LICENSE_STATUS"])
    y_test_encoded = pd.get_dummies(test_df['LICENSE_STATUS'])

    print("Evaluating model performance...")
    predictions = model.predict(X_test)
    
    # KerasClassifier might return probabilities, need to convert to class labels
    # If the output of predict is one-hot encoded, we can use argmax
    predicted_labels = pd.get_dummies(pd.DataFrame(predictions).idxmax(axis=1))

    accuracy = accuracy_score(y_test_encoded, predicted_labels)
    baseline_accuracy = config['training']['baseline_accuracy']
    print(f"Model Accuracy: {accuracy:.4f}")
    print(f"Baseline Accuracy Threshold: {baseline_accuracy:.4f}")

    # --- QUALITY GATE ---
    if accuracy < baseline_accuracy:
        raise ValueError(f"Model validation failed: Accuracy {accuracy:.4f} is below baseline {baseline_accuracy:.4f}.")

    print("Model validation successful!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--run_id", required=True)
    parser.add_argument("--test_data", required=True)
    args = parser.parse_args()
    validate_model(
        config_path=args.config,
        run_id=args.run_id,
        test_data_path=args.test_data,
    )