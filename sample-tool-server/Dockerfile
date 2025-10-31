# Simple container for the dummy score API service
FROM python:3.11-slim

WORKDIR /app

# Install dependencies separately to leverage Docker layer caching
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY app.py ./

EXPOSE 8080

# Run the Flask development server; replace with a production server if needed
CMD ["python", "app.py"]
