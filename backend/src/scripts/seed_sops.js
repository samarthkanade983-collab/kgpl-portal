import fs from 'fs';
import path from 'path';
import mysql from 'mysql2/promise';

const UPLOADS_DIR = path.resolve('uploads', 'sops');
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

// User-uploaded original docx source files
const USER_UPLOADS = 'C:\\Users\\Techsupport 002\\.gemini\\antigravity\\brain\\e56d7c26-646c-461b-8863-21d803f0c556\\.user_uploaded';

const SOP_DOCS = [
  {
    src: 'media_1794212463214_0155955f.docx',
    dest: 'Zabbix_Deployment_Setup_RHEL9_SOP.docx',
    title: 'SOP: Zabbix 7.0 Deployment & Setup on RHEL 9',
    category: 'IT Infrastructure & Monitoring',
    moduleId: 4, // Module 1: Enterprise Linux & Core Networking
    author: 'Sahil Kelaskar, Aniket Mhatre',
    version: '1.0',
    date: '5th March 2025',
    summary: 'Standard Operating Procedure for deploying enterprise Zabbix monitoring server on Red Hat Enterprise Linux 9 with MySQL 8.0, SELinux policies, and Apache Web UI.',
    steps: [
      'Pre-requisites: Verify RHEL 9 installation, install net-tools (`dnf install net-tools -y`), configure static IP (192.168.1.165/24) using nmtui, restart NetworkManager.',
      'MySQL Database Engine: Install mysql-server (`dnf install mysql-server -y`), enable & start mysqld (`systemctl enable --now mysqld`).',
      'Database Provisioning: Run mysql as root, execute `create database zabbix character set utf8mb4 collate utf8mb4_bin;`, grant full privileges to zabbix@localhost with password.',
      'Zabbix Repository & Packages: Install official Zabbix 7.0 RPM repository, install zabbix-server-mysql, zabbix-web-mysql, zabbix-apache-conf, zabbix-sql-scripts, zabbix-selinux-policy, and zabbix-agent.',
      'Schema Import: Import initial schema using `zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p zabbix`.',
      'Server Configuration: Update `/etc/zabbix/zabbix_server.conf` with `DBPassword=password`.',
      'Services Daemon: Start and enable zabbix-server, zabbix-agent, httpd, php-fpm (`systemctl restart zabbix-server zabbix-agent httpd php-fpm`).',
      'Web Console Setup: Open http://192.168.1.165/zabbix, verify PHP pre-requisites, configure DB credentials, and login with default Admin/zabbix.'
    ],
    markdownContent: `# SOP: Zabbix 7.0 Deployment & Setup on RHEL 9
**Document Version:** 1.0  
**Authors:** Sahil Kelaskar, Aniket Mhatre  
**Date:** 5th March 2025  
**Target Environment:** Red Hat Enterprise Linux (RHEL) 9 / AlmaLinux 9 / Rocky Linux 9  

---

### 1. Objective & Scope
This Standard Operating Procedure (SOP) provides step-by-step instructions for deploying, configuring, and verifying an enterprise Zabbix 7.0 LTS monitoring infrastructure on RHEL 9 with MySQL 8.0 database engine and Apache Web Interface.

---

### 2. Pre-requisites & System Configuration
- Minimum Hardware: 2 vCPU, 4GB RAM, 40GB SSD
- Static IP Address: \`192.168.1.165/24\`, Gateway: \`192.168.1.1\`, DNS: \`8.8.8.8\`
\`\`\`bash
dnf install net-tools -y
nmtui
# Set static IP 192.168.1.165/24
systemctl restart NetworkManager
ip a
\`\`\`

---

### 3. Database Server Setup (MySQL 8.0)
\`\`\`bash
dnf install mysql-server -y
systemctl enable --now mysqld
systemctl status mysqld

# Create Database and Grants
mysql -u root
\`\`\`
\`\`\`sql
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
FLUSH PRIVILEGES;
QUIT;
\`\`\`

---

### 4. Zabbix 7.0 LTS Packages Installation
\`\`\`bash
rpm -Uvh https://repo.zabbix.com/zabbix/7.0/rhel/9/x86_64/zabbix-release-7.0-5.el9.noarch.rpm
dnf clean all
dnf install zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent -y
\`\`\`

---

### 5. Schema Importation
\`\`\`bash
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p zabbix

# Disable log_bin_trust_function_creators after import
mysql -u root -e "SET GLOBAL log_bin_trust_function_creators = 0;"
\`\`\`

---

### 6. Zabbix Server Configuration
Edit \`/etc/zabbix/zabbix_server.conf\`:
\`\`\`ini
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=password
\`\`\`

---

### 7. Service Startup & Firewall Rules
\`\`\`bash
systemctl restart zabbix-server zabbix-agent httpd php-fpm
systemctl enable zabbix-server zabbix-agent httpd php-fpm

# Firewall configuration
firewall-cmd --add-port={10050/tcp,10051/tcp,80/tcp,443/tcp} --permanent
firewall-cmd --reload
\`\`\`

---

### 8. Web GUI Access & Initial Verification
- Access: \`http://192.168.1.165/zabbix\`
- Default Credentials:
  - **Username:** \`Admin\`
  - **Password:** \`zabbix\`
`
  },
  {
    src: 'media_1794212463213_bbef9715.docx',
    dest: 'Metallic_Creating_Laptop_Plan_SOP.docx',
    title: 'SOP: Creating an Endpoint Laptop Plan in Metallic (Commvault)',
    category: 'Data Protection & Backup',
    moduleId: 6, // Module 3: Cloud VPCs, Load Balancers & SSL / Backup
    author: 'Sahil Kelaskar, Sushant Pimple',
    version: '1.0',
    date: '30th January 2025',
    summary: 'Standard Operating Procedure for creating and configuring enterprise endpoint backup policies (Laptop Plans) within the Metallic Commvault Cloud console.',
    steps: [
      'Log into Metallic Cloud Administration Console with designated corporate credentials.',
      'From left navigation pane, expand Manage -> select Plans.',
      'Click Create Plan button -> select Laptop option.',
      'Specify General Information: Plan Name (e.g., KGPL_Corporate_Laptops_Daily).',
      'Define Backup Content: Include C:\\Users\\Administrator\\Documents, C:\\Users\\*\\Desktop, Pictures, Downloads.',
      'Configure Exclusions: Exclude temporary directories, Recycle Bin, and large system cache files (*.tmp, AppData\\Local\\Temp).',
      'Schedule & Network Rules: Set RPO frequency to 4 hours on metered/unmetered connections.',
      'Review Summary and click Submit to deploy the plan across registered company endpoints.'
    ],
    markdownContent: `# SOP: Creating an Endpoint Laptop Plan in Metallic (Commvault)
**Document Version:** 1.0  
**Authors:** Sahil Kelaskar, Sushant Pimple  
**Date:** 30th January 2025  
**Platform:** Metallic Cloud Platform (by Commvault)  

---

### 1. Objective
Establish standard enterprise guidelines for defining, creating, and publishing endpoint backup policies (Laptop Plans) to safeguard corporate devices against ransomware and data loss.

---

### 2. Step-by-Step Procedure

#### Step 1: Navigate to Plans
1. Access the Metallic Command Center (\`https://metallic.io\` or enterprise tenant portal).
2. From the navigation pane, expand **Manage** and click **Plans**.

#### Step 2: Initiate Laptop Plan Creation
1. In the upper-right corner, click **Create plan**.
2. From the modal selection list, choose **Laptop**.

#### Step 3: Define Plan Profile
- **Plan Name:** \`KGPL_Corp_Laptop_Standard\`
- **Storage Pool:** Select Primary Cloud Storage Tier (e.g., Metallic Cloud Storage)

#### Step 4: Content to Backup
- Add folder paths:
  - \`C:\\Users\\*\\Documents\`
  - \`C:\\Users\\*\\Desktop\`
  - \`C:\\Users\\*\\Work\`
- **Exclusion Filters:**
  - \`*.tmp\`
  - \`AppData\\Local\\Temp\`
  - \`$Recycle.Bin\`

#### Step 5: RPO Schedule & Retention
- **Backup Frequency:** Every 4 hours (when network connection is active)
- **Retention Rule:** Retain deleted files for 30 calendar days.

#### Step 6: Review & Finalize
Review all parameters and click **Submit**. All laptops assigned to this plan will automatically execute according to the defined policy.
`
  },
  {
    src: 'media_1794212463241_df5c4aac.docx',
    dest: 'CommVault_DBMaintenance_SOP.docx',
    title: 'SOP: CommVault CommServe Database Maintenance Procedure',
    category: 'Database & Infrastructure Operations',
    moduleId: 6, // Cloud & Backup
    author: 'Enterprise Backup & DB Operations Team',
    version: '1.2',
    date: '2025-2026 Updated',
    summary: 'Critical maintenance procedure for optimizing, shrinking, and verifying integrity of the Commvault CommServe Microsoft SQL Database.',
    steps: [
      'Suspend running jobs: Open CommCell Console -> Job Controller -> Select All Active Jobs -> Suspend.',
      'Disable Activity Controller to prevent new scheduled jobs from triggering during maintenance.',
      'Disaster Recovery (DR) Backup: Take immediate full DR backup of the CommServe database to local and network locations.',
      'Disable CommServe Scheduler.',
      'Stop Commvault Services: Launch Process Manager as Administrator -> Stop All Services.',
      'Execute Maintenance: Open Administrator CMD -> Navigate to C:\\Program Files\\Commvault\\ContentStore\\Base.',
      'Run DB Maintenance command: DBMaintenance.exe -full',
      'Start Commvault Services in Process Manager.',
      'Enable Scheduler and resume suspended jobs.',
      'Perform test DR Backup to confirm clean operational status.'
    ],
    markdownContent: `# SOP: CommVault DB Maintenance Procedure
**Classification:** Critical Operational Procedure  
**Frequency:** Monthly / Pre-Upgrade  
**Scope:** CommServe SQL Server Database Maintenance  

---

### 1. Preparation & Safety Steps
> [!CAUTION]
> Never run DBMaintenance while jobs are writing or Commvault services are running, as this may lead to database corruption.

1. Launch **CommCell Console** with administrative privileges.
2. In **Job Controller**, select all currently running jobs -> Right-click -> **Suspend**.
3. Right-click the CommServe hostname at top of the browser tree -> **Control** -> **Disable All Activities**.
4. Run an on-demand Disaster Recovery Backup:
   - Right-click CommServe -> **All Tasks** -> **Disaster Recovery Backup** -> **OK**.
   - Verify backup successfully completes in Job Controller.

---

### 2. Stopping Services
1. Open **Commvault Process Manager** from Windows Start Menu (Run as Administrator).
2. Click **Stop** on the Services tab and wait until all CV services report \`Stopped\`.

---

### 3. Running DBMaintenance
1. Open **Command Prompt as Administrator**.
2. Change directory to the Commvault Base binaries folder:
\`\`\`cmd
cd "C:\\Program Files\\Commvault\\ContentStore\\Base"
\`\`\`
3. Execute the full database maintenance routine:
\`\`\`cmd
DBMaintenance.exe -full
\`\`\`
4. Wait for the maintenance tool to check table integrity, rebuild indexes, and optimize transaction logs. Verify output reports:
   \`DBMaintenance completed successfully.\`

---

### 4. Post-Maintenance Restoration
1. Open **Commvault Process Manager** -> Click **Start All Services**.
2. Verify all services show green/running.
3. Open **CommCell Console**:
   - Right-click CommServe -> **Control** -> **Enable All Activities**.
   - In **Job Controller**, resume all suspended jobs.
   - Run a test Disaster Recovery (DR) backup to confirm full health.
`
  },
  {
    src: 'media_1794212463212_bd415bde.docx',
    dest: 'Metallic_SOP_Endpoint_Installation.docx',
    title: 'SOP: Metallic Endpoint Agent Silent Installation on Windows Laptops',
    category: 'Endpoint Security & Cloud Backup',
    moduleId: 4, // Linux & Networking / Endpoints
    author: 'Sahil Kelaskar',
    version: '1.0',
    date: 'February 2025',
    summary: 'Standard procedure for silent, automated installation of Metallic Endpoint agent package on Windows laptops using tenant Authcode.',
    steps: [
      'Log into Metallic Console -> Navigate to Protect -> Laptop.',
      'Click Add Laptop button in the top right.',
      'Select and download the Windows Endpoint package (WindowsEndpoint64.exe).',
      'Copy the unique single-use / tenant Authcode displayed on the screen.',
      'Place the downloaded executable on the target laptop Desktop.',
      'Open Command Prompt as Administrator.',
      'Execute silent installation: WindowsEndpoint64.exe /silent /install /authcode <AUTHCODE>',
      'Wait for silent background setup to conclude, then reboot laptop.',
      'Verify laptop status shows Online and Healthy in Metallic Console.'
    ],
    markdownContent: `# SOP: Metallic Endpoint Agent Silent Installation
**Target Platform:** Windows 10 / Windows 11 Enterprise (64-bit & 32-bit)  
**Author:** Sahil Kelaskar  

---

### 1. Objective
Ensure automated, zero-touch deployment of the Metallic Commvault cloud backup client onto employee workstations.

---

### 2. Download Package & Authcode
1. In the Metallic navigation pane, click **Protect > Laptop**.
2. Click **Add Laptop**.
3. Download the appropriate package:
   - For 64-bit systems: \`WindowsEndpoint64.exe\`
   - For 32-bit systems: \`WindowsEndpoint32.exe\`
4. Copy the generated **Authcode** (e.g. \`2F75B40F0F6...\`).

---

### 3. Silent Installation Execution
1. Copy the downloaded \`WindowsEndpoint64.exe\` to the laptop Desktop.
2. Open **Command Prompt as Administrator**.
3. Execute the silent install command:
\`\`\`cmd
cd %USERPROFILE%\\Desktop
WindowsEndpoint64.exe /silent /install /authcode <PASTE_COPIED_AUTHCODE_HERE>
\`\`\`
*(For 32-bit laptops)*:
\`\`\`cmd
WindowsEndpoint32.exe /silent /install /authcode <PASTE_COPIED_AUTHCODE_HERE>
\`\`\`

---

### 4. Finalization & Verification
1. The installer operates silently in the background without user prompts.
2. After approximately 2-3 minutes, restart the laptop:
\`\`\`cmd
shutdown /r /t 30
\`\`\`
3. Verify in the Metallic Web Console that the laptop appears under **Protect > Laptops** with status **Active / Backed Up**.
`
  },
  {
    src: 'media_1794212463212_3a392d06.docx',
    dest: 'SOP_Usercreation_SRA_Volksara.docx',
    title: 'SOP: SRA Linux User Creation & Passwordless Sudoers Setup (Volksara)',
    category: 'Enterprise Linux & Security Operations',
    moduleId: 4, // Module 1: Enterprise Linux & Core Networking
    author: 'Infrastructure & SRA Team',
    version: '1.1',
    date: '2025 Updated',
    summary: 'Procedure for provisioning the dedicated Secure Remote Access (SRA) service user "volksara" with isolated, passwordless sudo permissions on RHEL and Ubuntu servers.',
    steps: [
      'Create standard user account: sudo useradd -m volksara',
      'Assign secure password: sudo passwd volksara',
      'Add user to administrative group: sudo usermod -aG sudo volksara (Ubuntu/Debian) or sudo usermod -aG wheel volksara (RHEL/CentOS).',
      'Verify membership: groups volksara',
      'Configure isolated sudoers rule: visudo -f /etc/sudoers.d/volksara',
      'Add permission entry: volksara ALL=(ALL:ALL) NOPASSWD: ALL',
      'Apply secure file permissions: chmod 440 /etc/sudoers.d/volksara',
      'Verify root escalation without password: sudo -k, su - volksara, sudo -i'
    ],
    markdownContent: `# SOP: SRA Linux User Creation & Passwordless Sudoers Setup
**Target Operating Systems:** RHEL 8/9, Rocky Linux, Ubuntu 22.04/24.04  
**Account:** \`volksara\` (Dedicated SRA Service Account)  

---

### 1. Objective
Establish a secure, auditable Secure Remote Access (SRA) administrative account with isolated passwordless sudo privileges for automated infrastructure management.

---

### 2. User Creation & Group Provisioning
\`\`\`bash
# 1. Create the user with dedicated home directory
sudo useradd -m volksara

# 2. Set password for initial authentication
sudo passwd volksara

# 3. Add to administrative group
# For RHEL / Alma / Rocky Linux:
sudo usermod -aG wheel volksara

# For Ubuntu / Debian Linux:
sudo usermod -aG sudo volksara

# 4. Verify group membership
groups volksara
\`\`\`

---

### 3. Passwordless Sudoers Configuration
Always configure service user permissions in an isolated file under \`/etc/sudoers.d/\`:
\`\`\`bash
sudo visudo -f /etc/sudoers.d/volksara
\`\`\`
Add the following line to the file:
\`\`\`text
volksara ALL=(ALL:ALL) NOPASSWD: ALL
\`\`\`

Apply strict POSIX permissions so sudo will accept the file:
\`\`\`bash
sudo chmod 440 /etc/sudoers.d/volksara
\`\`\`

---

### 4. Verification & Validation Testing
Validate that the user can elevate to root privileges without being prompted for a password:
\`\`\`bash
# Clear any cached sudo tokens
sudo -k

# Switch to volksara user
su - volksara

# Elevate to root interactive shell
sudo -i
\`\`\`
**Expected Result:** Root prompt (\`root@hostname:~#\`) opens immediately without any password challenge.
`
  }
];

