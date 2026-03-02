#!/bin/bash
set -e

chown -R 99:100 /data
exec gosu minecraft "$@"
