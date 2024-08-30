# Use the official OSRM image as the base
FROM ghcr.io/project-osrm/osrm-backend

# Set the working directory
WORKDIR /app

# Copy the OSM PBF file to the working directory
COPY nepal-latest.osm.pbf /app/

# Run the OSRM build steps
RUN osrm-extract -p /opt/car.lua nepal-latest.osm.pbf || echo "osrm-extract failed" && \
    osrm-partition nepal-latest.osrm || echo "osrm-partition failed" && \
    osrm-customize nepal-latest.osrm || echo "osrm-customize failed"

# Expose the routing service port
EXPOSE 5000

# Command to start the OSRM service
CMD ["osrm-routed", "--algorithm", "mld", "nepal-latest.osrm"]
