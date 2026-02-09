# Django CI/CD Pipeline with GitHub Actions, Docker & AWS

This repository contains a complete CI/CD pipeline for a Django application using **GitHub Actions**, **Docker**, and **AWS**.  
The pipeline builds, versions, pushes Docker images to **Amazon ECR**, and deploys them automatically to:

- **EC2 (Docker runtime)** on `dev` branch
- **Kubernetes cluster** on `main` branch

---

## 🚀 Workflow Overview

The pipeline is triggered automatically on `push` events and behaves differently depending on the branch:

### 🔹 `dev` Branch (Development Environment)
1. Extracts the application version from `pyproject.toml`
2. Builds a Docker image using the extracted version
3. Pushes the image to Amazon ECR
4. Connects to an EC2 instance via SSH
5. Pulls and runs the new Docker image using Docker

### 🔹 `main` Branch (Production Environment)
1. Extracts the application version from `pyproject.toml`
2. Builds and pushes a versioned Docker image to Amazon ECR
3. Connects to an EC2 instance hosting a Kubernetes cluster
4. Creates/updates an ECR image pull secret
5. Deploys the application using Kubernetes manifests
6. Updates the running deployment image (rolling update)

---

## 🧱 Pipeline Jobs

### 1️⃣ Prepare
- Checks out the code
- Extracts the application version from `pyproject.toml`
- Exposes the version as a reusable output for other jobs

### 2️⃣ Test Version
- Verifies that the extracted version is correctly passed between jobs

### 3️⃣ Docker Build & Push
- Builds the Docker image
- Tags it with the extracted version
- Pushes it to Amazon ECR

### 4️⃣ Deploy
- **Dev:** SSH into EC2 and run the container directly using Docker
- **Main:** Deploy to Kubernetes and update the running image

---

## 🐳 Docker Image Versioning

The Docker image tag is dynamically generated from the version defined in ------> pyproject.toml

This ensures:

Traceable deployments

Easy rollbacks

Consistent versioning across environments

## ☁️ AWS Services Used

Amazon ECR – Docker image registry

Amazon EC2 – Hosting Docker runtime & Kubernetes cluster

IAM – Secure access using GitHub Secrets

## 🔐 Required GitHub Secrets

Make sure the following secrets are configured in your repository:

Secret Name	Description
AWS_USER_ACCESS_KEY	AWS access key
AWS_USER_SECRET_ACCESS_KEY	AWS secret key
AWS_ID	AWS account ID
REGION	AWS region
EC2_IP	Public IP of EC2 instance
EC2_USERNAME	SSH username
EC2_PRIVATE_KEY	SSH private key

## 📦 Kubernetes Deployment

The production deployment uses a Kubernetes manifest:

django-app.yaml


The image is updated dynamically using:

kubectl set image deployment/django-app django=<ECR_IMAGE:VERSION>


This allows zero-downtime rolling updates.

## ✅ Features

Branch-based environments (dev / production)

Automatic version extraction

Docker image versioning

Secure AWS authentication

EC2 & Kubernetes deployment support

Fully automated CI/CD pipeline

## 🛠️ Technologies Used

GitHub Actions

Docker

Django

AWS (ECR, EC2, IAM)

Kubernetes

Bash

Nginx

## 🔧 Prerequisites & Environment Setup

This section describes the required tools and configurations needed before running the CI/CD pipeline, including AWS, Docker, Kubernetes, GitHub Secrets, and Nginx configured as a reverse proxy.

Nginx is used to route incoming traffic from standard HTTP ports to the application services:

Port 80 → 3000 (Dockerized Django application on EC2 – development)

Port 8080 → 4000 (Application service running inside containers / Kubernetes – production)

This setup provides a clean entry point, improves security by hiding internal application ports, and allows seamless scaling and future SSL/TLS support.

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
                proxy_pass http://127.0.0.1:4000;
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

