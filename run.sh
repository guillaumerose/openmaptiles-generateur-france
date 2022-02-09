#!/bin/bash

set -exuo pipefail

if [ ! -d openmaptiles ]
then
    git clone https://github.com/openmaptiles/openmaptiles
fi

mkdir -p out/

function generate_background() {
    local zoom=$1

    if [ -f ./out/planet.mbtiles ]
    then
        return
    fi

    cd openmaptiles
    sed -i "s/MAX_ZOOM=.*/MAX_ZOOM=$zoom/" .env
    # Add an extra 0 at the end of the default bbox to avoid the computation of the area bbox and create the whole planet.
    sed -i "s/BBOX=.*/BBOX=-180.0,-85.0511,180.0,85.05110/" .env

    rm -f data/*.osm.pbf data/*.bbox
    make destroy-db
    make clean

    # A small area is needed to bootstrap the db
    make download area=guadeloupe
    rm data/guadeloupe.bbox
    ./quickstart.sh guadeloupe

    mv data/tiles.mbtiles ../out/planet.mbtiles
    cd -
}

function generate() {
    local area=$1
    local zoom=$2

    if [ -f "./out/$area-$zoom.mbtiles" ]
    then
        return
    fi

    cd openmaptiles
    sed -i "s/MAX_ZOOM=.*/MAX_ZOOM=$zoom/" .env
    sed -i "s/BBOX=.*/BBOX=-180.0,-85.0511,180.0,85.0511/" .env

    rm -f data/*.osm.pbf data/*.bbox
    make destroy-db
    make clean

    NO_REFRESH=1 ./quickstart.sh "$area"

    mv data/tiles.mbtiles "../out/$area-$zoom.mbtiles"
    cd -
}

# generate the full planet
generate_background 8

# generate France using geofabrik
zoom=14
areas="guadeloupe martinique guyane reunion mayotte wallis-et-futuna polynesie-francaise new-caledonia ile-de-clipperton france"
for area in $areas; do
    generate "$area" "$zoom"
done

# generate parts of France that are not directly in geofabrik

mkdir -p osmium/
docker build -t osmium:latest .
cd osmium

function extract() {
    local area=$1
    local link=$2
    local bbox=$3
    local target=$4


    if [ ! -f "$target.osm.pbf" ]
    then
        if [ ! -f "$area-latest.osm.pbf" ]
        then
            wget -O "$area-latest.osm.pbf" "$link"
        fi
        docker run -v "$(pwd):/data" --rm -u "$(id -u "${USER}"):$(id -g "${USER}")" osmium extract --overwrite --bbox "$bbox" -o "$target.osm.pbf" "$area-latest.osm.pbf"
    fi
}

extract "central-america" "https://download.geofabrik.de/central-america-latest.osm.pbf" "-63.165204,17.84369,-62.732617,18.144098" "st-martin"
extract "canada" "https://download.geofabrik.de/north-america/canada-latest.osm.pbf" "-56.566541,46.715062,-56.063916,47.165121" "st-pierre"

extract "africa" "https://download.geofabrik.de/africa-latest.osm.pbf" "39.3807,-22.666,40.6441,-21.2087" "taaf1"
extract "africa" "https://download.geofabrik.de/africa-latest.osm.pbf" "42.65289,-17.095511,42.778546,-17.006232" "taaf2"
extract "africa" "https://download.geofabrik.de/africa-latest.osm.pbf" "47.261827,-11.610539,47.413404,-11.493147" "taaf3"
extract "africa" "https://download.geofabrik.de/africa-latest.osm.pbf" "54.503534,-15.909334,54.543016,-15.871691" "taaf4"

extract "oceania" "https://download.geofabrik.de/australia-oceania-latest.osm.pbf" "67.6849,-50.2001,71.0138,-48.2671" "taaf5"
extract "oceania" "https://download.geofabrik.de/australia-oceania-latest.osm.pbf" "50.0738,-46.6121,52.4606,-45.9076" "taaf6"
extract "oceania" "https://download.geofabrik.de/australia-oceania-latest.osm.pbf" "77.3227,-38.8412,77.8006,-37.6918" "taaf7"

cd -

function generate_custom() {
    local area=$1
    local zoom=$2

    if [ -f "./out/$area-$zoom.mbtiles" ]
    then
        return
    fi

    cd openmaptiles
    sed -i "s/MAX_ZOOM=.*/MAX_ZOOM=$zoom/" .env
    sed -i "s/BBOX=.*/BBOX=-180.0,-85.0511,180.0,85.0511/" .env

    rm -f data/*.osm.pbf data/*.bbox
    make destroy-db
    make clean

    cp "../osmium/$area.osm.pbf" data/
    NO_REFRESH=1 ./quickstart.sh "$area"

    mv data/tiles.mbtiles "../out/$area-$zoom.mbtiles"
    cd -
}

generate_custom st-pierre "$zoom"
generate_custom st-martin "$zoom"
for i in {1..7}; do
    generate_custom "taaf$i" "$zoom"
done

# merge all parts

if [ ! -d tippecanoe ]
then
    git clone https://github.com/mapbox/tippecanoe.git
fi

(cd tippecanoe && docker build -t tippecanoe:latest .)

mbtiles="/data/st-pierre-$zoom.mbtiles /data/st-martin-$zoom.mbtiles "
for i in {1..7}; do
    mbtiles+="/data/taaf$i-$zoom.mbtiles "
done
for area in $areas; do
    mbtiles+="/data/$area-$zoom.mbtiles "
done

rm -f out/france-vector.mbtiles
docker run -t --rm -u "$(id -u "${USER}"):$(id -g "${USER}")" \
  -v "$(pwd)/out:/data" \
  tippecanoe:latest \
  /bin/sh -c "tile-join --no-tile-size-limit -o /data/france-vector.mbtiles /data/planet.mbtiles $mbtiles"

# add the correct metadata

function meta-set() {
    docker run -t --rm -u "$(id -u "${USER}"):$(id -g "${USER}")" \
        -v "${PWD}/out:/tileset" \
        openmaptiles/openmaptiles-tools mbtiles-tools meta-set france-vector.mbtiles "$1" "$2"
}

function meta-erase() {
    docker run -t --rm -u "$(id -u "${USER}"):$(id -g "${USER}")" \
        -v "${PWD}/out:/tileset" \
        openmaptiles/openmaptiles-tools mbtiles-tools meta-set france-vector.mbtiles "$1"
}

meta-set name "Tuiles vectorielles France par Etalab"
meta-set description "Tuiles vectorielles d’usage général pour la France et ses territoires d’outremer"
meta-set attribution "<a href=\"https://www.etalab.gouv.fr/\" target=\"_blank\">&copy; Etalab</a> <a href=\"https://www.openmaptiles.org/\" target=\"_blank\">&copy; OpenMapTiles</a> <a href=\"https://www.openstreetmap.org/copyright\" target=\"_blank\">&copy; Contributeurs OpenStreetMap</a>"
meta-set center 2.308097,48.850132,14
meta-set created "$(date --iso-8601=seconds)"
meta-erase generator_options
meta-erase generator

# docker run --rm --user=1000:1000 -it --name tileserver-gl -v $(pwd)/out:/data  -p 8085:8085 maptiler/tileserver-gl --port 8085 --mbtiles france-vector.mbtiles
