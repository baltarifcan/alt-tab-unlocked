#!/usr/bin/env bash
#
# Which certificate the build signs with, and how to make one.
#
# Why this matters more than it looks: macOS keys TCC permissions — Accessibility
# and Screen Recording, both of which AltTab is useless without — to the app's
# designated requirement. Those two look like this:
#
#   ad-hoc:      identifier "AltTab" and cdhash H"<hash of this exact build>"
#   certificate: identifier "AltTab" and certificate leaf = H"<hash of the cert>"
#
# The ad-hoc one changes on every single rebuild, so every upgrade silently costs
# AltTab its Accessibility grant — and the failure mode is not an error, it is
# the switcher listing no windows. The certificate one is stable for as long as
# the certificate is, which is the whole point.
#
# The certificate is deliberately NOT added to the trust store. codesign signs
# perfectly well with an untrusted self-signed identity (`find-identity` reports
# it as CSSMERR_TP_NOT_TRUSTED and signs with it anyway), the signature is just as
# stable, and skipping the trust step means this needs no sudo and pops no
# authorisation dialog — which is what makes it safe to run unattended on a fresh
# machine. Trusting a self-signed root for code signing is a real, system-wide
# decision, and nothing here needs it.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CN="${ATU_SIGNING_CN:-AltTab Unlocked Local Signing}"

# Deliberately not `find-identity -v`. The -v filter means "valid", which means
# "chains to a trusted root", which this certificate intentionally does not.
# Using -v here is what made an earlier version of this script silently fall back
# to ad-hoc forever.
have_identity() {
  /usr/bin/security find-identity -p codesigning 2>/dev/null | grep -qF "\"$CN\""
}

create_identity() {
  command -v openssl >/dev/null || die "openssl not found"

  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  cat > "$tmp/cfg" <<CFG
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = $CN
[ v3 ]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
CFG

  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cfg" 2>/dev/null \
    || die "openssl could not generate the certificate"

  # Two things Apple's Security framework is fussy about, both of which produce
  # the same useless "MAC verification failed (wrong password?)" on import:
  #   - OpenSSL 3 defaults to a PBKDF2/AES MAC that it cannot read, so the old
  #     SHA1/3DES scheme has to be forced.
  #   - An *empty* passphrase fails MAC verification outright, so the bundle gets
  #     a random one. It exists only between these two lines and is never stored;
  #     the private key's security comes from the login keychain, not from this.
  local pass; pass="$(openssl rand -hex 16)"
  openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$tmp/bundle.p12" -passout "pass:$pass" -name "$CN" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null \
    || die "openssl could not build the PKCS#12 bundle"

  # -T codesign pre-authorises codesign to use the key, so signing never pops a
  # "wants to use your confidential information" dialog.
  /usr/bin/security import "$tmp/bundle.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" -P "$pass" \
    -T /usr/bin/codesign >/dev/null \
    || die "could not import the identity into the login keychain"

  have_identity || die "the identity imported but codesign cannot see it.
      Check Keychain Access for \"$CN\" in the login keychain."
}

case "${1:---resolve}" in
  --resolve)
    if have_identity; then printf '%s\n' "$CN"; else printf '%s\n' '-'; fi
    ;;

  # Used by build.sh. Silent when the identity already exists, which is the
  # common case; creates it on a fresh machine without asking anything.
  --ensure)
    if [ "${ATU_SIGNING:-cert}" = "adhoc" ]; then
      warn "ATU_SIGNING=adhoc: signing ad-hoc, TCC grants will not survive rebuilds"
      exit 0
    fi
    have_identity && exit 0
    bold "Creating a local code-signing certificate"
    info "\"$CN\", self-signed, not added to the trust store. No password needed."
    create_identity
    ok "created \"$CN\""
    info "AltTab's Accessibility grant will now survive rebuilds — but this first"
    info "build changes its signature, so it has to be granted once more."
    ;;

  --create)
    if have_identity; then ok "\"$CN\" already exists; nothing to do"; exit 0; fi
    bold "Creating a local code-signing certificate"
    create_identity
    ok "created \"$CN\""
    info "run \`alt-tab-unlocked install\` to rebuild and sign with it"
    ;;

  --status)
    if have_identity; then
      ok "signing with \"$CN\"; the designated requirement pins the certificate,"
      info "  so Accessibility and Screen Recording survive rebuilds"
    else
      warn "signing ad-hoc: the designated requirement pins this build's cdhash, so
        Accessibility must be re-granted after every rebuild."
    fi
    ;;

  *) die "usage: signing-identity.sh [--resolve|--ensure|--create|--status]" ;;
esac
