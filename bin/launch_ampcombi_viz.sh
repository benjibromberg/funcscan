#!/usr/bin/env bash
# AMPcombi Visualization Launcher
# This script downloads and launches the interactive AMPcombi Shiny Dashboard using Singularity.
# You can use this dashboard to visualize the Ampcombi_summary_cluster.tsv output.

set -e

# Define container location and URL
SIF_URL="https://github.com/Darcy220606/AMPcombi-interface/releases/download/v2.0.0/ampcombi_interface.sif"
SIF_FILE="ampcombi_interface.sif"

echo "========================================="
echo "   AMPcombi Dashboard Launcher           "
echo "========================================="

# 1. Determine which container engine to use
if command -v singularity &> /dev/null; then
    echo "Using Singularity..."
    if [ ! -f "$SIF_FILE" ]; then
        echo "Downloading AMPcombi visualizations Singularity image..."
        wget -q --show-progress "$SIF_URL" -O "$SIF_FILE"
        echo "Download complete."
    else
        echo "AMPcombi image ($SIF_FILE) already exists."
    fi

    echo ""
    echo "Launching the interactive AMPcombi dashboard..."
    echo "Once the server starts, navigate to the localhost URL shown below in your web browser."
    echo "You can upload your test run's 'Ampcombi_summary_cluster.tsv' directly into the interface."
    echo "(Press Ctrl+C to stop the server when you're finished)"
    echo "-----------------------------------------"

    singularity run "$SIF_FILE"

elif command -v docker &> /dev/null; then
    echo "Using Docker..."
    echo ""
    echo "Launching the interactive AMPcombi dashboard via Python 3.13 container..."
    echo "Once the server starts, navigate to the localhost URL shown below in your web browser."
    echo "You can upload your test run's 'Ampcombi_summary_cluster.tsv' directly into the interface."
    echo "(Press Ctrl+C to stop the server when you're finished)"
    echo "-----------------------------------------"
    
    # Run the Shiny app interactively via a lightweight Python docker container, exposing port 37231
    docker run --rm -it -p 37231:37231 python:3.13-slim bash -c "
        echo 'Preparing environment...' &&
        apt-get update -qq && apt-get install -y git -qq &&
        git clone https://github.com/Darcy220606/AMPcombi.git &&
        cd AMPcombi &&
        pip install -q -r ./pyshiny/requirements.txt &&
        echo 'Starting AMPcombi Shiny Dashboard...' &&
        python -m shiny run --host 0.0.0.0 --port 37231 ./pyshiny/app.py
    "
else
    echo "Error: Neither Singularity nor Docker was found on your system."
    echo "Please install one of them to run the AMPcombi visualization."
    exit 1
fi
