#!/bin/bash

sudo docker run -v "$(pwd)":/app --rm -ti -w "/app" ucmercedandeslab/tinyos_debian
