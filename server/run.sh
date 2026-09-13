#!/bin/zsh
# Runs the site and the API together, so one process serves everything locally.
cd "${0:A:h}"
[[ -f .env ]] && set -a && source .env && set +a
[[ -z "$LICENCE_PRIVATE_KEY" && -f ../jendela-licence-private.key ]] && \
  export LICENCE_PRIVATE_KEY="$(cat ../jendela-licence-private.key)"
exec node src/server.mjs