async function seed() {
  console.log('--- SEEDING ENTERPRISE SOPS INTO MYSQL & MONGODB ---');

  // Copy files to uploads directory
  for (const doc of SOP_DOCS) {
    const srcPath = path.join(USER_UPLOADS, doc.src);
    const destPath = path.join(UPLOADS_DIR, doc.dest);
    try {
      if (fs.existsSync(srcPath)) {
        fs.copyFileSync(srcPath, destPath);
        console.log(`Copied ${doc.src} -> ${doc.dest}`);
      } else {
        console.log(`Source ${srcPath} does not exist, creating placeholder`);
        fs.writeFileSync(destPath, doc.markdownContent);
      }
    } catch (e) {
      console.error(`Error copying ${doc.src}:`, e);
    }
  }

  // Connect to MySQL
  const conn = await mysql.createConnection({
    host: '127.0.0.1',
    user: 'root',
    password: '',
    database: 'kgpl_portal'
  });

  console.log('Connected to MySQL kgpl_portal');

  // Insert or update learning_materials
  for (let i = 0; i < SOP_DOCS.length; i++) {
    const doc = SOP_DOCS[i];
    const filePath = `/uploads/sops/${doc.dest}`;
    const fileSize = fs.existsSync(path.join(UPLOADS_DIR, doc.dest)) 
      ? Math.round(fs.statSync(path.join(UPLOADS_DIR, doc.dest)).size / 1024) 
      : 150;

    // Check if exists
    const [existing] = await conn.execute(
      'SELECT id FROM learning_materials WHERE title = ?',
      [doc.title]
    );

    if (existing.length > 0) {
      await conn.execute(
        `UPDATE learning_materials 
         SET module_id = ?, material_type = 'sop', file_path = ?, file_size_kb = ?, allow_download = 1, order_sequence = ?, updated_at = NOW() 
         WHERE id = ?`,
        [doc.moduleId, filePath, fileSize, i + 10, existing[0].id]
      );
      console.log(`Updated MySQL learning_material id ${existing[0].id}: ${doc.title}`);
    } else {
      const [res] = await conn.execute(
        `INSERT INTO learning_materials (module_id, title, material_type, file_path, file_size_kb, allow_download, order_sequence, created_at, updated_at) 
         VALUES (?, ?, 'sop', ?, ?, 1, ?, NOW(), NOW())`,
        [doc.moduleId, doc.title, filePath, fileSize, i + 10]
      );
      console.log(`Inserted MySQL learning_material id ${res.insertId}: ${doc.title}`);
    }
  }

  await conn.end();

  // Save to persistent NoSQL store
  const nosqlDir = path.resolve('data', 'nosql');
  if (!fs.existsSync(nosqlDir)) {
    fs.mkdirSync(nosqlDir, { recursive: true });
  }

  const sopsJsonPath = path.join(nosqlDir, 'sops.json');
  fs.writeFileSync(sopsJsonPath, JSON.stringify(SOP_DOCS, null, 2), 'utf8');
  console.log(`Persisted ${SOP_DOCS.length} SOPs to NoSQL store at ${sopsJsonPath}`);

  console.log('--- SEED COMPLETED SUCCESSFULLY ---');
}

seed().catch(err => {
  console.error('Seed error:', err);
  process.exit(1);
});
