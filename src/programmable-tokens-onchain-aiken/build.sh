#!/usr/local/bin/bash

set -x

aiken build && cp plutus.json ../programmable-tokens-offchain-java/src/main/resources
