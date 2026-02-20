from datetime import timedelta
from feast import Entity, Feature, FeatureView, ValueType, FileSource

license_entity = Entity(name="license_id", value_type=ValueType.INT64)

raw_data_source = FileSource(
    path="feature_repo/data/License_Data_With_Timestamp.csv",
    event_timestamp_column="event_timestamp",
    created_timestamp_column="created_timestamp"
)

license_features_view = FeatureView(
    name="license_features_view",
    entities=["license_id"],
    ttl=timedelta(days=90),
    features=[
        Feature(name="SSA", dtype=ValueType.FLOAT),
        Feature(name="APPLICATION_TYPE", dtype=ValueType.STRING),
        Feature(name="BUSINESS_TYPE", dtype=ValueType.STRING),
    ],
    online=True,
    batch_source=raw_data_source,
    tags={"team": "mlops"},
)