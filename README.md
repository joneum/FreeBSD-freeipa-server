# Call For Testing — FreeIPA on FreeBSD (`net/freeipa-server` + `net/freeipa-client`)

This repository contains a **work-in-progress FreeBSD port of FreeIPA**
(FreeIPA 4.13.1), published for a **Call For Testing (CFT)**. It is **not
yet committed** to the official FreeBSD ports tree.

FreeIPA is integrated identity management: 389 Directory Server (LDAP) +
MIT Kerberos KDC + Dogtag PKI (CA) + an Apache/mod_wsgi management stack.

> **Status.** On FreeBSD 15 (amd64) `ipa-server-install` completes, and a
> FreeBSD client enrolls with `ipa-client-install` and resolves IPA
> users/groups (`id`, `getent`) via SSSD — **using the patched
> `net/freeipa-client` included in this repository**. The client fixes are
> not yet in the official ports tree (see *Client status* below). All
> blockers known to the maintainer are fixed here; the CFT should confirm
> this on other setups.

Maintainer: **joneum@FreeBSD.org**

---

## What to test

* Building both ports (poudriere strongly recommended).
* `ipa-server-install` on a freshly provisioned host.
* Enrolling a FreeBSD client and resolving users (`id`, `getent`).
* Boot persistence (reboot the server, verify the stack comes back up).
* Uninstall / reinstall.

Please report results — **success or failure** — via a GitHub issue on this
repository (include FreeBSD version, `uname -a`, and the relevant
`ipaserver-install.log` / poudriere build log on failure).

---

## Prerequisites (read this first)

1. **Build `security/cyrus-sasl2-gssapi` with the `GSSAPI_MIT` option**
   (not the default `GSSAPI_BASE`), so the SASL/GSSAPI plugin links the
   ports MIT Kerberos (`security/krb5`) instead of base-system Kerberos.
   In poudriere / `make.conf`:

   ```
   security_cyrus-sasl2-gssapi_SET=GSSAPI_MIT
   security_cyrus-sasl2-gssapi_UNSET=GSSAPI_BASE
   ```

   Otherwise `ipa-server-install` runs to the very end and then fails with
   `SPNEGO cannot find mechanisms to negotiate` / `Cannot find KDC for
   realm`. This is a **system-wide** choice — test on a host dedicated to
   FreeIPA, ideally a throwaway VM.

2. **Host naming.** The system hostname must be a fully-qualified domain
   name that resolves to the host's **real** IP (not loopback) and is the
   canonical name in `/etc/hosts`:

   ```sh
   sysrc hostname="ipa.example.com"
   hostname ipa.example.com
   ```

   ```
   # /etc/hosts
   ::1         localhost
   127.0.0.1   localhost
   10.0.0.10   ipa.example.com ipa
   ```

---

## Quick install — server

