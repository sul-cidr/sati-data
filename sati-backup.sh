#!/bin/bash

set -euo pipefail;

function absdir { cd "$1" && pwd -P; }

# Note: supplying --project-directory "${COMPOSE_PROJ_DIR}" to
#       docker-compose exec is necessary to have values from the .env
#       file successfully interpolated into docker-compose.yml.
#       This appears to be a bug in docker-compose (--project-directory
#       should default to the directory of the docker-compose file) -- see
#       https://github.com/docker/compose/issues/6310#issuecomment-765807115


BACKUP_DIR=${BACKUP_DIR:=$(absdir "${BASH_SOURCE%/*}")};
MEDIA_DIR=${MEDIA_DIR:=$(absdir "${BACKUP_DIR}/../sati/media")};
COMPOSE_PROJ_DIR=${COMPOSE_PROJ_DIR:=$(absdir "${BACKUP_DIR}/../sati/")};
COMPOSE_FILE=$(readlink -f "${COMPOSE_FILE:="${COMPOSE_PROJ_DIR}/docker-compose.yml"}");
ENV_FILE=$(readlink -f "${ENV_FILE:="${COMPOSE_PROJ_DIR}/.env"}");

[ -d "${BACKUP_DIR}" ] || { echo "Backup dir ${BACKUP_DIR} does not exist!" >&2; exit 1; }
[ -d "${MEDIA_DIR}" ] || { echo "Media dir ${MEDIA_DIR} does not exist!" >&2; exit 1; }
[ -d "${COMPOSE_PROJ_DIR}" ] || { echo "docker-compose dir ${COMPOSE_PROJ_DIR} does not exist!" >&2; exit 1; }
[ -e "${COMPOSE_FILE}" ] || { echo "docker-compose file not found at ${COMPOSE_FILE}!" >&2; exit 1; }
[ -e "${ENV_FILE}" ] || { echo ".env file not found at ${ENV_FILE}!" >&2; exit 1; }

# dump data from the Users app
docker-compose \
  --env-file "${ENV_FILE}" \
  --project-directory "${COMPOSE_PROJ_DIR}" \
  --file "${COMPOSE_FILE}" \
  exec django python manage.py dumpdata users \
  | jq "[.[] | {model, pk, fields: .fields | del(.date_joined, .last_login, .require_password_change)}]" \
  > "${BACKUP_DIR}/users.json";

# dump data from the Items app
docker-compose \
  --env-file "${ENV_FILE}" \
  --project-directory "${COMPOSE_PROJ_DIR}" \
  --file "${COMPOSE_FILE}" \
  exec django python manage.py dumpdata --indent 2 items \
  > "${BACKUP_DIR}/items.json";

# sync Item assets
rsync -avPh --delete --delete-excluded --exclude .gitignore "${MEDIA_DIR}" "${BACKUP_DIR}";

# Commit and push changes
cd "${BACKUP_DIR}";
git commit -am "Update $(date +%F)";
git push origin;
