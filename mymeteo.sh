#!/bin/bash

# flagi i parametry
CITY=""
VERBOSE=false
HELP=false


while [[ "$#" -gt 0 ]]; do
    case $1 in
        --city) CITY="$2"; shift ;;
        --verbose) VERBOSE=true ;;
        -h|--help) HELP=true ;;
        *) 
            # jesli argument nie zaczyna sie od "-" to traktuje go jako miasto
            if [[ "$1" != -* ]]; then
                CITY="$1"
            else
                echo "Nieznana opcja: $1"
                exit 1
            fi
            ;;
    esac
    shift
done

# help
if [ "$HELP" = true ]; then
    echo "Użycie: ./mymeteo.sh --city <miasto> [--verbose] lub ./mymeteo.sh <miasto>"
    echo "Autor: Aleksy Bukowski"
    exit 0
fi

# city
if [ -z "$CITY" ]; then
    echo "Proszę podać miasto za pomocą --city <miasto>."
    exit 1
fi


# zamiana znakow w miastach (bash nie radzi sobie ze spacjami i polskimi znakami w curl requestach)
handle_city_name() {
    local city=$(echo "$1" | awk '{print tolower($0)}')

    declare -A replacements=(
        ["ą"]="a"
        ["ć"]="c"
        ["ę"]="e"
        ["ł"]="l"
        ["ń"]="n"
        ["ó"]="o"
        ["ś"]="s"
        ["ź"]="z"
        ["ż"]="z"
        [" "]="%%20"
    )

    for key in "${!replacements[@]}"; do
        city="${city//${key}/${replacements[$key]}}"
    done
    
    echo "$city"
}



# koordynaty miasta
get_coordinates() {
    local city=$(handle_city_name "$1")
    local response=$(curl -s "https://nominatim.openstreetmap.org/search?q='$city'&format=json&countrycodes=pl&limit=1")
    if [ "$(echo "$response" | jq '. | length')" -gt 0 ]; then
        local lat=$(echo "$response" | jq -r '.[0].lat')
        local lon=$(echo "$response" | jq -r '.[0].lon')
        echo "$lat,$lon"
    else
        echo "Nie można pobrać współrzędnych dla miasta $city." >&2
        exit 1
    fi
}

# sciezki
CACHE_DIR="$HOME/.cache/mymeteo"
CACHE_FILE="$CACHE_DIR/city_coordinates.json"

# pobieranie stacji meteorologicznych
if [ ! -f "$CACHE_FILE" ]; then
    mkdir -p "$CACHE_DIR"
    echo "Pobieram dane meteorologiczne..."
    STATIONS=$(curl -s "https://danepubliczne.imgw.pl/api/data/synop")
    echo "{}" > "$CACHE_FILE"
    echo "$STATIONS" | jq -c '.[]' | while read -r station; do
        station_name=$(echo "$station" | jq -r '.stacja')
        coordinates=$(get_coordinates "$station_name" || echo "null")
        if [ "$coordinates" != "null" ]; then
            if [ "$VERBOSE" = true ]; then
                echo "Znaleziono koordynaty dla: $station_name"
            fi
            jq --arg name "$station_name" --arg coords "$coordinates" \
                '.[$name] = $coords' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
        fi
    done
else
    if [ "$VERBOSE" = true ]; then
        echo "Załadowano dane z pliku cache."
    fi
fi

# pobieranie koordow miasta wprowadzonego przez usera
if [ "$VERBOSE" = true ]; then
    echo "Pobieram koordynaty miasta uzytkownika..."
fi
USER_COORDS=$(get_coordinates "$CITY")
if [[ -z "$USER_COORDS" ]]; then
    exit 1
fi
USER_LAT=$(echo "$USER_COORDS" | cut -d',' -f1)
USER_LON=$(echo "$USER_COORDS" | cut -d',' -f2)

# szukanie najblizszej stacji
distance() {
  local lat1="$1" lon1="$2" lat2="$3" lon2="$4"
  echo "scale=2; sqrt((($lat2-$lat1)^2) + (($lon2-$lon1)^2))" | bc
}

NEAREST_STATION=""
MIN_DISTANCE=999999

# process substitution z jq w celu poprawnego przypisania wartosci do NEAREST_STATION (problem zakresu)
if [ "$VERBOSE" = true ]; then
    echo "Szukam najblizszej stacji..."
fi
while IFS= read -r station_name; do
    coords=$(jq -r --arg station "$station_name" '.[$station]' "$CACHE_FILE")
    lat=$(echo "$coords" | cut -d',' -f1)
    lon=$(echo "$coords" | cut -d',' -f2)
    distance=$(distance "$USER_LAT" "$USER_LON" "$lat" "$lon")
    
    if (( $(echo "$distance < $MIN_DISTANCE" | bc -l) )); then
        MIN_DISTANCE=$distance
        NEAREST_STATION=$station_name
    fi
done < <(jq -r 'keys[]' "$CACHE_FILE")

# pobranie danych dla najblizszej stacji
if [ -n "$NEAREST_STATION" ]; then
    WEATHER=$(curl -s "https://danepubliczne.imgw.pl/api/data/synop" | jq --arg station "$NEAREST_STATION" '.[] | select(.stacja == $station)')
    echo ""
    echo "Najbliższa stacja: $NEAREST_STATION"
    echo "Temperatura: $(echo "$WEATHER" | jq -r '.temperatura') °C"
    echo "Prędkość wiatru: $(echo "$WEATHER" | jq -r '.predkosc_wiatru') m/s"
    echo "Kierunek wiatru: $(echo "$WEATHER" | jq -r '.kierunek_wiatru') °"
    echo "Wilgotność względna: $(echo "$WEATHER" | jq -r '.wilgotnosc_wzgledna') %"
    echo "Suma opadów: $(echo "$WEATHER" | jq -r '.suma_opadu') mm"
    echo "Ciśnienie: $(echo "$WEATHER" | jq -r '.cisnienie') hPa"
else
    echo "Nie znaleziono najbliższej stacji."
fi
