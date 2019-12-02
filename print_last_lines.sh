#!/bin/bash

csv_name="$1"
shift
for dir in "$@"
do
    tail --lines=1 "$dir/$csv_name.csv"
done