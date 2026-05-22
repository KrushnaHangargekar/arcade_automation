apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-cloudbuild
spec:
  selector:
    matchLabels:
      app: hello-cloudbuild
  replicas: 1
  template:
    metadata:
      labels:
        app: hello-cloudbuild
    spec:
      containers:
      - name: hello-cloudbuild
        image: us-east4-docker.pkg.dev/GOOGLE_CLOUD_PROJECT/my-repository/hello-cloudbuild:COMMIT_SHA
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: hello-cloudbuild
spec:
  type: LoadBalancer
  selector:
    app: hello-cloudbuild
  ports:
  - port: 80
    targetPort: 8080
