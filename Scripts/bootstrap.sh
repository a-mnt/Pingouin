#!/bin/sh
# Vérifie le projet : lance les tests du paquet, puis compile l'application en Debug.
# Usage : sh Scripts/bootstrap.sh   (depuis la racine du dépôt)
set -eu

cd "$(dirname "$0")/.."

echo "== Outils =="
xcodebuild -version
swift --version

echo "== Tests de PingouinKit =="
swift test --package-path Packages/PingouinKit

echo "== Compilation Debug =="
xcodebuild -project Pingouin.xcodeproj -scheme Pingouin -configuration Debug -destination 'platform=macOS,arch=arm64' build

echo "Terminé."
