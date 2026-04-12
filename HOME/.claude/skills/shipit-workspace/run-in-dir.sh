#!/bin/bash
# Helper to run commands in a specified directory
DIR="$1"
shift
cd "$DIR" && "$@"
