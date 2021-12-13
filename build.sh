#!/bin/sh
set -e

mix deps.get
mix compile --warnings-as-errors
mix dialyzer --no-compile
mix format --check-formatted

