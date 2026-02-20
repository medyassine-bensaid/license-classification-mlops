FROM python:3.9-slim
WORKDIR /app
RUN pip install pandas scikit-learn==1.0.2 tensorflow==2.7.0 mlflow==1.22.0 pyyaml==6.0
COPY validate.py .
ENTRYPOINT ["python", "validate.py"]