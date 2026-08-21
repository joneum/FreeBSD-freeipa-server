# FreeIPA on FreeBSD

FreeIPA is integrated identity management: 389 Directory Server (LDAP),
an MIT Kerberos KDC, Dogtag PKI (CA) and an Apache/mod_wsgi management
stack, combined into a single managed domain.

> **`net/freeipa-server` is now committed to the official FreeBSD ports
> tree.** You no longer need this repository to install the server.
> See [commit 35e4879](https://cgit.freebsd.org/ports/commit/?id=35e48795412e5aba7dcf12b074b5ffa152aed031).
>
> The tree is at **4.13.2**. Upgrading an existing server from 4.13.1 needs
> two manual steps, because they touch the configuration of a deployed
> pki-tomcat instance that no package may rewrite: repoint the instance at
> Java 21 and correct its ACME paths. Both are spelled out in the ports
> `UPDATING` entry dated `20260819`.

The Call For Testing that this repository was created for has served its
purpose. What remains here:

* the **patched `net/freeipa-client`**, until [Bug 297487](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=297487) lands
* the **documentation** below (prerequisites, quick install, known issues)
* the **issue tracker**, still the central place for FreeIPA-on-FreeBSD reports

Maintainer: **joneum@FreeBSD.org**

> ⚠️ **Still not recommended for production.** The port is young and the
> FreeBSD integration has not seen wide real-world use yet. Use a dedicated
> VM, not your company login server.

---

## Prerequisites (read this first)

### 1. Two ports must be built with `GSSAPI_MIT`

FreeIPA on FreeBSD runs on the **MIT Kerberos from ports**
(`security/krb5`). Two ports default to `GSSAPI_BASE`, which links the
**base-system** Kerberos instead. Mixing both Kerberos implementations is
what causes the classic late-stage failures, so build these with
`GSSAPI_MIT`:

```
security_cyrus-sasl2-gssapi_SET=GSSAPI_MIT
security_cyrus-sasl2-gssapi_UNSET=GSSAPI_BASE
security_py-gssapi_SET=GSSAPI_MIT
security_py-gssapi_UNSET=GSSAPI_BASE
```

Put that in `make.conf` (ports or poudriere), or select the option
interactively:

```sh
make -C /usr/ports/security/cyrus-sasl2-gssapi config
make -C /usr/ports/security/py-gssapi config
```

Without this, `ipa-server-install` runs all the way through and then fails
right at the end with `SPNEGO cannot find mechanisms to negotiate` or
`Cannot find KDC for realm`. Verify afterwards (both must point into
`/usr/local`, never `/usr/lib`):

```sh
ldd /usr/local/lib/sasl2/libgssapiv2.so | grep libgssapi_krb5
ldd /usr/local/lib/python3*/site-packages/gssapi/raw/misc*.so | grep libgssapi_krb5
```

This is a system-wide choice. Every SASL/GSSAPI consumer on the host
(SSSD, OpenLDAP, Postfix) then uses the ports MIT Kerberos, which is the
correct, consistent setup on a machine dedicated to FreeIPA.

### 2. Host naming

The system hostname must be a fully-qualified domain name that resolves to
the host's **real** IP (not loopback), and it must be the canonical name in
`/etc/hosts`:

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

## Quick install: server

1. **Install it** from the ports tree or as a package:

   ```sh
   pkg install freeipa-server
   ```

2. **Enable the required services in `rc.conf`.** Three switches, the
   FreeIPA stack itself plus D-Bus and gssproxy (without the latter two the
   server does not survive a reboot):

   ```sh
   sysrc freeipa_server_enable=YES   # the whole stack, driven by ipactl
   sysrc dbus_enable=YES             # certmonger + oddjobd need the system bus
   sysrc gssproxy_enable=YES         # httpd/mod_auth_gssapi acquires HTTP creds
   ```

   You do **not** enable the individual back-ends (389-ds, KDC, Dogtag,
   httpd) in `rc.conf`. `ipactl` starts them in the correct order.

3. **Configure the instance.** `--no-host-dns` skips DNS pre-checks when you
   manage names via `/etc/hosts`, `--no-ntp` skips the chrony client which is
   not used on FreeBSD:

   ```sh
   ipa-server-install \
       --hostname=ipa.example.com \
       --domain=example.com \
       --realm=EXAMPLE.COM \
       --no-host-dns \
       --no-ntp
   ```

4. **Start and manage the server:**

   ```sh
   service freeipa_server start      # start | stop | status
   ```

5. **Reach the Web UI** at `https://ipa.example.com/` and log in as `admin`
   with the password you set during `ipa-server-install`. For Kerberos
   single sign-on your browser must trust the IPA CA
   (`https://ipa.example.com/ipa/config/ca.crt`) and have Negotiate/GSSAPI
   enabled, otherwise the UI falls back to form-based login.

6. **On cloud-init images**, stop cloud-init from rewriting `/etc/hosts` on
   every boot. It regenerates the file from a template, which drops the
   FQDN to real-IP line and maps the host to `127.0.0.1` only. FreeIPA can
   then no longer resolve its own name, and even `ipactl` aborts with
   `socket.gaierror: [Errno 8] Name does not resolve`:

   ```sh
   printf 'manage_etc_hosts: false\n' \
       > /usr/local/etc/cloud/cloud.cfg.d/99-ipa-no-manage-hosts.cfg
   ```

   That drop-in only wins when the image's own user-data leaves
   `manage_etc_hosts` alone. Proxmox, for instance, generates user-data
   containing `manage_etc_hosts: true`, and user-data outranks everything
   in `cloud.cfg.d`. Once the host is provisioned, cloud-init has no
   further job on an IPA server, so take it out of the boot path for good:

   ```sh
   touch /usr/local/etc/cloud/cloud-init.disabled
   ```

Full operator documentation (service map, uninstall, troubleshooting) ships
with the port as `/usr/local/share/doc/freeipa-server/README.md`.

---

## Quick install: client

The client in the official tree does **not** work yet. It lacks the
FreeBSD-specific fixes (getkeytab path, `nsswitch.conf` SSS integration,
platform paths), which are pending review in
[Bug 297487](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=297487).

Until that PR lands, use the patched `net/freeipa-client` from this
repository (it is the exact tree from that PR):

```sh
# clone and copy the client port into your ports tree
git clone https://github.com/joneum/FreeBSD-freeipa-server.git /tmp/ipa-cft
cp -R /tmp/ipa-cft/net/freeipa-client /usr/ports/net/

# build it (poudriere recommended)
poudriere testport -j <jail> -p <tree> net/freeipa-client
```

Then enroll the host:

```sh
ipa-client-install \
    --domain=example.com \
    --server=ipa.example.com \
    --realm=EXAMPLE.COM
```

After enrollment, `id admin` and `getent passwd admin` resolve IPA users
via SSSD. `net/freeipa-client` is not maintained by the FreeIPA porter, it
is included here only so that a full server plus client setup can be tested
today.

---

## Known issues and limitations

These are **already known**, so please do not file separate reports just for
them. Extra detail or fixes are of course welcome:

* **`oddjob-mkhomedir` is unverified.** `oddjobd` itself starts and stays up
  since `ipa-server-install` enables and starts the D-Bus system bus, but
  automatic creation of home directories on first login has not been
  tested on FreeBSD.
* **No DNS records without integrated DNS.** If you install without
  IPA-managed DNS, the `A`, `PTR` and `SSHFP` records are not created.
  Manage names via `/etc/hosts` or your own DNS server.
* **`sssctl` needs a running D-Bus.** `ipa-server-install` sets
  `dbus_enable=YES` and starts the bus itself, so this only bites on hosts
  where the bus was disabled again afterwards.
* **`ipa-getkeytab` run by hand** may print a TLS-context error. The
  enrolment path used by `ipa-client-install` itself works.
* **gssproxy S4U2 is unreliable on FreeBSD**, so the server uses a direct
  MIT-krb5 S4U2Self path for the HTTP stack by design. gssproxy stays
  installed and enabled for its credential-store role.

---

## Testing is still very welcome

The port being in the tree means it builds and installs cleanly, not that
every code path has been exercised. Reports are still valuable, especially
for the paths off the beaten track:

* All `ipa-server-install` options: self-signed vs. external CA
  (`--external-ca`), with and without integrated DNS, custom realm/domain
  combinations, non-default subject base, unattended (`-U`) installs.
* The full `ipa` command surface: users, groups, hosts, host groups, sudo
  rules, HBAC, RBAC/roles, certificates and cert profiles, OTP tokens,
  ID views, ID ranges, password policies, DNS records.
* Client enrollment, un-enrollment and re-enrollment, plus `id`, `getent`
  and Kerberos login for IPA users.
* Replicas and multi-server topologies.
* Boot persistence (reboot the server, verify the stack comes back up).
* Uninstall, reinstall and full decommission.

---

## Layout

```
net/freeipa-client/    the patched client port, per open PR 297487
net/freeipa-server/    reference copy of the committed server port
```

The server directory is kept as a reference snapshot only. The **official
ports tree is authoritative**, so install the server from there rather than
copying this directory over your tree.

---

## Support this work

Porting and maintaining FreeIPA on FreeBSD (server, client and the whole
389-DS, Kerberos, Dogtag and SSSD dependency chain) is a large and ongoing
effort, done unpaid alongside a regular job and a family. The hardware the
test VMs run on is paid for out of pocket as well.

If this port is useful to you or your organization, please consider a
donation. It directly supports continued maintenance and future FreeBSD
identity-management work, and it is especially appreciated from companies
that run FreeBSD and get real value out of ports like this one.

> 💛 **Donate via GitHub Sponsors:** https://github.com/sponsors/joneum

More ways to donate are listed on my blog: https://blog.bsdproject.de

Thank you!

---

## Feedback

Open a GitHub issue here, or contact the maintainer at
**joneum@FreeBSD.org**.

When reporting a failure, please attach as much of the following as applies:

* `uname -a` and the FreeBSD / `pkg` version
* the **poudriere build log** (for build failures)
* `/var/log/ipaserver-install.log` or `/var/log/ipaclient-install.log`
* `ipactl status` and `/var/log/httpd-error.log` (runtime or Web-UI issues)
* a `KRB5_TRACE=/dev/stderr <command>` trace for Kerberos/GSSAPI problems
* the Dogtag/PKI logs under `/var/log/pki/` (CA issues)

Thank you for testing!
