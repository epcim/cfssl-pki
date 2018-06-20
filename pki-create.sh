#!/bin/bash

C=./

./pki.sh install &&\
./pki.sh init    &&\
./pki.sh serve   &


sleep 1
if ./pki.sh ca_api POST info "{\"label\": \"\"}" >/dev/null; then

  source ./pki.sh
  ca_update $C/ca

  # EXAMPLE, vault-etcd
  CRTCN="vault-etcd"
  echo '{"CN":"'$CRTCN'","hosts":[""],"key":{"algo":"rsa","size":2048}}' |\
      cert_gen $C/$CRTCN.pem server /dev/stdin "$CRTCN.local" "$CRTCN" 127.0.0.1
  # ----
  # EXAMPLE2 - locally, vault-etcd
  #pushd $C
  #echo '{"CN":"'$CRTCN'","hosts":[""],"key":{"algo":"rsa","size":2048}}' |\
  #  cfssl gencert -ca=$C/ca.pem -ca-key=$C/ca-key.pem -config=$C/config.json -profile=server \
  #    -hostname="$CRTCN.local,$CRTCN,127.0.0.1" - | cfssljson -bare $CRTCN
  #popd

else
  echo "ERROR, server not operational!"
fi

pkill cfssl


