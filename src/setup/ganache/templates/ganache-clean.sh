#!/usr/bin/env sh

set -x #echo on

ROOT_DIR=$PWD
DATA_DIR=${DATA_DIR:-$ROOT_DIR/ganache-db}

rm -rf $DATA_DIR