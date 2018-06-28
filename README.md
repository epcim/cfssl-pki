# cfssl pki

Simple script wrapper for CFSSL to painlessly generate "unsafe" self-sign certificates.

# Usage

## Init/start CFSSL server

Note, API server is used by default to be compatible with habitat instance,
however basic functions `gen_cert` can be easily written to use only local cfssl commands.

### As a habitat service

    # install habitat.sh
    curl https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh | sudo bash

    # run
    echo <<-EOF >> cfss.toml
			[[ca.names]]
			"C":  "CZ",
			"L":  "Prague",
			"O":  "Demo",
			"OU": "Geeks"
			EOF

    HAB_ORIGIN=${HAB_OROGIN:-epcim}
    sudo HAB_CFSSL="$(cat cfssl.toml)" hab start $HAB_ORIGIN/cfssl --channel unstable

Mind `"Now listening on 192.168.xx.xx:8888"` or similar..
Obviously, this is the most trivial hab setup for the demo purpose.

### Locally with scripts

    ./pki.sh install &&\
    ./pki.sh init    &&\
    ./pki.sh serve

Mind `"Now listening on 192.168.xx.xx:8888"` or similar..
Obviously, this is the most trivial hab setup for the demo purpose.

## Generate certificates

    export CFSSL_HOST=192.168.43.3
    export CFSSL_PORT=8888

    # specify what/where to generate (update example)
    $EDITOR ./pki-create.sh

    # generate certificates
    ./pki-create.sh

## Check certs

    certtool -i < ./vault-client.pem

