#!/bin/bash

set -exuo pipefail

if [ ! -d openmaptiles ]
then
    git clone https://github.com/openmaptiles/openmaptiles
fi

mkdir -p out/

function generate_background() {
    local zoom=$1

    cd openmaptiles
    sed -i "s/MAX_ZOOM=.*/MAX_ZOOM=$zoom/" .env

    make refresh-docker-images
    make destroy-db
    make clean
    make all
    make start-db-preloaded
    make download area=guadeloupe
    rm data/guadeloupe.bbox
    make import-osm area=guadeloupe
    make import-wikidata
    make import-sql
    make analyze-db
    make test-perf-null
    make generate-tiles-pg
    make stop-db

    mv data/tiles.mbtiles ../out/planet.mbtiles
    cd -
}

function generate() {
    local area=$1
    local zoom=$2

    cd openmaptiles
    sed -i "s/MAX_ZOOM=.*/MAX_ZOOM=$zoom/" .env

    make destroy-db
    make clean
    NO_REFRESH=1 ./quickstart.sh $area

    mv data/tiles.mbtiles ../out/$area-$zoom.mbtiles
    cd -
}

generate_background 8

zoom=14
generate guadeloupe $zoom
generate martinique $zoom
generate guyane $zoom
generate reunion $zoom
# Saint-Pierre-et-Miquelon
generate mayotte $zoom
# Saint-Barthélemy
# Saint-Martin
generate wallis-et-futuna $zoom
generate polynesie-francaise $zoom
generate new-caledonia $zoom
# Terres australes et antarctiques françaises
generate ile-de-clipperton $zoom

generate france $zoom

if [ ! -d tippecanoe ]
then
    git clone https://github.com/mapbox/tippecanoe.git
fi

(cd tippecanoe && docker build -t tippecanoe:latest .)

docker run -it --rm -u $(id -u ${USER}):$(id -g ${USER}) \
  -v $(pwd)/out:/data \
  tippecanoe:latest \
  tile-join --no-tile-size-limit -o /data/france-vector.mbtiles /data/planet.mbtiles /data/guadeloupe-14.mbtiles /data/guyane-14.mbtiles /data/martinique-14.mbtiles /data/mayotte-14.mbtiles /data/reunion-14.mbtiles /data/france-14.mbtiles

function meta-set() {
    docker run -it --rm -u $(id -u ${USER}):$(id -g ${USER}) \
        -v "${PWD}/out:/tileset" \
        openmaptiles/openmaptiles-tools mbtiles-tools meta-set france-vector.mbtiles "$1" "$2"
}

function meta-erase() {
    docker run -it --rm -u $(id -u ${USER}):$(id -g ${USER}) \
        -v "${PWD}/out:/tileset" \
        openmaptiles/openmaptiles-tools mbtiles-tools meta-set france-vector.mbtiles "$1"
}

meta-set name "Tuiles vectorielles France par Etalab"
meta-set description "Tuiles vectorielles d’usage général pour la France et ses territoires d’outremer"
meta-set attribution "<a href=\"https://www.etalab.gouv.fr/\" target=\"_blank\">&copy; Etalab</a> <a href=\"https://www.openmaptiles.org/\" target=\"_blank\">&copy; OpenMapTiles</a> <a href=\"https://www.openstreetmap.org/copyright\" target=\"_blank\">&copy; Contributeurs OpenStreetMap</a>"
meta-set center 2.308097,48.850132,14
meta-erase generator_options
meta-erase generator

# docker run --rm --user=1000:1000 -it --name tileserver-gl -v $(pwd)/out:/data  -p 8085:8085 maptiler/tileserver-gl --port 8085 --mbtiles france-vector.mbtiles
