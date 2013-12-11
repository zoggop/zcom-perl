#!/bin/bash
NOW=$(date +"%Y %B %d %r")
cd ./build
git add .
git commit -m "automatic update at $NOW"
git push
cd ../