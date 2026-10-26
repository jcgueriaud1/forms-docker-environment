# Oracle Forms 12.2.1.4 in Docker

A local Oracle Forms 12.2.1.4 server (WebLogic + Forms + Oracle HTTP Server)
and an Oracle Database XE 21c, started with one `docker compose up`. Built for
development and demos, such as
[forms-vaadin-hybrid-demo](https://github.com/jcgueriaud1/forms-vaadin-hybrid-demo).

| Container | Image | Purpose |
| --- | --- | --- |
| `frdb` | `gvenzl/oracle-xe:21-slim` | Oracle XE 21c: the Forms repository (RCU) schemas and your application schemas, in the pluggable database `XEPDB1` |
| `frfmw` | `oracle/formsreports:12.2.1.4` (built here) | WebLogic AdminServer, the `WLS_FORMS` managed server and OHS. Reports is disabled to save memory. |

## Requirements

- **An x86_64 (Intel/AMD) machine.** Oracle ships no ARM build of Forms
  12.2.1.4, and these images are `amd64` only. Apple Silicon Macs are not
  supported (see forms-vaadin-hybrid-demo#3).
- **Docker** with about **12 GB of memory** for containers (the database uses
  ~2.3 GB, Forms ~5.6 GB, measured on a running system) and about **30 GB of
  free disk** for the images and installers.
- **An Oracle account**, to download the installers and pull the Java base
  image. You accept Oracle's licence terms when you do.

Verified on an Intel Mac (i7-9750H, 16 GB RAM) with Docker Desktop: images
rebuilt from this repository, first start from empty volumes, and
forms-vaadin-hybrid-demo deployed and running on it.

## 1. Get the Oracle installers

Download Oracle Fusion Middleware **12.2.1.4** from Oracle (Oracle Software
Delivery Cloud or oracle.com) and put the files here:

| File | Put it in |
| --- | --- |
| `fmw_12.2.1.4.0_infrastructure.jar` (Fusion Middleware Infrastructure) | `images/fmw-infrastructure/` |
| `fmw_12.2.1.4.0_fr_linux64.bin` and `fmw_12.2.1.4.0_fr_linux64-2.zip` (Forms and Reports, Linux x86-64) | `images/formsreports/` |

They are git-ignored and never committed.

## 2. Build the images

```bash
docker login container-registry.oracle.com   # Oracle account; accept the Java licence there first
./build-images.sh
```

This pulls `java/serverjre:8` and builds `oracle/fmw-infrastructure:12.2.1.4`
(~6.5 GB) and `oracle/formsreports:12.2.1.4` (~16 GB).

## 3. Start

```bash
docker compose up -d
docker compose logs -f frfmw       # wait for "Startup complete"
```

The **first start** builds the domain: it creates the RCU schemas in the
database, the WebLogic domain and the OHS instance. On the verified machine it
took about 10 minutes from `up` to "Startup complete" (6 of them building the
domain). Later starts take 2–4 minutes. All state lives in the volumes
`frdb_data` and `frfmw_domains`.

Stop with `docker compose stop`. `docker compose down -v` deletes everything,
including the domain and the database.

## 4. Check it works

`frrun.sh` registers a `[test]` configuration for Oracle's `test.fmx`. Open it
with the Forms Standalone Launcher (needs a local JDK):

```bash
curl -o frmsal.jar http://localhost:7777/forms/java/frmsal.jar
java -jar frmsal.jar -url "http://localhost:7777/forms/frmservlet?config=test"
```

## Endpoints and credentials (local defaults)

| What | Where |
| --- | --- |
| Forms servlet | http://localhost:7777/forms/frmservlet?config=NAME |
| WebLogic console / Enterprise Manager | http://localhost:7001/console, `/em` (`weblogic` / `welcome1`) |
| Database | `localhost:1521/XEPDB1` (`sys` / `Oracle12c` as SYSDBA) |

The passwords are set in `docker-compose.yml`. Change them for anything other
than a local machine.

## Deploying forms

Forms modules live in the `frfmw_domains` volume (for example under
`/opt/oracle/user_projects/<app>`), and each application gets a section in
`formsweb.cfg`:

```
/opt/oracle/user_projects/domains/FRDEMO/config/fmwconfig/servers/WLS_FORMS/applications/formsapp_12.2.1/config/
```

forms-vaadin-hybrid-demo's `deploy-form.sh` is a complete example: it builds a
form from XML, adds a database alias and an env file, and registers its own
config section.

## Gotchas

- **The Forms Standalone Launcher needs `baseSAAfile=basesaa.txt`** in every
  config section it opens, or it fails with FRM-93136.
- **OpenWebStart ignores the JNLP's Java version** and always runs its bundled
  Java 8. Use the standalone launcher to choose the client's JVM.
- **`frmcmp` (the form compiler) fails silently** (exit 1, no output) when it
  can't log in, and it rejects easy-connect strings: use a tnsnames alias. Call
  the instance wrapper `frmcmp_batch.sh`, not the bare binary (FRM-91500).
- **`frmxml2f` needs an X display** (Xvfb) and `FORMS_API_TK_BYPASS=TRUE`, or it
  fails with `_jni_initialize: Failed to create new forms context`.
- **Set `NLS_LANG`** (for example `AMERICAN_AMERICA.AL32UTF8`) in a
  configuration's env file. Without it, the runtime uses US7ASCII and non-ASCII
  characters are lost.
- **Linux file names are case-sensitive.** `OPEN_FORM('ORDERS')` won't find
  `orders.fmx`.
- **Docker Desktop single-file bind mounts go stale** after the file is edited
  on the host. Restart the container, or `docker cp` the file instead.

## Licence

GPL-3.0, because the image build files derive from
[DirkNachbar/Docker](https://github.com/DirkNachbar/Docker). See `NOTICE.md`
for what changed. No Oracle software is included.
