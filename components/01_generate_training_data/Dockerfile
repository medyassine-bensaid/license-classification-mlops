FROM python:3.9-slim
WORKDIR /app
RUN pip install feast[sqlite]==0.21.1 pandas
COPY generate.py .
ENTRYPOINT ["python", "generate.py"]