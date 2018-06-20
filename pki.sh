#!/bin/bash

# Usage:
# https://github.com/cloudflare/cfssl
# https://coreos.com/os/docs/latest/generate-self-signed-certificates.html

# Shamelessly copy/paste from https://github.com/ncerny/habitat-plans/tree/master/cfssl


# requires:
# - jq
# - Go env 1.8

function common() {
  W=.
  export C=${C:-$W/}

  # Certificate State Constants
  CERT_VALID=0
  CERT_NOEXIST=1
  CERT_INVALID=2
  CERT_EXPIRED=3

  export CFSSL_HOST=${CFSSL_HOST:-127.0.0.1}
  export CFSSL_PORT=${CFSSL_PORT:-8888}
  export ca_url="http://$CFSSL_HOST:$CFSSL_PORT/api/v1/cfssl"

  export VERBOSITY=${VERBOSITY:-3}
  export FMT=${FMT:-%Y/%m/%d %H:%M:%S}
}


function install() {
  which cfssl || \
    go get -u github.com/cloudflare/cfssl/cmd/...
}

function init() {
  common
  mkdir -p $C

  ca="ca.pem"
  key="ca-key.pem"

  PROFILES='"profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }'
  test -e $C/config.json || \
    echo '{"signing":{"default":{"expiry":"43800h","usages":["signing","key encipherment","server auth","client auth"]},$PROFILES}}' > $C/config.json


  pushd $C
  log info "Checking Certificate Authority validity."
  case $(cert_verify_local ${ca}) in
    "CERT_VALID")
      log info "Certificate Authority is valid."
      ;;
    "CERT_EXPIRED")
      log info "Renewing current certificate authority."
      cfssl gencert -renewca -ca "${ca}" -ca-key "${key}" -config "config.json" | cfssljson -bare ca
      ;;
    *)
      log info "Generating new certificate authority."
      echo '{"CN":"Certification Authority","key":{"algo":"rsa","size":2048}}' | cfssl gencert -initca --config config.json - | cfssljson -bare ca -
      ;;
  esac
  popd
}

function serve() {
  common

  exec 2>&1

  exec cfssl serve \
    -address $CFSSL_HOST \
    -port $CFSSL_PORT \
    -ca $C/ca.pem \
    -ca-key $C/ca-key.pem \
    -int-dir $C \
    -config $C/config.json
}


function ca_api() {
  common

  method=$1
  endpoint=$2
  shift
  shift

  if [[ -z "$ca_url" ]]; then
    log info "A Certificate Authority bind was not set, or there are no servers up."
    exit 1
  fi
  if [[ -z "$*" ]]; then
    curl -sS -X $method -H 'Content-Type: application/json' $ca_url/$endpoint
  else
    curl -sS -X $method -H 'Content-Type: application/json' -d "$(echo $* | jq -c .)" $ca_url/$endpoint
  fi
}

function ca_update() {
  common

  if ! cert_verify ${1}.pem; then
    ca_api POST info "{\"label\": \"${1##*/}\"}" | cfssljson $1
  fi
}

function cert_gen() {
  common

  name=$1
  shift
  profile=$1
  shift
  csr=$1
  shift

  hosts=$*
  hostname="-hostname=$(join_by , ${hosts})"

  if ! cert_verify "${name}" ${hosts}; then
    log debug "Issuing new certificate for ${name}."
    certdata=$(echo "{\"request\": $(cat ${csr} | jq -c .), \"profile\": \"${profile}\", \"bundle\": true}" | jq -c .)
    ca_api POST newcert ${certdata} | cfssljson ${name%.*}
  fi
}

