# Kubernetes Standards & Best Practices

> **Purpose:** Patterns and conventions for Kubernetes resources.

---

## 🏗️ Cluster Architecture

### Standard Setup
```
Cluster: [company]-[env]-[region]
│
├── System Namespaces
│   ├── kube-system         # K8s core components
│   ├── kube-public         # Publicly accessible data
│   ├── kube-node-lease     # Node heartbeats
│   ├── ingress-nginx       # Ingress controller
│   ├── cert-manager        # Certificate management
│   └── monitoring          # Prometheus, Grafana
│
└── Application Namespaces
    ├── [env]-[team]-[app]  # One per application
    └── [env]-shared        # Shared resources
```

---

## 🏷️ Naming Conventions

### Namespaces
```yaml
# Format: [env]-[team]-[app]
# Ejemplos:
prod-platform-api
staging-data-pipeline
dev-app-frontend
```

### Resources
```yaml
# Deployments: [app]-[component]
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
  namespace: prod-platform-api

# Services: [app]-[component]-svc
apiVersion: v1
kind: Service
metadata:
  name: api-backend-svc
  namespace: prod-platform-api

# ConfigMaps: [app]-config
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config

# Secrets: [app]-secrets
apiVersion: v1
kind: Secret
metadata:
  name: api-secrets
```

---

## 🏷️ Labels & Annotations

### Required Labels (ALL resources)
```yaml
metadata:
  labels:
    app.kubernetes.io/name: api
    app.kubernetes.io/instance: api-prod
    app.kubernetes.io/version: "1.2.3"
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: platform
    app.kubernetes.io/managed-by: helm  # or terraform, argocd

    # Custom labels
    environment: prod
    team: platform
    cost-center: "1234"
```

### Recommended Annotations
```yaml
metadata:
  annotations:
    description: "API backend service"
    owner: "platform-team@example.com"
    documentation: "https://docs.company.com/api"

    # Monitoring
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

---

## 🚀 Deployment Best Practices

### Standard Deployment
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
  namespace: prod-platform-api
  labels:
    app.kubernetes.io/name: api
spec:
  # ✅ Multiple replicas for HA
  replicas: 3

  # ✅ Rolling update strategy
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero downtime

  selector:
    matchLabels:
      app.kubernetes.io/name: api
      app.kubernetes.io/instance: api-prod

  template:
    metadata:
      labels:
        app.kubernetes.io/name: api
        app.kubernetes.io/instance: api-prod
        app.kubernetes.io/version: "1.2.3"

    spec:
      # ✅ Security context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000

      # ✅ Service account
      serviceAccountName: api-backend

      # ✅ Pod anti-affinity (spread across nodes)
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values: [api]
              topologyKey: kubernetes.io/hostname

      containers:
      - name: api
        image: registry.company.com/api:1.2.3  # ✅ Specific version, NOT :latest
        imagePullPolicy: IfNotPresent

        # ✅ Ports
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP

        # ✅ Health checks
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3

        # ✅ Resource limits
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi

        # ✅ Environment variables
        env:
        - name: ENVIRONMENT
          value: "prod"
        - name: LOG_LEVEL
          value: "info"

        # ✅ Secrets from external sources
        envFrom:
        - secretRef:
            name: api-secrets
        - configMapRef:
            name: api-config

        # ✅ Security context
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]

        # ✅ Volume mounts (if needed)
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /app/cache

      # ✅ Volumes
      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}
```

---

## 🌐 Service Best Practices

### ClusterIP (interno)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-backend-svc
  namespace: prod-platform-api
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: api
    app.kubernetes.io/instance: api-prod
  ports:
  - name: http
    port: 80
    targetPort: http
    protocol: TCP
  sessionAffinity: None
```

### LoadBalancer / Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: prod-platform-api
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rate-limit: "100"
spec:
  tls:
  - hosts:
    - api.company.com
    secretName: api-tls
  rules:
  - host: api.company.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-backend-svc
            port:
              number: 80
```

---

## 🔐 Security Best Practices

