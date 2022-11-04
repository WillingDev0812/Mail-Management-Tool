#!/usr/bin/env bash

set -euo pipefail

### CONFIG

DEV_NAME="${DEV_NAME:-mailu-dev}"
DEV_DB="${DEV_DB:-}"
DEV_PROFILER="${DEV_PROFILER:-false}"
DEV_LISTEN="${DEV_LISTEN:-127.0.0.1:8080}"
[[ "${DEV_LISTEN}" == *:* ]] || DEV_LISTEN="127.0.0.1:${DEV_LISTEN}"
DEV_ADMIN="${DEV_ADMIN:-admin@example.com}"
DEV_PASSWORD="${DEV_PASSWORD:-admin}"

### MAIN

[[ -n "${DEV_DB}" ]] && {
    [[ -f "${DEV_DB}" ]] || {
        echo "Sorry, can't find DEV_DB: '${DEV_DB}'"
        exit 1
    }
    DEV_DB="$(realpath "${DEV_DB}")"
}

docker="$(command -v podman || command -v docker || echo false)"
[[ "${docker}" == "false" ]] && {
    echo "Sorry, you'll need podman or docker to run this."
    exit 1
}

tmp="$(mktemp -d)"
[[ -n "${tmp}" && -d "${tmp}" ]] || {
    echo "Sorry, can't create temporary folder."
    exit 1
}
trap "rm -rf '${tmp}'" INT TERM EXIT

admin="$(realpath "$(pwd)/${0%/*}")"
base="${admin}/../base"
assets="${admin}/assets"

cd "${tmp}"

# base
cp "${base}"/requirements-* .
cp -r "${base}"/libs .
sed -E '/^#/d;s:^FROM system$:FROM system AS base:' "${base}/Dockerfile" >Dockerfile

# assets
cp -r "${assets}/content" .
sed -E '/^#/d;s:^(FROM [^ ]+$):\1 AS assets:' "${assets}/Dockerfile" >>Dockerfile

cat >>Dockerfile <<EOF
RUN set -euxo pipefail \
  ; rm -f /work/static/*.gz
EOF

# admin
sed -E '/^#/d;/^(COPY|EXPOSE|HEALTHCHECK|VOLUME|CMD) /d; s:^(.* )[^ ]*pybabel[^\\]*(.*):\1true \2:' "${admin}/Dockerfile" >>Dockerfile

# development
cat >>Dockerfile <<EOF
COPY --from=assets /work/static/ ./static/

RUN set -euxo pipefail \
  ; mkdir /data \
  ; ln -s /app/audit.py / \
  ; ln -s /app/start.py /

ENV \
    FLASK_ENV="development" \
    MEMORY_SESSIONS="true" \
    RATELIMIT_STORAGE_URL="memory://" \
    SESSION_COOKIE_SECURE="false" \
    \
    DEBUG="true" \
    DEBUG_PROFILER="${DEV_PROFILER}" \
    DEBUG_ASSETS="/app/static" \
    DEBUG_TB_ENABLED="true" \
    \
    IMAP_ADDRESS="127.0.0.1" \
    POP3_ADDRESS="127.0.0.1" \
    AUTHSMTP_ADDRESS="127.0.0.1" \
    SMTP_ADDRESS="127.0.0.1" \
    REDIS_ADDRESS="127.0.0.1" \
    WEBMAIL_ADDRESS="127.0.0.1"

CMD ["/bin/bash", "-c", "flask db upgrade &>/dev/null && flask mailu admin '${DEV_ADMIN/@*}' '${DEV_ADMIN#*@}' '${DEV_PASSWORD}' --mode ifmissing >/dev/null && flask run --host=0.0.0.0 --port=8080"]
EOF

# build
chmod -R u+rwX,go+rX .
cat Dockerfile
"${docker}" build --tag "${DEV_NAME}:latest" .

# gather volumes to map into container
volumes=()

if [[ -n "${DEV_DB}" ]]; then
    volumes+=( --volume "${DEV_DB}:/data/main.db" )
else
    mkdir -p "data"
    volumes=( --volume "${tmp}/data/:/data/" )
fi

for vol in audit.py start.py mailu/ migrations/; do
    volumes+=( --volume "${admin}/${vol}:/app/${vol}" )
done

for file in "${assets}/content/assets"/*; do
    [[ "${file}" == */vendor.js ]] && continue
    volumes+=( --volume "${file}:/app/static/${file/*\//}" )
done

# show configuration
cat <<EOF

=============================================================================
DEV_NAME="${DEV_NAME}"
DEV_DB="${DEV_DB}"
DEV_PROFILER="${DEV_PROFILER}"
DEV_LISTEN="${DEV_LISTEN}"
DEV_ADMIN="${DEV_ADMIN}"
DEV_PASSWORD="${DEV_PASSWORD}"
=============================================================================

=============================================================================
The Mailu UI can be found here: http://${DEV_LISTEN}/sso/login
EOF
[[ -z "${DEV_DB}" ]] && echo "You can log in with user ${DEV_ADMIN} and password ${DEV_PASSWORD}"
cat <<EOF
=============================================================================

Starting mailu dev environment...
EOF

# run
"${docker}" run --rm -it --name "${DEV_NAME}" --publish "${DEV_LISTEN}:8080" "${volumes[@]}" "${DEV_NAME}"

