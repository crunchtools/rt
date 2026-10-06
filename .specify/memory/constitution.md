# rt Constitution

> **Version:** 1.0.0
> **Ratified:** 2026-10-02
> **Status:** Active
> **Inherits:** [crunchtools/constitution](https://github.com/crunchtools/constitution) v1.20.0
> **Profile:** Container Image

This file holds what is specific to the rt image. The fleet rules and the
Container Image profile apply at the inherited version and are checked against
this repo's files by `constitution.yml`. They are not restated here.

## Image Purpose

All-in-one [Request Tracker](https://bestpractical.com/request-tracker) 6.0.3
image: RT, Apache with `mod_fcgid`, MariaDB and Postfix under systemd in one
container. Published to `quay.io/crunchtools/rt` and `ghcr.io/crunchtools/rt`.

## Parent Images

Both stages build on crunchtools parents, so this image rebuilds when they do:

| Stage | Parent | Role |
|-------|--------|------|
| Builder | `quay.io/crunchtools/ubi10-httpd-perl` | compiles RT and its CPAN dependencies (RHSM-registered for `-devel` packages) |
| Runtime | `quay.io/crunchtools/ubi10-httpd-perl-mariadb` | adds Postfix, copies `/opt/rt6` and the built Perl trees |

## Build Specifics

- **RT source:** the upstream release tarball from `download.bestpractical.com`,
  configured `--with-db-type=mysql`. 6.0.3 carries upstream's fix for the
  JS-squish wide-character crash, so no local patch to `Squish/JS.pm` is
  carried.
- **CPAN:** installed with `cpanm --notest`, split into layers for caching.
  `DBD::mysql` is pinned to 4.050 and built with
  `-Wno-error=incompatible-pointer-types` because GCC 14 rejects its
  `my_bool` pointer mismatch; `mysql_config` is symlinked to `mariadb_config`.
- **MariaDB schema names:** `schema.MariaDB` and `acl.MariaDB` are symlinks to
  RT's `*.mysql` files, which is what `DatabaseType MariaDB` looks for.
- **Postfix:** alias maps use `lmdb:` because RHEL 10 dropped Berkeley DB hash
  maps. `/usr/local/bin/mail` is a minimal `mail -s` wrapper over `sendmail`.

## Services and Boot Order

`ENTRYPOINT ["/sbin/init"]`; enabled units: `httpd`, `mariadb`, `postfix`,
`rt-db-prep`, `rt-db-setup`.

1. `rt-db-prep.service` runs `mysql_install_db` before `mariadb.service`, only
   when `/var/lib/mysql/mysql` does not exist.
2. `rt-db-setup.service` runs after MariaDB and before httpd. It creates the
   `rt4` database (utf8mb4) and runs RT's schema, acl, coredata and initial
   data steps, skipping all of them when `rt4.Users` already has rows.
3. httpd serves RT on port 80 via `ScriptAlias / /opt/rt6/sbin/rt-server.fcgi/`.

## Database Access Invariant

MariaDB lives inside the container and is reached only on `localhost`.
`rt-db-setup.sh` lets `root@localhost` authenticate with an empty password
over TCP (`mysql_native_password ... OR unix_socket`), because RT's DBI runs
as `apache`. The MariaDB port MUST NOT be published from the container.

## Site Configuration

The shipped `RT_SiteConfig.pm` is a placeholder (`example.com`, `localhost`);
the deployed instance's configuration and data come from the host at run
time, not the image.

## History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-10-02 | Initial constitution, written as a v1.18.0 manifest |
