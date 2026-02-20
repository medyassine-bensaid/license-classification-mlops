import bentoml
from bentoml.io import PandasDataFrame

license_classifier_runner = bentoml.sklearn.get("license_classifier:latest").to_runner()

svc = bentoml.Service("license_classifier_service", runners=[license_classifier_runner])

@svc.api(input=PandasDataFrame(), output=PandasDataFrame())
def predict(input_df):
    return license_classifier_runner.predict.run(input_df)