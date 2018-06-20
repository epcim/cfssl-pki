#!/bin/bash

# PATH to secret cert storage
C=.

if ./pki.sh ca_api POST info "{\"label\": \"\"}" >/dev/null; then

  source ./pki.sh

  [[ -z "$CERT_NAMES" ]] &&\
  export CERT_NAMES='
    "names": [
      {
        "C":  "CZ",
        "L":  "Prague",
        "O":  "Demo",
        "OU": "Geeks"
      }
    ]'
  ca_update $C/ca

  # ----
  # EXAMPLE 1
  FQDN="etcd-vault.demo.local" CN=${FQDN//.*/} AN="$FQDN $CN 127.0.0.1 $OTHER_ALT_NAME_FOR_ITS_CERT"
  echo '{"CN":"'$CN'","hosts":['$(join_by , $(enquote $AN))'],"key":{"algo":"rsa","size":2048},'$CERT_NAMES'}' |\
      cert_gen $C/$CN.pem server /dev/stdin

  # ----
  # EXAMPLE 2
  FQDN="vault.demo.local" CN=${FQDN//.*/} AN="$FQDN $CN 127.0.0.1 $OTHER_ALT_NAME_FOR_ITS_CERT"
  echo '{"CN":"'$CN'","hosts":['$(join_by , $(enquote $AN))'],"key":{"algo":"rsa","size":2048},'$CERT_NAMES'}' |\
      cert_gen $C/$CN.pem client /dev/stdin

  # ----
  # EXAMPLE3 - locally - direct invocation, no api server
  #pushd $C
  #echo '{"CN":"'$CRTCN'","hosts":[""],"key":{"algo":"rsa","size":2048}}' |\
  #  cfssl gencert -ca=$C/ca.pem -ca-key=$C/ca-key.pem -config=$C/config.json -profile=server \
  #    -hostname="$CRTCN.local,$CRTCN,127.0.0.1" - | cfssljson -bare $CRTCN
  #popd

else
  echo "ERROR, server not operational!"
  exit 1
fi