function cert_verify() {
  common

  name="$1"
  shift
  log debug "Checking ${name} certificate validity."
  if [ ! -f "$name" ]; then
    log debug "$name certificate does not exist!"
    echo "CERT_NOEXIST"
    return $CERT_NOEXIST
  fi

  certinfo=$(cfssl certinfo -cert ${name})
  log debug "certinfo=$(echo ${certinfo} | jq .)"

  if [ -n "$*" ]; then
    if [ "$(echo ${certinfo} | jq .sans)" == "null" ]; then
      log debug "Certificate contains no hosts!"
      echo "CERT_INVALID"
      return $CERT_INVALID
    fi

    sans=$(echo ${certinfo} | jq .sans[])
    for host in $*; do
      if [[ "${sans[@]}" =~ "$host" ]]; then
        log debug "$host does not exist on certificate!"
        echo "CERT_INVALID"
        return $CERT_INVALID
      fi
    done
  fi

  cert_exp=$(echo ${certinfo} | jq .not_after)
  log debug "cert_exp=${cert_exp}"
  cert_exp="${cert_exp/T/ }"
  log debug "cert_exp=${cert_exp}"
  cert_exp="${cert_exp//[Z\"]/}"
  log debug "cert_exp=${cert_exp}"
  calc_exp=$(date +%s -d "${cert_exp}")
  log debug "calc_exp=${calc_exp}"
  renew=$(( $(date +%s)+30*60*60*24 ))
  log debug "renew=${renew}"
  if [[ $cert_exp < $renew ]]; then
    log debug "${name} certificate is about to/or has expired."
    echo "CERT_EXPIRED"
    return $CERT_EXPIRED
  fi
  echo "CERT_VALID"
  return $CERT_VALID
}

function cert_verify_local() {
  common

  name="$1"
  shift
  log debug "Checking ${name} certificate validity."
  if [ ! -f "$name" ]; then
    log debug "$name certificate does not exist!"
    echo "CERT_NOEXIST"
    return $CERT_NOEXIST
  fi

  certinfo=$(cfssl certinfo -cert ${name})
  log debug "certinfo=$(echo ${certinfo} | jq .)"

  if [ -n "$*" ]; then
    if [ "$(echo ${certinfo} | jq .sans)" == "null" ]; then
      log debug "Certificate contains no hosts!"
      echo "CERT_INVALID"
      return $CERT_INVALID
    fi

    sans=$(echo ${certinfo} | jq .sans[])
    for host in "$*"; do
      if [[ "${sans[@]}" =~ "$host" ]]; then
        log debug "$host does not exist on certificate!"
        echo "CERT_INVALID"
        return $CERT_INVALID
      fi
    done
  fi

  cert_exp=$(echo ${certinfo} | jq .not_after)
  log debug "cert_exp=${cert_exp}"
  cert_exp="${cert_exp/T/ }"
  log debug "cert_exp=${cert_exp}"
  cert_exp="${cert_exp//[Z\"]/}"
  log debug "cert_exp=${cert_exp}"
  calc_exp=$(date +%s -d "${cert_exp}")
  log debug "calc_exp=${calc_exp}"
  renew=$(( $(date +%s)+30*60*60*24 ))
  log debug "renew=${renew}"
  if [[ $cert_exp < $renew ]]; then
    log debug "${name} certificate is about to/or has expired."
    echo "CERT_EXPIRED"
    return $CERT_EXPIRED
  fi
  echo "CERT_VALID"
  return $CERT_VALID
}



join_by() { local IFS="$1"; shift; echo "$*"; }
log_error() { if [ "$VERBOSITY" -ge 0 ]; then echo "$(date +"$FMT") [ERROR] $*"; fi }
log_warn()  { if [ "$VERBOSITY" -ge 2 ]; then echo "$(date +"$FMT") [WARN ] $*"; fi }
log_info()  { if [ "$VERBOSITY" -ge 3 ]; then echo "$(date +"$FMT") [INFO ] $*"; fi }
log_debug() { if [ "$VERBOSITY" -ge 9 ]; then echo "$(date +"$FMT") [DEBUG] $*"; fi }
log() {
        case "${1^^}" in
          "ERROR")
            shift
            log_error $*
            ;;
          "WARN")
            shift
            log_warn $*
            ;;
          "INFO")
            shift
            log_info $*
            ;;
          "DEBUG")
            shift
            log_debug $*
            ;;
          *)
            if [ "$VERBOSITY" -ge 1 ]; then
              echo "$(date +"$FMT") [LOG  ] $*"
            fi
            ;;
        esac
}

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

die () {
  echo "$@"
  exit 1
}

function contains() {
    local n="$#"
    local value="${!n}"
    for ((i=1;i < $#;i++)) {
        if [[ "${!i}" == "${value}" ]]; then
            echo "y"
            return 0
        fi
    }
    echo "n"
    return 1
}

# allow to be sourced to use functions independently
if [[ "$BASH_SOURCE" == "$0" ]]; then
  #set -eu -o pipefail
  if [[ $# -gt 0 ]]; then
    fn=$1
    shift
    $fn $@
  else
    serve
  fi
fi

