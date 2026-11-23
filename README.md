# KGPL Intern Training & Management Portal

> **Enterprise-grade, high-performance training and internship management portal built with Flutter 3.24 Web, Node.js (TypeScript) REST API, and MySQL 8.4.**

---

## 🚀 Quick Start (1-Click Run)

Everything runs from one command. The API starts automatically with the web portal; there is no separate backend step.

```bash
npm start
```

Or double-click:
```bat
START_PORTAL.bat
```

This will automatically:
1. Start the API on `http://localhost:5001`
2. Start the web portal on `http://localhost:3002`
3. Open your default browser to `http://localhost:3002`

MongoDB stores AI chat history, SOP metadata, question replies and video analytics. For production-style storage start it first with `START_MONGO.bat`; without it the API keeps working and falls back to JSON files in `backend/data/nosql/`. See `SETUP.md` section 2b.

Running `node frontend/serve.js` on its own also starts the API if it is not already running. Press `Ctrl+C` to stop both.

---

## 🔐 Demo Credentials & 1-Click Login

On the Login Page (`http://localhost:3000`), you will find **1-Click Quick Demo Login** buttons for instant testing without typing credentials:

| Role | Email | Password | Access Capabilities |
| :--- | :--- | :--- | :--- |
| **HR Admin** | `hr@kgpl.com` | `password` | User CRUD, Batches, Departments, Course/Video uploads, Announcements, Audit Logs, Excel/PDF Reports |
| **Team Leader** | `tl@kgpl.com` | `password` | Intern Progress Monitoring, Question Bank Builder, Test Scheduler with Date/Time Pickers, Task Reviews, Attendance Verification |
| **Intern** | `intern@kgpl.com` | `password` | Anti-Cheat Course Video Player, Interactive SOP Document Reader, Timed MCQ Quiz Runner, Task Submissions, Attendance Punch, QA Forum, Certificate Download |

---

## 📁 Project Architecture & Folder Structure

```
kgpl-portal-modern/
├── start.js                    # One-command launcher (API + web portal + browser)
├── package.json                # npm start / npm run dev
├── START_PORTAL.bat            # Double-click launcher for Windows
├── run_backend.bat             # Standalone API runner
├── run_frontend.bat            # Standalone Web runner
├── database_dump.sql           # Complete MySQL 8 database schema + seed data
├── README.md                   # Complete documentation & quickstart guide
│
├── backend/                    # High-Performance Node.js (TypeScript) REST API
│   ├── src/
│   │   ├── config/             # MySQL pool (db.ts) + MongoDB adapter (mongodb.ts)
│   │   ├── controllers/        # Auth, HR, Team Leader, Intern controllers
│   │   ├── middleware/         # JWT Auth & Audit Logging
│   │   ├── routes/             # RESTful API routing
│   │   └── server.ts           # Express application entrypoint
│   ├── package.json
│   └── tsconfig.json
│
└── frontend/                   # Modern Flutter 3.24 Web & Desktop Application
    ├── lib/
    │   ├── main.dart           # App entrypoint & routing
    │   ├── services/           # ApiService with JWT authentication headers
    │   └── views/
    │       ├── auth/           # Modern Glassmorphic Login with Quick Demo buttons
    │       ├── hr/             # HR Dashboard, Users, Batches, Courses, Reports, Audit Logs
    │       ├── team_leader/    # TL Dashboard, Intern Tracker, Question Bank & Test Scheduler
    │       └── intern/         # Intern Dashboard, Anti-Cheat Player, SOP Reader, Timed Quiz, Tasks
    ├── build/web/              # Precompiled production-ready web distribution
    ├── serve.js                # Lightweight Node.js static web server for port 3000
    └── pubspec.yaml            # Flutter dependencies & assets config
```

---

## 🗄️ Database Setup (Optional - If moving to a new machine)

The database schema and sample records are pre-exported in `database_dump.sql`.
To restore it on a fresh MySQL 8 installation:

```bash
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS kgpl_portal;"
mysql -u root -p kgpl_portal < database_dump.sql
```

The database configuration can be customized in `backend/src/config/db.ts` or via environment variables (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`).

---

## 🛠️ Manual Development Commands

### Entire portal (API + web):
```bash
npm start          # normal run
npm run dev        # auto-reloads the API on backend code changes
```

### Backend only:
```bash
cd backend
npm install
npm run dev
```

### Frontend:
```bash
cd frontend
flutter pub get
flutter run -d chrome
# or to rebuild web distribution:
flutter build web --release
```

---
© KGPL Intern Training & Management Portal. All rights reserved.
