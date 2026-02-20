FROM python:3.9-slim
WORKDIR /app
RUN pip install pandas scikit-learn==1.0.2 tensorflow==2.7.0 mlflow==1.22.0 bentoml==1.0.0rc3 pyyaml==6.0
COPY . .
ENTRYPOINT ["python", "train_and_build_bento.py"]