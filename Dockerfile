FROM python:3.11-slim

WORKDIR /app

# Install gunicorn
RUN pip install --no-cache-dir gunicorn

# Copy all files
COPY . /app/

# Install your app
RUN pip install /app/dist/*.whl*


ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

EXPOSE 4000

ENTRYPOINT [ "gunicorn" ]
CMD ["--bind", "0.0.0.0:4000", "book_shop.wsgi:application"]
