# Google Cloud Arcade Automation (GSP642)
Automated script to complete the "Import Data to a Firestore Database" lab.

## 🚀 One-Click Automation
This repository contains scripts to automate the following tasks:
1. Enable required APIs.
2. Setup Firestore Database (Native Mode).
3. Install Node.js dependencies.
4. Generate 1000 test records.
5. Import records into Firestore.

## 🛠️ Usage Instructions

### Method 1: Cloud Shell (Recommended)
1. Open Cloud Shell in your Google Cloud Console.
2. Clone this repository:
   ```bash
   git clone https://github.com/<YOUR_USERNAME>/arcade_automation.git
   cd arcade_automation
   ```
3. Run the automation script:
   ```bash
   chmod +x solve.sh
   ./solve.sh
   ```

### Method 2: Local Windows (PowerShell)
1. Clone the repo.
2. Open PowerShell and navigate to the folder.
3. Run:
   ```powershell
   .\solve.ps1
   ```

## 📂 Project Structure
- `lab01/`: Contains the Node.js logic for data generation and import.
- `solve.sh`: The master bash script for full automation.
- `solve.ps1`: The master PowerShell script for Windows.
