#!/usr/bin/env bash
# Fills in Flutter's Windows boilerplate around the committed runner. `flutter create` never
# overwrites an existing file, so main.cpp, Runner.rc and the icon stay as committed.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --org com.oryvex --project-name oryvexcore --platforms windows .
if [ -f windows/CMakeLists.txt ]; then
  sed -i.bak 's/set(BINARY_NAME "oryvexcore")/set(BINARY_NAME "OryvexVPN")/' windows/CMakeLists.txt && rm -f windows/CMakeLists.txt.bak
fi
git checkout -- test/widget_test.dart 2>/dev/null || true
flutter pub get
echo "desktop bootstrap done"
