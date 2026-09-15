#!/usr/bin/env bash
#
# Which certificate the build signs with, and how to make one.
#
# Why this matters more than it looks: macOS keys TCC permissions — Accessibility
# and Screen Recording, both of which AltTab cannot work without — to the app's
# code signature. An ad-hoc signature (`-`) has no stable identity, so the system
# falls back to the cdhash, which changes on every single rebuild. That means
# re-granting Accessibility by hand after every upgrade, and macOS does not always
# make that obvious: the app just silently stops listing windows.
#
# A self-signed certificate fixes that, because the signature is stable across
# rebuilds. Creating one needs a keychain authorisation prompt, so it cannot be
# part of an unattended wipe-day rebuild. Hence: ad-hoc works out of the box,
# `alt-tab-unlocked signing-cert` upgrades you to the stable one whenever you get
# round to it.

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CN="${ATU_SIGNING_CN:-AltTab Unlocked Local Signing}"

have_identity() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$CN\""
}

case "${1:---resolve}" in
  --resolve)
    if have_identity; then printf '%s\n' "$CN"; else printf '%s\n' '-'; fi
    ;;

  --status)
    if have_identity; then
      ok "signing with the self-signed identity \"$CN\" (TCC grants survive rebuilds)"
    else
      warn "signing ad-hoc. Accessibility and Screen Recording must be re-granted
        after every rebuild. Run \`alt-tab-unlocked signing-cert\` once to fix that."
    fi
    ;;

  --create)
    if have_identity; then
      ok "\"$CN\" already exists; nothing to do"
      exit 0
    fi
    command -v openssl >/dev/null || die "openssl not found"

    bold "Creating a local code-signing certificate"
    info "macOS will ask for your login password twice: once to import the key"
    info "into the login keychain, once to trust the certificate for code signing."

    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
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
    openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
      -out "$tmp/bundle.p12" -passout pass: -name "$CN" 2>/dev/null \
      || die "openssl could not build the p12"

    KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
    # -T codesign: pre-authorise codesign to use the key without a prompt per build.
    /usr/bin/security import "$tmp/bundle.p12" -k "$KEYCHAIN" -P "" \
      -T /usr/bin/codesign -T /usr/bin/security \
      || die "could not import the identity into the login keychain"
    # A self-signed certificate is its own root, so it has to be trusted as one
    # before codesign will build a chain to it.
    /usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem" \
      || die "could not mark the certificate as trusted for code signing"

    have_identity || die "the identity still is not visible to codesign. Open Keychain
      Access, find \"$CN\", and check that its trust settings allow code signing."
    ok "created \"$CN\""
    info "run \`alt-tab-unlocked install\` to rebuild and sign with it"
    ;;

  *) die "usage: signing-identity.sh [--resolve|--status|--create]" ;;
esac
