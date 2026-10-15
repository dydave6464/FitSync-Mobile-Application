# FitSync teammate setup

How to get FitSync running on your own computer after you fork or clone this repo, so you can try the app and change things.

**Windows is fine.** Every command below is for **PowerShell** on Windows. Mac or Linux differences are noted where they matter.

You do **not** need any API keys. Email, Google sign-in, FatSecret and AI coaching all have offline test modes that are on by default.

---

## 1. Install these first

| Tool | Version | Where to get it | Check it worked |
|---|---|---|---|
| Git | any recent | git-scm.com (Git for Windows) | `git --version` |
| Node.js | **22 or newer** | nodejs.org (LTS) | `node --version` |
| MySQL | **8.x — the real MySQL** | dev.mysql.com → MySQL Installer (Community) | `mysql --version` |
| Flutter | current stable (3.47+; needs Dart 3.13+) | docs.flutter.dev → Install → Windows → Android | `flutter --version` |
| Android Studio | latest | developer.android.com/studio | `flutter doctor` |

> ⚠️ **Don't use XAMPP's database.** XAMPP ships **MariaDB**, not MySQL. FitSync's setup scripts use MySQL 8 syntax that MariaDB rejects, so seeding fails. Install MySQL 8 with the MySQL Installer. If XAMPP is already installed, stop its MySQL service so the two don't fight over port 3306.

**After installing Flutter and Android Studio:**
1. Run `flutter doctor` and fix anything it marks with ❌. For example, run `flutter doctor --android-licenses` and accept them.
2. In Android Studio → **SDK Manager**, install **Android SDK Platform 36**. The app is built against Android 36.
3. **Optional:** install Python 3.9+ only if you want the real plan-generator service (section 6). The app works without it.

---

## 2. Get the code

```powershell
git clone https://github.com/<your-username>/FitSync-Mobile-Application.git
cd FitSync-Mobile-Application
```

The repo has three parts:

| Folder | What it is |
|---|---|
| `server/` | The backend (Node.js + MySQL). **The app needs this running.** |
| `client/` | The Flutter app |
| `ml/` | Optional plan-generator service (Python). The server has a built-in stand-in. |

---

## 3. Create the databases

Open **MySQL Command Line Client** (or MySQL Workbench) as `root` and run the following. Pick your own password.

```sql
CREATE DATABASE fitsync CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE fitsync_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'fitsync'@'localhost' IDENTIFIED BY 'pick-a-password';
GRANT ALL PRIVILEGES ON fitsync.* TO 'fitsync'@'localhost';
GRANT ALL PRIVILEGES ON fitsync_test.* TO 'fitsync'@'localhost';
FLUSH PRIVILEGES;
```

`fitsync` is the app's database. `fitsync_test` is only for the automated tests, which wipe it every run.

---

## 4. Set up and start the server

```powershell
cd server
npm install
Copy-Item .env.example .env
```

Open `server\.env` in an editor and set these two values:

| Key | What to put |
|---|---|
| `DB_PASSWORD` | the password you picked in step 3 |
| `JWT_SECRET` | a long random string. Generate one with the command below and paste it in. |

```powershell
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

Leave everything else as it is. The `*_MODE` settings left empty or set to `stub` mean "offline test mode".

**Build the database and load the starter data.** Run these in this order; each one depends on the one before:

```powershell
npm run migrate          # creates all the tables
npm run seed             # exercise catalogue
npm run seed:equipment   # equipment list
npm run seed:injuries    # injury regions
npm run seed:safety      # which exercises suit which injuries/equipment
npm run seed:categories  # exercise categories
npm run seed:foods       # 64 starter foods for the Nutrition tab
npm run seed:demo        # optional: two ready-made demo accounts (see below)
```

**Start the server:**

```powershell
npm run dev
```

Leave this window open; it restarts by itself when you change server code. It's working when it prints `FitSync API listening on port 3000`.

If **Windows Firewall** asks about Node.js, click **Allow** for **Private networks**. You only need that for the Wi-Fi option in step 5.

### Logging in

- **Demo accounts** (after `npm run seed:demo`): `test30@gmail.com` and `test31@gmail.com`, password `test123`. These are public test logins, not real ones.
- **Making your own account:** sign up in the app with any email. No email is actually sent. **The 6-digit code appears in the server window**; type it into the app.
- **Google sign-in won't work locally,** because it needs the project's real Google keys. Use email sign-up.

---

## 5. Run the app

Start an **Android emulator** (Android Studio → Device Manager → ▶), or plug in an Android phone with **USB debugging** turned on. Then connect the app to your server.

### Option A: `adb reverse` (easiest; works for a USB phone or an emulator)

This makes `localhost:3000` on the phone point to your computer, which is what the app expects by default. So there's no config file and no firewall step:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse tcp:3000 tcp:3000
```

