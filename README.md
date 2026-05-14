# GSP344 – Develop Serverless Apps with Firebase: Challenge Lab
# Arcade Automation

Automated one-click script to complete all **6 tasks** of the Google Cloud Arcade lab:
> **GSP344 – Develop Serverless Apps with Firebase: Challenge Lab**

---

## 🚀 What This Script Does

| # | Task | What Gets Deployed |
|---|------|--------------------|
| 1 | Create Firestore Database | Native mode · Region `us-west1` |
| 2 | Import Netflix CSV | Node.js import from `pet-theory` repo |
| 3 | REST API v0.1 | Cloud Run · `netflix-dataset-service` |
| 4 | REST API v0.2 | Firestore-connected revision |
| 5 | Staging Frontend | Cloud Run · `frontend-staging-service` |
| 6 | Production Frontend | Cloud Run · `frontend-production-service` · real data |

---

## 🛠️ Usage (Google Cloud Shell)

```bash
# 1. Clone this repo
git clone https://github.com/KrushnaHangargekar/arcade_automation.git
cd arcade_automation

# 2. Make executable & run
chmod +x solve.sh
./solve.sh
```

The script auto-detects your project ID and region. No manual edits required.

---

## ⚙️ Prerequisites

- Lab started and Cloud Shell open
- Student account credentials active
- All billing/quota available (handled by the lab)

---

## 📂 Structure

```
arcade_automation/
└── solve.sh    ← Master automation script (all 6 tasks)
```

---

## 🔑 Key Decisions

- **Firestore region**: `us-west1` (as required by lab instructions)
- **Cloud Run region**: `us-central1` (default; override with `REGION=<region> ./solve.sh`)
- **`--max-instances 1`** on every Cloud Run deployment (lab requirement)
- **`app.js` patch**: Handles multiple source variants from the `pet-theory` repo robustly
- **Idempotent**: Re-running the script skips already-completed steps (Firestore / Artifact Registry creation)
