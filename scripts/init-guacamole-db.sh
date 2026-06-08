#!/usr/bin/env sh
set -eu

GUAC_VERSION="${GUAC_VERSION:-latest}"

mkdir -p initdb postgres backups drive

if [ -s initdb/initdb.sql ]; then
  echo "initdb/initdb.sql already exists; skip generating it."
  exit 0
fi

docker run --rm "guacamole/guacamole:${GUAC_VERSION}" \
  /opt/guacamole/bin/initdb.sh --postgresql > initdb/initdb.sql

echo "Generated initdb/initdb.sql for Guacamole ${GUAC_VERSION}."