(If `adb` is already on your PATH, `adb reverse tcp:3000 tcp:3000` is enough.)

**Run it again every time you reconnect the phone or restart the emulator.**

Then:

```powershell
cd client
flutter pub get
flutter run
```

### Option B: over Wi-Fi (a phone without a cable)

The phone and computer must be on the same Wi-Fi. Find your computer's address with `ipconfig` (the **IPv4 Address** of the Wi-Fi adapter, e.g. `192.168.1.23`). Then create `client\env.json`; it's git-ignored, so it never gets committed:

```json
{ "API_BASE_URL": "http://192.168.1.23:3000", "GOOGLE_SERVER_CLIENT_ID": "" }
```

and run:

```powershell
cd client
flutter pub get
flutter run --dart-define-from-file=env.json
```

You also need to allow Node.js through Windows Firewall on **Private networks** (see step 4).

> **Emulator without `adb reverse`?** Use `"API_BASE_URL": "http://10.0.2.2:3000"` in `env.json`. `10.0.2.2` is how the emulator reaches your computer.

The first build takes a few minutes. While it's running, press `r` in the terminal to hot-reload after a code change, or `R` to restart.

> iPhone builds need a Mac. On Windows, use Android.

---

## 6. Optional: the real plan generator (Python)

The server's built-in stand-in creates workout plans fine for trying things out. Only do this if you're working on the plan generator in `ml/`.

1. **Create its read-only database account.** The grant is in `server/MIGRATIONS.md`; search for `fitsync_ml`.
2. **Set up Python:**
   ```powershell
   cd ml
   py -3 -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
   Copy-Item .env.example .env      # then set FITSYNC_DB_PASSWORD
   .venv\Scripts\uvicorn app.main:build --factory --port 8000
   ```
3. **Point the server at it:** in `server\.env`, set `ML_MODE=http` and `ML_SERVICE_URL=http://localhost:8000`, then restart the server.

This service **does not reload by itself**, so restart it after changing anything in `ml/`. See `ml/README.md` for more.

---

## 7. Running the tests (optional)

**Server tests**, from `server\`. They need MySQL running and use `fitsync_test`:

```powershell
npm test
```

The full run takes about 10 minutes. To give slow tests more time, or to run a single file, call Node directly:

```powershell
node --test --test-concurrency=1 --test-timeout=120000 "tests/**/*.test.js"
node --test --test-concurrency=1 tests/foods-routes.test.js
```

> If one test fails with `ECONNRESET`, a foreign `403`, or `HPE_INVALID_CONSTANT` while `npm run dev` is running, that's a known clash with the running server. Run that one file again on its own.

**App tests**, from `client\`:

```powershell
flutter test
flutter analyze
```

**ML tests:** see `ml/README.md`. They need their own `fitsync_ml_test` database.

---

## Mac / Linux differences

| Windows (PowerShell) | Mac / Linux |
|---|---|
| `Copy-Item .env.example .env` | `cp .env.example .env` |
| `py -3 -m venv .venv` | `python3 -m venv .venv` |
| `.venv\Scripts\pip ...` | `.venv/bin/pip ...` |
| `$env:DB_NAME="fitsync_test"; npm run migrate; Remove-Item Env:DB_NAME` | `DB_NAME=fitsync_test npm run migrate` |
| `ipconfig` → IPv4 Address | `ipconfig getifaddr en0` (Mac) / `hostname -I` (Linux) |
| `& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" reverse …` | `~/Library/Android/sdk/platform-tools/adb reverse …` (Mac) / `adb reverse …` |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Server stops right away, naming a missing setting | Fill in `DB_PASSWORD` and `JWT_SECRET` in `server\.env` |
| `ER_ACCESS_DENIED_ERROR` | The `.env` password doesn't match the MySQL user from step 3 |
| A seed fails with a SQL syntax error near `AS new` | You're on MariaDB (XAMPP). Install MySQL 8. |
| `Table … doesn't exist` | Run `npm run migrate` |
| The app says "Could not reach http://…" | Check the server window is running. With Option A, run `adb reverse tcp:3000 tcp:3000` again (it resets when the phone reconnects or the emulator restarts). With Option B, check the IPv4 address in `client\env.json` and allow Node through Windows Firewall. |
| You changed `env.json` but nothing changed | Fully stop the app and run `flutter run --dart-define-from-file=env.json` again; hot reload doesn't re-read it |
| The server won't start: *Database "fitsync" is behind on N migrations* | Run `npm run migrate` (and any new `seed:*` step mentioned in the commit), then start it again |
| `flutter doctor` complains about Android licenses | Run `flutter doctor --android-licenses` and accept |

More detail lives in `server/README.md` (database, seeds, re-migrating) and `ml/README.md`.
