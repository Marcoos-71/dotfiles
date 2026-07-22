#!/bin/bash
DAYS=("" "Lunes" "Martes" "Miércoles" "Jueves" "Viernes" "Sábado" "Domingo")
MONTHS=("" "enero" "febrero" "marzo" "abril" "mayo" "junio" "julio" "agosto" "septiembre" "octubre" "noviembre" "diciembre")

DOW=$(date +%u)
DOM=$(date +"%-d")
MON=$((10#$(date +%m)))
YEAR=$(date +%Y)
WEEK=$(date +%V)
TIME=$(date +%H:%M)

echo "{\"text\": \"${DAYS[$DOW]} ${TIME}\", \"tooltip\": \"${DOM} de ${MONTHS[$MON]} · Semana ${WEEK} · ${YEAR}\"}"
