# Call For Testing — FreeIPA server on FreeBSD (`net/freeipa-server`)

This repository contains a **work-in-progress FreeBSD port of the FreeIPA
server** (FreeIPA 4.13.1). It is published here for a **Call For Testing
(CFT)** and is **not yet committed** to the official FreeBSD ports tree.

FreeIPA is integrated identity management: 389 Directory Server (LDAP) +
MIT Kerberos KDC + Dogtag PKI (CA) + an Apache/mod_wsgi management stack.

> **Status.** On FreeBSD 15 (amd64) `ipa-server-install` completes and a
> FreeBSD client can enroll against the server with `ipa-client-install`
> and resolve IPA users/groups (`id`, `getent`) via SSSD. All blockers
> known to the maintainer are fixed in these patches. This is exactly what
> the CFT should confirm on other setups.

Maintainer: **joneum@FreeBSD.org**

---

## What to test

* Building the port (poudriere strongly recommended).
* `ipa-server-install` on a freshly provisioned host.
* Enrolling a FreeBSD client (`net/freeipa-client`) and resolving users.
* Boot persistence (reboot the server, verify the stack comes back up).
* Uninstall / reinstall.

Please report results — **success or failure** — via a GitHub issue on this
repository (include FreeBSD version, `uname -a`, and the relevant
`ipaserver-install.log` / poudriere build log on failure).

---

## Read the prerequisites first

The port ships a detailed operator + maintainer document at
`net/freeipa-server/files/README.md` (installed as
`/usr/local/share/doc/freeipa-server/README.md`). **Read its
“Prerequisites (read this first)” section before installing.** The two
things that trip people up:

1. **`security/cyrus-sasl2-gssapi` must be built with the `GSSAPI_MIT`
   option** (not the default `GSSAPI_BASE`), so the SASL/GSSAPI plugin
   links the ports MIT Kerberos (`security/krb5`) instead of base-system
   Kerberos. Otherwise `ipa-server-install` runs to the very end and then
   fails with `SPNEGO cannot find mechanisms to negotiate` /
   `Cannot find KDC for realm`.

2. **Correct host naming** — the system hostname must be an FQDN that
   resolves to the host’s real IP (not loopback) and is canonical in
   `/etc/hosts`.

Boot persistence additionally needs `dbus_enable=YES`, `gssproxy_enable=YES`
and (on cloud-init images) `manage_etc_hosts: false` — all documented in the
in-port README.

---

## How to use this during the CFT

`freeipa-server` depends on a number of other ports. Most are already in the
FreeBSD ports tree; a few FreeIPA-related ports are being added/updated in
parallel (e.g. `net/slapi-nis`, `sysutils/oddjob`,
`www/freeipa-auth-gssapi`). You therefore need a **current ports tree** plus
this port dropped in on top:

```sh
# in a ports tree checkout (or /usr/ports)
cp -R net/freeipa-server /path/to/ports/net/

# build + package with poudriere (recommended), with the required option:
#   security_cyrus-sasl2-gssapi_SET=GSSAPI_MIT
#   security_cyrus-sasl2-gssapi_UNSET=GSSAPI_BASE
poudriere testport -j <jail> -p <tree> net/freeipa-server
```

Then install the resulting package and run `ipa-server-install` as described
in the in-port README.

> **Important:** the SASL/GSSAPI `GSSAPI_MIT` choice is **system-wide**. Test
> on a host dedicated to FreeIPA, ideally a throwaway VM.

---

## Layout

```
net/freeipa-server/        the port (Makefile, distinfo, files/, pkg-*)
net/freeipa-server/files/README.md   operator + maintainer documentation
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
