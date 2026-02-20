FROM python:3.9-slim
WORKDIR /app
RUN pip install pandas==1.3.5 evidently==0.1.53.dev0
COPY validate.py .
ENTRYPOINT ["python", "validate.py"]