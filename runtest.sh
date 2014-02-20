#!/bin/bash
export TOWBOAT_CONFIGPATH="$(dirname $0)/tests/"
./towboat.sh start $*
