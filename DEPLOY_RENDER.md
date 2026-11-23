# Deploying KGPL Portal to Render

This project is configured for **Unified Deployment on Render**. One Web Service serves both the Flutter Web Portal and the Express REST API simultaneously from a single port.

---

## Architecture on Render
* **Frontend:** Flutter Web (pre-compiled in `frontend/build/web`, served statically by Node.js).
* **Backend:** Express REST API (`/api/v1`, `/uploads`, `/health`).
* **Databases:**
  * **MySQL 8:** Cloud MySQL (Aiven, TiDB Cloud, Clever Cloud, or Railway).
  * **MongoDB:** MongoDB Atlas (M0 free cluster) or local fallback.

---

## Step 1: Push Repository to GitHub

Run these commands in PowerShell or Terminal:

```bash
git remote add origin https://github.com/<YOUR_USERNAME>/<YOUR_REPO>.git
git push -u origin main
```

---

## Step 2: Deploy on Render

### Method A: 1-Click Blueprint (Recommended)
1. Go to [dashboard.render.com](https://dashboard.render.com/).
2. Click **New +** > **Blueprint**.
3. Select your GitHub repository.
4. Render will automatically detect `render.yaml` and configure:
   * **Name:** `kgpl-portal`
   * **Runtime:** Node.js
   * **Build Command:** `cd backend && npm install && npm run build`
   * **Start Command:** `cd backend && npm start`
   * **Health Check Path:** `/health`
5. Click **Apply**.

---

### Method B: Manual Web Service
1. Click **New +** > **Web Service**.
2. Select your repository.
3. Configure the settings:
   * **Environment:** `Node`
   * **Region:** Any (e.g., Oregon / Frankfurt)
   * **Branch:** `main`
   * **Build Command:** `cd backend && npm install && npm run build`
   * **Start Command:** `cd backend && npm start`
4. Add the **Environment Variables** (see below).
5. Click **Deploy Web Service**.

---

## Step 3: Configure Environment Variables

In your Render Service > **Environment**:

| Variable | Value / Description | Required? |
|---|---|---|
| `NODE_ENV` | `production` | Yes |
| `PORT` | `10000` (Render sets automatically) | Yes |
| `JWT_SECRET` | A secure random 32-character string | Yes |
| `MYSQL_URL` | Cloud MySQL URI (e.g. `mysql://user:pass@host:port/kgpl_portal`) | Yes |
| `MONGO_URI` | MongoDB Atlas URI (e.g. `mongodb+srv://user:pass@cluster.mongodb.net/kgpl_portal`) | Optional (falls back to local JSON if omitted) |
| `CORS_ORIGINS` | `*` | Yes |

---

## Step 4: Database Setup (Cloud MySQL)

Render provides PostgreSQL natively, so for MySQL 8 you can use any free MySQL cloud provider:

1. **Aiven (Free MySQL):** [aiven.io](https://aiven.io/)
2. **TiDB Cloud (Free Serverless MySQL):** [tidbcloud.com](https://tidbcloud.com/)
3. **Clever Cloud:** [clever-cloud.com](https://www.clever-cloud.com/)

### Initializing Database Schema:
Once your cloud MySQL database is created, import the tables and seed data:

```bash
# Using mysql CLI or DBeaver / MySQL Workbench:
mysql -h <HOST> -u <USER> -p <DB_NAME> < database_schema.sql
mysql -h <HOST> -u <USER> -p <DB_NAME> < seed_demo.sql
```

---

## Verification
Once Render finishes building:
* Health Check: `https://<your-render-subdomain>.onrender.com/health` (returns `{"status":"online"}`)
* Live Web App: `https://<your-render-subdomain>.onrender.com/` (loads the portal login & workspace)
