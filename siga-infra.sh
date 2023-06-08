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

if [ -z "$SIGA_SERVICE_POSTFIX" ]; then
  SIGA_SERVICE_POSTFIX="default"
fi

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

STACKS=""
add_stack_file() {
  if [[ "$1" != /* ]]; then
    STACK_FILE="$(pwd)/$1"
  else
    STACK_FILE=$1
  fi

  echo "$(realpath $STACK_FILE)"
  if [ -f "$STACK_FILE" ]; then
    STACKS="$STACKS -c $STACK_FILE"
  fi
}

deploy_siga() {
  add_stack_file "$STACKS_FOLDER/siga/siga-base.yaml"
  TLS=""
  ENTRY="web"

  if [ -z "${SIGA_SERVICE_POSTFIX}" ];
  then
    SIGA_SERVICE_POSTFIX="default"
  fi

  while true; do
    case "$1" in
    --tls)
      shift
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
    -n)
      SIGA_SERVICE_POSTFIX="$2"
      shift 2;
      ;;
    *) break ;;
    esac
  done

  if [ ! -d "$DATA_FOLDER/siga-$SIGA_SERVICE_POSTFIX" ]; then
    if [ "$SIGA_SERVICE_POSTFIX" == "default" ]; then
      echo "Deploy não especificado. Criando o default"
      check_binds
    else
      echo "O deploy denominado de $SIGA_SERVICE_POSTFIX não foi localizado!"
      echo "Execute o comando setup <nome do deploy>"
      exit 1
    fi
  fi

  if [ -f "$DATA_FOLDER/siga-$SIGA_SERVICE_POSTFIX/siga.conf" ]; then
    # shellcheck disable=SC1090
    . "$DATA_FOLDER/siga-$SIGA_SERVICE_POSTFIX/siga.conf"
  fi

  if [ -z "${SIGA_HOST}" ];
  then
      echo "Para utilizar o siga em produção informe um valor para SIGA_HOST."
      exit 1
  fi

  if [ -n "$TLS" ]; then
    add_stack_file "$STACKS_FOLDER/siga/siga-tls.yaml"
  fi

  eval "SIGA_HOST=$SIGA_HOST SIGA_SERVICE_POSTFIX=${SIGA_SERVICE_POSTFIX-default} ENTRY=$ENTRY SIGA_TAG=$SIGA_TAG docker stack deploy$STACKS siga-${SIGA_SERVICE_POSTFIX-default}"
}

deploy_infra() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi

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

check_binds() {
  if [ ! -d "$DATA_FOLDER/siga-$SIGA_SERVICE_POSTFIX" ]; then
    siga_dir="$DATA_FOLDER/siga-$SIGA_SERVICE_POSTFIX"
    env_file="$siga_dir/.env"
    conf_file="$siga_dir/siga.conf"

    cp -r "$BASE_FOLDER/config/base/siga-skel" "$siga_dir"
    echo "Pasta de deploy criada: $(realpath $siga_dir)"

    cp -r "$conf_file.example" "$conf_file"
    echo "Aqrquivo de configuração de infra do siga: $(realpath $conf_file)"

    cp -r "$env_file.example" "$env_file"
    echo "Aqrquivo de configuração do ambiente siga: $(realpath $env_file)"
  fi
}

setup_command() {
  if [ ! -f "$CONFIG_FILE" ]; then
    cp -r "$BASE_FOLDER/config/base/siga-infra.conf.exemple" "$CONFIG_FILE"
    echo "Arquivo de configuração da infra criado: $(realpath $CONFIG_FILE)"
  else
    echo "Arquivo de configuração da infra já existe: $(realpath $CONFIG_FILE)"  
  fi

  SIGA_SERVICE_POSTFIX="$1"
  if [ -z "$SIGA_SERVICE_POSTFIX" ]; then
    SIGA_SERVICE_POSTFIX="default"
  fi

  if [ -d "$DATA_FOLDER/siga-$SIGA_SERVICE_POSTFIX" ]; then
    echo "O deploy com nome $SIGA_SERVICE_POSTFIX já existe!"
    exit 1
  fi

  check_binds
}

case "$1" in
deploy)
  shift
  eval "deploy_command $*"
  ;;
setup)
  shift
  eval "setup_command $*"
  ;;
esac