1. **Install the package** (built from this repo's ports):

   ```sh
   pkg install freeipa-server
   ```

2. **Enable the required services in `rc.conf`.** Three switches are needed
   — the FreeIPA stack itself, plus D-Bus and gssproxy (without the latter
   two the server does not survive a reboot):

   ```sh
   sysrc freeipa_server_enable=YES   # the whole stack, driven by ipactl
   sysrc dbus_enable=YES             # certmonger + oddjobd need the system bus
   sysrc gssproxy_enable=YES         # httpd/mod_auth_gssapi acquires HTTP creds
   ```

   You do **not** enable the individual back-ends (389-ds, KDC, Dogtag,
   httpd) in `rc.conf`; `ipactl` starts them in the correct order.

3. **Configure the instance** (interactive; `--no-host-dns` skips DNS
   pre-checks when you manage names via `/etc/hosts`, `--no-ntp` skips the
   chrony client which is not used on FreeBSD):

   ```sh
   ipa-server-install \
       --hostname=ipa.example.com \
       --domain=example.com \
       --realm=EXAMPLE.COM \
       --no-host-dns \
       --no-ntp
   ```

   This creates and configures 389-ds, the KDC, the Dogtag CA, httpd and
   the helper services.

4. **Start / manage the server:**

   ```sh
   service freeipa_server start      # start | stop | status
   ```

5. **On cloud-init images**, stop cloud-init from rewriting `/etc/hosts` on
   every boot (it would drop the FQDN → real-IP line):

   ```sh
   printf 'manage_etc_hosts: false\n' \
       > /usr/local/etc/cloud/cloud.cfg.d/99-ipa-no-manage-hosts.cfg
   ```

Full operator documentation (service map, uninstall, troubleshooting) is in
`net/freeipa-server/files/README.md`, installed as
`/usr/local/share/doc/freeipa-server/README.md`.

---

## Quick install — client (FreeBSD host joining the realm)

```sh
pkg install freeipa-client

ipa-client-install \
    --domain=example.com \
    --server=ipa.example.com \
    --realm=EXAMPLE.COM
```

After enrollment, `id admin` and `getent passwd admin` resolve IPA users
via SSSD.

---

## Client status — `net/freeipa-client`

The FreeBSD client shipped **in the official ports tree does not yet work** —
it lacks the FreeBSD-specific fixes (getkeytab path, `nsswitch.conf` SSS
integration, platform paths). Those fixes are pending review in an open
FreeBSD PR:

> **Open PR:** [Bug 297487](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=297487)

Until that PR lands, use the **patched `net/freeipa-client` included in this
repository** — it is the exact tree from that PR. `freeipa-client` is not
maintained by the FreeIPA porter; it is included here only to make the CFT
self-contained.

---

## How to use this during the CFT

Both ports depend on other ports; most are already in the FreeBSD ports
tree, a few FreeIPA-related ones are being added/updated in parallel (e.g.
`net/slapi-nis`, `sysutils/oddjob`, `www/freeipa-auth-gssapi`). Use a
**current ports tree** and drop these two ports in on top.

The repository mirrors the ports-tree layout (`net/freeipa-server`,
`net/freeipa-client`), so you can clone it and copy the two directories
straight into your tree:

```sh
# 1. clone this repo somewhere temporary
git clone https://github.com/joneum/FreeBSD-freeipa-server.git /tmp/ipa-cft

# 2. copy the two ports into your ports tree
#    (/usr/ports, or your own checkout / poudriere ports tree)
cp -R /tmp/ipa-cft/net/freeipa-server \
      /tmp/ipa-cft/net/freeipa-client /usr/ports/net/

# 3. build + package with poudriere (recommended), with the required option:
#    security_cyrus-sasl2-gssapi_SET=GSSAPI_MIT
#    security_cyrus-sasl2-gssapi_UNSET=GSSAPI_BASE
poudriere testport -j <jail> -p <tree> net/freeipa-server
poudriere testport -j <jail> -p <tree> net/freeipa-client
```

To pick up a newer revision later, refresh the clone and copy again:

```sh
git -C /tmp/ipa-cft pull
cp -R /tmp/ipa-cft/net/freeipa-server \
      /tmp/ipa-cft/net/freeipa-client /usr/ports/net/
```

---

## Layout

```
net/freeipa-server/                  the server port
net/freeipa-server/files/README.md   full operator + maintainer documentation
net/freeipa-client/                  the client port (patched, per the open PR)
```

---

## Support this work

Porting and maintaining FreeIPA on FreeBSD — server, client and the whole
389-DS / Kerberos / Dogtag / SSSD dependency chain — is a large and ongoing
effort. If this port is useful to **you or your organization**, please
consider a donation. It directly supports continued maintenance and future
FreeBSD identity-management work.

> 💛 **Donate via GitHub Sponsors:** https://github.com/sponsors/joneum

More ways to donate are listed on my blog: https://blog.bsdproject.de

Thank you!

---

## Feedback

Open a GitHub issue here, or contact the maintainer at
**joneum@FreeBSD.org**. Thank you for testing!
