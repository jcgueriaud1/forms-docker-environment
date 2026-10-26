# Notice

The image build files under `images/` are derived from Dirk Nachbar's
[DirkNachbar/Docker](https://github.com/DirkNachbar/Docker) repository,
licensed under the GNU General Public License v3.0. Upstream has no 12.2.1.4
build files and has been inactive since 2020, so this repository carries
12.2.1.4 versions adapted from its 12.2.1.3 files. This repository is
distributed under the same licence (see `LICENSE`).

## Changes from upstream 12.2.1.3

- `images/fmw-infrastructure/Dockerfile` (from
  `OracleFMWInfrastructure/dockerfiles/12.2.1.3`): targets 12.2.1.4; installs
  from the bare `fmw_12.2.1.4.0_infrastructure.jar` instead of the Disk1 zip;
  drops `compat-libcap1` and `compat-libstdc++-33`, and adds `libnsl` and
  `libnsl2`, so the package step works on the current base image.
- `images/formsreports/Dockerfile` (from
  `OracleFormsReports/dockerfiles/12.2.1.3`): targets 12.2.1.4; builds the
  non-FADS image without the SQL Developer `ADD` step.
- `images/formsreports/container-scripts/crDomain.py`: RCU connects with the
  service-name form `host:port/service`, so it can reach a pluggable database
  such as XE's `XEPDB1`. The upstream `host:port:sid` form cannot.

`frrun.sh`, `docker-compose.yml` and `build-images.sh` are new in this
repository.

## Oracle software

No Oracle software is included. The installers and the base image come from
Oracle under Oracle's licence terms, which you accept when you download them.
Oracle, Java, WebLogic and Oracle Forms are trademarks of Oracle and/or its
affiliates. This project is not affiliated with or endorsed by Oracle.
