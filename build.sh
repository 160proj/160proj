#!/bin/bash

sudo docker run -v "$(pwd)":/app --rm -w "/app" ucmercedandeslab/tinyos_debian bash -c "make micaz sim"
