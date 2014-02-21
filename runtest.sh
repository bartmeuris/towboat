#!/bin/bash
export TOWBOAT_CONFIGPATH="$(dirname $0)/tests/"
$(dirname $0)/towboat start $*
