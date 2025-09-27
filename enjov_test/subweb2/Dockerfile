FROM python:3.9-slim
ENV PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt
COPY . /app
EXPOSE 8000
USER 1000
CMD ["gunicorn", "subweb2project.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2"]
