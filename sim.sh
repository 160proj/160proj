#!/bin/bash

if [ ! $# -eq 1 ]; then
    echo "Missing simulation file name"
    exit 1
fi

sudo docker run -v "$(pwd)":/app --rm -ti -w "/app" ucmercedandeslab/tinyos_debian bash -c "python $1"
