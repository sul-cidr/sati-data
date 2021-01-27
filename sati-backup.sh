#!/bin/bash

set -euo pipefail;

show_help() {
cat << EOF
Usage: ${0##*/} [-q]

  Backs up user data from the SATI application -- all the database data from the
  Items and Users apps, as well as the uploaded item images -- and commits new or
  modified data to GitHub.

    -h          display this help and exit
    -q          quiet operation; will only produce output in case of error
                (intended for use from cron)


Respects the following environment variables (the defaults are expected to be
used in production).

  BACKUP_DIR          Directory that contains the backup repo
                       - defaults to this script's parent dir
  COMPOSE_PROJ_DIR    Context directory for docker-compose
                       - defaults to \$BACKUP_DIR/../sati
  COMPOSE_FILE        docker-compose configuration file
                       - defaults to \$COMPOSE_PROJ_DIR/docker-compose.yml
  MEDIA_DIR           Directory that contains the item images (Django's MEDIA_ROOT)
                       - defaults to \$COMPOSE_PROJ_DIR/media
  ENV_FILE            .env file passed both to docker-compose and to the containers
                       - defaults to \$COMPOSE_PROJ_DIR/.env

EOF
}

quiet=;

while :; do
    case ${1-} in
        -h|-\?|--help)
            show_help
            exit
            ;;
        -q|--quiet)
            quiet=--quiet
            ;;
        --)
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)
            break
    esac

    shift
done

function absdir { cd "$1" && pwd -P; }

function log() {
  [ $quiet ] && return;
  [ ! -t 1 ] && printf "\n%s\n" "$1" && return;
  COLOR='\e[;93m'; # light yellow (93)
  RESET='\e[0m';
  printf "\n%b%s%b\n" "${COLOR}" "$1" "${RESET}";
}


# Note: supplying --project-directory "${COMPOSE_PROJ_DIR}" to
#       docker-compose exec is necessary to have values from the .env
#       file successfully interpolated into docker-compose.yml.
#       This appears to be a bug in docker-compose (--project-directory
#       should default to the directory of the docker-compose file) -- see
#       https://github.com/docker/compose/issues/6310#issuecomment-765807115


BACKUP_DIR=${BACKUP_DIR:=$(absdir "${BASH_SOURCE%/*}")};
COMPOSE_PROJ_DIR=${COMPOSE_PROJ_DIR:=$(absdir "${BACKUP_DIR}/../sati/")};
COMPOSE_FILE=$(readlink -f "${COMPOSE_FILE:="${COMPOSE_PROJ_DIR}/docker-compose.yml"}");
MEDIA_DIR=${MEDIA_DIR:=$(absdir "${COMPOSE_PROJ_DIR}/media")};
ENV_FILE=$(readlink -f "${ENV_FILE:="${COMPOSE_PROJ_DIR}/.env"}");

[ -d "${BACKUP_DIR}" ] || { echo "Backup dir ${BACKUP_DIR} does not exist!" >&2; exit 1; }
[ -d "${MEDIA_DIR}" ] || { echo "Media dir ${MEDIA_DIR} does not exist!" >&2; exit 1; }
[ -d "${COMPOSE_PROJ_DIR}" ] || { echo "docker-compose dir ${COMPOSE_PROJ_DIR} does not exist!" >&2; exit 1; }
[ -e "${COMPOSE_FILE}" ] || { echo "docker-compose file not found at ${COMPOSE_FILE}!" >&2; exit 1; }
[ -e "${ENV_FILE}" ] || { echo ".env file not found at ${ENV_FILE}!" >&2; exit 1; }

log "Dumping data from the Users app to ${BACKUP_DIR}/users.json";
docker-compose \
  --env-file "${ENV_FILE}" \
  --project-directory "${COMPOSE_PROJ_DIR}" \
  --file "${COMPOSE_FILE}" \
  exec -T django python manage.py dumpdata users \
  | jq "[.[] | {model, pk, fields: .fields | del(.date_joined, .last_login, .require_password_change)}]" \
  > "${BACKUP_DIR}/users.json";

log "Dumping data from the Items app to ${BACKUP_DIR}/items.json";
docker-compose \
  --env-file "${ENV_FILE}" \
  --project-directory "${COMPOSE_PROJ_DIR}" \
  --file "${COMPOSE_FILE}" \
  exec -T django python manage.py dumpdata --indent 2 items \
  | tr -d "\r" \
  > "${BACKUP_DIR}/items.json";

log "Syncing Item images from ${MEDIA_DIR} to ${BACKUP_DIR}";
rsync -avPh ${quiet} --delete --delete-excluded --exclude .gitignore "${MEDIA_DIR}" "${BACKUP_DIR}";


cd "${BACKUP_DIR}";

log "Commiting changes";
git commit ${quiet} -am "Update $(date +%F)";

log "Pushing changes";
git push ${quiet} origin;
