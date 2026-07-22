#!/bin/bash
data=$(curl -fsS --max-time 5 "https://wttr.in/Rivas+Vaciamadrid?format=j1" 2>/dev/null) || {
    printf '{"text":"","class":"unavailable"}\n'; exit 0
}

weather_code=$(echo "$data" | jq -r '.current_condition[0].weatherCode // empty')
temp=$(echo "$data" | jq -r '.current_condition[0].temp_C // empty')
sunrise=$(echo "$data" | jq -r '.weather[0].astronomy[0].sunrise // empty')
sunset=$(echo "$data" | jq -r '.weather[0].astronomy[0].sunset // empty')

[ -z "$weather_code" ] && [ -z "$temp" ] && {
    printf '{"text":"","class":"unavailable"}\n'; exit 0
}

now=$(date +%s)
sunrise_ts=$(date -d "today $sunrise" +%s 2>/dev/null || echo 0)
sunset_ts=$(date -d "today $sunset" +%s 2>/dev/null || echo 0)

if (( sunrise_ts > 0 && sunset_ts > 0 && (now < sunrise_ts || now >= sunset_ts) )); then
    night=true
else
    night=false
fi

SUN=""      # nf-weather-day-sunny
MOON=""     # nf-weather-night-clear
PCDAY=""    # nf-weather-day-cloudy
PCNIGHT=""  # nf-weather-night-alt-partly-cloudy
CLOUD=""    # nf-weather-cloudy
FOG=""      # nf-weather-day-fog
RAINDAY=""  # nf-weather-day-rain
RAINNIGHT="" # nf-weather-night-alt-rain
SLEET=""    # nf-weather-sleet
THUNDER=""  # nf-weather-thunderstorm
HEAVYRAIN="" # nf-weather-day-rain-mix
SNOW=""     # nf-weather-day-snow
SNOWNIGHT="" # nf-weather-night-snow

case $weather_code in
    113) $night && icon="$MOON" || icon="$SUN" ;;
    116) $night && icon="$PCNIGHT" || icon="$PCDAY" ;;
    119|122) icon="$CLOUD" ;;
    143|248|260) icon="$FOG" ;;
    176|263|266|293|296|353) $night && icon="$RAINNIGHT" || icon="$RAINDAY" ;;
    179|227|230|323|326|368) $night && icon="$SNOWNIGHT" || icon="$SNOW" ;;
    182|185|281|284|311|314|317|320|350|362|365|374|377) icon="$SLEET" ;;
    200|386|389|392|395) icon="$THUNDER" ;;
    299|302|305|308|356|359) icon="$HEAVYRAIN" ;;
    329|332|335|338|371) icon="$SNOW" ;;
    *) icon="$CLOUD" ;;
esac

icon_e=$(printf '%s' "$icon" | sed 's/["\\]/\\&/g')
desc=$(echo "$data" | jq -r '.current_condition[0].weatherDesc[0].value // empty')
humidity=$(echo "$data" | jq -r '.current_condition[0].humidity // empty')
printf '{"text":"%s %s°","tooltip":"%s · %s°C · Humedad %s%%","class":"ok"}\n' "$icon_e" "$temp" "$desc" "$temp" "$humidity"