### RBAC
```yaml
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-backend
  namespace: prod-platform-api

---
# Role (namespace-scoped)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: api-backend-role
  namespace: prod-platform-api
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]

---
# RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-backend-binding
  namespace: prod-platform-api
subjects:
- kind: ServiceAccount
  name: api-backend
  namespace: prod-platform-api
roleRef:
  kind: Role
  name: api-backend-role
  apiGroup: rbac.authorization.k8s.io
```

### Pod Security Standards
```yaml
# Namespace-level enforcement (K8s 1.25+)
apiVersion: v1
kind: Namespace
metadata:
  name: prod-platform-api
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-network-policy
  namespace: prod-platform-api
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: api

  policyTypes:
  - Ingress
  - Egress

  # Allow ingress from ingress controller only
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080

  # Allow egress to database namespace
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: prod-platform-database
    ports:
    - protocol: TCP
      port: 5432

  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

---

## 📦 ConfigMaps & Secrets

### ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-config
  namespace: prod-platform-api
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  DATABASE_HOST: "postgres.prod-platform-database.svc.cluster.local"

  # Files
  app.properties: |
    server.port=8080
    spring.datasource.url=jdbc:postgresql://postgres/mydb
```

### Secrets (External Secrets Operator preferred)
```yaml
# ✅ PREFERIDO: External Secrets Operator
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-secrets
  namespace: prod-platform-api
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: api-secrets
    creationPolicy: Owner
  data:
  - secretKey: DATABASE_PASSWORD
    remoteRef:
      key: prod/api/database-password

---
# ⚠️ ALTERNATIVE: Sealed Secrets (encrypted in git)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: api-secrets
  namespace: prod-platform-api
spec:
  encryptedData:
    DATABASE_PASSWORD: AgBh7F8... # encrypted
```

---

## 📊 Resource Management

### Resource Quotas (Namespace)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: prod-platform-api-quota
  namespace: prod-platform-api
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    persistentvolumeclaims: "10"
    services.loadbalancers: "2"
```

### LimitRange (Default limits)
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: prod-platform-api
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 256Mi
    type: Container
```

---

## 🔄 GitOps Patterns

### ArgoCD Application
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api-backend-prod
  namespace: argocd
spec:
  project: platform

  source:
    repoURL: https://github.com/company/k8s-manifests
    targetRevision: main
    path: apps/api/overlays/prod

  destination:
    server: https://kubernetes.default.svc
    namespace: prod-platform-api

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

---

## 🛡️ Pod Disruption Budget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: prod-platform-api
spec:
  minAvailable: 1  # Or maxUnavailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: api
```

---

## 📈 HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
  namespace: prod-platform-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-backend

  minReplicas: 3
  maxReplicas: 10

  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70

  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80

  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

---

## 🚫 Anti-Patterns

❌ **AVOID:**
- The `latest` tag on images
- Deployments without health checks
- Containers running as root
- No definir resource requests/limits
- Unencrypted secrets in git
- Network policies inexistentes (allow all by default)
- A single replica in prod
- Privileged containers without a reason
- No namespaces (everything in default)

---

## 🔍 Troubleshooting Checklist

```bash
# 1. Check pod status
kubectl get pods -n [namespace]

# 2. Describe pod (events, conditions)
kubectl describe pod [pod-name] -n [namespace]

# 3. Logs
kubectl logs [pod-name] -n [namespace] --tail=100 -f

# 4. Previous logs (if crashed)
kubectl logs [pod-name] -n [namespace] --previous

# 5. Exec into pod
kubectl exec -it [pod-name] -n [namespace] -- /bin/sh

# 6. Check events
kubectl get events -n [namespace] --sort-by='.lastTimestamp'

# 7. Check resource usage
kubectl top pods -n [namespace]
kubectl top nodes
```

---

## 📝 Notas

- **Kubernetes version:** [1.28+]
- **CNI:** [Calico, Cilium, etc.]
- **Ingress Controller:** [nginx, traefik, etc.]
- **Certificate Manager:** cert-manager
- **Secrets Management:** External Secrets Operator + AWS Secrets Manager
- **GitOps:** ArgoCD / Flux
