# FreeIPA on FreeBSD

[![Port files][ports-badge]][ports-link]

[ports-badge]: https://github.com/joneum/FreeBSD-freeipa-server/actions/workflows/ports.yml/badge.svg
[ports-link]: https://github.com/joneum/FreeBSD-freeipa-server/actions/workflows/ports.yml

FreeIPA is integrated identity management: 389 Directory Server (LDAP), an
MIT Kerberos KDC, Dogtag PKI (CA) and an Apache/mod_wsgi administration
stack, combined into a single domain.

Both ports are in the official FreeBSD ports tree:

| Port | Maintainer |
|---|---|
| [`net/freeipa-server`](https://cgit.freebsd.org/ports/tree/net/freeipa-server) | `joneum@FreeBSD.org` |
| [`net/freeipa-client`](https://cgit.freebsd.org/ports/tree/net/freeipa-client) | `kiwi@FreeBSD.org` |

`net/freeipa-server/` in this repository is a snapshot of the committed
server port, kept for reference; the ports tree is authoritative. You do not
need either to install FreeIPA. What this page carries is the FreeBSD
specifics that neither the upstream FreeIPA documentation nor the FreeBSD
handbook has.

The reference for operating a running server, service map and uninstall
included, is the **port documentation**. It ships as
`/usr/local/share/doc/freeipa-server/README.md` and is readable without
installing anything [in cgit](https://cgit.freebsd.org/ports/tree/net/freeipa-server/files/README.md).

* [What works and what does not](#what-works-and-what-does-not)
* [Coming from Linux](#coming-from-linux)
* [Why you must build your own packages](#why-you-must-build-your-own-packages)
* [Other prerequisites](#other-prerequisites) (hostname, time, cloud-init,
  firewall, sizing)
* [Installing the server](#installing-the-server)
* [Services and rc.conf](#services-and-rcconf)
* [Verifying the installation](#verifying-the-installation)
* [Enrolling a client](#enrolling-a-client)
* [Upgrading](#upgrading)
* [Error messages](#error-messages)
* [Reporting problems](#reporting-problems)
* [Supporting this work](#supporting-this-work)

---

## What works and what does not

Written against **FreeBSD 15.1 amd64**; older branches are untested rather
than unsupported. Read this before you build anything, two entries are
show-stoppers for common deployments.

| Area | Status (as of 2026-09) |
|---|---|
| Server install with self-signed CA | works |
| Web UI, `ipa` command line, Kerberos SSO | works |
| Client enrollment, `id` and `getent` via SSSD | works |
| Boot persistence | works |
| **Integrated DNS (`--setup-dns`)** | **not possible**, `bind-dyndb-ldap` is not in the ports tree |
| **Login of IPA users through PAM** | **not configured**, the client installer does not touch `/etc/pam.d/` |
| Replica setup, AD trust | untested |
| Enrollment of Linux clients against this server | untested |
| `ipa-backup`, `ipa-restore`, certificate renewal | untested |
| `oddjob-mkhomedir` | untested |

Untested means that since the port landed in 2026-08 nobody has reported
either success or failure.

**Without integrated DNS** the `A`, `PTR` and `SSHFP` records are not
created. Manage names in `/etc/hosts` or in your own DNS server. Clients
that enroll without `--server` discover it through DNS and therefore need a
real DNS server carrying the `SRV` records for `_kerberos._tcp`,
`_kerberos._udp`, `_kerberos-master._tcp`, `_kerberos-master._udp`,
`_ldap._tcp`, `_kpasswd._tcp` and `_kpasswd._udp`, plus the `_kerberos`
`TXT` record holding the realm name.

**Without PAM** IPA users resolve but cannot log in. Add `pam_sss` to
`/etc/pam.d/sshd` and `/etc/pam.d/system` yourself; `security/sssd2`
installs the modules as `/usr/local/lib/pam_sss.so` and
`/usr/local/lib/pam_sss_gss.so`.

**Certificates and backups.** certmonger tracks the IPA certificates and is
enabled by the installer; `getcert list` must show every request as
`status: MONITORING`. No certificate has reached its renewal date on FreeBSD
yet, so that path is untested rather than known broken. Subsystem
certificates come first, they run for two years while the CA runs for
twenty. Force one early with `getcert resubmit -i <id>` on a test system
rather than finding out when it matters. Until someone confirms
`ipa-backup`, treat a snapshot of the **stopped** machine as your backup; a
snapshot of a running one is only crash-consistent, which for 389-DS means a
database recovery on the next start.

---

## Coming from Linux

| Linux | FreeBSD |
|---|---|
| `systemctl start ipa` | `service freeipa-server start` |
| `systemctl status <backend>` | `ipactl status` |
| `dnf install` | `pkg install` from [your own repository](#why-you-must-build-your-own-packages) |
| `/etc/krb5.conf` | `/usr/local/etc/krb5.conf` |
| `/etc/sssd/sssd.conf` | `/usr/local/etc/sssd/sssd.conf` |
| `/etc/ipa/` | `/usr/local/etc/ipa/` |
| `firewalld` | pf or ipfw; neither is enabled by default |
| `/var/log/httpd/error_log` | `/var/log/httpd-error.log` |

FreeBSD carries a Kerberos in its base system, with libraries under
`/usr/lib` and its own `/etc/krb5.conf`, and FreeIPA needs the separate one
from ports (`security/krb5`) under `/usr/local`. Both are MIT these days, so
the problem is not the implementation but two installations on one host.

---

## Why you must build your own packages

Two ports default to `GSSAPI_BASE`, which links the base Kerberos:

* `security/py-gssapi`, a direct dependency of `freeipa-server`
* `security/cyrus-sasl2-gssapi`, pulled in through `security/sssd2`

The official package builders use default options, so `pkg install` from the
official repository gives you `GSSAPI_BASE` builds of both and the two
Kerberos installations collide at runtime. The failure surfaces late:
`ipa-server-install` usually runs to the end and then stops at the
self-enrollment step. There is no way around building the packages yourself.

Set the options in the `make.conf` of the poudriere set you build in, for
example `/usr/local/etc/poudriere.d/freeipa-make.conf` for a set named
`freeipa`:

```conf
security_cyrus-sasl2-gssapi_SET=GSSAPI_MIT
security_cyrus-sasl2-gssapi_UNSET=GSSAPI_BASE
security_py-gssapi_SET=GSSAPI_MIT
security_py-gssapi_UNSET=GSSAPI_BASE
```

`make config` does **not** work here, poudriere does not read
`/var/db/ports`. Without poudriere, put the same block in `/etc/make.conf`.
Then build both ports; their dependencies, including the two above, come
along:

```sh
poudriere bulk -j 151amd64 -p ports -z freeipa net/freeipa-server net/freeipa-client
```

Setting up poudriere itself, the jail, the ports tree and the package
repository is covered by the
[poudriere handbook](https://github.com/freebsd/poudriere/wiki). Two things
about it are worth knowing here.

**Disable the official repositories on the IPA host**, otherwise `pkg
install` keeps taking the default-option packages. Since FreeBSD 15 they are
`FreeBSD-ports` and `FreeBSD-ports-kmods`; on 14 and older there is a single
`FreeBSD`. `FreeBSD-base` is separate and keeps working.

**Then every ports package on that host comes from your own repository**,
which has a consequence that only shows up months later: a package you never
built is never updated again. Add the tools you actually use, editors and
shells included, and check with `pkg version -vRL=` that nothing is reported
as `orphaned`. If you build on the IPA server itself, this catches you
immediately, because `poudriere` and `git` came from the repository you just
switched off.

**Verify the linkage** once the packages are installed. Both must point into
`/usr/local`, never `/usr/lib`:

```sh
ldd /usr/local/lib/sasl2/libgssapiv2.so | grep libgssapi_krb5
ldd /usr/local/lib/python3*/site-packages/gssapi/raw/misc*.so | grep libgssapi_krb5
```

Changing options on a host that already has the packages does nothing on its
own; rebuild **and** reinstall them.

---

## Other prerequisites

**Hostname.** The system hostname must be a fully qualified domain name that
resolves to the host's real IP, not loopback, and it must be the canonical
name in `/etc/hosts`. The [port documentation](https://cgit.freebsd.org/ports/tree/net/freeipa-server/files/README.md), installed
as `/usr/local/share/doc/freeipa-server/README.md`, has the exact `sysrc` and
`/etc/hosts` lines.

**Time.** Kerberos rejects tickets once clocks drift apart by more than five
minutes. FreeBSD enables no time source by default (`ntpd_enable` is `NO` in
`/etc/defaults/rc.conf`), although most cloud images turn `ntpd` on. Check
with `service ntpd status` and `ntpq -p` before installing. The server port
depends on `net/chrony` because `ipa-server-install` can configure it, but
that path is untested here and a second time daemon next to a running `ntpd`
helps nobody, so pass `--no-ntp` and keep the source you have.

**cloud-init images.** cloud-init regenerates `/etc/hosts` from a template on
every boot, which drops the line mapping the FQDN to the real IP. FreeIPA can
then no longer resolve its own name and even `ipactl` aborts with
`socket.gaierror: [Errno 8] Name does not resolve`. Before installing:

```conf
# /usr/local/etc/cloud/cloud.cfg.d/99-freeipa.cfg
preserve_hostname: true
manage_etc_hosts: false
```

That drop-in only wins when the image's own user-data leaves the settings
alone, and Proxmox for instance generates user-data with
`manage_etc_hosts: true`, which outranks everything in `cloud.cfg.d`. Once
the host is provisioned cloud-init has no further job on an IPA server, so
take it out of the boot path for good with
`touch /usr/local/etc/cloud/cloud-init.disabled`.

**Firewall.** FreeBSD enables no packet filter by default, so on a stock
installation there is nothing to open. If you run pf or ipfw, FreeIPA needs
tcp 80 and 443, tcp 389 and 636, tcp and udp 88 and 464, and udp 123 if the
server is your time source. Dogtag additionally listens on `*:8080` and
`*:8443` and `kadmind` on `*:749`; those are administrative, keep them off
any untrusted network.

**Sizing, RAM and disk.** The reference system is a VM with 8 GB RAM. Its
complete package set, FreeIPA and everything else on that machine, measured
a good 2 GiB of disk in 2026-09, so that is an upper bound rather than a
figure for FreeIPA alone. Dogtag runs its own Tomcat on OpenJDK, which is why
RAM rather than disk is the limiting factor. No lower bound has been measured,
so if you find one, please report it.

---

## Installing the server

```sh
pkg install freeipa-server
sysrc freeipa_server_enable=YES
sysrc gssproxy_enable=YES
ipa-server-install --hostname=ipa.example.com --domain=example.com \
    --realm=EXAMPLE.COM --no-host-dns --no-ntp
```

`--no-host-dns` skips the DNS pre-checks when you manage names in
`/etc/hosts`. Do not use `--setup-dns`. The installer asks for a Directory
Manager password and an `admin` password, then runs for several minutes;
Dogtag and its Tomcat take the longest.

The Web UI is then at `https://ipa.example.com/`. For Kerberos single
sign-on your browser must trust the IPA CA
(`https://ipa.example.com/ipa/config/ca.crt`) and have Negotiate enabled,
otherwise the UI falls back to form-based login.

---

## Services and rc.conf

The rc script is named `freeipa-server` with a hyphen, its variable
`freeipa_server_enable` with an underscore. That asymmetry is normal for
rc.subr and trips people up:

```sh
service freeipa-server start      # start | stop | status
```

You set exactly two switches yourself, `freeipa_server_enable` and
`gssproxy_enable`. The installer sets the back-end services it needs, the
port documentation lists them, and it deliberately leaves `dirsrv_enable`,
`pki_tomcatd_pki_tomcat_enable`, `apache24_enable` and `ipa_custodia_enable`
at `NO`. Those four are started by `ipactl` in dependency order; pki-tomcatd
in particular must not start before the Directory Server accepts
connections, which is exactly what a boot-time start would do.

gssproxy is enabled for a narrower reason than its name suggests. It holds
the HTTP keytab as a credential store for the IPA API and the ccache
sweeper. `mod_auth_gssapi` itself does not go through it: delegation through
the proxy proved unreliable in the long-running httpd worker, so the
installer writes `GSS_USE_PROXY=no` into
`/usr/local/etc/apache24/envvars.d/ipa.env` and the framework performs
S4U2Proxy constrained delegation through MIT krb5 directly.

---

## Verifying the installation

`ipactl status` only reports whether processes are alive. The `curl` below is
what tells you the CA web application is actually deployed:

```sh
# as root
ipactl status     # Directory Service, krb5kdc, kadmin, httpd,
                  # ipa-custodia, pki-tomcatd and ipa-otpd, all RUNNING
curl -sk https://localhost:8443/ca/admin/ca/getStatus

# as an unprivileged user, so that kinit does not overwrite
# the host ticket root holds in /tmp/krb5cc_0
kinit admin
ipa user-find admin
```

Then reboot once and run the same checks again. This is the only check that
covers the rc configuration, and the next power cut is a bad time for it.

---

## Enrolling a client

`net/freeipa-client` needs the same `GSSAPI_MIT` builds as the server, so
install it from your own repository as well. The host needs an FQDN and a
working time source just like the server:

```sh
pkg install freeipa-client
ipa-client-install --domain=example.com --server=ipa.example.com \
    --realm=EXAMPLE.COM
```

The installer configures SSSD and sets `passwd`, `group` and `sudoers` to
`files sss` in `/etc/nsswitch.conf` itself. Afterwards `id admin`,
`getent passwd admin` and `kinit admin` work. Interactive login does not,
see [what works and what does not](#what-works-and-what-does-not).
Un-enroll with `ipa-client-install --uninstall`.

---

## Upgrading

The port has no install script, so upgrading the package never runs
`ipa-server-upgrade` against a deployed instance; on Linux the RPM does that
for you. Run it yourself after upgrading.

Release-specific manual steps are documented in the `UPDATING` file of the
ports tree, which `pkg upgrade` points at. Read it before upgrading a
deployed server; some entries change a running pki-tomcat instance, which no
package is allowed to rewrite.

---

## Error messages

| Symptom | Cause | Where |
|---|---|---|
| `SPNEGO cannot find mechanisms to negotiate` | one of the two ports built with `GSSAPI_BASE` | [own packages](#why-you-must-build-your-own-packages) |
| `Cannot find KDC for realm` at the end of the install | one of the two ports built with `GSSAPI_BASE` | [own packages](#why-you-must-build-your-own-packages) |
| `ns-slapd` aborts with SIGABRT | `cyrus-sasl2-gssapi` linked against the base Kerberos | [own packages](#why-you-must-build-your-own-packages) |
| `socket.gaierror: [Errno 8] Name does not resolve` | `/etc/hosts` lost the FQDN line, usually cloud-init | [prerequisites](#other-prerequisites) |
| `id admin` works but login fails | no `pam_sss` in `/etc/pam.d/` | [what works](#what-works-and-what-does-not) |
| `/ca` returns 404 while `ipactl status` says RUNNING | pki-tomcatd started before the Directory Server | [rc.conf](#services-and-rcconf) |
| Web UI asks for a password instead of using Kerberos | browser does not trust the IPA CA, or Negotiate is off | [installing](#installing-the-server) |
| Server misbehaves right after a `pkg upgrade` | `ipa-server-upgrade` was not run against the instance | [upgrading](#upgrading) |

---

## Reporting problems

Bugs in the ports themselves go to
[Bugzilla](https://bugs.freebsd.org/bugzilla/) against `net/freeipa-server`
or `net/freeipa-client`. Everything else about running FreeIPA on FreeBSD
belongs in the issue tracker of this repository. When reporting a failure,
attach `uname -a`, the relevant install log from `/var/log/`, and for
Kerberos problems a `KRB5_TRACE=/dev/stderr` trace.

---

## Supporting this work

Porting and maintaining FreeIPA on FreeBSD, with the whole 389-DS, Kerberos,
Dogtag and SSSD dependency chain behind it, is unpaid work done alongside a
regular job, on hardware paid for out of pocket. Donations go towards the
test machines and the time.

[GitHub Sponsors](https://github.com/sponsors/joneum) ·
[other ways](https://blog.bsdproject.de)
