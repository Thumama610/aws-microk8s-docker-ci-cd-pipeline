# microk8s installation

      sudo apt update && sudo apt upgrade -y
      sudo apt install -y curl wget apt-transport-https ca-certificates gnupg
      sudo snap install microk8s --classic
      sudo usermod -aG microk8s ubuntu
      mkdir -p ~/.kube
      microk8s config > ~/.kube/config
      sudo chown -f -R ubuntu ~/.kube
      microk8s status --wait-ready
      microk8s enable dns storage
      microk8s kubectl get nodes
      sudo snap alias microk8s.kubectl kubectl
      kubectl get nodes # I'll use this alias all over the workflow (microk8s.kubectl = kubectl)
      
# docker installation

    sudo apt update && sudo apt upgrade -y
    sudo apt install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker ubuntu

# nginx installation

    sudo apt update && sudo apt upgrade -y
    sudo apt install nginx
    sudo systemctl start nginx
    sudo systemctl enable nginx

# nginx config file

    user www-data;
    worker_processes auto;
    
    error_log /var/log/nginx/error.log warn;
    pid /run/nginx.pid;
    
    events {
        worker_connections 1024;
    }
    
    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;
    
        log_format main
          '$remote_addr - $remote_user [$time_local] "$request" '
          '$status $body_bytes_sent "$http_referer" '
          '"$http_user_agent" "$http_x_forwarded_for"';
    
        access_log /var/log/nginx/access.log main;
    
        sendfile        on;
        keepalive_timeout 65;
    
        
        # Docker run: -p 8080:4000
    	
        server {
            listen 8080;
            server_name _;
    
            location / {
                proxy_pass http://127.0.0.1:8080;
                proxy_http_version 1.1;
    
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
    
                proxy_connect_timeout 60s;
                proxy_read_timeout 60s;
            }
        }
    
        #Kubernetes NodePort: 32000
    	
        server {
            listen 80;
            server_name _;
    
            location / {
                proxy_pass http://127.0.0.1:32000;
                proxy_http_version 1.1;
    
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
    
                proxy_connect_timeout 60s;
                proxy_read_timeout 60s;
            }
        }
    }

# k8s resource definition:

    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: django-app
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: django
      template:
        metadata:
          labels:
            app: django
        spec:
          imagePullSecrets:
            - name: ecr-secret
          containers:
            - name: django
              image: AWS_ID.dkr.ecr.us-east-1.amazonaws.com/thumama/task:0.1.0.dev0 # AWS_ID is hidden for security
              ports:
                - containerPort: 3000
              env:
                - name: DJANGO_SETTINGS_MODULE
                  value: project.settings
              command: ["gunicorn"]
              args:
                - project.wsgi:application
                - --bind
                - 0.0.0.0:3000
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: django-service
    spec:
      type: NodePort
      selector:
        app: django
      ports:
        - port: 3000
          targetPort: 3000
          nodePort: 32000

# aws installation

	sudo apt update
	sudo apt install -y unzip curl 
	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
	unzip awscliv2.zip
	sudo ./aws/install
	aws --version # verify
	aws login

# Dockerfile 

    FROM python:3.11-slim
    
    ENV PYTHONDONTWRITEBYTECODE=1
    ENV PYTHONUNBUFFERED=1
    
    WORKDIR /app
    
    RUN apt-get update && apt-get install -y \
        build-essential \
        libpq-dev \
        curl \
        && rm -rf /var/lib/apt/lists/*
    
    RUN pip install --upgrade pip && pip install poetry
    
    COPY pyproject.toml poetry.lock* /app/
    RUN poetry install --no-root --only main
    
    COPY . /app/
    
    EXPOSE 80
    
    CMD ["poetry", "run", "gunicorn", "--bind", "0.0.0.0:80", "book_shop.wsgi:application"]
