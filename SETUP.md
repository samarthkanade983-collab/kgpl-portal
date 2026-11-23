# KGPL Portal - Testing Package

This package runs the full portal with one command. The web app is already built, so **Flutter is not required**.

## Requirements

- Node.js 20.19 or newer (`node --version`)
- MySQL 8 running on this machine
- MongoDB 8 (optional, recommended) - see section 2b

## 1. Load the database

From this folder:

```bash
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS kgpl_portal;"
mysql -u root -p kgpl_portal < database_schema.sql
mysql -u root -p kgpl_portal < seed_demo.sql
```

If your MySQL root account has no password, leave out `-p`.

The schema file creates empty tables. The seed file adds two departments and the HR sign-in account only - no employee or intern records are included.

## 2. Check the database settings

Open `backend/.env` and adjust only if your MySQL setup differs:

```
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=
DB_NAME=kgpl_portal
```

The signing secret and the AI assistant key in that file were prepared for this package. Keep the file private and do not share the package outside the team.

## 2b. MongoDB (recommended)

AI assistant history, SOP metadata, question replies, video watch sessions and playback telemetry are stored in MongoDB. Without it the API falls back to JSON files in `backend/data/nosql/`, which does not scale to large volumes.

1. Start the local server in its own window:

   ```bat
   START_MONGO.bat
   ```

   It runs `mongodb-portable\bin\mongod.exe` on `127.0.0.1:27017` with data in `mongodb-portable\data` and a log in `mongodb-portable\log\mongod.log`.

2. Import any existing JSON documents (safe to re-run; existing `_id`s are skipped):

   ```bash
   cd backend
   npm run mongo:import
   ```

3. Start the portal. The API log should show:

   ```
   🍃 Connected to live MongoDB instance: mongodb://localhost:27017/kgpl_portal_nosql
   ```

Settings (all optional, defaults shown):

```
MONGO_URI=mongodb://localhost:27017
MONGO_DB_NAME=kgpl_portal_nosql
```

To use an existing MongoDB or Atlas cluster, set `MONGO_URI` in `backend/.env` and skip `START_MONGO.bat`.

## 3. Start the portal

Double-click `START_PORTAL.bat`, or from a terminal:

```bash
node start.js
```

On the first run the server installs what it needs (about a minute). Then:

- API: http://localhost:5001
- Portal: http://localhost:3002 (opens in your browser)

Press `Ctrl+C` in the launcher window to stop both services.

In an editor, run the task named **Start Portal** (it is the default build task). Do not run an `npm` build task - the web app is already built.

## Sign in

| Role | Email | Password |
| --- | --- | --- |
| HR Admin | `hr@kgpl.com` | `Admin@123` |

Team Leader and Intern accounts can be created from HR > User Accounts.

## Notes

- The chat assistant is preconfigured and answers all roles. It needs internet access.
- The prebuilt web app calls the API at port 5001. Keep the API on 5001 unless you rebuild the web app (see README).
- If a port is busy, `API_PORT` and `WEB_PORT` can change the servers, but the web app then needs a rebuild to match.
- Uploaded documents and videos are not included. Attach new files from the portal; folders are created on demand.

## Troubleshooting

- `npm.ps1 cannot be loaded because running scripts is disabled` - the editor or terminal is running `npm` through PowerShell, which this machine blocks. Start with `START_PORTAL.bat` or `node start.js` instead; both work without changing any system settings.
- `MySQL connection failed` - MySQL is not running or the values in `backend/.env` are wrong.
- `Node 20.19 or newer is required` - install a current Node.js.
- Port already in use - run `API_PORT=5101 WEB_PORT=3102 node start.js` or close the program using the port.
- Assistant replies with a configuration message - the key in `backend/.env` is missing or has been reset.
