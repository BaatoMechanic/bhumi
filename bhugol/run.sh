#!/bin/bash

set -euo pipefail

function createPostgresConfig() {
  cp /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  cat /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
}

function setPostgresPassword() {
    sudo -u postgres psql -c "ALTER USER renderer PASSWORD '${PGPASSWORD:-renderer}'"
}

if [ "$#" -ne 1 ]; then
    echo "usage: <import|run>"
    exit 1
fi

# Use default style if none provided
if [ ! "$(ls -A /data/style/)" ]; then
    mv /home/renderer/src/openstreetmap-carto-backup/* /data/style/
fi

# Generate mapnik.xml if not exists
if [ ! -f /data/style/mapnik.xml ]; then
    cd /data/style/
    carto ${NAME_MML:-project.mml} > mapnik.xml
fi

if [ "$1" == "import" ]; then
    mkdir -p /data/database/postgres/
    chown renderer: /data/database/
    chown -R postgres: /var/lib/postgresql /data/database/postgres/
    if [ ! -f /data/database/postgres/PG_VERSION ]; then
        sudo -u postgres /usr/lib/postgresql/$PG_VERSION/bin/pg_ctl -D /data/database/postgres/ initdb -o "--locale C.UTF-8"
    fi

    createPostgresConfig
    service postgresql start

    # Check if the renderer role exists, create it if not
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='renderer'" | grep -q 1; then
        sudo -u postgres createuser renderer
    fi

    # Check if the database "gis" exists, create it if not
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='gis'" | grep -q 1; then
        sudo -u postgres createdb -E UTF8 -O renderer gis
        sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
        sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
        sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
        sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"
    fi

    setPostgresPassword

    if [ ! -f /data/region.osm.pbf ] && [ -z "${DOWNLOAD_PBF:-}" ]; then
        echo "WARNING: No import file at /data/region.osm.pbf, importing Luxembourg as example..."
        DOWNLOAD_PBF="https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
        DOWNLOAD_POLY="https://download.geofabrik.de/europe/luxembourg.poly"
    fi

    if [ -n "${DOWNLOAD_PBF:-}" ]; then
        wget ${WGET_ARGS:-} "$DOWNLOAD_PBF" -O /data/region.osm.pbf
        if [ -n "${DOWNLOAD_POLY:-}" ]; then
            wget ${WGET_ARGS:-} "$DOWNLOAD_POLY" -O /data/region.poly
        fi
    fi

    if [ "${UPDATES:-}" == "enabled" ]; then
        REPLICATION_TIMESTAMP=$(osmium fileinfo -g header.option.osmosis_replication_timestamp /data/region.osm.pbf)
        sudo -E -u renderer openstreetmap-tiles-update-expire.sh $REPLICATION_TIMESTAMP
    fi

    if [ -f /data/region.poly ]; then
        cp /data/region.poly /data/database/region.poly
        chown renderer: /data/database/region.poly
    fi

    if [ "${FLAT_NODES:-}" == "enabled" ]; then
        OSM2PGSQL_EXTRA_ARGS="--flat-nodes /data/database/flat_nodes.bin"
    fi

    sudo -u renderer osm2pgsql -d gis --create --slim -G --hstore \
      --tag-transform-script /data/style/${NAME_LUA:-openstreetmap-carto.lua} \
      --number-processes ${THREADS:-4} \
      -S /data/style/${NAME_STYLE:-openstreetmap-carto.style} \
      /data/region.osm.pbf \
      ${OSM2PGSQL_EXTRA_ARGS:-}

    if [ -f /data/style/${NAME_SQL:-indexes.sql} ]; then
        sudo -u postgres psql -d gis -f /data/style/${NAME_SQL:-indexes.sql}
    fi

    if [ -f /data/style/scripts/get-external-data.py ] && [ -f /data/style/external-data.yml ]; then
        sudo -E -u renderer python3 /data/style/scripts/get-external-data.py -c /data/style/external-data.yml -D /data/style/data
    fi

    sudo -u renderer touch /data/database/planet-import-complete
    service postgresql stop

    exit 0
fi

if [ "$1" == "run" ]; then
    rm -rf /tmp/*

    # Migrate old files if necessary
    [ -f /data/database/PG_VERSION ] && ! [ -d /data/database/postgres/ ] && mkdir /data/database/postgres/ && mv /data/database/* /data/database/postgres/
    [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/database/flat_nodes.bin ] && mv /nodes/flat_nodes.bin /data/database/flat_nodes.bin
    [ -f /data/tiles/data.poly ] && ! [ -f /data/database/region.poly ] && mv /data/tiles/data.poly /data/database/region.poly

    [ -f /data/tiles/planet-import-complete ] && ! [ -f /data/database/planet-import-complete ] && cp /data/tiles/planet-import-complete /data/database/planet-import-complete
    ! [ -f /data/tiles/planet-import-complete ] && [ -f /data/database/planet-import-complete ] && cp /data/database/planet-import-complete /data/tiles/planet-import-complete

    chown -R postgres: /var/lib/postgresql/ /data/database/postgres/

    [ "${ALLOW_CORS:-}" == "enabled" ] && echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars

    createPostgresConfig
    service postgresql start
    service apache2 restart
    setPostgresPassword

    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /etc/renderd.conf

    if [ "${UPDATES:-}" == "enabled" ]; then
        /etc/init.d/cron start
        for log in run osmosis expiry osm2pgsql; do
            sudo -u renderer touch /var/log/tiles/${log}.log
            tail -f /var/log/tiles/${log}.log >> /proc/1/fd/1 &
        done
    fi

    stop_handler() {
        kill -TERM "$child"
    }
    trap stop_handler SIGTERM

    sudo -u renderer renderd -f -c /etc/renderd.conf &
    child=$!
    wait "$child"

    service postgresql stop
    exit 0
fi

echo "invalid command"
exit 1

