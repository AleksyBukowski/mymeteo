# sprawdzanie wprowadzonych flag: help, verbose i city
param (
    [string]$city,
    [switch]$verbose,
    [Alias('h')] [switch]$help
)

# help
if ($help) {
    Write-Host "Użycie: ./mymeteo <miasto> lub ./mymeteo --city <miasto>" -ForegroundColor Magenta
    Write-Host "Autor: Aleksy Bukowski" -ForegroundColor DarkMagenta
    return
}

# verbose
if ($verbose) {
    Write-Host "TRYB VERBOSE" -ForegroundColor Red
}

# city
if (-not $city) {
    Write-Host "Prosze podać miasto." -ForegroundColor Yellow
    return
}


# funkcja pobierania wspolrzednych miasta
function Get-Coordinates {
    param($city)
    
    $response = Invoke-RestMethod -Uri "https://nominatim.openstreetmap.org/search?q=$city&format=json&countrycodes=pl&limit=1" -Method Get

    if ($response) {
        if ($verbose) {
            Write-Host "Znaleziono koordynaty miasta $city" -ForegroundColor Green
        }
        return [PSCustomObject]@{
            latitude = [double]$response[0].lat
            longitude = [double]$response[0].lon
        }
    } else {
        throw "Nie mozna pobrac wspolrzednych dla miasta $city."
    }
}


# sciezka
$cacheDirectory = "$env:HOMEPATH\.cache\mymeteo"
$cacheFilePath = "$cacheDirectory\city_coordinates.json"


# obsluga pliku z danymi
$IMGWresponse = Invoke-RestMethod -Uri https://danepubliczne.imgw.pl/api/data/synop -Method Get
if (Test-Path $cacheFilePath) {
    $cityCoordinatesData = Get-Content -Path $cacheFilePath | ConvertFrom-Json
} 
else {
    if (-not (Test-Path $cacheDirectory)) {
        if ($verbose) {
            Write-Host "Tworzenie katalogu: $cacheDirectory" -ForegroundColor Yellow
        }
        New-Item -Path $cacheDirectory -ItemType Directory -Force > $null 2>&1
    }
    Write-Host "Pobieram dane meteorologiczne..." -ForegroundColor Yellow
    $cityCoordinatesData = @{}

    # pobranie koordynatow dla kazdej stacji
    foreach ($station in $IMGWresponse) {
        $cityName = $station.stacja
        try {
            $coordinates = Get-Coordinates -city $cityName
            $cityCoordinatesData[$cityName] = $coordinates
        } 
        catch {
            Write-Host "Błąd podczas pobierania współrzędnych dla miasta $cityName." -ForegroundColor Red
        }
    }

    # zapis do pliku
    $cityCoordinatesData | ConvertTo-Json -Depth 10 | Set-Content -Path $cacheFilePath

    # pobranie
    $cityCoordinatesData = Get-Content -Path $cacheFilePath | ConvertFrom-Json
}

# dane stacji: nazwa i koordynaty
if ($cityCoordinatesData) {
    if ($verbose) {
        Write-Host "Dane o miastach i współrzędnych zostały załadowane pomyślnie." -ForegroundColor Green
    }
} 
else {
    Write-Host "Błąd podczas ładowania danych o miastach." -ForegroundColor Red
}


$usersCityCoordinates = Get-Coordinates -city $city
# odleglosc euklidesowa
$nearestStationObject = $cityCoordinatesData.PSObject.Properties | Sort-Object {
    [math]::Sqrt([math]::Pow($_.Value.latitude - $usersCityCoordinates.latitude, 2) + [math]::Pow($_.Value.longitude - $usersCityCoordinates.longitude, 2))
} | Select-Object -First 1


$nearestStation = $IMGWresponse | Where-Object { $_.stacja -eq $nearestStationObject.Name }

if ($nearestStation -and $verbose) {
    Write-Host "Znaleziono najbliższę stację do podanej oraz jej informacje meteorologiczne: $($NearestStationObject.Name)" -ForegroundColor Green
}


if ($nearestStation) {
    if ($verbose) {
        Write-Host "Ładuję informacje..." -ForegroundColor Yellow
        Write-Host "-------------------------------------------"
    }
    Write-Host ""
    Write-Host "$($nearestStation.stacja) [$($nearestStation.id_stacji)] / $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Temperatura:        $($nearestStation.temperatura) °C" -ForegroundColor Yellow
    Write-Host "Prędkość wiatru:      $($nearestStation.predkosc_wiatru) m/s" -ForegroundColor Green
    Write-Host "Kierunek wiatru:    $($nearestStation.kierunek_wiatru) °" -ForegroundColor Green
    Write-Host "Wilgotność wzgl.:  $($nearestStation.wilgotnosc_wzgledna) %" -ForegroundColor Cyan
    Write-Host "Suma opadu:           $($nearestStation.suma_opadu) mm" -ForegroundColor Blue
    Write-Host "Ciśnienie:       $($nearestStation.cisnienie) hPa" -ForegroundColor Red
    if ($verbose) {
        Write-Host "-------------------------------------------"
        Write-Host ""
        Write-Host "Wszystkie dane zostały załadowane - kończę działanie skryptu." -ForegroundColor Green
    }
} 
else {
    Write-Host "Nie znaleziono danych pogodowych dla miasta $City." -ForegroundColor Red
}