# pipeline 

	name: django app

	on:
	  push:
	    branches:
	      - main
	      - dev
	
	jobs:
	  prepare:
	    outputs:
	      image_version: ${{ steps.set_version.outputs.version }}
	    runs-on: ubuntu-latest
	    steps:
	      - name: check out
	        uses: actions/checkout@v4
	
	      - name: extract version (main)
	        if: ${{ github.ref == 'refs/heads/main' }}
	        run: |
	          echo "VERSION=$(grep 'version' pyproject.toml | grep -Eo '[0-9]+\.[0-9]+([.][0-9]+)*|[0-9]+')" >> "$GITHUB_ENV"
	
	      - name: extract version (dev)
	        if: ${{ github.ref == 'refs/heads/dev' }}
	        run: |
	          echo "VERSION=$(grep 'version' pyproject.toml | cut -d'"' -f2)" >> "$GITHUB_ENV"
	
	      - name: test the env var
	        run: echo "${{ env.VERSION }}"
	
	      - name: set and output the version
	        id: set_version
	        run: echo "version=$VERSION" >> $GITHUB_OUTPUT
	
	  test_version:
	    runs-on: ubuntu-latest
	    needs: prepare
	    steps:
	      - name: check for the version
	        run: echo "version is :${{ needs.prepare.outputs.image_version }}"
	
	  docker_build_and_push:
	    runs-on: ubuntu-latest
	    needs: prepare
	    steps:
	      - name: check out
	        uses: actions/checkout@v4
	
	      - name: Configure AWS Credentials
	        uses: aws-actions/configure-aws-credentials@v4
	        with:
	          aws-access-key-id: ${{ secrets.AWS_USER_ACCESS_KEY }}
	          aws-secret-access-key: ${{ secrets.AWS_USER_SECRET_ACCESS_KEY }}
	          aws-region: ${{ secrets.REGION }}
	
	      - name: docker login
	        run: |
	          aws ecr get-login-password --region ${{ secrets.REGION }} \
	          | docker login --username AWS --password-stdin \
	          ${{ secrets.AWS_ID }}.dkr.ecr.${{ secrets.REGION }}.amazonaws.com
	
	      - name: Build and push
	        run: |
	          docker build -t thumama/task:${{ needs.prepare.outputs.image_version }} .
	
	          docker tag thumama/task:${{ needs.prepare.outputs.image_version }} \
	          ${{ secrets.AWS_ID }}.dkr.ecr.${{ secrets.REGION }}.amazonaws.com/thumama/task:${{ needs.prepare.outputs.image_version }}
	
	          docker push \
	          ${{ secrets.AWS_ID }}.dkr.ecr.${{ secrets.REGION }}.amazonaws.com/thumama/task:${{ needs.prepare.outputs.image_version }}
	
	          echo "=====================success========================="
	
	  ec2-ssh-pull-and-deploy:
	    runs-on: ubuntu-latest
	    needs: [docker_build_and_push, prepare]
	    steps:
	      - name: ec2 ssh and pull to dev
	        if: ${{ github.ref == 'refs/heads/dev' }}
	        uses: appleboy/ssh-action@v1
	        with:
	          host: ${{ secrets.EC2_IP }}
	          username: ${{ secrets.EC2_USERNAME }}
	          key: ${{ secrets.EC2_PRIVATE_KEY }}
	          script: |
	            echo "version is:====> ${{ needs.prepare.outputs.image_version }}"
	            echo "================ssh works===================="
	            aws ecr get-login-password --region ${{ secrets.REGION }} \
	            | docker login --username AWS --password-stdin \
	            ${{ secrets.AWS_ID }}.dkr.ecr.${{ secrets.REGION }}.amazonaws.com
	
	            docker pull ${{ secrets.AWS_ID }}.dkr.ecr.${{ secrets.REGION }}\
	            .amazonaws.com/thumama/task:${{ needs.prepare.outputs.image_version }}
	
	            docker run --name test -dp 4000:4000 ${{ secrets.AWS_ID }}.dkr.ecr.${{ secrets.REGION }}.amazonaws.com/thumama/task:${{ needs.prepare.outputs.image_version }}
	
	      - name: ec2 ssh and pull to main
	        if: ${{ github.ref == 'refs/heads/main' }}
	        uses: appleboy/ssh-action@v1
	        with:
	          host: ${{ secrets.EC2_IP }}
	          username: ${{ secrets.EC2_USERNAME }}
	          key: ${{ secrets.EC2_PRIVATE_KEY }}
	          script: |
	            echo "version is:====> ${{ needs.prepare.outputs.image_version }}"
	            echo "================ssh works===================="
	            aws ecr get-login-password --region ${{ secrets.REGION }} \
	            | sudo kubectl create secret docker-registry ecr-secret \
	            --docker-server=${{ secrets.AWS_ID }}.dkr.ecr.${{ secrets.REGION }}.amazonaws.com \
	            --docker-username=AWS \
	            --docker-password-stdin
	
	            kubectl apply -f django-app.yaml
	
	            kubectl set image deployment/django-app \
	            django=${{ secrets.AWS_ID }}.dkr.ecr.${{ secrets.REGION }}.amazonaws.com/thumama/task:${{ needs.prepare.outputs.image_version }}


<img width="1920" height="919" alt="Screenshot (154) new" src="https://github.com/user-attachments/assets/21839daf-1b5b-4008-ba1b-6cf260e390b9" />
<img width="1920" height="922" alt="Screenshot (153) new" src="https://github.com/user-attachments/assets/e41e30ca-5acc-446b-9236-c19cdfbbd00e" />
<img width="1920" height="923" alt="Screenshot (152) new" src="https://github.com/user-attachments/assets/cea0fea9-cba4-4596-83e9-3debe4a44d85" />

<img width="1920" height="1041" alt="Screenshot (156) new" src="https://github.com/user-attachments/assets/cab0659e-ced8-4119-9b94-25ec78c122dd" />
<img width="1920" height="1041" alt="Screenshot (155) new" src="https://github.com/user-attachments/assets/b5ca709d-c371-41cc-b586-fbae2b1b9a12" />
<img width="1920" height="828" alt="Screenshot (157) new" src="https://github.com/user-attachments/assets/6239b6b0-f3b1-41aa-b6f0-d6ad1c8d6bfb" />



## 👤 Author

Thumama Alrowwad
DevOps / Cloud Enthusiast
