FROM python:3.9-slim

WORKDIR /app

RUN pip install pandas==1.3.5 evidently==0.1.53.dev0 requests==2.27.1

COPY generate_report.py .

# The entrypoint will be the script itself
ENTRYPOINT ["python", "generate_report.py"]