import argparse
import pandas as pd
import mlflow
import bentoml
import yaml
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import OneHotEncoder
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from tensorflow import keras
from tensorflow.keras import layers

def train_and_build(config_path: str, data_path: str, bento_tag_output: str):
    with open(config_path) as f:
        config = yaml.safe_load(f)

    df = pd.read_csv(data_path)
    
    mlflow.set_tracking_uri(config['mlflow_tracking_uri'])
    mlflow.set_experiment(config['mlflow_experiment_name'])
    
    with mlflow.start_run() as run:
        print(f"Starting MLflow Run: {run.info.run_id}")
        mlflow.log_params(config['training'])

        X = df.drop(columns=["event_timestamp", "license_id", "LICENSE_STATUS"])
        y = pd.get_dummies(df["LICENSE_STATUS"])
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=config['training']['random_state'])

        cat_features = X.select_dtypes(include=['object', 'string']).columns.tolist()
        num_features = X.select_dtypes(include=['number']).columns.tolist()

        preprocessor = ColumnTransformer(transformers=[
            ('num', 'passthrough', num_features),
            ('cat', OneHotEncoder(handle_unknown='ignore', sparse=False), cat_features)
        ])
        
        preprocessor.fit(X_train)
        input_shape = preprocessor.transform(X_train).shape[1]

        def create_model():
            model = keras.Sequential([
                layers.InputLayer(input_shape=(input_shape,)),
                layers.Dense(128, activation="relu"),
                layers.Dense(64, activation="relu"),
                layers.Dense(y.shape[1], activation="softmax"),
            ])
            model.compile(loss="categorical_crossentropy", optimizer="adam", metrics=['accuracy'])
            return model

        pipeline = Pipeline(steps=[
            ('preprocessor', preprocessor),
            ('classifier', keras.wrappers.scikit_learn.KerasClassifier(build_fn=create_model, epochs=config['training']['epochs']))
        ])
        pipeline.fit(X_train, y_train)

        accuracy = pipeline.score(X_test, y_test)
        print(f"Model accuracy: {accuracy:.4f}")
        mlflow.log_metric("accuracy", accuracy)
        mlflow.sklearn.log_model(sk_model=pipeline, artifact_path="model")
        
        print("Packaging model with BentoML...")
        bento_model = bentoml.sklearn.save_model(
            name=config['deployment']['model_name'],
            model=pipeline,
            signatures={"predict": {"batchable": True, "batch_dim": 0}},
            metadata={"mlflow_run_id": run.info.run_id, "accuracy": accuracy}
        )
        print(f"BentoML model saved: {bento_model.tag}")
        
        # Write run_id and bento_tag to files for downstream components
        with open("mlflow_run_id.txt", "w") as f:
            f.write(run.info.run_id)
        with open(bento_tag_output, "w") as f:
            f.write(str(bento_model.tag))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--data", required=True)
    parser.add_argument("--bento_tag_output", required=True)
    args = parser.parse_args()
    train_and_build(
        config_path=args.config,
        data_path=args.data,
        bento_tag_output=args.bento_tag_output
    )