FROM postgis/postgis

# Install osm2pgsql
RUN apt-get update \
    && apt-get install -y osm2pgsql \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app/

# Copy the Nepal PBF file into the container
COPY nepal-latest.osm.pbf /app/

# Start PostgreSQL server and run osm2pgsql to import the data into the PostGIS database

CMD osm2pgsql -c -d gis --create --slim /app/nepal-latest.osm.pbf
# CMD service postgresql start && /usr/bin/osm2pgsql -c -d gis --create --slim /app/nepal-latest.osm.pbf


# FROM debian:bookworm-slim

# ENV DEBIAN_FRONTEND=noninteractive
# RUN apt-get update 
# RUN apt-get install -y \
#     osm2pgsql \
#     postgresql-client-15 \
#     osmctools

# # clean up
# RUN apt-get clean \
#     && rm -rf /var/lib/apt/lists/*

# ADD ./osm-importer.sh /usr/local/bin/osm-importer.sh
# ADD ./custom.style /user/local/bin/custom.style
# WORKDIR /osm