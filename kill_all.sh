#!/bin/bash
#
# Kills all worker processes, locally and remotely.
#

sudo pkill -f RPC_PARALLEL_WORKER
sudo pkill -f probnetkat
sudo pkill -f java  # PRISM

for I in {24..1}; do
  SSH="ssh -t "abilene@atlas-$I""
  $SSH "sudo pkill -f RPC_PARALLEL_WORKER"
  $SSH "sudo pkill -f probnetkat"
  $SSH "sudo pkill -f java"
done