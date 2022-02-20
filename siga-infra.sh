#!/bin/bash

BASE_FOLDER="$(dirname -- "$(pwd)/$0")"
DATA_FOLDER="$BASE_FOLDER/data"
STACKS_FOLDER="$BASE_FOLDER/stacks"
CONFIG_FILE="$BASE_FOLDER/config/siga-infra.conf"

if command -v docker >/dev/null 2>&1; then
  if ! docker stack ls >/dev/null 2>&1; then
    echo -n "Para utilizar esse script, o docker deve estar executando em modo swarm."
    exit 1
  fi
else
  echo -n "O comando docker não foi encontrado"
  exit 1
fi

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

if [ -z "$SIGA_SERVICE_POSTFIX" ]; then
  SIGA_SERVICE_POSTFIX="default"
fi

STACKS=""
add_stack_file() {
  if [[ "$1" != /* ]]; then
    STACK_FILE="$(pwd)/$1"
  else
    STACK_FILE=$1
  fi

  echo "$STACK_FILE"
  if [ -f "$STACK_FILE" ]; then
    STACKS="$STACKS -c $STACK_FILE"
  fi
}

check_binds() {
  if [ ! -d "$DATA_FOLDER/siga-$SIGA_SERVICE_POSTFIX" ]; then
    cp -r "BASE_FOLDER/config/siga-skel" "$DATA_FOLDER/siga-$SIGA_SERVICE_POSTFIX"
  fi
}

deploy_siga() {
#  if [ -n "$(docker service ls -q -f "label=siga-$SIGA_SERVICE_POSTFIX")" ]; then
#    echo "O serviço do siga-$SIGA_SERVICE_POSTFIX já existe!. Por favor redefina a variável SIGA_SERVICE_POSTFIX"
#    exit
#  fi

  add_stack_file "$STACKS_FOLDER/siga/siga-base.yaml"
  TLS=""
  ENTRY="web"

  while true; do
    case "$1" in
    --tls)
      shift
      if [ -z "${SIGA_HOST}" ];
      then
          echo "Para utilizar o siga em produção informe um valor para SIGA_HOST."
          exit 1
      fi

      TLS="true"
      ENTRY="websecure"
      ;;
    --test)
      shift
      add_stack_file "$STACKS_FOLDER/siga/siga-test.yaml"
      ;;
    --dev)
      shift
      add_stack_file "$STACKS_FOLDER/siga/siga-test.yaml"
      add_stack_file "$STACKS_FOLDER/siga/siga-dev.yaml"
      ;;
    --alternative-entry)
      shift
      ENTRY="test"
      ;;
    --add)
      add_stack_file "$2"
      shift 2;
      ;;
    *) break ;;
    esac
  done

  if [ -n "$TLS" ]; then
    add_stack_file "$STACKS_FOLDER/siga/siga-tls.yaml"
  fi

  check_binds
  eval "SIGA_HOST=$SIGA_HOST SIGA_SERVICE_POSTFIX=$SIGA_SERVICE_POSTFIX ENTRY=$ENTRY docker stack deploy$STACKS siga-${SIGA_SERVICE_POSTFIX-default}"
}

deploy_infra() {
  add_stack_file "$STACKS_FOLDER/traefik/traefik-base.yaml"
  use_tls=false
  use_panel=false

  while true; do
    case "$1" in
    --tls)
      shift
      if [ -z "${TRAEFIK_ACME_EMAIL}" ];
      then
          echo "Para utilizar o traefik com tls informe um valor para TRAEFIK_ACME_EMAIL."
          exit 1
      fi
      if [ -z "${INFRA_HOST}" ];
      then
          echo "Para utilizar o traefik com tls informe um valor para INFRA_HOST."
          exit 1
      fi

      if [ ! -d "$DATA_FOLDER/infra/traefik" ]; then
        mkdir -p "$DATA_FOLDER/infra/traefik"
      fi

      use_tls=true
      ;;
    --add)
      add_stack_file "$2"
      shift 2;
      ;;
    --panel)
      if [ ! -d "$DATA_FOLDER/infra/couchdb" ]; then
        mkdir -p "$DATA_FOLDER/infra/couchdb"
      fi

      if [ ! -d "$DATA_FOLDER/infra/influxdb" ]; then
        mkdir -p "$DATA_FOLDER/infra/influxdb"
      fi

      use_panel=true
      shift 1;
      ;;
    *) break ;;
    esac
  done

  $use_panel && add_stack_file "$STACKS_FOLDER/swarmpit/swarmpit.yaml"
  if $use_tls; then
    add_stack_file "$STACKS_FOLDER/traefik/traefik-tls.yaml"
    $use_panel && add_stack_file "$STACKS_FOLDER/swarmpit/swarmpit-tls.yaml"
  else
     add_stack_file "$STACKS_FOLDER/traefik/traefik-default.yaml"
     $use_panel && add_stack_file "$STACKS_FOLDER/swarmpit/swarmpit-default.yaml"
  fi

  eval "TRAEFIK_ACME_EMAIL=$TRAEFIK_ACME_EMAIL TRAEFIK_AUTH=$TRAEFIK_AUTH INFRA_HOST=$INFRA_HOST docker stack deploy$STACKS infra"
}

deploy_command() {
  if ! docker network inspect traefik-public >/dev/null 2>&1; then
    docker network create --driver=overlay traefik-public
  fi

  case "$1" in
  infra)
    shift
    eval "deploy_infra $*"
    ;;
  siga)
    shift
    eval "deploy_siga $*"
    ;;
  esac
}

case "$1" in
deploy)
  shift
  eval "deploy_command $*"
  ;;
esac
