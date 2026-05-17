# 🕹️ Google Cloud Arcade – Automation Hub

One-click bash scripts that automate Google Cloud Arcade labs.  
Run directly in **Google Cloud Shell** inside the lab environment.

---

## 🚀 Quick Start

```bash
git clone https://github.com/KrushnaHangargekar/arcade_automation.git
cd arcade_automation
```

Then navigate to the specific lab folder and run its `solve.sh`.

---

## 📚 Available Labs

### GSP344 – Develop Serverless Apps with Firebase: Challenge Lab

```bash
cd arcade_automation
bash solve.sh
```

| # | Task | Detail |
|---|------|--------|
| 1 | Create Firestore Database | Native mode · Auto-detected region |
| 2 | Import Netflix CSV | Node.js import from `pet-theory` repo |
| 3 | REST API v0.1 | Cloud Run · `netflix-dataset-service` |
| 4 | REST API v0.2 | Firestore-connected · smoke-tested |
| 5 | Staging Frontend | Cloud Run · `frontend-staging-service` |
| 6 | Production Frontend | `app.js` patched · `frontend-production-service` |

---

### GSP699 – Migrating a Monolithic Website to Microservices on GKE

```bash
cd arcade_automation/GSP699
bash solve.sh
```

> Resume from a specific task (e.g. if cluster already exists):
> ```bash
> bash solve.sh 4
> ```

| # | Task | Detail |
|---|------|--------|
| 1 | Clone source repo | Install NodeJS deps via `setup.sh` |
| 2 | Create GKE cluster | `fancy-cluster` · 3 nodes · `e2-standard-4` |
| 3 | Deploy Monolith | `deploy-monolith.sh` · LoadBalancer service |
| 4 | Migrate Orders | Cloud Build image · GKE deploy · reconfigure monolith |
| 5 | Migrate Products | Cloud Build image · GKE deploy · reconfigure monolith |
| 6 | Migrate Frontend + Delete Monolith | Final microservices deployment · monolith deleted |

---

## ⚙️ Options

### GSP344 – Override region

```bash
REGION=us-east1 bash solve.sh
```

### GSP699 – Override zone/region

```bash
ZONE=us-central1-a REGION=us-central1 bash GSP699/solve.sh
```

### Both labs – Resume from a task

```bash
bash solve.sh 3        # start from task 3
```

---

## ⚠️ Important Notes

- Run **only** in **Google Cloud Shell** inside the lab
- Use **Incognito mode** to avoid personal account conflicts
- Do **not** run on your personal GCP project (charges may apply)
- Scripts are **idempotent** – safe to re-run if interrupted

---

## 📂 Repository Structure

```
arcade_automation/
├── solve.sh          ← GSP344 master script
└── GSP699/
    └── solve.sh      ← GSP699 master script
```

---

## 🔑 Key Technical Decisions

| Lab | Decision | Reason |
|-----|----------|--------|
| GSP344 | Auto-detect allowed region via Artifact Registry probe | Org policy differs per lab |
| GSP344 | `--max-instances 1` on all services | Lab quota requirement |
| GSP344 | Exact `sed` pattern for `app.js` | Matched against real `pet-theory` source |
| GSP699 | Write `.env.monolith` directly (no `nano`) | Fully non-interactive |
| GSP699 | `wait_for_ip` polls 30× with 10s delay | LoadBalancer IP takes time to provision |
| GSP699 | Save IPs to `/tmp/` between tasks | Allows safe `--start-task N` resumption |
| GSP699 | Idempotent deployment checks | Re-runs won't duplicate resources |
