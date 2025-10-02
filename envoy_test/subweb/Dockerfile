FROM python:3.9-slim
RUN pip install flask flask-socketio eventlet
COPY app.py /app.py
EXPOSE 80
CMD ["python","/app.py"]
