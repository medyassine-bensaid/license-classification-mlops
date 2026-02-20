FROM python:3.9-slim
WORKDIR /app
#Install Git for cloning the manifest repo
RUN apt-get update && apt-get install -y git
RUN pip install mlflow==1.22.0 pyyaml==6.0 GitPython==3.1.27
COPY promote_and_commit.py .
ENTRYPOINT ["python", "promote_and_commit.py"]