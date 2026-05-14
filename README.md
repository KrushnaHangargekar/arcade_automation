# GSP344 – Develop Serverless Apps with Firebase: Challenge Lab
# Arcade Automation

Automated one-click script to complete all **6 tasks** of the Google Cloud Arcade lab:
> **GSP344 – Develop Serverless Apps with Firebase: Challenge Lab**

---

## 🚀 One Command in Cloud Shell

Open **Google Cloud Shell** inside the lab and run:

```bash
git clone https://github.com/KrushnaHangargekar/arcade_automation.git
cd arcade_automation
bash solve.sh
```

> ⚠️ **Must run in Google Cloud Shell**, not locally (Windows/Mac/Linux terminal).  
> `chmod` is not needed — just use `bash solve.sh`.

---

## 📋 What Gets Automated

| # | Task | Detail |
|---|------|--------|
| 1 | Create Firestore Database | Native mode · Region `us-west1` |
| 2 | Import Netflix CSV | Node.js script from `pet-theory` repo |
| 3 | REST API v0.1 | Cloud Run · `netflix-dataset-service` |
| 4 | REST API v0.2 | Firestore-connected · smoke-tested |
| 5 | Staging Frontend | Cloud Run · `frontend-staging-service` |
| 6 | Production Frontend | `app.js` patched · `frontend-production-service` |

---

## ⚙️ Optional: Override Cloud Run Region

The default Cloud Run region is `us-central1`. To change it:

```bash
REGION=us-east1 bash solve.sh
```

> Firestore is always created in `us-west1` (lab requirement — cannot be overridden).

---

## 🔑 Key Technical Decisions

| Decision | Reason |
|----------|--------|
| Firestore → `us-west1` | Explicitly required by lab instructions |
| Cloud Run → `us-central1` | Default; most capacity, lowest latency |
| `--max-instances 1` on all services | Lab requirement to stay within quota |
| Exact `sed` patterns for `app.js` | Matched against the real `pet-theory` source |
| Smoke-test after Task 4 | Catches Firestore permission issues early |
| Patch verification guard | Script exits with clear error if `app.js` wasn't updated |

---

## 📂 Structure

```
arcade_automation/
└── solve.sh    ← Master script — handles all 6 tasks
```
